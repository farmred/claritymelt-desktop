import 'dart:async';
import 'dart:convert';
import 'dart:io';


import 'package:dartssh2/dartssh2.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_pty/flutter_pty.dart';
import 'package:xterm/xterm.dart';

import '../theme/app_theme.dart';
import '../utils/app_log.dart';
import '../utils/platform_utils.dart';

/// A full-screen terminal that can either:
/// 1. Connect via SSH directly (with optional key file)
/// 2. Run a local command (e.g. `uc exec recurrencedb psql -U postgres`)
class SshTerminalScreen extends StatefulWidget {
  final String host;
  final int port;
  final String username;
  final String? sshKeyFile;

  /// If set, run this local command instead of SSH.
  /// E.g. `['uc', 'exec', 'recurrencedb', 'psql', '-U', 'postgres']`
  final List<String>? localCommand;

  /// Display label for the terminal title bar.
  final String? titleOverride;

  /// Optional password for SSH authentication.
  /// If provided, used when the server requests password auth.
  final String? password;

  const SshTerminalScreen({
    super.key,
    required this.host,
    this.port = 22,
    required this.username,
    this.sshKeyFile,
    this.localCommand,
    this.titleOverride,
    this.password,
  });

  @override
  State<SshTerminalScreen> createState() => _SshTerminalScreenState();
}

class _SshTerminalScreenState extends State<SshTerminalScreen> {
  late Terminal terminal;
  final FocusNode _terminalFocusNode = FocusNode();
  SSHClient? _sshClient;
  Pty? _localPty;
  String _status = 'Connecting…';
  bool _connected = false;
  String? _error;
  String? _errorDetail;

  bool get _isLocal => widget.localCommand != null;

  String get _title => widget.titleOverride ?? '${widget.username}@${widget.host}';

  @override
  void initState() {
    super.initState();
    terminal = Terminal(maxLines: 10000);
    if (_isLocal) {
      _connectLocal();
    } else {
      _connectSsh();
    }
  }

  @override
  void dispose() {
    _terminalFocusNode.dispose();
    _sshClient?.close();
    _localPty?.kill();
    super.dispose();
  }

  // ── Helpers ──────────────────────────────────────────────────────────

  /// Write a status line to the terminal (dimmed, cyan).
  void _termLog(String message) {
    if (!mounted) return;
    terminal.write('\x1b[38;5;87m── $message ──\x1b[0m\r\n');
  }

  /// Write an error line to the terminal (red).
  void _termError(String message) {
    if (!mounted) return;
    terminal.write('\x1b[38;5;203m✗ $message\x1b[0m\r\n');
  }

  /// Write a success line to the terminal (green).
  void _termSuccess(String message) {
    if (!mounted) return;
    terminal.write('\x1b[38;5;120m✓ $message\x1b[0m\r\n');
  }

  /// Write a warning line to the terminal (yellow).
  void _termWarn(String message) {
    if (!mounted) return;
    terminal.write('\x1b[38;5;220m⚠ $message\x1b[0m\r\n');
  }

  /// Resolve a potentially `~`-prefixed path to an absolute path.
  String _resolvePath(String path) {
    if (path.startsWith('/')) return path;
    final home = realHome();
    if (path.startsWith('~/')) return '$home/${path.substring(2)}';
    return '$home/$path';
  }

