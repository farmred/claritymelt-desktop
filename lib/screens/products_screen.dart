import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/models.dart';
import '../models/product_models.dart';
import '../providers/app_providers.dart';
import '../theme/app_theme.dart';

import 'domain_detail_screen.dart';
import 'machine_detail_screen.dart';

/// Products screen showing grouped infrastructure resources as deployed services.
class ProductsScreen extends ConsumerStatefulWidget {
  const ProductsScreen({super.key});

  @override
  ConsumerState<ProductsScreen> createState() => _ProductsScreenState();
}

class _ProductsScreenState extends ConsumerState<ProductsScreen> {
  @override
  Widget build(BuildContext context) {
    final productsAsync = ref.watch(productsProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Products'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: FilledButton.icon(
              onPressed: () => _showCreateProductDialog(context),
              icon: const Icon(Icons.add, size: 18),
              label: const Text('New Product'),
            ),
          ),
        ],
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(24, 16, 24, 0),
            child: Text(
              'Products group your infrastructure into deployed services — linking machines, domains, '
              'DNS zones, Cloudflare Workers, and Pages together.',
              style: TextStyle(fontSize: 14, color: AppColors.secondary),
            ),
          ),
          const SizedBox(height: 16),
          Expanded(
            child: productsAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (err, _) => SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: Column(
                  children: [
                    ErrorBanner(message: err.toString()),
                    const SizedBox(height: 16),
                    FilledButton.icon(
                      onPressed: () => ref.read(productsProvider.notifier).refresh(),
                      icon: const Icon(Icons.refresh),
                      label: const Text('Retry'),
                    ),
                  ],
                ),
              ),
              data: (products) {
                if (products.isEmpty) {
                  return const EmptyState(
                    icon: Icons.inventory_2_outlined,
                    title: 'No products yet',
                    subtitle: 'Create a product to group your infrastructure resources together. '
                        'For example, "ClarityMelt API" might link a VPS, a Cloudflare zone, and a Worker.',
                  );
                }

                return ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  itemCount: products.length,
                  itemBuilder: (context, index) {
                    final product = products[index];
                    return _ProductCard(product: product);
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  void _showCreateProductDialog(BuildContext context) {
    showDialog(context: context, builder: (ctx) => const _CreateProductDialog());
  }
}

class _ProductCard extends ConsumerWidget {
  final ProductInfo product;
  const _ProductCard({required this.product});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Group resources by type
    final machines = product.resources.where((r) => r.resourceType == 'machine').toList();
    final domains = product.resources.where((r) => r.resourceType == 'domain').toList();
    final dnsZones = product.resources.where((r) => r.resourceType == 'dns_zone').toList();
    final workers = product.resources.where((r) => r.resourceType == 'cloudflare_worker').toList();
    final pages = product.resources.where((r) => r.resourceType == 'cloudflare_page').toList();

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Card(
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () {
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (context) => ProductDetailScreen(product: product),
              ),
            );
          },
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ── Header ──
                Row(
                  children: [
                    Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: AppColors.primary.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Center(
                        child: Icon(Icons.folder_special, size: 20, color: AppColors.primary),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(product.name,
                              style: const TextStyle(fontFamily: 'WorkSans', fontSize: 17, fontWeight: FontWeight.w700)),
                          if (product.description != null && product.description!.isNotEmpty)
                            Text(product.description!, style: const TextStyle(fontSize: 13, color: AppColors.secondary)),
                        ],
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: AppColors.tertiary.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        '${product.resources.length} resource${product.resources.length != 1 ? 's' : ''}',
                        style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: AppColors.tertiary),
                      ),
                    ),
                    const SizedBox(width: 8),
                    PopupMenuButton<String>(
                      itemBuilder: (ctx) => [
                        const PopupMenuItem(value: 'add_resource', child: Text('Add Resource')),
                        const PopupMenuItem(value: 'delete', child: Text('Delete Product', style: TextStyle(color: AppColors.danger))),
                      ],
                      onSelected: (action) async {
                        if (action == 'delete') {
                          final confirm = await showDialog<bool>(
                            context: context,
                            builder: (ctx) => AlertDialog(
                              title: const Text('Delete Product'),
                              content: Text('Are you sure you want to delete "${product.name}"?'),
                              actions: [
                                TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
                                FilledButton(
                                  style: FilledButton.styleFrom(backgroundColor: AppColors.danger),
                                  onPressed: () => Navigator.pop(ctx, true),
                                  child: const Text('Delete'),
                                ),
                              ],
                            ),
                          );
                          if (confirm == true) {
                            await ref.read(productsProvider.notifier).deleteProduct(product.id);
                          }
                        } else if (action == 'add_resource') {
                          _showAddResourceDialog(context, ref, product);
                        }
                      },
                    ),
                  ],
                ),

                // ── Resource sections ──
                if (machines.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  _MachineResourceSection(
                    machines: machines,
                    onMachineTap: (res) => _navigateToMachine(context, ref, res.resourceId),
                  ),
                ],
                if (domains.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  _ResourceSection(
                    icon: Icons.language,
                    label: 'Domains',
                    color: AppColors.tertiary,
                    resources: domains,
                    onResourceTap: (res) => _navigateToDomain(context, ref, res.resourceId),
                  ),
                ],
                if (dnsZones.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  _ResourceSection(
                    icon: Icons.dns,
                    label: 'DNS Zones',
                    color: AppColors.cloudflare,
                    resources: dnsZones,
                  ),
                ],
                if (workers.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  _ResourceSection(
                    icon: Icons.bolt,
                    label: 'Workers',
                    color: const Color(0xFFF6821F),
                    resources: workers,
                  ),
                ],
                if (pages.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  _ResourceSection(
                    icon: Icons.web,
                    label: 'Pages',
                    color: const Color(0xFF8B5CF6),
                    resources: pages,
                  ),
                ],
                // ── UC Context ──
                Builder(
                  builder: (context) {
                    final machinesList = ref.watch(machinesProvider).value ?? [];
                    final ucContexts = <String>{};
                    for (final mRes in machines) {
                      final m = machinesList.where((m) => m.id == mRes.resourceId).firstOrNull;
                      if (m != null && m.uncloudContext != null && m.uncloudContext!.isNotEmpty) {
                        ucContexts.add(m.uncloudContext!);
                      }
                    }
                    if (ucContexts.isEmpty) return const SizedBox.shrink();
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            const Icon(Icons.cloud_outlined, size: 14, color: AppColors.success),
                            const SizedBox(width: 6),
                            const Text('UC CONTEXTS', style: AppTheme.labelStyle),
                            const SizedBox(width: 8),
                            ...ucContexts.map((ctx) => Padding(
                              padding: const EdgeInsets.only(right: 6),
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                decoration: BoxDecoration(
                                  color: AppColors.success.withValues(alpha: 0.1),
                                  borderRadius: BorderRadius.circular(4),
                                  border: Border.all(color: AppColors.success.withValues(alpha: 0.3)),
                                ),
                                child: Text(ctx, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: AppColors.success, fontFamily: AppTheme.bodyFont)),
                              ),
                            )),
                          ],
                        ),
                      ],
                    );
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _showAddResourceDialog(BuildContext context, WidgetRef ref, ProductInfo product) {
    showDialog(
      context: context,
      builder: (ctx) => _AddResourceDialog(product: product),
    );
  }

  void _navigateToMachine(BuildContext context, WidgetRef ref, String machineId) {
    final machines = ref.read(machinesProvider).value ?? [];
    final machine = machines.firstWhere(
      (m) => m.id == machineId,
      orElse: () => MachineInfo(
        id: machineId,
        name: machineId,
        provider: 'unknown',
        status: 'unknown',
        ipAddresses: [],
        region: '',
      ),
    );
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => MachineDetailScreen(machine: machine)),
    );
  }

  void _navigateToDomain(BuildContext context, WidgetRef ref, String domainName) {
    final domains = ref.read(domainsProvider).value ?? [];
    final domain = domains.firstWhere(
      (d) => d.name == domainName,
      orElse: () => DomainInfo(name: domainName, provider: 'unknown', nameservers: []),
    );
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => DomainDetailScreen(domain: domain)),
    );
  }
}

