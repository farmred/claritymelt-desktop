import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/models.dart';
import '../providers/app_providers.dart';
import '../theme/app_theme.dart';
import '../widgets/notes_and_tasks_section.dart';
import 'machine_detail_screen.dart';

class DomainDetailScreen extends ConsumerWidget {
  final DomainInfo domain;

  const DomainDetailScreen({super.key, required this.domain});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dnsMapAsync = ref.watch(dnsMapProvider);

    // Find DNS records pointing to this domain
    final dnsRecords = dnsMapAsync.value?.values.expand((r) => r).where((r) => r.zoneName == domain.name).toList() ?? <DnsRecordInfo>[];

    // Check for root A/CNAME records
    final hasRootA = dnsRecords.any((r) => (r.type == 'A' || r.type == 'AAAA') && (r.name == '@' || r.name == domain.name));
    final hasRootCname = dnsRecords.any((r) => r.type == 'CNAME' && (r.name == '@' || r.name == domain.name));

    // Find machines that have IPs pointing to this domain
    final machinesAsync = ref.watch(machinesProvider);
    final linkedMachines = <MachineInfo>[];
    if (machinesAsync.hasValue && dnsMapAsync.hasValue) {
      final dnsMap = dnsMapAsync.value!;
      for (final machine in machinesAsync.value!) {
        for (final ip in machine.ipAddresses) {
          final records = dnsMap[ip] ?? [];
          if (records.any((r) => r.zoneName == domain.name)) {
            linkedMachines.add(machine);
            break;
          }
        }
      }
    }

