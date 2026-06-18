import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/models.dart';
import '../models/product_models.dart';
import '../providers/app_providers.dart';
import '../theme/app_theme.dart';

class DnsManagerScreen extends ConsumerStatefulWidget {
  const DnsManagerScreen({super.key});

  @override
  ConsumerState<DnsManagerScreen> createState() => _DnsManagerScreenState();
}

class _DnsManagerScreenState extends ConsumerState<DnsManagerScreen> {
  @override
  Widget build(BuildContext context) {
    final domainsAsync = ref.watch(domainsProvider);
    final selectedDomain = ref.watch(selectedDnsDomainProvider);
    final recordsAsync = ref.watch(dnsRecordsProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('DNS Records'),
        actions: [
          if (selectedDomain != null)
            Padding(
              padding: const EdgeInsets.only(right: 16),
              child: FilledButton.icon(
                onPressed: () => ref.read(dnsRecordsProvider.notifier).refresh(),
                icon: const Icon(Icons.refresh, size: 18),
                label: const Text('Sync Live'),
              ),
            ),
        ],
      ),
      body: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Domain list sidebar
          SizedBox(
            width: 280,
            child: _DomainSidebar(domainsAsync: domainsAsync, selectedDomain: selectedDomain),
          ),
          const VerticalDivider(thickness: 1, width: 1),
          // DNS records content
          Expanded(
            child: selectedDomain == null
                ? const Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.dns, size: 64, color: AppColors.outline),
                        SizedBox(height: 16),
                        Text('Select a domain to view its DNS records', style: TextStyle(color: AppColors.secondary)),
                      ],
                    ),
                  )
                : _DnsRecordsPanel(
                    domain: selectedDomain,
                    recordsAsync: recordsAsync,
                  ),
          ),
        ],
      ),
    );
  }
}

class _DomainSidebar extends StatelessWidget {
  final AsyncValue<List<DomainInfo>> domainsAsync;
  final DomainInfo? selectedDomain;