class _ResourceSection extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final List<ProductResourceInfo> resources;
  final void Function(ProductResourceInfo)? onResourceTap;

  const _ResourceSection({required this.icon, required this.label, required this.color, required this.resources, this.onResourceTap});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, size: 14, color: color),
            const SizedBox(width: 6),
            Text(label, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 0.5, color: color)),
            const SizedBox(width: 8),
            Text('${resources.length}', style: TextStyle(fontSize: 11, color: AppColors.secondary)),
          ],
        ),
        const SizedBox(height: 6),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: resources.map((res) => InkWell(
            onTap: onResourceTap != null ? () => onResourceTap!(res) : null,
            borderRadius: BorderRadius.circular(6),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: color.withValues(alpha: 0.2)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(icon, size: 13, color: color),
                  const SizedBox(width: 5),
                  Flexible(
                    child: Text(res.resourceId,
                        style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: color),
                        overflow: TextOverflow.ellipsis),
                  ),
                  const SizedBox(width: 4),
                  Text(res.role, style: TextStyle(fontSize: 10, color: color.withValues(alpha: 0.7))),
                ],
              ),
            ),
          )).toList(),
        ),
      ],
    );
  }
}

/// Machine resource section with sparkline status indicators.
class _MachineResourceSection extends ConsumerWidget {
  final List<ProductResourceInfo> machines;
  final void Function(ProductResourceInfo)? onMachineTap;

