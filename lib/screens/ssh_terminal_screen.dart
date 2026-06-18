import 'dart:convert';
import 'dart:io';

import 'package:dartssh2/dartssh2.dart';
import 'package:flutter/material.dart';
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

  const SshTerminalScreen({
    super.key,
    required this.host,
    this.port = 22,
    required this.username,
    this.sshKeyFile,
    this.localCommand,
    this.titleOverride,
  });

  @override
  State<SshTerminalScreen> createState() => _SshTerminalScreenState();
}

class _SshTerminalScreenState extends State<SshTerminalScreen> {
  late Terminal terminal;
  SSHClient? _sshClient;
  Process? _localProcess;
  String _status = 'Connecting…';
  bool _connected = false;
  String? _error;

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
    _sshClient?.close();
    _localProcess?.kill();
    super.dispose();
  }

  // ── SSH Connection ──────────────────────────────────────────────────

  Future<void> _connectSsh() async {
    AppLog.info('SSH: connecting to ${widget.username}@${widget.host}:${widget.port}');
    try {
      final socket = await SSHSocket.connect(widget.host, widget.port);
      AppLog.debug('SSH: socket connected to ${widget.host}:${widget.port}');

      // Load SSH key pair if provided
      List<SSHKeyPair>? identities;
      if (widget.sshKeyFile != null && widget.sshKeyFile!.isNotEmpty) {
        try {
          final keyFile = File(widget.sshKeyFile!);
          if (await keyFile.exists()) {
            final pemContent = await keyFile.readAsString();
            AppLog.info('SSH: loaded key from ${widget.sshKeyFile}');
            if (SSHKeyPair.isEncryptedPem(pemContent)) {
              AppLog.warning('SSH: key ${widget.sshKeyFile} is encrypted, trying without passphrase');
              identities = SSHKeyPair.fromPem(pemContent);
            } else {
              identities = SSHKeyPair.fromPem(pemContent);
            }
          } else {
            AppLog.warning('SSH: key file not found: ${widget.sshKeyFile}');
          }
        } catch (e, st) {
          // Key loading failed — fall back to password auth
          AppLog.error('SSH: key load failed from ${widget.sshKeyFile}', e, st);
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('SSH key load failed: $e'), backgroundColor: AppColors.warning),
            );
          }
        }
      }

      _sshClient = SSHClient(
        socket,
        username: widget.username,
        identities: identities,
        onPasswordRequest: () {
          // No password available — key auth should work
          AppLog.warning('SSH: server requested password auth (no password available)');
          return '';
        },
      );

      await _sshClient!.authenticated;
      AppLog.info('SSH: authenticated as ${widget.username}@${widget.host}');

      if (!mounted) return;

      setState(() {
        _connected = true;
        _status = 'Connected';
      });

      final session = await _sshClient!.shell(
        pty: SSHPtyConfig(
          type: 'xterm-256color',
          width: terminal.viewWidth,
          height: terminal.viewHeight,
        ),
      );

      terminal.onOutput = (data) {
        session.write(utf8.encode(data));
      };

      terminal.onResize = (width, height, pixelWidth, pixelHeight) {
        session.resizeTerminal(width, height, pixelWidth, pixelHeight);
      };

      _pipeSshOutput(session);

    } catch (e, st) {
      AppLog.error('SSH: connection failed to ${widget.host}:${widget.port}', e, st);
      if (!mounted) return;
      setState(() {
        _error = e.toString();
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
      onError: (_) => _handleDisconnect(),
    );

    session.stderr.listen(
      (data) {
        if (!mounted) return;
        terminal.write(utf8.decode(data, allowMalformed: true));
      },
    );
  }

  // ── Local Command ────────────────────────────────────────────────────

  Future<void> _connectLocal() async {
    final cmd = widget.localCommand!;
    AppLog.info('Local: starting command: ${cmd.join(' ')}');
    try {
      _localProcess = await Process.start(
        cmd.first,
        cmd.sublist(1),
        environment: realHomeEnvironment(),
      );
      AppLog.debug('Local: process started (pid: ${_localProcess!.pid})');

      if (!mounted) return;

      setState(() {
        _connected = true;
        _status = 'Running';
      });

      terminal.onOutput = (data) {
        _localProcess!.stdin.write(data);
      };

      _localProcess!.stdout.listen(
        (data) {
          if (!mounted) return;
          terminal.write(utf8.decode(data, allowMalformed: true));
        },
        onDone: _handleDisconnect,
        onError: (_) => _handleDisconnect(),
      );

      _localProcess!.stderr.listen(
        (data) {
          if (!mounted) return;
          terminal.write(utf8.decode(data, allowMalformed: true));
        },
      );

      final exitCode = await _localProcess!.exitCode;
      AppLog.info('Local: process exited with code $exitCode');
      if (mounted && exitCode != 0) {
        terminal.write('\r\n\x1b[33mProcess exited with code $exitCode\x1b[0m\r\n');
        _handleDisconnect();
      }

    } catch (e, st) {
      AppLog.error('Local: command failed: ${cmd.join(' ')}', e, st);
      if (!mounted) return;
      setState(() {
        _error = e.toString();
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
      _status = 'Connecting…';
      _connected = false;
    });
    _sshClient?.close();
    _localProcess?.kill();
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
            const Padding(
              padding: EdgeInsets.only(right: 16),
              child: Center(
                child: SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
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
                  ),
                ),
              ],
            ),
    );
  }

  Widget _buildError() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(48),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, size: 48, color: AppColors.danger),
            const SizedBox(height: 16),
            const Text('Connection Failed', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, fontFamily: AppTheme.displayFont, color: AppColors.primary)),
            const SizedBox(height: 8),
            Text(_error ?? 'Unknown error', style: const TextStyle(fontSize: 13, color: AppColors.secondary, fontFamily: AppTheme.bodyFont), textAlign: TextAlign.center),
            const SizedBox(height: 16),
            if (_isLocal)
              Text(
                'Command: ${widget.localCommand!.join(' ')}',
                style: TextStyle(fontSize: 12, color: AppColors.secondary.withValues(alpha: 0.7), fontFamily: AppTheme.bodyFont),
                textAlign: TextAlign.center,
              )
            else
              Text(
                'Host: ${widget.host}:${widget.port}\nUser: ${widget.username}${widget.sshKeyFile != null ? '\nKey: ${widget.sshKeyFile}' : ''}',
                style: TextStyle(fontSize: 12, color: AppColors.secondary.withValues(alpha: 0.7), fontFamily: AppTheme.bodyFont),
                textAlign: TextAlign.center,
              ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: _reconnect,
              icon: const Icon(Icons.refresh),
              label: const Text('RETRY'),
            ),
          ],
        ),
      ),
    );
  }
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