  /// Load an SSH key file and return the key pairs, or null on failure.
  /// If [silent] is true, don't write errors to the terminal (used for default key probing).
  Future<List<SSHKeyPair>?> _loadKeyFile(String resolvedPath, {bool silent = false}) async {
    try {
      final keyFile = File(resolvedPath);
      if (await keyFile.exists()) {
        final pemContent = await keyFile.readAsString();
        AppLog.info('SSH: loaded key from $resolvedPath');
        try {
          final keys = SSHKeyPair.fromPem(pemContent);
          if (!silent) {
            _termLog('Key loaded successfully (${keys.length} identit${keys.length == 1 ? 'y' : 'ies'})');
          }
          return keys;
        } catch (e) {
          AppLog.error('SSH: key parse failed from $resolvedPath', e, StackTrace.current);
          if (!silent) {
            _termError('Failed to parse key file: $e');
            _termWarn('The key format may not be supported. Ensure it\'s OpenSSH format (not PuTTY .ppk).');
          } else {
            // For default key probing, just log that we skipped this key
            _termLog('Skipped $resolvedPath (format not supported)');
          }
          return null;
        }
      } else {
        AppLog.warning('SSH: key file not found: $resolvedPath');
        if (!silent) {
          _termError('Key file not found: $resolvedPath');
          _termWarn('Check that the path is correct. The app resolves ~ to your real home directory.');
          final home = realHome();
          _termLog('Home directory resolved to: $home');
          _termLog('Expected key at: $resolvedPath');
        }
        return null;
      }
    } catch (e, st) {
      AppLog.error('SSH: key load failed from $resolvedPath', e, st);
      if (!silent) {
        _termError('Key load error: $e');
        _termWarn('Will attempt password authentication instead.');
      }
      return null;
    }
  }

  /// Categorize an SSH error and return a user-friendly message + detail.
  _ErrorInfo _categorizeSshError(Object error) {
    final errorStr = error.toString().toLowerCase();
    final detail = StringBuffer();

    // Connection refused / network errors
    if (errorStr.contains('connection refused') || errorStr.contains('errno = 61') || errorStr.contains('econnrefused')) {
      detail.writeln('The server actively refused the connection on port ${widget.port}.');
      detail.writeln();
      detail.writeln('Possible causes:');
      detail.writeln('  • SSH daemon (sshd) is not running on the remote host');
      detail.writeln('  • SSH is listening on a different port (default is 22)');
      detail.writeln('  • A firewall is blocking the connection');
      detail.writeln('  • The server is powered off or unreachable');
      return _ErrorInfo(
        title: 'Connection Refused',
        detail: detail.toString(),
      );
    }

    // Timeout
    if (errorStr.contains('timed out') || errorStr.contains('timeout') || errorStr.contains('connection timeout')) {
      detail.writeln('The connection attempt timed out after 15 seconds.');
      detail.writeln();
      detail.writeln('Possible causes:');
      detail.writeln('  • The host ${widget.host} is unreachable from this network');
      detail.writeln('  • A firewall is silently dropping packets');
      detail.writeln('  • DNS resolution succeeded but the host is not routable');
      return _ErrorInfo(
        title: 'Connection Timeout',
        detail: detail.toString(),
      );
    }

    // DNS / host not found
    if (errorStr.contains('not found') || errorStr.contains('nodename') || errorStr.contains('enoent') || errorStr.contains('no address') || errorStr.contains('name or service not known')) {
      detail.writeln('Could not resolve hostname: ${widget.host}');
      detail.writeln();
      detail.writeln('Possible causes:');
      detail.writeln('  • The hostname is misspelled');
      detail.writeln('  • DNS is not configured for this host');
      detail.writeln('  • The host entry has been removed from DNS');
      return _ErrorInfo(
        title: 'Host Not Found',
        detail: detail.toString(),
      );
    }

    // Authentication failures
    if (errorStr.contains('auth') || errorStr.contains('permission denied') || errorStr.contains('denied') || errorStr.contains('rejected')) {
      detail.writeln('Authentication failed for ${widget.username}@${widget.host}.');
      detail.writeln();
      if (widget.sshKeyFile != null) {
        detail.writeln('Key file: ${widget.sshKeyFile}');
        detail.writeln();
        detail.writeln('Possible causes:');
        detail.writeln('  • The SSH key is not authorized on the server');
        detail.writeln('  • The key file is corrupted or in wrong format');
        detail.writeln('  • The key requires a passphrase that was not provided');
        detail.writeln('  • The server requires a different key or method');
      } else {
        detail.writeln('Possible causes:');
        detail.writeln('  • No SSH key was provided and password auth may be disabled');
        detail.writeln('  • Wrong username or password');
        detail.writeln('  • The server requires key-based authentication only');
      }
      return _ErrorInfo(
        title: 'Authentication Failed',
        detail: detail.toString(),
      );
    }

    // Key file errors
    if (errorStr.contains('key') && (errorStr.contains('load') || errorStr.contains('parse') || errorStr.contains('format') || errorStr.contains('unsupported'))) {
      detail.writeln('Failed to load or parse the SSH key file.');
      detail.writeln();
      detail.writeln('Key file: ${widget.sshKeyFile ?? "(none)"}');
      detail.writeln();
      detail.writeln('Possible causes:');
      detail.writeln('  • The key file format is not supported (e.g. PuTTY .ppk)');
      detail.writeln('  • The key file is corrupted');
      detail.writeln('  • The key file requires a passphrase');
      return _ErrorInfo(
        title: 'SSH Key Error',
        detail: detail.toString(),
      );
    }

    // Host key verification
    if (errorStr.contains('host key') || errorStr.contains('hostkey')) {
      detail.writeln('The server host key could not be verified.');
      detail.writeln();
      detail.writeln('This could mean:');
      detail.writeln('  • The server has changed its host key (possible MITM attack)');
      detail.writeln('  • This is a new server you haven\'t connected to before');
      return _ErrorInfo(
        title: 'Host Key Verification Failed',
        detail: detail.toString(),
      );
    }

    // Generic fallback
    detail.writeln('Raw error:');
    detail.writeln(error.toString());
    return _ErrorInfo(
      title: 'Connection Failed',
      detail: detail.toString(),
    );
  }