  const _MachineResourceSection({required this.machines, this.onMachineTap});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final machinesList = ref.watch(machinesProvider).value ?? [];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.computer, size: 14, color: AppColors.primary),
            const SizedBox(width: 6),
            Text('Machines', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 0.5, color: AppColors.primary)),
            const SizedBox(width: 8),
            Text('${machines.length}', style: TextStyle(fontSize: 11, color: AppColors.secondary)),
          ],
        ),
        const SizedBox(height: 6),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: machines.map((res) {
            // Find the machine info for sparkline data
            MachineInfo? machine;
            try {
              machine = machinesList.firstWhere((m) => m.id == res.resourceId);
            } catch (_) {
              machine = null;
            }

            // Check for OVH monitoring data
            Widget? sparkline;
            if (machine != null && machine.provider.startsWith('ovh')) {
              sparkline = _MiniMachineStatus(machineId: machine.id);
            }

            return InkWell(
              onTap: onMachineTap != null ? () => onMachineTap!(res) : null,
              borderRadius: BorderRadius.circular(6),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: AppColors.primary.withValues(alpha: 0.2)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.computer, size: 13, color: AppColors.primary),
                    const SizedBox(width: 5),
                    Flexible(
                      child: Text(res.resourceId,
                          style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: AppColors.primary),
                          overflow: TextOverflow.ellipsis),
                    ),
                    const SizedBox(width: 4),
                    Text(res.role, style: TextStyle(fontSize: 10, color: AppColors.primary.withValues(alpha: 0.7))),
                    if (sparkline != null) ...[
                      const SizedBox(width: 6),
                      sparkline,
                    ],
                  ],
                ),
              ),
            );
          }).toList(),
        ),
      ],
    );
  }
}

/// Mini sparkline indicator showing CPU/memory status from OVH API.
class _MiniMachineStatus extends ConsumerWidget {
  final String machineId;
  const _MiniMachineStatus({required this.machineId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final statsAsync = ref.watch(ovhVpsStatsProvider(machineId));

    return statsAsync.when(
      loading: () => const SizedBox(
        width: 24,
        height: 14,
        child: LinearProgressIndicator(minHeight: 2),
      ),
      error: (_, __) => const SizedBox(
        width: 24,
        height: 14,
        child: Icon(Icons.speed_outlined, size: 12, color: AppColors.secondary),
      ),
      data: (stats) {
        if (stats.isEmpty) return const SizedBox.shrink();
        final cpu = _parseCpu(stats);
        if (cpu == null) return const SizedBox.shrink();

        final color = cpu > 0.8 ? AppColors.danger : cpu > 0.5 ? AppColors.warning : AppColors.success;
        return Container(
          width: 32,
          height: 14,
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(2),
            border: Border.all(color: color.withValues(alpha: 0.3), width: 1),
          ),
          child: Center(
            child: Text(
              '${(cpu * 100).toStringAsFixed(0)}%',
              style: TextStyle(fontSize: 8, fontWeight: FontWeight.w700, color: color, fontFamily: AppTheme.bodyFont),
            ),
          ),
        );
      },
    );
  }

