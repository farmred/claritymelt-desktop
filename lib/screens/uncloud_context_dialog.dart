/// Shared dialog for viewing Uncloud context details:
/// services, machines, cluster domain, and links to ClarityMelt machines.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/models.dart';
import '../providers/app_providers.dart';
import '../services/uncloud_service.dart';
import '../theme/app_theme.dart';
import 'machine_detail_screen.dart';
import 'ssh_terminal_screen.dart';

/// Show a dialog with details for a specific Uncloud context.
void showUncloudContextDetailDialog({
  required BuildContext context,
  required String contextName,
  required UncloudContext ctx,
  required bool isActive,
}) {
  showDialog(
    context: context,
    builder: (_) => UncloudContextDetailDialog(
      contextName: contextName,
      ctx: ctx,
      isActive: isActive,
    ),
  );
}

class UncloudContextDetailDialog extends ConsumerStatefulWidget {
  final String contextName;
  final UncloudContext ctx;
  final bool isActive;

  const UncloudContextDetailDialog({
    super.key,
    required this.contextName,
    required this.ctx,
    required this.isActive,
  });

  @override
  ConsumerState<UncloudContextDetailDialog> createState() =>
      _UncloudContextDetailDialogState();
}

class _UncloudContextDetailDialogState
    extends ConsumerState<UncloudContextDetailDialog> {
  @override
  Widget build(BuildContext context) {
    final servicesAsync =
        ref.watch(uncloudServicesForContextProvider(widget.contextName));
    final machinesAsync =
        ref.watch(uncloudMachinesForContextProvider(widget.contextName));
    final domainAsync =
        ref.watch(uncloudDomainForContextProvider(widget.contextName));
    final cmMachinesAsync = ref.watch(machinesProvider);

    return AlertDialog(
      title: Row(
        children: [
          const Icon(Icons.dns, size: 20, color: AppColors.tertiary),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              widget.contextName.toUpperCase(),
              style: const TextStyle(
                  fontFamily: AppTheme.displayFont, fontSize: 16),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (widget.isActive)
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                  color: AppColors.success.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(2)),
              child: const Text('ACTIVE',
                  style: TextStyle(
                      fontSize: 9,
                      fontWeight: FontWeight.w700,
                      color: AppColors.success,
                      fontFamily: AppTheme.bodyFont,
                      letterSpacing: 0.5)),
            ),
          const SizedBox(width: 8),
          IconButton(
            icon: const Icon(Icons.refresh, size: 16),
            tooltip: 'Refresh',
            onPressed: () {
              ref.invalidate(
                  uncloudServicesForContextProvider(widget.contextName));
              ref.invalidate(
                  uncloudMachinesForContextProvider(widget.contextName));
              ref.invalidate(
                  uncloudDomainForContextProvider(widget.contextName));
            },
          ),
        ],
      ),
      content: SizedBox(
        width: 600,
        height: 500,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Cluster domain ──
              Row(
                children: [
                  const Icon(Icons.language,
                      size: 14, color: AppColors.secondary),
                  const SizedBox(width: 6),
                  const Text('DOMAIN', style: AppTheme.labelStyle),
                  const SizedBox(width: 8),
                  domainAsync.when(
                    loading: () => const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2)),
                    error: (_, __) => Text('—',
                        style: TextStyle(
                            fontSize: 12,
                            color: AppColors.secondary,
                            fontFamily: AppTheme.bodyFont)),
                    data: (d) => Text(d ?? '—',
                        style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: AppColors.tertiary,
                            fontFamily: AppTheme.bodyFont)),
                  ),
                ],
              ),
              const SizedBox(height: 6),

              // ── Connections ──
              Row(
                children: [
                  const Icon(Icons.cable,
                      size: 14, color: AppColors.secondary),
                  const SizedBox(width: 6),
                  const Text('CONNECTIONS', style: AppTheme.labelStyle),
                  const SizedBox(width: 8),
                  Text('${widget.ctx.connections.length}',
                      style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: AppColors.primary,
                          fontFamily: AppTheme.bodyFont)),
                ],
              ),
              const SizedBox(height: 6),
              ...widget.ctx.connections.map((conn) => Container(
                    margin: const EdgeInsets.only(bottom: 4),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: AppColors.surfaceVariant,
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(color: AppColors.outline),
                    ),
                    child: Row(
                      children: [
                        Icon(_connIcon(conn.typeLabel),
                            size: 14, color: AppColors.tertiary),
                        const SizedBox(width: 8),
                        Expanded(
                            child: Text(conn.sshTarget,
                                style: TextStyle(
                                    fontSize: 12,
                                    fontFamily: AppTheme.bodyFont))),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 4, vertical: 1),
                          decoration: BoxDecoration(
                            color:
                                AppColors.tertiary.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(2),
                          ),
                          child: Text(conn.typeLabel,
                              style: TextStyle(
                                  fontSize: 9,
                                  fontWeight: FontWeight.w700,
                                  color: AppColors.tertiary,
                                  fontFamily: AppTheme.bodyFont)),
                        ),
                      ],
                    ),
                  )),
              const SizedBox(height: 16),

              // ── UC Machines ──
              Row(
                children: [
                  const Icon(Icons.dns,
                      size: 14, color: AppColors.secondary),
                  const SizedBox(width: 6),
                  const Text('MACHINES', style: AppTheme.labelStyle),
                  const SizedBox(width: 8),
                  machinesAsync.when(
                    loading: () => const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2)),
                    error: (_, __) => Text('—',
                        style: TextStyle(
                            fontSize: 11,
                            color: AppColors.danger,
                            fontFamily: AppTheme.bodyFont)),
                    data: (m) => Text('${m.length}',
                        style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: AppColors.primary,
                            fontFamily: AppTheme.bodyFont)),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              machinesAsync.when(
                loading: () =>
                    const Center(child: CircularProgressIndicator()),
                error: (e, _) => Text('Failed to load machines: $e',
                    style: TextStyle(
                        fontSize: 12,
                        color: AppColors.danger,
                        fontFamily: AppTheme.bodyFont)),
                data: (ucMachines) {
                  if (ucMachines.isEmpty) {
                    return Text(
                        'No machines running in this context',
                        style: TextStyle(
                            fontSize: 12,
                            color: AppColors.secondary,
                            fontFamily: AppTheme.bodyFont));
                  }
                  final cmMachines = cmMachinesAsync.value ?? [];
                  return Column(
                    children: ucMachines
                        .map((ucM) =>
                            _buildUcMachineRow(context, ucM, cmMachines))
                        .toList(),
                  );
                },
              ),
              const SizedBox(height: 16),

              // ── Services ──
              Row(
                children: [
                  const Icon(Icons.widgets,
                      size: 14, color: AppColors.secondary),
                  const SizedBox(width: 6),
                  const Text('SERVICES', style: AppTheme.labelStyle),
                  const SizedBox(width: 8),
                  servicesAsync.when(
                    loading: () => const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2)),
                    error: (_, __) => Text('—',
                        style: TextStyle(
                            fontSize: 11,
                            color: AppColors.danger,
                            fontFamily: AppTheme.bodyFont)),
                    data: (s) => Text('${s.length}',
                        style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: AppColors.primary,
                            fontFamily: AppTheme.bodyFont)),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              servicesAsync.when(
                loading: () =>
                    const Center(child: CircularProgressIndicator()),
                error: (e, _) => Text('Failed to load services: $e',
                    style: TextStyle(
                        fontSize: 12,
                        color: AppColors.danger,
                        fontFamily: AppTheme.bodyFont)),
                data: (services) {
                  if (services.isEmpty) {
                    return Text(
                        'No services deployed in this context',
                        style: TextStyle(
                            fontSize: 12,
                            color: AppColors.secondary,
                            fontFamily: AppTheme.bodyFont));
                  }
                  final pgServices = services.where((s) => s.isPostgres).toList();
                  return Column(
                    children: [
                      // Regular services
                      ...services.where((s) => !s.isPostgres).map((svc) => Container(
                        margin: const EdgeInsets.only(bottom: 4),
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(
                          color: AppColors.surfaceVariant,
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(color: AppColors.outline),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.widgets, size: 14, color: AppColors.secondary),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(svc.name, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, fontFamily: AppTheme.bodyFont)),
                                  Text(svc.image, style: TextStyle(fontSize: 10, color: AppColors.secondary, fontFamily: AppTheme.bodyFont)),
                                ],
                              ),
                            ),
                            if (svc.endpoints.isNotEmpty)
                              Flexible(child: Text(svc.endpoints, style: TextStyle(fontSize: 9, color: AppColors.tertiary, fontFamily: AppTheme.bodyFont), overflow: TextOverflow.ellipsis)),
                            const SizedBox(width: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                              decoration: BoxDecoration(color: AppColors.tertiary.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(2)),
                              child: Text('${svc.replicas}×', style: TextStyle(fontSize: 9, fontWeight: FontWeight.w700, color: AppColors.tertiary, fontFamily: AppTheme.bodyFont)),
                            ),
                          ],
                        ),
                      )),
                      // Postgres services with PSQL access
                      if (pgServices.isNotEmpty) ...[
                        const SizedBox(height: 12),
                        const Text('DATABASE ACCESS', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 1.2, fontFamily: AppTheme.displayFont, color: AppColors.secondary)),
                        const SizedBox(height: 8),
                        ...pgServices.map((pgSvc) => Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: AppColors.success.withValues(alpha: 0.05),
                              borderRadius: BorderRadius.circular(4),
                              border: Border.all(color: AppColors.success.withValues(alpha: 0.2)),
                            ),
                            child: Row(
                              children: [
                                const Icon(Icons.storage, size: 18, color: AppColors.success),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(pgSvc.name, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, fontFamily: AppTheme.bodyFont)),
                                      const SizedBox(height: 2),
                                      Text('${pgSvc.image} — connect via psql', style: TextStyle(fontSize: 12, color: AppColors.secondary, fontFamily: AppTheme.bodyFont)),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 8),
                                FilledButton.icon(
                                  onPressed: () => _openPsqlTerminal(context, pgSvc.name),
                                  icon: const Icon(Icons.terminal, size: 16),
                                  label: const Text('PSQL'),
                                  style: FilledButton.styleFrom(
                                    backgroundColor: AppColors.success,
                                    foregroundColor: AppColors.neutral,
                                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                                    textStyle: TextStyle(fontSize: 11, fontFamily: AppTheme.bodyFont, letterSpacing: 0.5),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        )),
                      ],
                    ],
                  );
                },
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('CLOSE'),
        ),
      ],
    );
  }

  Widget _buildUcMachineRow(
      BuildContext context, UncloudRunningMachine ucM, List<MachineInfo> cmMachines) {
    // Find matching ClarityMelt machine
    final cmMatch = cmMachines.where((m) =>
        m.ipAddresses.contains(ucM.publicIp) ||
        m.name == ucM.name ||
        m.uncloudMachineId == ucM.machineId).firstOrNull;

    return Container(
      margin: const EdgeInsets.only(bottom: 4),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: cmMatch != null
            ? AppColors.tertiary.withValues(alpha: 0.05)
            : AppColors.surfaceVariant,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(
            color: cmMatch != null
                ? AppColors.tertiary.withValues(alpha: 0.2)
                : AppColors.outline),
      ),
      child: Row(
        children: [
          AppTheme.statusDot(ucM.state, size: 8),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    if (cmMatch != null)
                      InkWell(
                        onTap: () {
                          Navigator.pop(context); // Close dialog
                          Navigator.push(
                              context,
                              MaterialPageRoute(
                                  builder: (_) => MachineDetailScreen(
                                      machine: cmMatch)));
                        },
                        borderRadius: BorderRadius.circular(2),
                        child: Text(
                          ucM.name,
                          style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: AppColors.tertiary,
                              fontFamily: AppTheme.bodyFont,
                              decoration: TextDecoration.underline),
                        ),
                      )
                    else
                      Text(ucM.name,
                          style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              fontFamily: AppTheme.bodyFont)),
                    const SizedBox(width: 6),
                    CodeBlock(text: ucM.publicIp),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  'WG: ${ucM.address}  •  ID: ${ucM.machineId.length > 12 ? '${ucM.machineId.substring(0, 12)}…' : ucM.machineId}',
                  style: TextStyle(
                      fontSize: 10,
                      color: AppColors.secondary.withValues(alpha: 0.7),
                      fontFamily: AppTheme.bodyFont),
                ),
              ],
            ),
          ),
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: ucM.isUp
                  ? AppColors.success.withValues(alpha: 0.1)
                  : AppColors.danger.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(2),
            ),
            child: Text(
              ucM.state.toUpperCase(),
              style: TextStyle(
                fontSize: 9,
                fontWeight: FontWeight.w700,
                color: ucM.isUp ? AppColors.success : AppColors.danger,
                fontFamily: AppTheme.bodyFont,
                letterSpacing: 0.5,
              ),
            ),
          ),
        ],
      ),
    );
  }

  IconData _connIcon(String label) {
    switch (label) {
      case 'SSH':
        return Icons.terminal;
      case 'SSH (Go)':
        return Icons.terminal;
      case 'TCP':
        return Icons.settings_ethernet;
      case 'Unix Socket':
        return Icons.settings_input_component;
      default:
        return Icons.link;
    }
  }

  void _openPsqlTerminal(BuildContext context, String serviceName) {
    // Build the uc exec command: uc --context <context> exec <service> psql -U postgres
    final cmd = ['uc', '--context', widget.contextName, 'exec', serviceName, 'psql', '-U', 'postgres'];
    final navigator = Navigator.of(context);
    navigator.pop(); // Close the dialog
    // Use the root navigator to push the terminal screen
    navigator.push(
      MaterialPageRoute(
        builder: (_) => SshTerminalScreen(
          host: '',
          username: '',
          localCommand: cmd,
          titleOverride: 'psql://$serviceName [${widget.contextName}]',
        ),
      ),
    );
  }
}