  // ── SSH Connection ──────────────────────────────────────────────────

  Future<void> _connectSsh() async {
    AppLog.info('SSH: connecting to ${widget.username}@${widget.host}:${widget.port}');
    _termLog('Connecting to ${widget.username}@${widget.host}:${widget.port}…');
    setState(() {
      _error = null;
      _errorDetail = null;
      _status = 'Connecting…';
    });

    try {
      final socket = await SSHSocket.connect(
        widget.host,
        widget.port,
        timeout: const Duration(seconds: 15),
      );
      AppLog.debug('SSH: socket connected to ${widget.host}:${widget.port}');
      _termLog('TCP connection established');
      if (!mounted) return;

      // Load SSH key pair(s):
      // 1. If an explicit key file is specified, load that
      // 2. If no key specified, try default SSH keys from ~/.ssh/ (like ssh CLI does)
      List<SSHKeyPair>? identities;
      final home = realHome();
      final sshDir = '$home/.ssh';

      if (widget.sshKeyFile != null && widget.sshKeyFile!.isNotEmpty) {
        // Explicit key file specified
        final resolvedPath = _resolvePath(widget.sshKeyFile!);
        _termLog('Loading SSH key: $resolvedPath');
        identities = await _loadKeyFile(resolvedPath);
      } else {
        // No explicit key — try default SSH keys from ~/.ssh/
        // (mirrors what `ssh` does when no -i flag is given)
        _termLog('No explicit SSH key — trying default keys from $sshDir');
        final defaultKeyNames = ['id_ed25519', 'id_ecdsa', 'id_rsa', 'id_ed25519_sk', 'id_ecdsa_sk'];
        final foundKeys = <SSHKeyPair>[];
        for (final name in defaultKeyNames) {
          final path = '$sshDir/$name';
          final file = File(path);
          if (await file.exists()) {
            _termLog('Trying $path');
            final keys = await _loadKeyFile(path, silent: true);
            if (keys != null) {
              foundKeys.addAll(keys);
              _termLog('Loaded default key: $name (${keys.length} identit${keys.length == 1 ? 'y' : 'ies'})');
            }
          }
        }
        if (foundKeys.isNotEmpty) {
          identities = foundKeys;
          _termLog('Using ${foundKeys.length} identit${foundKeys.length == 1 ? 'y' : 'ies'} from default SSH keys');
        } else {
          _termLog('No default SSH keys found in $sshDir');
          _termLog('Will attempt password/keyboard-interactive auth only');
        }
      }

      if (!mounted) return;

      _termLog('Authenticating as ${widget.username}…');
      setState(() { _status = 'Authenticating…'; });

      _sshClient = SSHClient(
        socket,
        username: widget.username,
        identities: identities,
        onPasswordRequest: () {
          if (widget.password != null && widget.password!.isNotEmpty) {
            AppLog.info('SSH: providing password for ${widget.username}');
            _termLog('Server requested password auth — using provided password');
            return widget.password!;
          }
          // No password available — key auth should work
          AppLog.warning('SSH: server requested password auth (no password available)');
          _termWarn('Server requested password auth, but no password was provided');
          _termWarn('If key auth fails, try re-entering the password in the connection dialog');
          return '';
        },
        onVerifyHostKey: (type, fingerprint) {
          // Accept all host keys for now — could add TOFU later
          _termLog('Host key accepted ($type)');
          return true;
        },
      );

      try {
        await _sshClient!.authenticated.timeout(
          const Duration(seconds: 30),
        );
      } on TimeoutException catch (_) {
        throw TimeoutException('Authentication timed out after 30 seconds. The server may not accept the provided credentials.');
      }
      AppLog.info('SSH: authenticated as ${widget.username}@${widget.host}');
      _termSuccess('Authenticated as ${widget.username}@${widget.host}');
      if (!mounted) return;

      setState(() {
        _connected = true;
        _status = 'Connected';
      });

      _termLog('Opening shell…');
      final session = await _sshClient!.shell(
        pty: SSHPtyConfig(
          type: 'xterm-256color',
          width: terminal.viewWidth,
          height: terminal.viewHeight,
        ),
      );

      _termLog('Shell opened — terminal ready');

      // Wire terminal output to SSH session immediately so input is captured
      // from the moment the shell is ready (not after a delay).
      terminal.onOutput = (data) {
        session.write(utf8.encode(data));
      };

      terminal.onResize = (width, height, pixelWidth, pixelHeight) {
        session.resizeTerminal(width, height, pixelWidth, pixelHeight);
      };

      _pipeSshOutput(session);

      // Clear the connection log from terminal after successful connection
      // so it doesn't pollute the shell session
      await Future.delayed(const Duration(milliseconds: 300));
      terminal.write('\x1b[2J\x1b[H'); // Clear screen and move cursor to top-left

      // Ensure the terminal has focus so keyboard input is accepted
      _terminalFocusNode.requestFocus();

    } on TimeoutException catch (e) {
      final errorInfo = _categorizeSshError(e);
      AppLog.error('SSH: timeout connecting to ${widget.host}:${widget.port}', e, StackTrace.current);
      if (!mounted) return;
      _termError(errorInfo.title);
      for (final line in errorInfo.detail.split('\n')) {
        if (line.trim().isNotEmpty) _termError(line.trim());
      }
      setState(() {
        _error = errorInfo.title;
        _errorDetail = errorInfo.detail;
      });
    } catch (e, st) {
      final errorInfo = _categorizeSshError(e);
      AppLog.error('SSH: connection failed to ${widget.host}:${widget.port}', e, st);
      if (!mounted) return;
      _termError(errorInfo.title);
      if (errorInfo.detail.isNotEmpty) {
        for (final line in errorInfo.detail.split('\n')) {
          if (line.trim().isNotEmpty) _termError(line.trim());
        }
      }
      setState(() {
        _error = errorInfo.title;
        _errorDetail = errorInfo.detail;
        _status = 'Connection failed';
      });
    }
  }

