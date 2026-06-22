import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/models.dart';
import '../providers/app_providers.dart';
import '../theme/app_theme.dart';
import 'machine_detail_screen.dart';

class MachinesScreen extends ConsumerWidget {
  final VoidCallback? onNavigateToDns;
  const MachinesScreen({super.key, this.onNavigateToDns});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final machinesAsync = ref.watch(machinesProvider);
    final dnsMapAsync = ref.watch(dnsMapProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('MACHINES'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: OutlinedButton.icon(
              onPressed: () => ref.read(machinesProvider.notifier).refresh(),
              icon: const Icon(Icons.refresh, size: 16),
              label: const Text('SYNC'),
            ),
          ),
        ],
      ),
      body: machinesAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, _) => SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            children: [
              ErrorBanner(message: err.toString()),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: () => ref.read(machinesProvider.notifier).refresh(),
                icon: const Icon(Icons.refresh),
                label: const Text('RETRY'),
              ),
            ],
          ),
        ),
        data: (machines) {
          final dnsMap = dnsMapAsync.value ?? <String, List<DnsRecordInfo>>{};

          if (machines.isEmpty) {
            return const EmptyState(
              icon: Icons.dns,
              title: 'No machines found',
              subtitle: 'Add provider credentials in Providers to connect your VPS instances.',
            );
          }

          final running = machines.where((m) => m.isRunning).length;
          final ovhVps = machines.where((m) => m.provider == 'ovh-vps').length;
          final ovhDedicated = machines.where((m) => m.provider == 'ovh-dedicated').length;
          final ovhCloud = machines.where((m) => m.provider == 'ovh').length;
          final hetznerCount = machines.where((m) => m.provider == 'hetzner').length;

          return ListView(
            padding: const EdgeInsets.all(24),
            children: [
              Text(
                'VPS instances from OVH Cloud & Hetzner Cloud — linked to DNS records',
                style: TextStyle(fontSize: 13, color: AppColors.secondary.withValues(alpha: 0.7), fontFamily: AppTheme.bodyFont),
              ),
              const SizedBox(height: 20),

              // ── Summary cards ──
              Row(
                children: [
                  Expanded(child: StatCard(label: 'TOTAL', value: '${machines.length}')),
                  const SizedBox(width: 12),
                  Expanded(child: StatCard(label: 'RUNNING', value: '$running', valueColor: AppColors.success)),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _BreakdownCard(
                      label: 'SERVICES',
                      items: [
                        if (ovhCloud > 0) _BreakdownItem(icon: Icons.cloud_outlined, label: 'Cloud', count: ovhCloud, color: AppColors.ovh),
                        if (ovhVps > 0) _BreakdownItem(icon: Icons.dns_outlined, label: 'VPS', count: ovhVps, color: AppColors.ovh),
                        if (ovhDedicated > 0) _BreakdownItem(icon: Icons.storage, label: 'Ded', count: ovhDedicated, color: AppColors.ovh),
                        if (hetznerCount > 0) _BreakdownItem(icon: Icons.cloud_queue, label: 'Hetzner', count: hetznerCount, color: AppColors.hetzner),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),

              // ── Machine list ──
              ...machines.map((machine) {
                final machineDnsRecords = machine.ipAddresses
                    .expand((ip) => dnsMap[ip] ?? <DnsRecordInfo>[])
                    .toList();
                return _MachineCard(
                  machine: machine,
                  dnsRecords: machineDnsRecords,
                  onNavigateToDns: onNavigateToDns,
                );
              }),
            ],
          );
        },
      ),
    );
  }
}

class _MachineCard extends ConsumerWidget {
  final MachineInfo machine;
  final List<DnsRecordInfo> dnsRecords;
  final VoidCallback? onNavigateToDns;