  double? _parseCpu(Map<String, dynamic> stats) {
    final v = stats['cpu'];
    if (v is num) return v.toDouble();
    if (v is String) return double.tryParse(v);
    final nested = stats['cpu'] as Map<String, dynamic>?;
    if (nested != null) {
      final used = nested['used'] ?? nested['value'] ?? nested['percentage'];
      if (used is num) return used.toDouble();
      if (used is String) return double.tryParse(used);
    }
    return null;
  }
}

class _CreateProductDialog extends ConsumerStatefulWidget {
  const _CreateProductDialog();

  @override
  ConsumerState<_CreateProductDialog> createState() => _CreateProductDialogState();
}

class _CreateProductDialogState extends ConsumerState<_CreateProductDialog> {
  final _nameController = TextEditingController();
  final _descController = TextEditingController();
  bool _submitting = false;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Row(
        children: [
          Icon(Icons.folder_special, color: AppColors.primary),
          SizedBox(width: 8),
          Text('Create Product', style: TextStyle(fontFamily: 'WorkSans')),
        ],
      ),
      content: SizedBox(
        width: 400,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'A product groups machines, domains, DNS zones, and Cloudflare Workers/Pages into a deployed service.',
              style: TextStyle(fontSize: 13, color: AppColors.secondary),
            ),
            const SizedBox(height: 20),
            TextField(
              controller: _nameController,
              decoration: const InputDecoration(labelText: 'Product Name', hintText: 'e.g. ClarityMelt API'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _descController,
              decoration: const InputDecoration(labelText: 'Description (optional)', hintText: 'What does this service do?'),
              maxLines: 2,
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(
          onPressed: _submitting ? null : _handleSubmit,
          child: _submitting
              ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
              : const Text('Create'),
        ),
      ],
    );
  }

  Future<void> _handleSubmit() async {
    if (_nameController.text.isEmpty) return;
    setState(() => _submitting = true);
    try {
      await ref.read(productsProvider.notifier).createProduct(
            name: _nameController.text,
            description: _descController.text.isEmpty ? null : _descController.text,
          );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('${_nameController.text} created!')));
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

/// Dialog for adding a resource to a product.
class _AddResourceDialog extends ConsumerStatefulWidget {
  final ProductInfo product;
  const _AddResourceDialog({required this.product});

  @override
  ConsumerState<_AddResourceDialog> createState() => _AddResourceDialogState();
}