  void _pipeSshOutput(SSHSession session) {
    session.stdout.listen(
      (data) {
        if (!mounted) return;
        terminal.write(utf8.decode(data, allowMalformed: true));
      },
      onDone: () => _handleDisconnect(),
      onError: (e) {
        AppLog.error('SSH: stdout error', e);
        _handleDisconnect();
      },
    );

    session.stderr.listen(
      (data) {
        if (!mounted) return;
        terminal.write(utf8.decode(data, allowMalformed: true));
      },
    );

    session.done.then((_) {
      // Session closed
    });
  }

  // ── Local Command (with PTY for interactive terminal support) ────────

  Future<void> _connectLocal() async {
    final cmd = widget.localCommand!;
    AppLog.info('Local: starting command with PTY: ${cmd.join(' ')}');
    _termLog('Starting: ${cmd.join(' ')}');
    setState(() {
      _error = null;
      _errorDetail = null;
    });

    try {
      _localPty = Pty.start(
        cmd.first,
        arguments: cmd.sublist(1),
        environment: {
          ...realHomeEnvironment(),
          'TERM': 'xterm-256color',
        },
        rows: terminal.viewHeight,
        columns: terminal.viewWidth,
      );
      AppLog.debug('Local: PTY process started (pid: ${_localPty!.pid})');
      _termLog('Process started (pid: ${_localPty!.pid})');

      if (!mounted) return;

      setState(() {
        _connected = true;
        _status = 'Running';
      });

      // Wire terminal output to PTY input
      terminal.onOutput = (data) {
        _localPty!.write(utf8.encode(data));
      };

      // Wire terminal resize to PTY resize
      terminal.onResize = (width, height, pixelWidth, pixelHeight) {
        _localPty!.resize(height, width);
      };

      // Ensure the terminal has focus so keyboard input is accepted
      _terminalFocusNode.requestFocus();

      // Pipe PTY output to terminal
      _localPty!.output.listen(
        (data) {
          if (!mounted) return;
          terminal.write(utf8.decode(data, allowMalformed: true));
        },
        onDone: () {
          AppLog.info('Local: PTY output stream closed');
          _handleDisconnect();
        },
        onError: (e) {
          AppLog.error('Local: PTY output error', e);
          _termError('PTY error: $e');
          _handleDisconnect();
        },
      );

      // Wait for exit code
      _localPty!.exitCode.then((exitCode) {
        AppLog.info('Local: PTY process exited with code $exitCode');
        if (mounted && exitCode != 0) {
          terminal.write('\r\n\x1b[33mProcess exited with code $exitCode\x1b[0m\r\n');
        }
        _handleDisconnect();
      });

    } catch (e, st) {
      AppLog.error('Local: PTY command failed: ${cmd.join(' ')}', e, st);
      if (!mounted) return;
      _termError('Command failed: $e');

      // Provide more context for common local command errors
      final errorStr = e.toString().toLowerCase();
      String detail = e.toString();
      if (errorStr.contains('no such file') || errorStr.contains('not found') || errorStr.contains('enoent')) {
        detail = 'Command not found: ${cmd.first}\n\n'
            'Make sure the command is installed and in your PATH.\n'
            'If using \'uc\', install it with: brew install psviderski/tap/uncloud';
      } else if (errorStr.contains('permission denied') || errorStr.contains('eacces')) {
        detail = 'Permission denied: ${cmd.first}\n\nThe command may need elevated permissions.';
      }

      setState(() {
        _error = 'Command Failed';
        _errorDetail = detail;
        _status = 'Command failed';
      });
    }
  }