  const _DomainSidebar({required this.domainsAsync, required this.selectedDomain});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppColors.surface,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text(
              'Domains',
              style: Theme.of(context).textTheme.titleSmall?.copyWith(color: AppColors.secondary),
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: domainsAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (err, _) => Center(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text('Error: $err', style: const TextStyle(color: AppColors.danger, fontSize: 12)),
                ),
              ),
              data: (domains) {
                // Only show domains that can manage DNS
                final manageableDomains = domains.where((d) => d.canManageDns).toList();
                final nonManageable = domains.where((d) => !d.canManageDns).toList();

                if (domains.isEmpty) {
                  return const Center(
                    child: Padding(
                      padding: EdgeInsets.all(16),
                      child: Text(
                        'No domains found.\nAdd provider credentials first.',
                        style: TextStyle(color: AppColors.secondary, fontSize: 12),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  );
                }

                return ListView(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  children: [
                    if (manageableDomains.isNotEmpty) ...[
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        child: Text(
                          'MANAGEABLE',
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                            color: AppColors.secondary.withValues(alpha: 0.6),
                            letterSpacing: 1.2,
                          ),
                        ),
                      ),
                      ...manageableDomains.map((d) => _DomainTile(
                            domain: d,
                            isSelected: selectedDomain?.name == d.name,
                          )),
                    ],
                    if (nonManageable.isNotEmpty) ...[
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        child: Text(
                          'NO DNS ACCESS',
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                            color: AppColors.secondary.withValues(alpha: 0.6),
                            letterSpacing: 1.2,
                          ),
                        ),
                      ),
                      ...nonManageable.map((d) => _DomainTile(
                            domain: d,
                            isSelected: false,
                            disabled: true,
                          )),
                    ],
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _DomainTile extends ConsumerWidget {
  final DomainInfo domain;
  final bool isSelected;
  final bool disabled;

  const _DomainTile({required this.domain, required this.isSelected, this.disabled = false});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final providerColor = AppTheme.providerColor(domain.effectiveDnsProvider);

    return ListTile(
      dense: true,
      selected: isSelected,
      selectedTileColor: AppColors.primary.withValues(alpha: 0.08),
      enabled: !disabled,
      onTap: disabled
          ? null
          : () {
              ref.read(dnsRecordsProvider.notifier).selectDomain(domain);
            },
      title: Row(
        children: [
          Expanded(
            child: Text(
              domain.name,
              style: TextStyle(
                fontSize: 13,
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
                color: disabled ? AppColors.secondary.withValues(alpha: 0.5) : null,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
            decoration: BoxDecoration(
              color: providerColor.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              domain.effectiveDnsProvider.toUpperCase(),
              style: TextStyle(fontSize: 8, fontWeight: FontWeight.w700, color: providerColor),
            ),
          ),
        ],
      ),
      subtitle: disabled
          ? const Text('No DNS API access', style: TextStyle(fontSize: 10, color: AppColors.secondary))
          : Text(
              domain.effectiveDnsProvider == 'cloudflare' ? 'Cloudflare zone' : '${domain.effectiveDnsProvider.toUpperCase()} zone',
              style: const TextStyle(fontSize: 10, color: AppColors.secondary),
            ),
    );
  }
}

class _DnsRecordsPanel extends ConsumerWidget {
  final DomainInfo domain;
  final AsyncValue<List<DnsRecordInfo>> recordsAsync;

  const _DnsRecordsPanel({required this.domain, required this.recordsAsync});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return recordsAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (err, _) => Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, size: 48, color: AppColors.danger),
            const SizedBox(height: 16),
            Text('Error: $err', style: const TextStyle(color: AppColors.danger)),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: () => ref.read(dnsRecordsProvider.notifier).refresh(),
              icon: const Icon(Icons.refresh),
              label: const Text('Retry'),
            ),
          ],
        ),
      ),
      data: (records) {
        final isCloudflare = domain.effectiveDnsProvider == 'cloudflare';

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header showing selected domain info
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: AppColors.surface,
                border: Border(bottom: BorderSide(color: AppColors.outline)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.language, size: 24, color: AppColors.primary),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          domain.name,
                          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
                        ),
                        const SizedBox(height: 2),
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: AppTheme.providerColor(domain.effectiveDnsProvider).withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                'DNS via ${domain.effectiveDnsProvider.toUpperCase()}',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                  color: AppTheme.providerColor(domain.effectiveDnsProvider),
                                ),
                              ),
                            ),
                            if (domain.cfZoneId != null) ...[
                              const SizedBox(width: 8),
                              Text(
                                'Zone: ${domain.cfZoneId}',
                                style: const TextStyle(fontSize: 10, fontFamily: 'monospace', color: AppColors.secondary),
                              ),
                            ],
                            if (domain.expires != null) ...[
                              const SizedBox(width: 8),
                              Text(
                                'Expires: ${domain.expires}',
                                style: const TextStyle(fontSize: 11, color: AppColors.secondary),
                              ),
                            ],
                          ],
                        ),
                        if (domain.nameserverMismatch) ...[
                          const SizedBox(height: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                            decoration: BoxDecoration(
                              color: AppColors.warning.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: AppColors.warning.withValues(alpha: 0.3)),
                            ),
                            child: Row(
                              children: [
                                const Icon(Icons.warning_amber, size: 16, color: AppColors.warning),
                                const SizedBox(width: 6),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      const Text(
                                        'Nameserver Mismatch',
                                        style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.warning),
                                      ),
                                      const Text(
                                        "This domain's nameservers are not pointing to Cloudflare. DNS records may not be active.",
                                        style: TextStyle(fontSize: 11, color: AppColors.secondary),
                                      ),
                                      if (domain.cfNameservers.isNotEmpty) ...[
                                        const SizedBox(height: 4),
                                        Wrap(
                                          spacing: 4,
                                          runSpacing: 2,
                                          children: domain.cfNameservers.map((ns) => Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                                            decoration: BoxDecoration(
                                              color: AppColors.cloudflare.withValues(alpha: 0.1),
                                              borderRadius: BorderRadius.circular(4),
                                            ),
                                            child: Text(ns, style: const TextStyle(fontSize: 10, fontFamily: 'monospace', color: AppColors.cloudflare)),
                                          )).toList(),
                                        ),
                                      ],
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  if (isCloudflare)
                    FilledButton.icon(
                      onPressed: () {
                        _showCreateRecordDialog(context, ref);
                      },
                      icon: const Icon(Icons.add, size: 18),
                      label: const Text('Add Record'),
                    ),
                ],
              ),
            ),
            // Nameservers
            if (domain.nameservers.isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 12, 24, 0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Nameservers', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: AppColors.secondary)),
                    const SizedBox(height: 4),
                    Wrap(
                      spacing: 4,
                      runSpacing: 2,
                      children: domain.nameservers.map((ns) => Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: AppColors.neutral,
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(ns, style: const TextStyle(fontFamily: 'monospace', fontSize: 11)),
                          )).toList(),
                    ),
                  ],
                ),
              ),
            // Records table
            Expanded(
              child: records.isEmpty
                  ? const Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.content_paste, size: 64, color: AppColors.outline),
                          SizedBox(height: 16),
                          Text('No DNS records found for this domain.', style: TextStyle(color: AppColors.secondary)),
                        ],
                      ),
                    )
                  : SingleChildScrollView(
                      padding: const EdgeInsets.all(24),
                      scrollDirection: Axis.horizontal,
                      child: SizedBox(
                        width: MediaQuery.of(context).size.width - 340,
                        child: DataTable(
                          headingRowColor: WidgetStateProperty.all(AppColors.neutral),
                          columns: [
                            const DataColumn(label: Text('Type', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600))),
                            const DataColumn(label: Text('Name', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600))),
                            const DataColumn(label: Text('Content', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600))),
                            const DataColumn(label: Text('TTL', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600))),
                            if (isCloudflare)
                              const DataColumn(label: Text('Proxied', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600))),
                            const DataColumn(label: Text('Source', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600))),
                            if (isCloudflare)
                              const DataColumn(label: Text('Actions', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600))),
                          ],
                          rows: records.map((record) => DataRow(cells: [
                            DataCell(Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: AppColors.primary.withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                record.type,
                                style: const TextStyle(fontFamily: 'monospace', fontSize: 11, fontWeight: FontWeight.w700, color: AppColors.primary),
                              ),
                            )),
                            DataCell(Text(record.name, style: const TextStyle(fontWeight: FontWeight.w500))),
                            DataCell(Text(record.content, style: const TextStyle(fontFamily: 'monospace', fontSize: 12))),
                            DataCell(Text(record.ttlLabel, style: const TextStyle(color: AppColors.secondary))),
                            if (isCloudflare)
                              DataCell(record.proxied
                                  ? const Text('Yes', style: TextStyle(color: AppColors.success, fontWeight: FontWeight.w600, fontSize: 12))
                                  : const Text('No', style: TextStyle(color: AppColors.secondary, fontSize: 12))),
                            DataCell(Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: AppTheme.providerColor(record.provider).withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                record.providerLabel,
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w600,
                                  color: AppTheme.providerColor(record.provider),
                                ),
                              ),
                            )),
                            if (isCloudflare)
                              DataCell(IconButton(
                                icon: const Icon(Icons.delete_outline, size: 18, color: AppColors.danger),
                                onPressed: () => _confirmDelete(context, ref, record.id),
                              )),
                          ])).toList(),
                        ),
                      ),
                    ),
            ),

            // ── Cloudflare Workers & Pages ──
            if (isCloudflare) ...[
              const SizedBox(height: 16),
              _CloudflareWorkersPagesSection(domain: domain),
            ],
          ],
        );
      },
    );
  }

  void _confirmDelete(BuildContext context, WidgetRef ref, String recordId) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete DNS Record'),
        content: const Text('Are you sure you want to delete this DNS record?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.danger),
            onPressed: () async {
              Navigator.pop(ctx);
              try {
                await ref.read(dnsRecordsProvider.notifier).deleteRecord(recordId);
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Record deleted')),
                  );
                }
              } catch (e) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Failed: $e'), backgroundColor: AppColors.danger),
                  );
                }
              }
            },
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }

  void _showCreateRecordDialog(BuildContext context, WidgetRef ref) {
    showDialog(
      context: context,
      builder: (ctx) => CreateDnsRecordDialog(domain: domain),
    );
  }
}