class _AddResourceDialogState extends ConsumerState<_AddResourceDialog> {
  String _resourceType = 'machine';
  final _resourceIdController = TextEditingController();
  final _roleController = TextEditingController(text: 'primary');
  bool _submitting = false;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('Add Resource to ${widget.product.name}', style: const TextStyle(fontFamily: 'WorkSans')),
      content: SizedBox(
        width: 400,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            DropdownButtonFormField<String>(
              initialValue: _resourceType,
              decoration: const InputDecoration(labelText: 'Resource Type'),
              items: const [
                DropdownMenuItem(value: 'machine', child: Text('Machine')),
                DropdownMenuItem(value: 'domain', child: Text('Domain')),
                DropdownMenuItem(value: 'dns_zone', child: Text('DNS Zone')),
                DropdownMenuItem(value: 'cloudflare_worker', child: Text('Cloudflare Worker')),
                DropdownMenuItem(value: 'cloudflare_page', child: Text('Cloudflare Pages')),
              ],
              onChanged: (v) => setState(() => _resourceType = v!),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _resourceIdController,
              decoration: InputDecoration(
                labelText: 'Resource ID',
                hintText: _resourceIdHint(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _roleController,
              decoration: const InputDecoration(labelText: 'Role', hintText: 'primary, secondary, cdn...'),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(
          onPressed: _submitting ? null : _handleSubmit,
          child: _submitting
              ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
              : const Text('Add'),
        ),
      ],
    );
  }

  String _resourceIdHint() {
    switch (_resourceType) {
      case 'machine':
        return 'e.g. hetzner-12345';
      case 'domain':
        return 'e.g. example.com';
      case 'dns_zone':
        return 'e.g. zone-id or example.com';
      case 'cloudflare_worker':
        return 'e.g. my-worker';
      case 'cloudflare_page':
        return 'e.g. my-page-project';
      default:
        return '';
    }
  }

  Future<void> _handleSubmit() async {
    if (_resourceIdController.text.isEmpty) return;
    setState(() => _submitting = true);
    try {
      await ref.read(productsProvider.notifier).addResource(
            productId: widget.product.id,
            resourceType: _resourceType,
            resourceId: _resourceIdController.text,
            role: _roleController.text.isEmpty ? 'primary' : _roleController.text,
          );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Resource added')));
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

/// Full product detail screen showing all associated resources.
class ProductDetailScreen extends ConsumerWidget {
  final ProductInfo product;
  const ProductDetailScreen({super.key, required this.product});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final machines = product.resources.where((r) => r.resourceType == 'machine').toList();
    final domains = product.resources.where((r) => r.resourceType == 'domain').toList();
    final dnsZones = product.resources.where((r) => r.resourceType == 'dns_zone').toList();
    final workers = product.resources.where((r) => r.resourceType == 'cloudflare_worker').toList();
    final pages = product.resources.where((r) => r.resourceType == 'cloudflare_page').toList();

    return Scaffold(
      appBar: AppBar(
        title: Text(product.name),
        actions: [
          PopupMenuButton<String>(
            itemBuilder: (ctx) => [
              const PopupMenuItem(value: 'add_resource', child: Text('Add Resource')),
              const PopupMenuItem(value: 'delete', child: Text('Delete Product', style: TextStyle(color: AppColors.danger))),
            ],
            onSelected: (action) async {
              if (action == 'delete') {
                final confirm = await showDialog<bool>(
                  context: context,
                  builder: (ctx) => AlertDialog(
                    title: const Text('Delete Product'),
                    content: Text('Are you sure you want to delete "${product.name}"?'),
                    actions: [
                      TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
                      FilledButton(
                        style: FilledButton.styleFrom(backgroundColor: AppColors.danger),
                        onPressed: () => Navigator.pop(ctx, true),
                        child: const Text('Delete'),
                      ),
                    ],
                  ),
                );
                if (confirm == true) {
                  await ref.read(productsProvider.notifier).deleteProduct(product.id);
                  if (context.mounted) Navigator.pop(context);
                }
              } else if (action == 'add_resource') {
                showDialog(
                  context: context,
                  builder: (ctx) => _AddResourceDialog(product: product),
                );
              }
            },
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          Text(
            product.description ?? 'No description',
            style: const TextStyle(fontSize: 14, color: AppColors.secondary),
          ),
          const SizedBox(height: 20),

          // ── Summary cards ──
          Row(
            children: [
              Expanded(child: StatCard(label: 'MACHINES', value: '${machines.length}', valueColor: AppColors.primary)),
              const SizedBox(width: 12),
              Expanded(child: StatCard(label: 'DOMAINS', value: '${domains.length}', valueColor: AppColors.tertiary)),
              const SizedBox(width: 12),
              Expanded(child: StatCard(label: 'DNS ZONES', value: '${dnsZones.length}', valueColor: AppColors.cloudflare)),
              const SizedBox(width: 12),
              Expanded(child: StatCard(label: 'WORKERS', value: '${workers.length + pages.length}', valueColor: const Color(0xFFF6821F))),
            ],
          ),
          const SizedBox(height: 20),

          // ── Resource sections (clickable) ──
          if (machines.isNotEmpty)
            _DetailResourceSection(
              icon: Icons.computer,
              label: 'Machines',
              color: AppColors.primary,
              resources: machines,
              onResourceTap: (res) => _navigateToMachine(context, ref, res.resourceId),
            ),
          if (domains.isNotEmpty)
            _DetailResourceSection(
              icon: Icons.language,
              label: 'Domains',
              color: AppColors.tertiary,
              resources: domains,
              onResourceTap: (res) => _navigateToDomain(context, ref, res.resourceId),
            ),
          if (dnsZones.isNotEmpty)
            _DetailResourceSection(
              icon: Icons.dns,
              label: 'DNS Zones',
              color: AppColors.cloudflare,
              resources: dnsZones,
            ),
          if (workers.isNotEmpty)
            _DetailResourceSection(
              icon: Icons.bolt,
              label: 'Cloudflare Workers',
              color: const Color(0xFFF6821F),
              resources: workers,
            ),
          if (pages.isNotEmpty)
            _DetailResourceSection(
              icon: Icons.web,
              label: 'Cloudflare Pages',
              color: const Color(0xFF8B5CF6),
              resources: pages,
            ),

          // ── UC Contexts for machines in this product ──
          Builder(
            builder: (context) {
              final machinesList = ref.watch(machinesProvider).value ?? [];
              final ucContexts = <String>{};
              for (final mRes in machines) {
                final m = machinesList.where((m) => m.id == mRes.resourceId).firstOrNull;
                if (m != null && m.uncloudContext != null && m.uncloudContext!.isNotEmpty) {
                  ucContexts.add(m.uncloudContext!);
                }
              }
              if (ucContexts.isEmpty) return const SizedBox.shrink();
              return Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Card(
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Icon(Icons.cloud_outlined, size: 18, color: AppColors.success),
                            const SizedBox(width: 8),
                            const Text('UC CONTEXTS', style: AppTheme.labelStyle),
                            const SizedBox(width: 8),
                            ...ucContexts.map((ctx) => Padding(
                              padding: const EdgeInsets.only(right: 6),
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                decoration: BoxDecoration(
                                  color: AppColors.success.withValues(alpha: 0.1),
                                  borderRadius: BorderRadius.circular(4),
                                  border: Border.all(color: AppColors.success.withValues(alpha: 0.3)),
                                ),
                                child: Text(ctx, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: AppColors.success, fontFamily: AppTheme.bodyFont)),
                              ),
                            )),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  void _navigateToMachine(BuildContext context, WidgetRef ref, String machineId) {
    final machines = ref.read(machinesProvider).value ?? [];
    final machine = machines.firstWhere(
      (m) => m.id == machineId,
      orElse: () => MachineInfo(
        id: machineId,
        name: machineId,
        provider: 'unknown',
        status: 'unknown',
        ipAddresses: [],
        region: '',
      ),
    );
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => MachineDetailScreen(machine: machine)),
    );
  }

  void _navigateToDomain(BuildContext context, WidgetRef ref, String domainName) {
    final domains = ref.read(domainsProvider).value ?? [];
    final domain = domains.firstWhere(
      (d) => d.name == domainName,
      orElse: () => DomainInfo(name: domainName, provider: 'unknown', nameservers: []),
    );
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => DomainDetailScreen(domain: domain)),
    );
  }
}

class _DetailResourceSection extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final List<ProductResourceInfo> resources;
  final void Function(ProductResourceInfo)? onResourceTap;

  const _DetailResourceSection({
    required this.icon,
    required this.label,
    required this.color,
    required this.resources,
    this.onResourceTap,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(icon, size: 18, color: color),
                  const SizedBox(width: 8),
                  Text(label, style: AppTheme.labelStyle),
                  const Spacer(),
                  Text('${resources.length}', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: color)),
                ],
              ),
              const SizedBox(height: 12),
              ...resources.map((res) => Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: InkWell(
                  onTap: onResourceTap != null ? () => onResourceTap!(res) : null,
                  borderRadius: BorderRadius.circular(6),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.05),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: color.withValues(alpha: 0.15)),
                    ),
                    child: Row(
                      children: [
                        Icon(icon, size: 16, color: color),
                        const SizedBox(width: 8),
                        Expanded(child: Text(res.resourceId, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500))),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: AppColors.neutral,
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(res.role, style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: AppColors.secondary)),
                        ),
                        if (onResourceTap != null) ...[
                          const SizedBox(width: 8),
                          Icon(Icons.chevron_right, size: 16, color: color.withValues(alpha: 0.5)),
                        ],
                      ],
                    ),
                  ),
                ),
              )),
            ],
          ),
        ),
      ),
    );
  }
}