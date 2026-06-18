import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/models.dart';
import '../providers/app_providers.dart';
import '../theme/app_theme.dart';
import 'domain_detail_screen.dart';

class DomainsScreen extends ConsumerStatefulWidget {
  final VoidCallback? onNavigateToDns;

  const DomainsScreen({super.key, this.onNavigateToDns});

  @override
  ConsumerState<DomainsScreen> createState() => _DomainsScreenState();
}

class _DomainsScreenState extends ConsumerState<DomainsScreen> {
  int _tabIndex = 0; // 0 = Active (managed DNS), 1 = All

  @override
  Widget build(BuildContext context) {
    final domainsAsync = ref.watch(domainsProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Domains'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: OutlinedButton.icon(
              onPressed: () => ref.read(domainsProvider.notifier).refresh(),
              icon: const Icon(Icons.refresh, size: 16),
              label: const Text('Sync Live'),
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          // ── Tab bar + actions ──
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 16, 24, 0),
            child: Row(
              children: [
                ChoiceChip(
                  label: const Text('Active'),
                  selected: _tabIndex == 0,
                  onSelected: (_) => setState(() => _tabIndex = 0),
                  selectedColor: AppColors.success.withValues(alpha: 0.15),
                ),
                const SizedBox(width: 8),
                ChoiceChip(
                  label: const Text('All'),
                  selected: _tabIndex == 1,
                  onSelected: (_) => setState(() => _tabIndex = 1),
                  selectedColor: AppColors.primary.withValues(alpha: 0.15),
                ),
                const Spacer(),
                FilledButton.icon(
                  onPressed: () {
                    showDialog(context: context, builder: (ctx) => const ProvisionDomainDialog());
                  },
                  icon: const Icon(Icons.add, size: 16),
                  label: const Text('Provision Domain'),
                ),
              ],
            ),
          ),
          const SizedBox(height: 4),