class _CloudflareWorkersPagesSection extends ConsumerWidget {
  final DomainInfo domain;
  const _CloudflareWorkersPagesSection({required this.domain});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final workersAsync = ref.watch(workersProvider);
    final pagesAsync = ref.watch(pagesProvider);

    return ExpansionTile(
      tilePadding: const EdgeInsets.symmetric(horizontal: 0),
      childrenPadding: const EdgeInsets.only(top: 8),
      title: Row(
        children: [
          const Icon(Icons.cloud_queue, size: 18, color: AppColors.tertiary),
          const SizedBox(width: 8),
          const Text('WORKERS & PAGES', style: AppTheme.labelStyle),
        ],
      ),
      children: [
        // ── Workers ──
        workersAsync.when(
          loading: () => const Center(child: SizedBox(height: 24, child: CircularProgressIndicator(strokeWidth: 2))),
          error: (_, __) => const Padding(
            padding: EdgeInsets.only(bottom: 8),
            child: Text('Could not load Workers', style: TextStyle(color: AppColors.danger, fontFamily: AppTheme.bodyFont)),
          ),
          data: (workers) {
            if (workers.isEmpty) {
              return const Padding(
                padding: EdgeInsets.only(bottom: 8),
                child: Text('No Workers found', style: TextStyle(fontSize: 13, color: AppColors.secondary, fontFamily: AppTheme.bodyFont)),
              );
            }
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Workers', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, fontFamily: AppTheme.bodyFont, color: AppColors.secondary)),
                const SizedBox(height: 4),
                ...workers.map((w) => Container(
                  margin: const EdgeInsets.only(bottom: 4),
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: AppColors.surfaceVariant,
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(color: AppColors.outline),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.functions, size: 16, color: AppColors.secondary),
                      const SizedBox(width: 8),
                      Expanded(child: Text(w.name, style: const TextStyle(fontSize: 13, fontFamily: AppTheme.bodyFont))),
                      if (w.status != null)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                          decoration: BoxDecoration(
                            color: AppColors.tertiary.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(2),
                          ),
                          child: Text(w.status!, style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: AppColors.tertiary, fontFamily: AppTheme.bodyFont)),
                        ),
                    ],
                  ),
                )),
              ],
            );
          },
        ),
        const SizedBox(height: 8),
        // ── Pages ──
        pagesAsync.when(
          loading: () => const Center(child: SizedBox(height: 24, child: CircularProgressIndicator(strokeWidth: 2))),
          error: (_, __) => const Padding(
            padding: EdgeInsets.only(bottom: 8),
            child: Text('Could not load Pages projects', style: TextStyle(color: AppColors.danger, fontFamily: AppTheme.bodyFont)),
          ),
          data: (pages) {
            if (pages.isEmpty) {
              return const Padding(
                padding: EdgeInsets.only(bottom: 8),
                child: Text('No Pages projects found', style: TextStyle(fontSize: 13, color: AppColors.secondary, fontFamily: AppTheme.bodyFont)),
              );
            }
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Pages', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, fontFamily: AppTheme.bodyFont, color: AppColors.secondary)),
                const SizedBox(height: 4),
                ...pages.map((p) => Container(
                  margin: const EdgeInsets.only(bottom: 4),
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: AppColors.surfaceVariant,
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(color: AppColors.outline),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.web, size: 16, color: AppColors.tertiary),
                      const SizedBox(width: 8),
                      Expanded(child: Text(p.name, style: const TextStyle(fontSize: 13, fontFamily: AppTheme.bodyFont))),
                      if (p.subdomain != null)
                        Text(p.subdomain!, style: TextStyle(fontSize: 10, fontFamily: AppTheme.bodyFont, color: AppColors.secondary.withValues(alpha: 0.6))),
                    ],
                  ),
                )),
              ],
            );
          },
        ),
      ],
    );
  }
}