  // ── Common ──────────────────────────────────────────────────────────

  void _handleDisconnect() {
    if (mounted && _connected) {
      setState(() {
        _connected = false;
        _status = _isLocal ? 'Exited' : 'Disconnected';
      });
    }
  }

  void _reconnect() {
    setState(() {
      _error = null;
      _errorDetail = null;
      _status = 'Connecting…';
      _connected = false;
    });
    terminal.write('\x1b[2J\x1b[H'); // Clear terminal
    _sshClient?.close();
    _localPty?.kill();
    if (_isLocal) {
      _connectLocal();
    } else {
      _connectSsh();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_title),
        actions: [
          if (!_connected && _error == null)
            Padding(
              padding: const EdgeInsets.only(right: 16),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const SizedBox(width: 12, height: 12, child: CircularProgressIndicator(strokeWidth: 2)),
                  const SizedBox(width: 8),
                  Text(_status, style: TextStyle(fontSize: 11, color: AppColors.secondary, fontFamily: AppTheme.bodyFont)),
                ],
              ),
            ),
          if (_connected)
            Padding(
              padding: const EdgeInsets.only(right: 16),
              child: Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: AppColors.success.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(2),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.circle, size: 6, color: AppColors.success),
                      const SizedBox(width: 4),
                      Text(_isLocal ? 'RUNNING' : 'CONNECTED', style: const TextStyle(fontSize: 9, fontWeight: FontWeight.w700, color: AppColors.success, fontFamily: AppTheme.bodyFont, letterSpacing: 0.5)),
                    ],
                  ),
                ),
              ),
            ),
          if (_error != null)
            IconButton(
              icon: const Icon(Icons.refresh),
              tooltip: 'Reconnect',
              onPressed: _reconnect,
            ),
          IconButton(
            icon: const Icon(Icons.close),
            tooltip: 'Close',
            onPressed: () => Navigator.of(context).pop(),
          ),
        ],
      ),
      body: _error != null
          ? _buildError()
          : Column(
              children: [
                Expanded(
                  child: TerminalView(
                    terminal,
                    theme: _terminalTheme,
                    textStyle: const TerminalStyle(
                      fontFamily: AppTheme.bodyFont,
                      fontSize: 13,
                    ),
                    autofocus: true,
                    focusNode: _terminalFocusNode,
                  ),
                ),
              ],
            ),
    );
  }

  Widget _buildError() {
    return SingleChildScrollView(
      child: Column(
        children: [
          // Show the terminal with connection log even on error
          SizedBox(
            height: 180,
            child: TerminalView(
              terminal,
              theme: _terminalTheme,
              textStyle: const TerminalStyle(
                fontFamily: AppTheme.bodyFont,
                fontSize: 12,
              ),
              autofocus: false,
              focusNode: _terminalFocusNode,
            ),
          ),
          const Divider(height: 1),
          // Detailed error panel
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.error_outline, size: 48, color: AppColors.danger),
                const SizedBox(height: 16),
                Text(
                  _error ?? 'Connection Failed',
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700, fontFamily: AppTheme.displayFont, color: AppColors.primary),
                ),
                const SizedBox(height: 8),
                // Connection details
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: AppColors.surfaceVariant,
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(color: AppColors.outline),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (_isLocal) ...[
                        _ErrorDetailRow(label: 'Command', value: widget.localCommand!.join(' ')),
                      ] else ...[
                        _ErrorDetailRow(label: 'Host', value: '${widget.host}:${widget.port}'),
                        _ErrorDetailRow(label: 'User', value: widget.username),
                        if (widget.sshKeyFile != null) ...[
                          _ErrorDetailRow(label: 'Key', value: _resolvePath(widget.sshKeyFile!)),
                          Builder(builder: (context) {
                            final keyFile = File(_resolvePath(widget.sshKeyFile!));
                            return FutureBuilder<bool>(
                              future: keyFile.exists(),
                              builder: (context, snapshot) {
                                if (!snapshot.hasData) return const SizedBox.shrink();
                                final exists = snapshot.data!;
                                return _ErrorDetailRow(
                                  label: 'Key exists',
                                  value: exists ? 'Yes' : 'NO — file not found',
                                  valueColor: exists ? AppColors.success : AppColors.danger,
                                );
                              },
                            );
                          }),
                        ] else ...[
                          _ErrorDetailRow(label: 'Auth', value: 'Password / keyboard-interactive'),
                        ],
                      ],
                    ],
                  ),
                ),
                // Detailed error explanation
                if (_errorDetail != null && _errorDetail!.trim().isNotEmpty) ...[
                  const SizedBox(height: 16),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: AppColors.danger.withValues(alpha: 0.05),
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(color: AppColors.danger.withValues(alpha: 0.2)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Icon(Icons.info_outline, size: 16, color: AppColors.danger),
                            const SizedBox(width: 8),
                            const Text('DETAILS', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 0.5, color: AppColors.danger, fontFamily: AppTheme.bodyFont)),
                          ],
                        ),
                        const SizedBox(height: 8),
                        SelectableText(
                          _errorDetail!.trim(),
                          style: TextStyle(fontSize: 12, color: AppColors.primary.withValues(alpha: 0.85), fontFamily: AppTheme.bodyFont, height: 1.5),
                        ),
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: 24),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    FilledButton.icon(
                      onPressed: _reconnect,
                      icon: const Icon(Icons.refresh),
                      label: const Text('RETRY'),
                    ),
                    const SizedBox(width: 12),
                    if (!_isLocal)
                      OutlinedButton.icon(
                        onPressed: _copySshCommand,
                        icon: const Icon(Icons.copy, size: 16),
                        label: const Text('COPY SSH CMD'),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _copySshCommand() {
    final keyFlag = widget.sshKeyFile != null ? ' -i ${_resolvePath(widget.sshKeyFile!)}' : '';
    final cmd = 'ssh$keyFlag ${widget.username}@${widget.host} -p ${widget.port}';
    Clipboard.setData(ClipboardData(text: cmd));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Copied: $cmd')),
    );
  }
}