    return Scaffold(
      appBar: AppBar(
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.language, size: 20),
            const SizedBox(width: 8),
            Flexible(child: Text(domain.name, overflow: TextOverflow.ellipsis)),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () => ref.read(domainsProvider.notifier).refresh(),
            tooltip: 'Sync Live',
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          Text(
            'Domain details, DNS configuration, and linked infrastructure',
            style: TextStyle(fontSize: 13, color: AppColors.secondary.withValues(alpha: 0.7), fontFamily: AppTheme.bodyFont),
          ),
          const SizedBox(height: 20),

          // ── Status header ──
          _StatusHeader(domain: domain),
          const SizedBox(height: 16),

          // ── Summary cards ──
          Row(
            children: [
              Expanded(
                child: StatCard(
                  label: 'PROVIDER',
                  value: domain.providerLabel,
                  valueColor: AppTheme.providerColor(domain.provider),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: StatCard(
                  label: 'DNS',
                  value: domain.effectiveDnsProvider.toUpperCase(),
                  valueColor: AppTheme.providerColor(domain.effectiveDnsProvider),
                ),
              ),
              if (domain.cfStatus != null) ...[
                const SizedBox(width: 12),
                Expanded(
                  child: StatCard(
                    label: 'STATUS',
                    value: domain.cfStatus!.toUpperCase(),
                    valueColor: domain.cfStatus == 'active' ? AppColors.success : AppColors.warning,
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 16),

          // ── Root DNS validation ──
          if (!hasRootA && !hasRootCname) ...[
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.warning.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(4),
                border: Border.all(color: AppColors.warning.withValues(alpha: 0.3)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.warning_amber, size: 16, color: AppColors.warning),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'No root A or CNAME record found for this domain. '
                      'The domain may not resolve correctly.',
                      style: TextStyle(fontSize: 12, color: AppColors.warning, fontFamily: AppTheme.bodyFont),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
          ],

          // ── Nameserver mismatch warning ──
          if (domain.nameserverMismatch) ...[
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.warning.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(4),
                border: Border.all(color: AppColors.warning.withValues(alpha: 0.3)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.warning_amber, size: 16, color: AppColors.warning),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Nameserver Mismatch',
                          style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.warning, fontFamily: AppTheme.bodyFont),
                        ),
                        Text(
                          "Nameservers don't point to ${domain.effectiveDnsProvider == 'cloudflare' ? 'Cloudflare' : 'provider'}. DNS may not be active.",
                          style: TextStyle(fontSize: 12, color: AppColors.secondary, fontFamily: AppTheme.bodyFont),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
          ],

          // ── Nameservers ──
          if (domain.nameservers.isNotEmpty || domain.cfNameservers.isNotEmpty) ...[
            Card(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.dns, size: 18, color: AppColors.tertiary),
                        const SizedBox(width: 8),
                        const Text('NAMESERVERS', style: AppTheme.labelStyle),
                      ],
                    ),
                    const SizedBox(height: 16),
                    if (domain.nameservers.isNotEmpty) ...[
                      const Text('Registrar Nameservers', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: AppColors.secondary, fontFamily: AppTheme.bodyFont, letterSpacing: 1.2)),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 4,
                        runSpacing: 4,
                        children: domain.nameservers.map((ns) => CodeBlock(text: ns)).toList(),
                      ),
                    ],
                    if (domain.cfNameservers.isNotEmpty) ...[
                      const SizedBox(height: 16),
                      const Text('Cloudflare Nameservers', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: AppColors.secondary, fontFamily: AppTheme.bodyFont, letterSpacing: 1.2)),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 4,
                        runSpacing: 4,
                        children: domain.cfNameservers.map((ns) => CodeBlock(text: ns)).toList(),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
          ],

          // ── Zone info ──
          if (domain.cfZoneId != null || domain.expires != null) ...[
            Card(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.info_outline, size: 18, color: AppColors.tertiary),
                        const SizedBox(width: 8),
                        const Text('ZONE INFO', style: AppTheme.labelStyle),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Wrap(
                      spacing: 24,
                      runSpacing: 12,
                      children: [
                        if (domain.cfZoneId != null)
                          _CopyableRow(icon: Icons.vpn_key, label: 'Zone ID', value: domain.cfZoneId!),
                        if (domain.expires != null)
                          _CopyableRow(icon: Icons.calendar_today, label: 'Expires', value: domain.expires!),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
          ],

          // ── Linked machines ──
          if (linkedMachines.isNotEmpty) ...[
            Card(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.computer, size: 18, color: AppColors.tertiary),
                        const SizedBox(width: 8),
                        const Text('LINKED MACHINES', style: AppTheme.labelStyle),
                      ],
                    ),
                    const SizedBox(height: 16),
                    ...linkedMachines.map((machine) => Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: InkWell(
                        onTap: () {
                          Navigator.of(context).push(
                            MaterialPageRoute(builder: (_) => MachineDetailScreen(machine: machine)),
                          );
                        },
                        borderRadius: BorderRadius.circular(4),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          decoration: BoxDecoration(
                            color: AppColors.surfaceVariant,
                            borderRadius: BorderRadius.circular(4),
                            border: Border.all(color: AppColors.outline),
                          ),
                          child: Row(
                            children: [
                              AppTheme.statusDot(machine.status, size: 8),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        Text(
                                          machine.displayName,
                                          style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500, fontFamily: AppTheme.bodyFont, color: AppColors.tertiary),
                                        ),
                                        const SizedBox(width: 4),
                                        Icon(Icons.open_in_new, size: 11, color: AppColors.tertiary.withValues(alpha: 0.6)),
                                      ],
                                    ),
                                    Text(
                                      machine.ipAddresses.join(', '),
                                      style: TextStyle(fontSize: 11, color: AppColors.secondary, fontFamily: AppTheme.bodyFont),
                                    ),
                                  ],
                                ),
                              ),
                              AppTheme.providerBadge(machine.provider),
                            ],
                          ),
                        ),
                      ),
                    )),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
          ],

          // ── DNS records quick view ──
          Card(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.list_alt, size: 18, color: AppColors.tertiary),
                      const SizedBox(width: 8),
                      const Text('DNS RECORDS', style: AppTheme.labelStyle),
                      const Spacer(),
                      if (domain.canManageDns)
                        FilledButton.icon(
                          onPressed: () {
                            ref.read(dnsRecordsProvider.notifier).selectDomain(domain);
                            // Navigate to DNS tab
                            Navigator.of(context).pop(); // Go back to main
                          },
                          icon: const Icon(Icons.open_in_new, size: 14),
                          label: const Text('VIEW DNS MANAGER'),
                          style: FilledButton.styleFrom(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                            textStyle: TextStyle(fontSize: 11, fontFamily: AppTheme.bodyFont, letterSpacing: 0.5),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  if (dnsRecords.isEmpty)
                    const Text(
                      'No DNS records found for this domain. Open the DNS Manager to view and manage records.',
                      style: TextStyle(fontSize: 13, color: AppColors.secondary, fontFamily: AppTheme.bodyFont),
                    )
                  else
                    ...dnsRecords.take(10).map((rec) => Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(
                          color: AppColors.surfaceVariant,
                          borderRadius: BorderRadius.circular(2),
                        ),
                        child: Row(
                          children: [
                            AppTheme.recordTypeBadge(rec.type),
                            const SizedBox(width: 8),
                            Text(rec.name, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, fontFamily: AppTheme.bodyFont)),
                            const Spacer(),
                            Text(rec.content, style: TextStyle(fontSize: 11, fontFamily: AppTheme.bodyFont, color: AppColors.secondary)),
                          ],
                        ),
                      ),
                    )),
                  if (dnsRecords.length > 10)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(
                        '+ ${dnsRecords.length - 10} more records',
                        style: TextStyle(fontSize: 12, color: AppColors.secondary, fontFamily: AppTheme.bodyFont),
                      ),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          // ── Notes & Tasks ──
          NotesAndTasksSection(resourceType: 'domain', resourceId: domain.name),
        ],
      ),
    );
  }
}