class CreateDnsRecordDialog extends ConsumerStatefulWidget {
  final DomainInfo domain;

  const CreateDnsRecordDialog({super.key, required this.domain});

  @override
  ConsumerState<CreateDnsRecordDialog> createState() => _CreateDnsRecordDialogState();
}

class _CreateDnsRecordDialogState extends ConsumerState<CreateDnsRecordDialog> {
  String _type = 'A';
  final _nameController = TextEditingController();
  final _contentController = TextEditingController();
  bool _proxied = false;
  bool _submitting = false;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('Add DNS Record — ${widget.domain.name}'),
      content: SizedBox(
        width: 400,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Creating record via ${widget.domain.effectiveDnsProvider.toUpperCase()}',
              style: const TextStyle(fontSize: 12, color: AppColors.secondary),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: _type,
              decoration: const InputDecoration(labelText: 'Record Type'),
              items: ['A', 'AAAA', 'CNAME', 'MX', 'TXT', 'SRV']
                  .map((t) => DropdownMenuItem(value: t, child: Text(t)))
                  .toList(),
              onChanged: (v) => setState(() => _type = v!),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _nameController,
              decoration: const InputDecoration(labelText: 'Name', hintText: '@ or subdomain'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _contentController,
              decoration: const InputDecoration(labelText: 'Content', hintText: 'IP address or hostname'),
            ),
            if (_type == 'A' && widget.domain.effectiveDnsProvider == 'cloudflare') ...[
              const SizedBox(height: 12),
              SwitchListTile(
                title: const Text('Proxy through Cloudflare'),
                value: _proxied,
                onChanged: (v) => setState(() => _proxied = v),
                dense: true,
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(
          onPressed: _submitting ? null : _handleSubmit,
          child: _submitting
              ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
              : const Text('Create Record'),
        ),
      ],
    );
  }

  Future<void> _handleSubmit() async {
    if (_nameController.text.isEmpty || _contentController.text.isEmpty) return;

    setState(() => _submitting = true);
    try {
      await ref.read(dnsRecordsProvider.notifier).createRecord(
            type: _type,
            name: _nameController.text,
            content: _contentController.text,
            proxied: _proxied,
          );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('DNS record created!')),
        );
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed: $e'), backgroundColor: AppColors.danger),
        );
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }
}