  const _MachineCard({required this.machine, required this.dnsRecords, this.onNavigateToDns});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final aliases = ref.watch(machineAliasesProvider);
    final alias = aliases[machine.id] ?? machine.alias ?? '';
    final productsAsync = ref.watch(productsProvider);
    final products = productsAsync.value ?? [];
    final machineProducts = products.where((p) => p.resources.any((r) => r.resourceType == 'machine' && r.resourceId == machine.id)).toList();
    final productNames = machineProducts.map((p) => p.name).toList();

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Card(
        child: InkWell(
          onTap: () {
            Navigator.of(context).push(
              MaterialPageRoute(builder: (context) => MachineDetailScreen(machine: machine, onNavigateToDns: (_) {
                Navigator.of(context).pop();
                onNavigateToDns?.call();
              })),
            );
          },
          borderRadius: BorderRadius.circular(4),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ── Machine info (left) ──
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Header row: status dot + name (copyable) + badges
                      Row(
                        children: [
                          AppTheme.statusDot(machine.status, size: 10),
                          const SizedBox(width: 10),
                          // Tappable name → copies to clipboard
                          GestureDetector(
                            onTap: () {
                              Clipboard.setData(ClipboardData(text: machine.name));
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(content: Text('Copied: ${machine.name}')),
                              );
                            },
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  machine.name,
                                  style: const TextStyle(fontFamily: AppTheme.displayFont, fontSize: 15, fontWeight: FontWeight.w700, color: AppColors.primary),
                                  overflow: TextOverflow.ellipsis,
                                ),
                                const SizedBox(width: 4),
                                Icon(Icons.copy, size: 12, color: AppColors.secondary.withValues(alpha: 0.3)),
                              ],
                            ),
                          ),
                          if (alias.isNotEmpty) ...[
                            const SizedBox(width: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                              decoration: BoxDecoration(
                                color: AppColors.tertiary.withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(2),
                              ),
                              child: Text(alias, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: AppColors.tertiary, fontFamily: AppTheme.bodyFont)),
                            ),
                          ],
                          const SizedBox(width: 8),
                          AppTheme.providerBadge(machine.provider),
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(
                              color: AppColors.surfaceVariant,
                              borderRadius: BorderRadius.circular(2),
                            ),
                            child: Text(
                              machine.status.toUpperCase(),
                              style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, letterSpacing: 0.5, color: AppColors.secondary, fontFamily: AppTheme.bodyFont),
                            ),
                          ),
                          if (machine.flavor != null || machine.commercialRange != null) ...[
                            const SizedBox(width: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: AppColors.primary.withValues(alpha: 0.08),
                                borderRadius: BorderRadius.circular(2),
                                border: Border.all(color: AppColors.primary.withValues(alpha: 0.2)),
                              ),
                              child: Text(
                                machine.machineTypeTag,
                                style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: AppColors.primary, fontFamily: AppTheme.bodyFont),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 4),
                      // Copyable ID line
                      GestureDetector(
                        onTap: () {
                          Clipboard.setData(ClipboardData(text: machine.id));
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text('Copied ID: ${machine.id}')),
                          );
                        },
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.fingerprint, size: 11, color: AppColors.secondary),
                            const SizedBox(width: 3),
                            Text(machine.id, style: TextStyle(fontFamily: AppTheme.bodyFont, fontSize: 10, color: AppColors.secondary.withValues(alpha: 0.5))),
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),

                      // ── Products ──
                      if (productNames.isNotEmpty) ...[
                        Row(
                          children: [
                            const Icon(Icons.folder_special, size: 14, color: AppColors.tertiary),
                            const SizedBox(width: 4),
                            Flexible(child: Text(productNames.join(', '), style: TextStyle(fontSize: 12, color: AppColors.tertiary, fontFamily: AppTheme.bodyFont, fontWeight: FontWeight.w500), overflow: TextOverflow.ellipsis)),
                          ],
                        ),
                        const SizedBox(height: 8),
                      ],

                      // ── UC Context ──
                      if (machine.uncloudContext != null && machine.uncloudContext!.isNotEmpty) ...[
                        Row(
                          children: [
                            const Icon(Icons.cloud_outlined, size: 14, color: AppColors.success),
                            const SizedBox(width: 4),
                            Text('UC: ', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.success, fontFamily: AppTheme.bodyFont)),
                            Flexible(child: Text(machine.uncloudContext!, style: TextStyle(fontSize: 12, color: AppColors.success, fontFamily: AppTheme.bodyFont), overflow: TextOverflow.ellipsis)),
                          ],
                        ),
                        const SizedBox(height: 8),
                      ],

                      // ── Service type + specs ──
                      if (machine.hasSpecs || machine.serviceTypeLabel.isNotEmpty) ...[
                        Row(
                          children: [
                            _ServiceTypeIcon(provider: machine.provider, size: 14, color: AppColors.secondary),
                            const SizedBox(width: 4),
                            Text(
                              machine.serviceTypeLabel,
                              style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 0.5, fontFamily: AppTheme.bodyFont, color: AppColors.secondary),
                            ),
                            if (machine.specsSummary.isNotEmpty) ...[
                              const SizedBox(width: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: AppColors.tertiary.withValues(alpha: 0.08),
                                  borderRadius: BorderRadius.circular(2),
                                  border: Border.all(color: AppColors.tertiary.withValues(alpha: 0.2)),
                                ),
                                child: Text(
                                  machine.specsSummary,
                                  style: TextStyle(fontSize: 11, fontFamily: AppTheme.bodyFont, color: AppColors.tertiary, fontWeight: FontWeight.w600),
                                ),
                              ),
                            ],
                            if (machine.monthlyCost != null) ...[
                              const SizedBox(width: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: AppColors.success.withValues(alpha: 0.1),
                                  borderRadius: BorderRadius.circular(2),
                                  border: Border.all(color: AppColors.success.withValues(alpha: 0.25)),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const Icon(Icons.payments, size: 11, color: AppColors.success),
                                    const SizedBox(width: 3),
                                    Text(
                                      machine.monthlyCostLabel,
                                      style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: AppColors.success, fontFamily: AppTheme.bodyFont),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ],
                        ),
                        const SizedBox(height: 8),
                      ],

                      // Details grid
                      Wrap(
                        spacing: 16,
                        runSpacing: 8,
                        children: [
                          ...machine.ipAddresses.map((ip) => Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.wifi, size: 14, color: AppColors.tertiary),
                              const SizedBox(width: 4),
                              CodeBlock(text: ip),
                            ],
                          )),
                          if (machine.flavor != null)
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(Icons.memory, size: 14, color: AppColors.secondary),
                                const SizedBox(width: 4),
                                Text(machine.flavor!, style: TextStyle(fontSize: 13, color: AppColors.secondary, fontFamily: AppTheme.bodyFont)),
                              ],
                            ),
                          if (machine.region.isNotEmpty)
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(Icons.location_on, size: 14, color: AppColors.secondary),
                                const SizedBox(width: 4),
                                Text(machine.region, style: TextStyle(fontSize: 13, color: AppColors.secondary, fontFamily: AppTheme.bodyFont)),
                              ],
                            ),
                          if (machine.image != null)
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(Icons.layers, size: 14, color: AppColors.secondary),
                                const SizedBox(width: 4),
                                Text(machine.image!, style: TextStyle(fontSize: 13, color: AppColors.secondary, fontFamily: AppTheme.bodyFont)),
                              ],
                            ),
                        ],
                      ),
                    ],
                  ),
                ),

                // ── DNS records panel (right) ──
                if (dnsRecords.isNotEmpty || machine.ipAddresses.isNotEmpty)
                  SizedBox(
                    width: 320,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Icon(Icons.language, size: 14, color: AppColors.secondary),
                            const SizedBox(width: 6),
                            const Text('DNS RECORDS', style: AppTheme.labelStyle),
                          ],
                        ),
                        const SizedBox(height: 10),
                        if (dnsRecords.isEmpty)
                          Text(
                            "No DNS records pointing to this machine's IPs",
                            style: TextStyle(fontSize: 12, color: AppColors.secondary.withValues(alpha: 0.5), fontFamily: AppTheme.bodyFont, fontStyle: FontStyle.italic),
                          )
                        else
                          ...dnsRecords.map((rec) => Padding(
                            padding: const EdgeInsets.only(bottom: 6),
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                              decoration: BoxDecoration(
                                color: AppColors.surfaceVariant,
                                borderRadius: BorderRadius.circular(2),
                              ),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Row(
                                    children: [
                                      AppTheme.recordTypeBadge(rec.type),
                                      const SizedBox(width: 8),
                                      Text(rec.name, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, fontFamily: AppTheme.bodyFont)),
                                    ],
                                  ),
                                  Text('→ ${rec.zoneName}', style: TextStyle(fontSize: 11, color: AppColors.secondary, fontFamily: AppTheme.bodyFont)),
                                ],
                              ),
                            ),
                          )),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Icon for the type of hosting service (VPS, Dedicated, Cloud Instance, etc.).
class _ServiceTypeIcon extends StatelessWidget {
  final String provider;
  final double size;
  final Color color;

  const _ServiceTypeIcon({required this.provider, this.size = 14, required this.color});

  @override
  Widget build(BuildContext context) {
    return Icon(AppTheme.serviceTypeIcon(provider), size: size, color: color);
  }
}

class _BreakdownItem {
  final IconData icon;
  final String label;
  final int count;
  final Color color;
  const _BreakdownItem({required this.icon, required this.label, required this.count, required this.color});
}

class _BreakdownCard extends StatelessWidget {
  final String label;
  final List<_BreakdownItem> items;
  const _BreakdownCard({required this.label, required this.items});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: AppTheme.labelStyle),
            const SizedBox(height: 8),
            ...items.map((item) => Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Row(
                children: [
                  Icon(item.icon, size: 14, color: item.color),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(item.label, style: TextStyle(fontSize: 13, color: AppColors.primary, fontFamily: AppTheme.bodyFont)),
                  ),
                  Text('${item.count}', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: item.color, fontFamily: AppTheme.displayFont)),
                ],
              ),
            )),
          ],
        ),
      ),
    );
  }
}