          // ── Description ──
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 4, 24, 12),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'DNS zones and domains scoped to your organization',
                style: const TextStyle(fontSize: 14, color: AppColors.secondary),
              ),
            ),
          ),

          // ── Domain list ──
          Expanded(
            child: domainsAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (err, _) => SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: Column(
                  children: [
                    ErrorBanner(message: err.toString()),
                    const SizedBox(height: 16),
                    FilledButton.icon(
                      onPressed: () => ref.read(domainsProvider.notifier).refresh(),
                      icon: const Icon(Icons.refresh),
                      label: const Text('Retry'),
                    ),
                  ],
                ),
              ),
              data: (domains) {
                final filtered = _tabIndex == 0
                    ? domains.where((d) => d.canManageDns).toList()
                    : domains;

                if (filtered.isEmpty) {
                  return EmptyState(
                    icon: _tabIndex == 0 ? Icons.dns : Icons.language,
                    title: _tabIndex == 0 ? 'No active domains' : 'No domains found',
                    subtitle: _tabIndex == 0
                        ? 'Domains with managed DNS (Cloudflare, OVH, Namecheap) will appear here.'
                        : 'Add Cloudflare, OVH, or Namecheap credentials in Providers to see your domains.',
                  );
                }

                return ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  itemCount: filtered.length,
                  itemBuilder: (context, index) {
                    final domain = filtered[index];
                    return _DomainCard(
                      domain: domain,
                      onViewDns: () {
                        ref.read(dnsRecordsProvider.notifier).selectDomain(domain);
                        widget.onNavigateToDns?.call();
                      },
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _DomainCard extends ConsumerWidget {
  final DomainInfo domain;
  final VoidCallback? onViewDns;

  const _DomainCard({required this.domain, this.onViewDns});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dnsProviderColor = AppTheme.providerColor(domain.effectiveDnsProvider);

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Card(
        child: InkWell(
          onTap: () {
            Navigator.of(context).push(
              MaterialPageRoute(builder: (context) => DomainDetailScreen(domain: domain)),
            );
          },
          borderRadius: BorderRadius.circular(4),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ── Header row ──
                Row(
                  children: [
                    const Icon(Icons.language, size: 20, color: AppColors.primary),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        domain.name,
                        style: const TextStyle(
                          fontFamily: 'WorkSans',
                          fontSize: 17,
                          fontWeight: FontWeight.w700,
                          color: AppColors.onSurface,
                        ),
                      ),
                    ),
                    AppTheme.providerBadge(domain.provider),
                    if (domain.cfStatus != null) ...[
                      const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: domain.cfStatus == 'active'
                            ? AppColors.success.withValues(alpha: 0.1)
                            : AppColors.warning.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        domain.cfStatus!,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: domain.cfStatus == 'active' ? AppColors.success : AppColors.warning,
                        ),
                      ),
                    ),
                  ],
                    const SizedBox(width: 8),
                    const Icon(Icons.chevron_right, size: 16, color: AppColors.secondary),
                  ],
                ),
                const SizedBox(height: 14),

              // ── DNS provider + View DNS button ──
              Row(
                children: [
                  Icon(Icons.dns, size: 14, color: dnsProviderColor),
                  const SizedBox(width: 4),
                  Text(
                    'DNS: ${domain.effectiveDnsProvider.toUpperCase()}',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: dnsProviderColor),
                  ),
                  if (domain.canManageDns) ...[
                    const SizedBox(width: 12),
                    FilledButton.icon(
                      onPressed: onViewDns ??
                          () {
                            ref.read(dnsRecordsProvider.notifier).selectDomain(domain);
                          },
                      icon: const Icon(Icons.open_in_new, size: 14),
                      label: const Text('View DNS'),
                      style: FilledButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                        textStyle: const TextStyle(fontSize: 12),
                      ),
                    ),
                  ],
                  const Spacer(),
                  OutlinedButton.icon(
                    onPressed: () => _showAddToProductDialog(context, ref, domain.name, 'domain'),
                    icon: const Icon(Icons.folder_special, size: 14),
                    label: const Text('Add to Product'),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      textStyle: const TextStyle(fontSize: 11),
                    ),
                  ),
                ],
              ),

              // ── Nameserver mismatch warning ──
              if (domain.nameserverMismatch) ...[
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: AppColors.warning.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: AppColors.warning.withValues(alpha: 0.3)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.warning_amber, size: 16, color: AppColors.warning),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          "Nameservers don't point to ${domain.effectiveDnsProvider == 'cloudflare' ? 'Cloudflare' : 'provider'}. DNS may not be active.",
                          style: const TextStyle(fontSize: 12, color: AppColors.warning),
                        ),
                      ),
                    ],
                  ),
                ),
              ],

              // ── Nameservers ──
              if (domain.nameservers.isNotEmpty) ...[
                const SizedBox(height: 12),
                const Text('Nameservers', style: AppTheme.labelStyle),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 4,
                  runSpacing: 4,
                  children: domain.nameservers.map((ns) => CodeBlock(text: ns)).toList(),
                ),
              ],

              // ── Meta info ──
              if (domain.expires != null || domain.cfZoneId != null) ...[
                const SizedBox(height: 12),
                Row(
                  children: [
                    if (domain.expires != null) ...[
                      const Text('Expires: ', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.secondary)),
                      Text(domain.expires!, style: const TextStyle(fontSize: 12)),
                      const SizedBox(width: 16),
                    ],
                    if (domain.cfZoneId != null) ...[
                      const Text('Zone ID: ', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.secondary)),
                      CodeBlock(text: domain.cfZoneId!, backgroundColor: AppColors.codeBackground),
                    ],
                  ],
                ),
              ],

              ],
            ),
          ),
        ),
      ),
    );
  }
}

class ProvisionDomainDialog extends ConsumerStatefulWidget {
  const ProvisionDomainDialog({super.key});

  @override
  ConsumerState<ProvisionDomainDialog> createState() => _ProvisionDomainDialogState();
}

