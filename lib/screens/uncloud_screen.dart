/// Uncloud cluster overview screen.
///
/// Shows current UC contexts, machines per context, and deployed services/images.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/app_providers.dart';
import '../services/uncloud_service.dart';
import '../theme/app_theme.dart';
import 'uncloud_context_dialog.dart';

class UncloudScreen extends ConsumerWidget {
  const UncloudScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final configAsync = ref.watch(uncloudConfigProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('UNCLOUD'),
        actions: [
          IconButton(
            icon: const Icon(Icons.sync, size: 18),
            tooltip: 'Sync machine IDs',
            onPressed: () => ref.invalidate(uncloudSyncProvider),
          ),
          IconButton(
            icon: const Icon(Icons.refresh, size: 18),
            tooltip: 'Refresh live data',
            onPressed: () {
              ref.invalidate(uncloudRunningServicesProvider);
              ref.invalidate(uncloudRunningMachinesProvider);
              ref.invalidate(uncloudClusterDomainProvider);
              ref.invalidate(uncloudContainersForIpProvider);
            },
          ),
        ],
      ),
      body: configAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, st) => SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            children: [
              ErrorBanner(message: 'Failed to load Uncloud config: $err'),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: () => ref.invalidate(uncloudConfigProvider),
                icon: const Icon(Icons.refresh),
                label: const Text('RETRY'),
              ),
            ],
          ),
        ),
        data: (config) {
          if (config == null) {
            return _buildNoConfig(context);
          }
          return _buildConfigured(context, ref, config);
        },
      ),
    );
  }

  Widget _buildNoConfig(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(48),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.cloud_off, size: 64, color: AppColors.secondary),
            const SizedBox(height: 16),
            const Text('No Uncloud Config Found', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, fontFamily: AppTheme.displayFont)),
            const SizedBox(height: 8),
            Text(
              'Place your Uncloud config at:\n~/.config/uncloud/config.yaml\n\n'
              'Run `uc machine init` to create one.',
              style: TextStyle(fontSize: 13, color: AppColors.secondary, fontFamily: AppTheme.bodyFont, height: 1.6),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: () => debugPrint('Navigate to setup'),
              icon: const Icon(Icons.help_outline, size: 16),
              label: const Text('SETUP GUIDE'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildConfigured(BuildContext context, WidgetRef ref, UncloudConfig config) {
    final machinesAsync = ref.watch(uncloudRunningMachinesProvider);
    final servicesAsync = ref.watch(uncloudRunningServicesProvider);
    final domainAsync = ref.watch(uncloudClusterDomainProvider);
    final syncAsync = ref.watch(uncloudSyncProvider);

    return RefreshIndicator(
      onRefresh: () async {
        ref.invalidate(uncloudConfigProvider);
        ref.invalidate(uncloudRunningMachinesProvider);
        ref.invalidate(uncloudRunningServicesProvider);
        ref.invalidate(uncloudClusterDomainProvider);
        ref.invalidate(uncloudSyncProvider);
      },
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Overview stats ──
            _buildOverviewRow(config, domainAsync, syncAsync),
            const SizedBox(height: 24),

            // ── Contexts ──
            const Text('CONTEXTS', style: AppTheme.labelStyle),
            const SizedBox(height: 8),
            ...config.contexts.entries.map((entry) => _buildContextCard(context, ref, entry.key, entry.value, config.currentContext)),
            const SizedBox(height: 24),

            // ── Machines ──
            Row(
              children: [
                const Text('MACHINES', style: AppTheme.labelStyle),
                const Spacer(),
                machinesAsync.when(
                  loading: () => const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
                  error: (_, __) => const SizedBox.shrink(),
                  data: (m) => Text('${m.length} running', style: TextStyle(fontSize: 11, color: AppColors.secondary, fontFamily: AppTheme.bodyFont)),
                ),
              ],
            ),
            const SizedBox(height: 8),
            machinesAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (err, _) => ErrorBanner(message: 'Failed to list machines: $err'),
              data: (machines) {
                if (machines.isEmpty) {
                  return const Card(child: Padding(padding: EdgeInsets.all(16), child: Text('No machines running', style: TextStyle(fontSize: 13, color: AppColors.secondary, fontFamily: AppTheme.bodyFont))));
                }
                return Column(children: machines.map((m) => _buildMachineRow(m)).toList());
              },
            ),
            const SizedBox(height: 24),

            // ── Services / Images ──
            Row(
              children: [
                const Text('SERVICES', style: AppTheme.labelStyle),
                const Spacer(),
                servicesAsync.when(
                  loading: () => const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
                  error: (_, __) => const SizedBox.shrink(),
                  data: (s) => Text('${s.length} deployed', style: TextStyle(fontSize: 11, color: AppColors.secondary, fontFamily: AppTheme.bodyFont)),
                ),
              ],
            ),
            const SizedBox(height: 8),
            servicesAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (err, _) => ErrorBanner(message: 'Failed to list services: $err'),
              data: (services) {
                if (services.isEmpty) {
                  return const Card(child: Padding(padding: EdgeInsets.all(16), child: Text('No services deployed', style: TextStyle(fontSize: 13, color: AppColors.secondary, fontFamily: AppTheme.bodyFont))));
                }
                return Column(children: services.map((s) => _buildServiceRow(s)).toList());
              },
            ),
          ],
        ),
      ),
    );
  }

  // ── Overview ──────────────────────────────────────────────────────────

  Widget _buildOverviewRow(UncloudConfig config, AsyncValue<String?> domainAsync, AsyncValue<int> syncAsync) {
    return Row(
      children: [
        StatCard(
          label: 'CONTEXTS',
          value: '${config.contexts.length}',
          valueColor: AppColors.tertiary,
        ),
        const SizedBox(width: 12),
        StatCard(
          label: 'ACTIVE',
          value: config.currentContext,
        ),
        const SizedBox(width: 12),
        StatCard(
          label: 'CLUSTER DOMAIN',
          value: domainAsync.value ?? '—',
        ),
        const SizedBox(width: 12),
        StatCard(
          label: 'SYNCED',
          value: syncAsync.when(loading: () => '…', error: (_, __) => 'err', data: (n) => '$n'),
          valueColor: syncAsync.hasValue && syncAsync.value! > 0 ? AppColors.success : null,
        ),
      ],
    );
  }

  // ── Context card ────────────────────────────────────────────────────

  Widget _buildContextCard(BuildContext context, WidgetRef ref, String name, UncloudContext ctx, String activeName) {
    final isActive = name == activeName;
    final primary = ctx.primary;

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ExpansionTile(
        tilePadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
        iconColor: AppColors.secondary,
        collapsedIconColor: AppColors.secondary,
        title: Row(
          children: [
            Icon(Icons.dns, size: 16, color: isActive ? AppColors.tertiary : AppColors.secondary),
            const SizedBox(width: 8),
            InkWell(
              onTap: () => showUncloudContextDetailDialog(context: context, contextName: name, ctx: ctx, isActive: isActive),
              borderRadius: BorderRadius.circular(4),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(name, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, fontFamily: AppTheme.bodyFont, color: isActive ? AppColors.tertiary : AppColors.primary)),
                  const SizedBox(width: 4),
                  Icon(Icons.open_in_new, size: 12, color: isActive ? AppColors.tertiary : AppColors.secondary),
                ],
              ),
            ),
            const SizedBox(width: 8),
            if (isActive)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(color: AppColors.success.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(2)),
                child: const Text('ACTIVE', style: TextStyle(fontSize: 9, fontWeight: FontWeight.w700, color: AppColors.success, fontFamily: AppTheme.bodyFont, letterSpacing: 0.5)),
              ),
            const Spacer(),
            Text('${ctx.connections.length} connection${ctx.connections.length != 1 ? 's' : ''}', style: TextStyle(fontSize: 11, color: AppColors.secondary, fontFamily: AppTheme.bodyFont)),
          ],
        ),
        children: [
          if (primary != null) ...[
            const Text('PRIMARY CONNECTION', style: AppTheme.labelStyle),
            const SizedBox(height: 6),
            _buildConnectionRow(primary),
            if (ctx.connections.length > 1) ...[
              const SizedBox(height: 12),
              const Text('OTHER CONNECTIONS', style: AppTheme.labelStyle),
              const SizedBox(height: 6),
              ...ctx.connections.skip(1).map((c) => _buildConnectionRow(c)),
            ],
          ] else
            Text('No connections configured', style: TextStyle(fontSize: 13, color: AppColors.secondary, fontFamily: AppTheme.bodyFont)),
        ],
      ),
    );
  }

  Widget _buildConnectionRow(UncloudConnection conn) {
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.surfaceVariant,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: AppColors.outline),
      ),
      child: Row(
        children: [
          Icon(_connIcon(conn.typeLabel), size: 16, color: AppColors.tertiary),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(conn.sshTarget, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500, fontFamily: AppTheme.bodyFont)),
                if (conn.machineId != null)
                  Text('Machine ID: ${conn.machineId}', style: TextStyle(fontSize: 10, color: AppColors.secondary.withValues(alpha: 0.7), fontFamily: AppTheme.bodyFont)),
                if (conn.resolvedSshKeyFile != null)
                  Text('Key: ${conn.resolvedSshKeyFile}', style: TextStyle(fontSize: 10, color: AppColors.secondary.withValues(alpha: 0.7), fontFamily: AppTheme.bodyFont)),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: AppColors.tertiary.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(2),
            ),
            child: Text(conn.typeLabel, style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: AppColors.tertiary, fontFamily: AppTheme.bodyFont, letterSpacing: 0.5)),
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

  // ── Machine row ──────────────────────────────────────────────────────

  Widget _buildMachineRow(UncloudRunningMachine m) {
    return Card(
      margin: const EdgeInsets.only(bottom: 6),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            AppTheme.statusDot(m.state, size: 10),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(m.name, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, fontFamily: AppTheme.bodyFont)),
                      const SizedBox(width: 8),
                      CodeBlock(text: m.publicIp),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'WG: ${m.address}  •  ID: ${_shorten(m.machineId, 12)}',
                    style: TextStyle(fontSize: 11, color: AppColors.secondary.withValues(alpha: 0.7), fontFamily: AppTheme.bodyFont),
                  ),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: m.isUp ? AppColors.success.withValues(alpha: 0.1) : AppColors.danger.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(2),
              ),
              child: Text(
                m.state.toUpperCase(),
                style: TextStyle(
                  fontSize: 9,
                  fontWeight: FontWeight.w700,
                  color: m.isUp ? AppColors.success : AppColors.danger,
                  fontFamily: AppTheme.bodyFont,
                  letterSpacing: 0.5,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Service row ─────────────────────────────────────────────────────

  Widget _buildServiceRow(UncloudRunningService svc) {
    return Card(
      margin: const EdgeInsets.only(bottom: 6),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            Icon(svc.isPostgres ? Icons.storage : Icons.widgets, size: 18, color: svc.isPostgres ? AppColors.success : AppColors.secondary),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(svc.name, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, fontFamily: AppTheme.bodyFont)),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: AppColors.surfaceVariant,
                          borderRadius: BorderRadius.circular(2),
                        ),
                        child: Text('${svc.replicas}×', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: AppColors.secondary, fontFamily: AppTheme.bodyFont)),
                      ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(svc.image, style: TextStyle(fontSize: 11, color: AppColors.secondary.withValues(alpha: 0.7), fontFamily: AppTheme.bodyFont)),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: AppColors.tertiary.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(2),
              ),
              child: Text(svc.mode.toUpperCase(), style: TextStyle(fontSize: 9, fontWeight: FontWeight.w700, color: AppColors.tertiary, fontFamily: AppTheme.bodyFont, letterSpacing: 0.5)),
            ),
          ],
        ),
      ),
    );
  }

  String _shorten(String s, int len) => s.length > len ? '${s.substring(0, len)}…' : s;
}