/// A row in the error detail panel.
class _ErrorDetailRow extends StatelessWidget {
  final String label;
  final String value;
  final Color? valueColor;

  const _ErrorDetailRow({required this.label, required this.value, this.valueColor});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 80,
            child: Text(
              label.toUpperCase(),
              style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, letterSpacing: 0.5, color: AppColors.secondary, fontFamily: AppTheme.bodyFont),
            ),
          ),
          Expanded(
            child: SelectableText(
              value,
              style: TextStyle(
                fontSize: 13,
                fontFamily: AppTheme.bodyFont,
                color: valueColor ?? AppColors.primary,
                fontWeight: valueColor != null ? FontWeight.w600 : FontWeight.normal,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Categorized error information for better user feedback.
class _ErrorInfo {
  final String title;
  final String detail;

  _ErrorInfo({required this.title, this.detail = ''});
}

/// Dark terminal theme matching the Cyber Matrix aesthetic.
const _terminalTheme = TerminalTheme(
  cursor: AppColors.tertiary,
  selection: AppColors.tertiary,
  foreground: AppColors.primary,
  background: AppColors.neutral,
  black: AppColors.neutral,
  red: AppColors.danger,
  green: AppColors.success,
  yellow: AppColors.warning,
  blue: AppColors.ovh,
  magenta: AppColors.tertiary,
  cyan: AppColors.secondary,
  white: AppColors.primary,
  brightBlack: AppColors.secondary,
  brightRed: AppColors.danger,
  brightGreen: AppColors.success,
  brightYellow: AppColors.warning,
  brightBlue: AppColors.ovh,
  brightMagenta: AppColors.tertiary,
  brightCyan: AppColors.secondary,
  brightWhite: AppColors.primary,
  searchHitBackground: AppColors.tertiary,
  searchHitBackgroundCurrent: AppColors.tertiary,
  searchHitForeground: AppColors.neutral,
);