class _ProvisionDomainDialogState extends ConsumerState<ProvisionDomainDialog> {
  final _domainController = TextEditingController();
  final _ipController = TextEditingController();
  final _subdomainController = TextEditingController();
  bool _proxied = false;
  bool _updateNs = true;
  bool _submitting = false;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Row(
        children: [
          Icon(Icons.add_circle, color: AppColors.primary),
          SizedBox(width: 8),
          Text('Provision Domain', style: TextStyle(fontFamily: 'WorkSans')),
        ],
      ),
      content: SizedBox(
        width: 400,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Create a Cloudflare zone, add an A record, and optionally update nameservers. Uses your configured credentials.',
              style: TextStyle(fontSize: 13, color: AppColors.secondary),
            ),
            const SizedBox(height: 20),
            TextField(
              controller: _domainController,
              decoration: const InputDecoration(
                labelText: 'Domain Name',
                hintText: 'example.com',
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _ipController,
              decoration: const InputDecoration(
                labelText: 'Machine IP Address',
                hintText: '192.168.1.1',
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _subdomainController,
              decoration: const InputDecoration(
                labelText: 'Subdomain (optional)',
                hintText: 'www or leave empty for root',
              ),
            ),
            const SizedBox(height: 16),
            SwitchListTile(
              title: const Text('Proxy through Cloudflare'),
              value: _proxied,
              onChanged: (v) => setState(() => _proxied = v),
              dense: true,
              contentPadding: EdgeInsets.zero,
            ),
            SwitchListTile(
              title: const Text('Update Namecheap nameservers'),
              value: _updateNs,
              onChanged: (v) => setState(() => _updateNs = v),
              dense: true,
              contentPadding: EdgeInsets.zero,
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _submitting ? null : _handleSubmit,
          child: _submitting
              ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
              : const Text('Provision'),
        ),
      ],
    );
  }

  Future<void> _handleSubmit() async {
    if (_domainController.text.isEmpty || _ipController.text.isEmpty) return;

    setState(() => _submitting = true);
    try {
      await ref.read(domainsProvider.notifier).provisionDomain(
            domain: _domainController.text,
            machineIp: _ipController.text,
            subdomain: _subdomainController.text.isEmpty ? null : _subdomainController.text,
            proxied: _proxied,
            updateNameservers: _updateNs,
          );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${_domainController.text} provisioned successfully!')),
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
void _showAddToProductDialog(BuildContext context, WidgetRef ref, String resourceId, String resourceType) {
  showDialog(
    context: context,
    builder: (ctx) => _AddDomainToProductDialog(
      resourceId: resourceId,
      resourceType: resourceType,
    ),
  );
}

class _AddDomainToProductDialog extends ConsumerStatefulWidget {
  final String resourceId;
  final String resourceType;

  const _AddDomainToProductDialog({required this.resourceId, required this.resourceType});

  @override
  ConsumerState<_AddDomainToProductDialog> createState() => _AddDomainToProductDialogState();
}

class _AddDomainToProductDialogState extends ConsumerState<_AddDomainToProductDialog> {
  String? _selectedProductId;
  bool _submitting = false;

  @override
  Widget build(BuildContext context) {
    final productsAsync = ref.watch(productsProvider);

    return AlertDialog(
      title: const Text('Add to Product', style: TextStyle(fontFamily: 'WorkSans')),
      content: SizedBox(
        width: 400,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Add ${widget.resourceType} "${widget.resourceId}" to a product:',
              style: const TextStyle(fontSize: 13, color: AppColors.secondary),
            ),
            const SizedBox(height: 16),
            productsAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (_, __) => const Text('Error loading products'),
              data: (products) {
                if (products.isEmpty) {
                  return const Text('No products yet. Create one first.', style: TextStyle(color: AppColors.secondary));
                }
                return DropdownButtonFormField<String>(
                  initialValue: _selectedProductId,
                  decoration: const InputDecoration(labelText: 'Product'),
                  items: products.map((p) => DropdownMenuItem(value: p.id, child: Text(p.name))).toList(),
                  onChanged: (v) => setState(() => _selectedProductId = v),
                );
              },
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(
          onPressed: _submitting || _selectedProductId == null ? null : _handleSubmit,
          child: _submitting
              ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
              : const Text('Add'),
        ),
      ],
    );
  }

  Future<void> _handleSubmit() async {
    if (_selectedProductId == null) return;
    setState(() => _submitting = true);
    try {
      await ref.read(productsProvider.notifier).addResource(
            productId: _selectedProductId!,
            resourceType: widget.resourceType,
            resourceId: widget.resourceId,
          );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Added to product!')));
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed: $e'), backgroundColor: AppColors.danger));
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }
}