class _StatusHeader extends StatelessWidget {
  final DomainInfo domain;
  const _StatusHeader({required this.domain});

  @override
  Widget build(BuildContext context) {
    final dnsColor = AppTheme.providerColor(domain.effectiveDnsProvider);
    final statusColor = domain.cfStatus == 'active' ? AppColors.success : AppColors.warning;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: dnsColor.withValues(alpha: 0.12),
                border: Border.all(color: dnsColor, width: 2),
              ),
              child: const Icon(Icons.language, size: 28, color: AppColors.primary),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  GestureDetector(
                    onTap: () {
                      Clipboard.setData(ClipboardData(text: domain.name));
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('Copied: ${domain.name}')),
                      );
                    },
                    child: Row(
                      children: [
                        Flexible(
                          child: Text(
                            domain.name,
                            style: const TextStyle(fontFamily: AppTheme.displayFont, fontSize: 20, fontWeight: FontWeight.w700),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Icon(Icons.copy, size: 14, color: AppColors.secondary.withValues(alpha: 0.4)),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      AppTheme.providerBadge(domain.provider),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: dnsColor.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(2),
                        ),
                        child: Text(
                          'DNS: ${domain.effectiveDnsProvider.toUpperCase()}',
                          style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: dnsColor, fontFamily: AppTheme.bodyFont, letterSpacing: 0.5),
                        ),
                      ),
                      if (domain.cfStatus != null) ...[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: statusColor.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text(
                            domain.cfStatus!,
                            style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: statusColor),
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CopyableRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  const _CopyableRow({required this.icon, required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () {
        Clipboard.setData(ClipboardData(text: value));
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Copied: $value')));
      },
      borderRadius: BorderRadius.circular(4),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: AppColors.secondary),
            const SizedBox(width: 6),
            Text(label, style: AppTheme.labelStyle),
            const SizedBox(width: 8),
            Flexible(child: CodeBlock(text: value)),
            const SizedBox(width: 4),
            Icon(Icons.copy, size: 12, color: AppColors.secondary.withValues(alpha: 0.4)),
          ],
        ),
      ),
    );
  }
}