import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/models.dart';
import '../providers/app_providers.dart';
import '../services/uncloud_service.dart';
import '../theme/app_theme.dart';
import '../widgets/notes_and_tasks_section.dart';
import 'ssh_terminal_screen.dart';
import 'uncloud_context_dialog.dart';

class MachineDetailScreen extends ConsumerStatefulWidget {
  final MachineInfo machine;
  final void Function(DomainInfo)? onNavigateToDns;

  const MachineDetailScreen({super.key, required this.machine, this.onNavigateToDns});

  @override
  ConsumerState<MachineDetailScreen> createState() => _MachineDetailScreenState();
}

class _MachineDetailScreenState extends ConsumerState<MachineDetailScreen> {
  late TextEditingController _aliasController;

  @override
  void initState() {
    super.initState();
    _aliasController = TextEditingController();
    // Load aliases from cache
    Future.microtask(() => ref.read(machineAliasesProvider.notifier).loadFromCache());
  }

  @override
  void dispose() {
    _aliasController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final dnsMapAsync = ref.watch(dnsMapProvider);
    final aliases = ref.watch(machineAliasesProvider);
    final alias = aliases[widget.machine.id] ?? widget.machine.alias ?? '';
    _aliasController.text = alias;

    return Scaffold(
      appBar: AppBar(
        title: GestureDetector(
          onTap: () {
            Clipboard.setData(ClipboardData(text: widget.machine.name));
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Copied: ${widget.machine.name}')),
            );
          },
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(child: Text(widget.machine.displayName, overflow: TextOverflow.ellipsis)),
              const SizedBox(width: 6),
              Icon(Icons.copy, size: 14, color: AppColors.secondary.withValues(alpha: 0.5)),
            ],
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () => ref.read(machinesProvider.notifier).refresh(),
            tooltip: 'Sync Live',
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          Text(
            'Machine details, hardware specs, SSH access, and linked DNS records',
            style: TextStyle(fontSize: 13, color: AppColors.secondary.withValues(alpha: 0.7), fontFamily: AppTheme.bodyFont),
          ),
          const SizedBox(height: 20),
          _StatusHeader(machine: widget.machine, alias: alias, onAliasChanged: _saveAlias),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(child: StatCard(label: 'STATUS', value: widget.machine.statusLabel, valueColor: AppTheme.statusColor(widget.machine.status))),
              const SizedBox(width: 12),
              Expanded(
                child: _ServiceTypeStatCard(machine: widget.machine),
              ),
              if (widget.machine.ipAddresses.isNotEmpty) ...[
                const SizedBox(width: 12),
                Expanded(child: StatCard(label: 'PUBLIC IPS', value: '${widget.machine.ipAddresses.length}')),
              ],
              if (widget.machine.vcpus != null) ...[
                const SizedBox(width: 12),
                Expanded(child: StatCard(label: 'vCPUs', value: '${widget.machine.vcpus}', valueColor: AppColors.tertiary)),
              ],
              if (widget.machine.memoryMB != null) ...[
                const SizedBox(width: 12),
                Expanded(child: StatCard(label: 'RAM', value: widget.machine.memoryMB! >= 1024
                    ? '${(widget.machine.memoryMB! / 1024).toStringAsFixed(widget.machine.memoryMB! % 1024 == 0 ? 0 : 1)} GB'
                    : '${widget.machine.memoryMB} MB')),
              ],
              if (widget.machine.diskGB != null) ...[
                const SizedBox(width: 12),
                Expanded(child: StatCard(label: 'DISK', value: '${widget.machine.diskGB} GB')),
              ],
              if (widget.machine.monthlyCost != null) ...[
                const SizedBox(width: 12),
                Expanded(child: StatCard(label: 'COST', value: widget.machine.monthlyCostLabel, valueColor: AppColors.success)),
              ],
            ],
          ),
          const SizedBox(height: 16),
          _SpecsSection(machine: widget.machine),
          const SizedBox(height: 16),
          _OvhHardwareSection(machine: widget.machine),
          const SizedBox(height: 16),
          _MonitoringSection(machine: widget.machine),
          const SizedBox(height: 16),
          _IpAddressSection(machine: widget.machine, dnsMapAsync: dnsMapAsync, onNavigateToDns: widget.onNavigateToDns),
          const SizedBox(height: 16),
          _DomainsSection(machine: widget.machine, dnsMapAsync: dnsMapAsync, onNavigateToDns: widget.onNavigateToDns),
          const SizedBox(height: 16),
          _SshSection(machine: widget.machine),
          const SizedBox(height: 16),
          _UncloudServicesSection(machine: widget.machine),
          const SizedBox(height: 16),
          _UncloudSection(machine: widget.machine),
          const SizedBox(height: 16),
          _ProductsSection(machine: widget.machine),
          const SizedBox(height: 16),

          // ── Notes & Tasks ──
          NotesAndTasksSection(resourceType: 'machine', resourceId: widget.machine.id),
        ],
      ),
    );
  }

  void _saveAlias(String value) {
    ref.read(machineAliasesProvider.notifier).setAlias(widget.machine.id, value);
  }
}

class _StatusHeader extends StatelessWidget {
  final MachineInfo machine;
  final String alias;
  final ValueChanged<String> onAliasChanged;

  const _StatusHeader({required this.machine, required this.alias, required this.onAliasChanged});

  @override
  Widget build(BuildContext context) {
    final statusColor = AppTheme.statusColor(machine.status);
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
                color: statusColor.withValues(alpha: 0.12),
                border: Border.all(color: statusColor, width: 2),
              ),
              child: Icon(
                machine.isRunning ? Icons.check_circle_outline : Icons.stop_circle_outlined,
                color: statusColor,
                size: 28,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // ── Copyable name ──
                  GestureDetector(
                    onTap: () {
                      Clipboard.setData(ClipboardData(text: machine.name));
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('Copied name: ${machine.name}')),
                      );
                    },
                    child: Row(
                      children: [
                        Flexible(
                          child: Text(machine.name,
                              style: const TextStyle(fontFamily: AppTheme.displayFont, fontSize: 20, fontWeight: FontWeight.w700),
                              overflow: TextOverflow.ellipsis),
                        ),
                        const SizedBox(width: 6),
                        Icon(Icons.copy, size: 14, color: AppColors.secondary.withValues(alpha: 0.4)),
                      ],
                    ),
                  ),
                  // ── Copyable ID ──
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
                        const Icon(Icons.fingerprint, size: 12, color: AppColors.secondary),
                        const SizedBox(width: 4),
                        Text(machine.id, style: TextStyle(fontFamily: AppTheme.bodyFont, fontSize: 11, color: AppColors.secondary.withValues(alpha: 0.7))),
                        const SizedBox(width: 4),
                        Icon(Icons.copy, size: 10, color: AppColors.secondary.withValues(alpha: 0.3)),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
                  // ── Alias (friendly name) ──
                  _AliasField(alias: alias, onChanged: onAliasChanged),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      AppTheme.providerBadge(machine.provider),
                      const SizedBox(width: 8),
                      // Service type label
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: AppColors.tertiary.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(2),
                          border: Border.all(color: AppColors.tertiary.withValues(alpha: 0.2)),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(AppTheme.serviceTypeIcon(machine.provider), size: 12, color: AppColors.tertiary),
                            const SizedBox(width: 4),
                            Text(
                              machine.serviceTypeLabel,
                              style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 0.3, fontFamily: AppTheme.bodyFont, color: AppColors.tertiary),
                            ),
                          ],
                        ),
                      ),
                      if (machine.specsSummary.isNotEmpty) ...[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: AppColors.surfaceVariant,
                            borderRadius: BorderRadius.circular(2),
                          ),
                          child: Text(
                            machine.specsSummary,
                            style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, fontFamily: AppTheme.bodyFont, color: AppColors.secondary),
                          ),
                        ),
                      ],
                      if (machine.flavor != null) ...[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(color: AppColors.surfaceVariant, borderRadius: BorderRadius.circular(2)),
                          child: Text(machine.flavor!, style: TextStyle(fontSize: 11, fontFamily: AppTheme.bodyFont, color: AppColors.secondary)),
                        ),
                      ],
                      if (machine.region.isNotEmpty) ...[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(color: AppColors.surfaceVariant, borderRadius: BorderRadius.circular(2)),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.location_on, size: 12, color: AppColors.secondary),
                              const SizedBox(width: 4),
                              Text(machine.region, style: TextStyle(fontSize: 11, fontFamily: AppTheme.bodyFont, color: AppColors.secondary)),
                            ],
                          ),
                        ),
                      ],
                      // ── Machine Type Tag ──
                      if (machine.machineTypeTag != machine.serviceTypeLabel) ...[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: AppColors.primary.withValues(alpha: 0.08),
                            borderRadius: BorderRadius.circular(2),
                            border: Border.all(color: AppColors.primary.withValues(alpha: 0.2)),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.label, size: 12, color: AppColors.primary),
                              const SizedBox(width: 4),
                              Text(machine.machineTypeTag, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, fontFamily: AppTheme.bodyFont, color: AppColors.primary)),
                            ],
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

class _AliasField extends StatefulWidget {
  final String alias;
  final ValueChanged<String> onChanged;
  const _AliasField({required this.alias, required this.onChanged});

  @override
  State<_AliasField> createState() => _AliasFieldState();
}

class _AliasFieldState extends State<_AliasField> {
  late TextEditingController _controller;
  bool _editing = false;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.alias);
  }

  @override
  void didUpdateWidget(covariant _AliasField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.alias != _controller.text) {
      _controller.text = widget.alias;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_editing) {
      return InkWell(
        onTap: () => setState(() => _editing = true),
        borderRadius: BorderRadius.circular(2),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                widget.alias.isEmpty ? 'Add friendly name…' : widget.alias,
                style: TextStyle(
                  fontSize: 13,
                  fontFamily: AppTheme.bodyFont,
                  color: widget.alias.isEmpty ? AppColors.secondary.withValues(alpha: 0.4) : AppColors.primary,
                  fontStyle: widget.alias.isEmpty ? FontStyle.italic : FontStyle.normal,
                ),
              ),
              const SizedBox(width: 4),
              Icon(Icons.edit, size: 12, color: AppColors.secondary.withValues(alpha: 0.3)),
            ],
          ),
        ),
      );
    }

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: 250,
          child: TextField(
            controller: _controller,
            autofocus: true,
            style: const TextStyle(fontSize: 13, fontFamily: AppTheme.bodyFont, color: AppColors.primary),
            decoration: InputDecoration(
              labelText: 'Friendly Name',
              isDense: true,
              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            ),
            onSubmitted: (value) {
              widget.onChanged(value);
              setState(() => _editing = false);
            },
          ),
        ),
        IconButton(
          icon: const Icon(Icons.check, size: 16, color: AppColors.success),
          onPressed: () {
            widget.onChanged(_controller.text);
            setState(() => _editing = false);
          },
        ),
        IconButton(
          icon: const Icon(Icons.close, size: 16, color: AppColors.danger),
          onPressed: () {
            _controller.text = widget.alias;
            setState(() => _editing = false);
          },
        ),
      ],
    );
  }
}

class _SpecsSection extends StatelessWidget {
  final MachineInfo machine;
  const _SpecsSection({required this.machine});

  @override
  Widget build(BuildContext context) {
    final hasSpecs = machine.vcpus != null || machine.memoryMB != null ||
        machine.diskGB != null || machine.bandwidth != null ||
        machine.os != null || machine.commercialRange != null ||
        machine.image != null || machine.createdAt.isNotEmpty;

    if (!hasSpecs) return const SizedBox.shrink();

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(AppTheme.serviceTypeIcon(machine.provider), size: 18, color: AppColors.tertiary),
                const SizedBox(width: 8),
                const Text('HARDWARE & SOFTWARE', style: AppTheme.labelStyle),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: AppColors.tertiary.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(2),
                    border: Border.all(color: AppColors.tertiary.withValues(alpha: 0.2)),
                  ),
                  child: Text(
                    machine.serviceTypeLabel,
                    style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, letterSpacing: 0.3, fontFamily: AppTheme.bodyFont, color: AppColors.tertiary),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 24,
              runSpacing: 12,
              children: [
                if (machine.vcpus != null)
                  _CopyableRow(icon: Icons.memory, label: 'vCPUs', value: '${machine.vcpus}'),
                if (machine.memoryMB != null)
                  _CopyableRow(icon: Icons.storage, label: 'RAM', value: machine.memoryMB! >= 1024
                      ? '${(machine.memoryMB! / 1024).toStringAsFixed(1)} GB'
                      : '${machine.memoryMB} MB'),
                if (machine.diskGB != null)
                  _CopyableRow(icon: Icons.save, label: 'Disk', value: '${machine.diskGB} GB'),
                if (machine.bandwidth != null)
                  _CopyableRow(icon: Icons.network_check, label: 'BW', value: machine.bandwidth!),
                if (machine.os != null || machine.image != null)
                  _CopyableRow(icon: Icons.computer, label: 'OS', value: machine.os ?? machine.image ?? ''),
                if (machine.commercialRange != null)
                  _CopyableRow(icon: Icons.category, label: 'Range', value: machine.commercialRange!),
                if (machine.image != null && machine.os != null)
                  _CopyableRow(icon: Icons.layers, label: 'Image', value: machine.image!),
                if (machine.createdAt.isNotEmpty)
                  _CopyableRow(icon: Icons.calendar_today, label: 'Created', value: machine.createdAt),
                if (machine.id.isNotEmpty)
                  _CopyableRow(icon: Icons.fingerprint, label: 'ID', value: machine.id),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Fetches and displays OVH hardware specifications when available.
class _OvhHardwareSection extends ConsumerWidget {
  final MachineInfo machine;
  const _OvhHardwareSection({required this.machine});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Only show for OVH machines (VPS and dedicated)
    if (!machine.provider.startsWith('ovh')) return const SizedBox.shrink();

    final specsAsync = ref.watch(ovhHardwareSpecsProvider(machine.id));

    return specsAsync.when(
      loading: () => const SizedBox.shrink(), // Don't show a spinner — specs load in background
      error: (_, __) => const SizedBox.shrink(),
      data: (specs) {
        if (specs.isEmpty) return const SizedBox.shrink();
        return _buildSpecsCard(context, specs);
      },
    );
  }

  Widget _buildSpecsCard(BuildContext context, Map<String, dynamic> specs) {
    // Extract common OVH hardware fields
    final fields = <_SpecField>[];

    // ── Dedicated server hardware ──
    final hardware = specs['hardware'] ?? specs;
    if (hardware is Map) {
      final h = hardware as Map<String, dynamic>;
      _addIfPresent(h, 'serverModel', 'Model', Icons.memory, fields);
      _addIfPresent(h, 'brand', 'Brand', Icons.business, fields);
      _addIfPresent(h, 'family', 'Family', Icons.category, fields);
      _addIfPresent(h, 'numberOfProcessors', 'CPUs', Icons.memory, fields);
      _addIfPresent(h, 'processorArchitecture', 'Arch', Icons.memory, fields);
      _addIfPresent(h, 'processorName', 'CPU Model', Icons.memory, fields);
      _addIfPresent(h, 'numberOfCores', 'Cores', Icons.memory, fields);
      _addIfPresent(h, 'numberOfThreads', 'Threads', Icons.memory, fields);
      _addIfPresent(h, 'frequency', 'Frequency', Icons.speed, fields);
      _addIfPresent(h, 'memorySize', 'Memory', Icons.storage, fields);
      _addIfPresent(h, 'memory', 'RAM', Icons.storage, fields);
      _addIfPresent(h, 'diskGroups', 'Disk Groups', Icons.save, fields);
      _addIfPresent(h, 'storageCapacity', 'Storage', Icons.save, fields);
      _addIfPresent(h, 'diskSize', 'Disk', Icons.save, fields);
      _addIfPresent(h, 'storage', 'Storage', Icons.save, fields);
      _addIfPresent(h, 'bandwidth', 'Bandwidth', Icons.network_check, fields);
      _addIfPresent(h, 'traffic', 'Traffic', Icons.network_check, fields);
      _addIfPresent(h, 'networkSpecification', 'Network', Icons.settings_ethernet, fields);
      _addIfPresent(h, 'expansionCards', 'Expansion', Icons.extension, fields);
      _addIfPresent(h, 'defaultHardwareRaid', 'HW RAID', Icons.save, fields);
      _addIfPresent(h, 'defaultHardwareRaidDetail', 'RAID Detail', Icons.save, fields);
    }

    // ── VPS specs ──
    final vpsSpecs = specs['vps'] ?? specs['vpsSpecs'];
    if (vpsSpecs is Map) {
      final v = vpsSpecs as Map<String, dynamic>;
      _addIfPresent(v, 'vcpus', 'vCPUs', Icons.memory, fields);
      _addIfPresent(v, 'ram', 'RAM', Icons.storage, fields);
      _addIfPresent(v, 'disk', 'Disk', Icons.save, fields);
      _addIfPresent(v, 'bandwidth', 'Bandwidth', Icons.network_check, fields);
      _addIfPresent(v, 'traffic', 'Traffic', Icons.network_check, fields);
      _addIfPresent(v, 'model', 'Model', Icons.memory, fields);
      _addIfPresent(v, 'offer', 'Offer', Icons.category, fields);
      _addIfPresent(v, 'cluster', 'Cluster', Icons.dns, fields);
      _addIfPresent(v, 'datacenter', 'Datacenter', Icons.location_on, fields);
      _addIfPresent(v, 'distribution', 'OS', Icons.computer, fields);
    }

    // ── Top-level fields (VPS or general) ──
    _addIfPresent(specs, 'vcpus', 'vCPUs', Icons.memory, fields);
    _addIfPresent(specs, 'cores', 'Cores', Icons.memory, fields);
    _addIfPresent(specs, 'memory', 'Memory', Icons.storage, fields);
    _addIfPresent(specs, 'storage', 'Storage', Icons.save, fields);
    _addIfPresent(specs, 'bandwidth', 'Bandwidth', Icons.network_check, fields);
    _addIfPresent(specs, 'model', 'Model', Icons.memory, fields);
    _addIfPresent(specs, 'offer', 'Offer', Icons.category, fields);

    // ── Monitoring / boot info ──
    final monitoring = specs['monitoring'];
    if (monitoring is Map) {
      final m = monitoring as Map<String, dynamic>;
      _addIfPresent(m, 'state', 'Monitoring', Icons.monitor_heart, fields);
      _addIfPresent(m, 'monitoringPeriod', 'Period', Icons.timer, fields);
      _addIfPresent(m, 'ipv4', 'Monitor IPv4', Icons.wifi, fields);
    }

    // Deduplicate by label
    final seenLabels = <String>{};
    final uniqueFields = <_SpecField>[];
    for (final f in fields) {
      if (seenLabels.add(f.label)) {
        uniqueFields.add(f);
      }
    }

    if (uniqueFields.isEmpty) return const SizedBox.shrink();

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.memory, size: 18, color: AppColors.tertiary),
                const SizedBox(width: 8),
                const Text('OVH HARDWARE', style: AppTheme.labelStyle),
                const Spacer(),
                AppTheme.providerBadge(machine.provider),
              ],
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 24,
              runSpacing: 12,
              children: uniqueFields.map((f) => _CopyableRow(
                icon: f.icon,
                label: f.label,
                value: f.value,
              )).toList(),
            ),
          ],
        ),
      ),
    );
  }

  void _addIfPresent(Map<String, dynamic> map, String key, String label, IconData icon, List<_SpecField> fields) {
    final value = map[key];
    if (value == null) return;
    final str = value is Map ? value.toString() : value.toString();
    if (str.isEmpty) return;
    fields.add(_SpecField(icon: icon, label: label, value: str));
  }
}

class _SpecField {
  final IconData icon;
  final String label;
  final String value;
  _SpecField({required this.icon, required this.label, required this.value});
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

/// Section showing live monitoring metrics from the OVH API.
/// Displays CPU/RAM/disk/network stats for VPS, traffic for dedicated servers,
/// active tasks, and ongoing interventions.
class _MonitoringSection extends ConsumerWidget {
  final MachineInfo machine;
  const _MonitoringSection({required this.machine});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isOvh = machine.provider.startsWith('ovh');
    if (!isOvh) return const SizedBox.shrink();

    final statsAsync = ref.watch(ovhVpsStatsProvider(machine.id));
    final diskUsageAsync = ref.watch(ovhVpsDiskUsageProvider(machine.id));
    final tasksAsync = ref.watch(ovhServerTasksProvider(machine.id));
    final interventionsAsync = ref.watch(ovhInterventionsProvider(machine.id));

    // Only show if we have at least some data
    final hasStats = statsAsync.hasValue && (statsAsync.value?.isNotEmpty ?? false);
    final hasDisk = diskUsageAsync.hasValue && (diskUsageAsync.value?.isNotEmpty ?? false);
    final hasTasks = tasksAsync.hasValue && (tasksAsync.value?.isNotEmpty ?? false);
    final hasInterventions = interventionsAsync.hasValue && (interventionsAsync.value?.isNotEmpty ?? false);

    if (!hasStats && !hasDisk && !hasTasks && !hasInterventions &&
        !statsAsync.isLoading && !diskUsageAsync.isLoading && !tasksAsync.isLoading) {
      return const SizedBox.shrink();
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.speed, size: 18, color: AppColors.tertiary),
                const SizedBox(width: 8),
                const Text('MONITORING', style: AppTheme.labelStyle),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.refresh, size: 16),
                  tooltip: 'Refresh metrics',
                  onPressed: () {
                    ref.invalidate(ovhVpsStatsProvider(machine.id));
                    ref.invalidate(ovhVpsDiskUsageProvider(machine.id));
                    ref.invalidate(ovhServerTasksProvider(machine.id));
                    ref.invalidate(ovhInterventionsProvider(machine.id));
                  },
                ),
              ],
            ),
            const SizedBox(height: 16),

            // ── Stats metrics ──
            if (statsAsync.isLoading) ...[
              const Center(child: SizedBox(height: 24, child: CircularProgressIndicator(strokeWidth: 2))),
            ] else if (hasStats) ...[
              _buildStatsCards(context, statsAsync.value!),
              const SizedBox(height: 16),
            ],

            // ── Disk usage ──
            if (diskUsageAsync.isLoading) ...[
              const Center(child: SizedBox(height: 24, child: CircularProgressIndicator(strokeWidth: 2))),
            ] else if (hasDisk) ...[
              _buildDiskUsage(context, diskUsageAsync.value!),
              const SizedBox(height: 16),
            ],

            // ── Active tasks ──
            if (tasksAsync.isLoading) ...[
              // skip — tasks are secondary info
            ] else if (hasTasks) ...[
              _buildTasks(context, tasksAsync.value!),
              const SizedBox(height: 16),
            ],

            // ── Ongoing interventions ──
            if (interventionsAsync.isLoading) ...[
              // skip
            ] else if (hasInterventions) ...[
              _buildInterventions(context, interventionsAsync.value!),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildStatsCards(BuildContext context, Map<String, dynamic> stats) {
    final cpu = _parseDouble(stats, 'cpu');
    final memory = stats['memory'] as Map<String, dynamic>?;
    final memUsed = memory != null ? _parseDouble(memory, 'used') : null;
    final memTotal = memory != null ? _parseDouble(memory, 'total') : null;
    final memPercent = (memUsed != null && memTotal != null && memTotal > 0) ? (memUsed / memTotal) : null;
    final network = stats['network'] as Map<String, dynamic>?;

    final cards = <Widget>[];

    if (cpu != null) {
      cards.add(_MetricCard(
        label: 'CPU',
        value: '${(cpu * 100).toStringAsFixed(1)}%',
        percent: cpu,
        color: cpu > 0.8 ? AppColors.danger : cpu > 0.5 ? AppColors.warning : AppColors.success,
      ));
    }

    if (memPercent != null) {
      cards.add(_MetricCard(
        label: 'MEMORY',
        value: memUsed != null && memTotal != null
            ? '${_formatMB(memUsed)} / ${_formatMB(memTotal)}'
            : '${(memPercent * 100).toStringAsFixed(1)}%',
        percent: memPercent,
        color: memPercent > 0.9 ? AppColors.danger : memPercent > 0.7 ? AppColors.warning : AppColors.success,
      ));
    }

    if (network != null) {
      final rx = _parseDouble(network, 'rx') ?? _parseDouble(network, 'in');
      final tx = _parseDouble(network, 'tx') ?? _parseDouble(network, 'out');
      if (rx != null || tx != null) {
        cards.add(_MetricCard(
          label: 'NETWORK',
          value: '↓${_formatBytes(rx ?? 0)}/s  ↑${_formatBytes(tx ?? 0)}/s',
          percent: null,
          color: AppColors.secondary,
        ));
      }
    }

    if (cards.isEmpty) {
      return Text('No metrics available', style: TextStyle(fontSize: 13, color: AppColors.secondary.withValues(alpha: 0.7), fontFamily: AppTheme.bodyFont));
    }

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: cards.map((c) => Padding(padding: const EdgeInsets.only(right: 12), child: c)).toList(),
    );
  }

  Widget _buildDiskUsage(BuildContext context, List<Map<String, dynamic>> disks) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('DISK USAGE', style: AppTheme.labelStyle),
        const SizedBox(height: 8),
        ...disks.map((d) {
          final id = d['id']?.toString() ?? 'Disk';
          final used = _parseDouble(d, 'used') ?? _parseDouble(d, 'usedPercent');
          final total = _parseDouble(d, 'total') ?? _parseDouble(d, 'size');
          final percent = (total != null && total > 0 && used != null) ? used / total : null;
          return Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Row(
              children: [
                SizedBox(width: 100, child: Text(id, style: TextStyle(fontSize: 12, fontFamily: AppTheme.bodyFont, color: AppColors.primary))),
                Expanded(
                  child: LinearProgressIndicator(
                    value: percent ?? 0,
                    backgroundColor: AppColors.surfaceVariant,
                    color: (percent ?? 0) > 0.9 ? AppColors.danger : (percent ?? 0) > 0.7 ? AppColors.warning : AppColors.success,
                    minHeight: 8,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  percent != null ? '${(percent * 100).toStringAsFixed(0)}%' : '--',
                  style: TextStyle(fontSize: 11, fontFamily: AppTheme.bodyFont, color: AppColors.secondary),
                ),
              ],
            ),
          );
        }),
      ],
    );
  }

  Widget _buildTasks(BuildContext context, List<Map<String, dynamic>> tasks) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('TASKS', style: AppTheme.labelStyle),
        const SizedBox(height: 8),
        ...tasks.take(5).map((t) {
          final function_ = t['function']?.toString() ?? t['comment']?.toString() ?? 'task';
          final status = t['status']?.toString() ?? 'unknown';
          final color = status == 'done' ? AppColors.success : status == 'error' ? AppColors.danger : AppColors.warning;
          return Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Row(
              children: [
                Icon(Icons.circle, size: 6, color: color),
                const SizedBox(width: 8),
                Expanded(child: Text(function_, style: TextStyle(fontSize: 12, fontFamily: AppTheme.bodyFont))),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(color: color.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(2)),
                  child: Text(status.toUpperCase(), style: TextStyle(fontSize: 9, fontWeight: FontWeight.w700, color: color, fontFamily: AppTheme.bodyFont)),
                ),
              ],
            ),
          );
        }),
      ],
    );
  }

  Widget _buildInterventions(BuildContext context, List<Map<String, dynamic>> interventions) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('INTERVENTIONS', style: AppTheme.labelStyle),
        const SizedBox(height: 8),
        ...interventions.take(3).map((i) {
          final type = i['type']?.toString() ?? i['comment']?.toString() ?? 'intervention';
          final date = i['date']?.toString() ?? i['lastUpdate']?.toString() ?? '';
          return Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Row(
              children: [
                const Icon(Icons.build, size: 14, color: AppColors.warning),
                const SizedBox(width: 8),
                Expanded(child: Text(type, style: TextStyle(fontSize: 12, fontFamily: AppTheme.bodyFont))),
                if (date.isNotEmpty) Text(date.substring(0, date.length > 10 ? 10 : date.length), style: TextStyle(fontSize: 11, color: AppColors.secondary, fontFamily: AppTheme.bodyFont)),
              ],
            ),
          );
        }),
      ],
    );
  }

  double? _parseDouble(Map<String, dynamic> map, String key) {
    final v = map[key];
    if (v is num) return v.toDouble();
    if (v is String) return double.tryParse(v);
    // Nested map: e.g. cpu: {used: 0.45}
    final nested = map[key] as Map<String, dynamic>?;
    if (nested != null) {
      final used = nested['used'] ?? nested['value'] ?? nested['percentage'];
      if (used is num) return used.toDouble();
      if (used is String) return double.tryParse(used);
    }
    return null;
  }

  String _formatMB(double mb) {
    if (mb >= 1024) return '${(mb / 1024).toStringAsFixed(1)} GB';
    return '${mb.toStringAsFixed(0)} MB';
  }

  String _formatBytes(double bytes) {
    if (bytes >= 1e9) return '${(bytes / 1e9).toStringAsFixed(1)} GB';
    if (bytes >= 1e6) return '${(bytes / 1e6).toStringAsFixed(1)} MB';
    if (bytes >= 1e3) return '${(bytes / 1e3).toStringAsFixed(1)} KB';
    return '${bytes.toStringAsFixed(0)} B';
  }
}

/// A single metric card with label, value, and optional progress bar.
class _MetricCard extends StatelessWidget {
  final String label;
  final String value;
  final double? percent;
  final Color color;

  const _MetricCard({required this.label, required this.value, this.percent, required this.color});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppColors.surfaceVariant,
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: AppColors.outline),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w700, letterSpacing: 0.5, color: AppColors.secondary, fontFamily: AppTheme.bodyFont)),
            const SizedBox(height: 4),
            Text(value, style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: color, fontFamily: AppTheme.displayFont)),
            if (percent != null) ...[
              const SizedBox(height: 6),
              ClipRRect(
                borderRadius: BorderRadius.circular(2),
                child: LinearProgressIndicator(
                  value: percent!,
                  backgroundColor: AppColors.neutral,
                  color: color,
                  minHeight: 6,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _IpAddressSection extends ConsumerWidget {
  final MachineInfo machine;
  final AsyncValue<Map<String, List<DnsRecordInfo>>> dnsMapAsync;
  final void Function(DomainInfo)? onNavigateToDns;
  const _IpAddressSection({required this.machine, required this.dnsMapAsync, this.onNavigateToDns});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dnsMap = dnsMapAsync.value ?? <String, List<DnsRecordInfo>>{};
    final domainsAsync = ref.watch(domainsProvider);
    final domains = domainsAsync.value ?? [];

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.wifi, size: 18, color: AppColors.tertiary),
                const SizedBox(width: 8),
                const Text('IP ADDRESSES', style: AppTheme.labelStyle),
              ],
            ),
            const SizedBox(height: 16),
            if (machine.ipAddresses.isEmpty)
              Text('No IP addresses found', style: TextStyle(color: AppColors.secondary, fontFamily: AppTheme.bodyFont))
            else
              ...machine.ipAddresses.map((ip) {
                final records = dnsMap[ip] ?? [];
                return Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: AppColors.surfaceVariant,
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(color: AppColors.outline),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            GestureDetector(
                              onTap: () {
                                Clipboard.setData(ClipboardData(text: ip));
                                ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Copied: $ip')));
                              },
                              child: Row(mainAxisSize: MainAxisSize.min, children: [
                                CodeBlock(text: ip),
                                const SizedBox(width: 4),
                                Icon(Icons.copy, size: 12, color: AppColors.secondary.withValues(alpha: 0.4)),
                              ]),
                            ),
                            const Spacer(),
                            if (records.isNotEmpty)
                              Text('${records.length} DNS', style: TextStyle(fontSize: 12, color: AppColors.secondary, fontFamily: AppTheme.bodyFont)),
                          ],
                        ),
                        if (records.isNotEmpty) ...[
                          const SizedBox(height: 12),
                          ...records.map((rec) {
                            // Find the domain for this record to enable navigation
                            final domain = domains.firstWhere(
                              (d) => d.name == rec.zoneName || d.cfZoneId == rec.zoneId,
                              orElse: () => domains.firstWhere(
                                (d) => d.name == rec.zoneName,
                                orElse: () => DomainInfo(name: rec.zoneName, provider: 'unknown', nameservers: []),
                              ),
                            );
                            final canNavigate = domain.provider != 'unknown' && domain.canManageDns;
                            return Padding(
                              padding: const EdgeInsets.only(bottom: 6),
                              child: InkWell(
                                onTap: canNavigate ? () {
                                  ref.read(dnsRecordsProvider.notifier).selectDomain(domain);
                                  onNavigateToDns?.call(domain);
                                } : null,
                                borderRadius: BorderRadius.circular(4),
                                child: Row(
                                  children: [
                                    AppTheme.recordTypeBadge(rec.type),
                                    const SizedBox(width: 8),
                                    Expanded(child: Text(rec.name, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500, fontFamily: AppTheme.bodyFont))),
                                    const SizedBox(width: 8),
                                    Text('→ ${rec.zoneName}', style: TextStyle(fontSize: 12, color: AppColors.secondary, fontFamily: AppTheme.bodyFont)),
                                    if (canNavigate) ...[
                                      const SizedBox(width: 4),
                                      Icon(Icons.open_in_new, size: 12, color: AppColors.tertiary.withValues(alpha: 0.6)),
                                    ],
                                  ],
                                ),
                              ),
                            );
                          }),
                        ],
                      ],
                    ),
                  ),
                );
              }),
          ],
        ),
      ),
    );
  }
}

/// Section showing domains whose DNS records point to this machine.
/// Each domain row is tappable to navigate to the DNS manager.
class _DomainsSection extends ConsumerWidget {
  final MachineInfo machine;
  final AsyncValue<Map<String, List<DnsRecordInfo>>> dnsMapAsync;
  final void Function(DomainInfo)? onNavigateToDns;
  const _DomainsSection({required this.machine, required this.dnsMapAsync, this.onNavigateToDns});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dnsMap = dnsMapAsync.value ?? <String, List<DnsRecordInfo>>{};
    final domainsAsync = ref.watch(domainsProvider);

    // Find domains that have DNS records pointing to this machine's IPs
    final linkedDomainNames = <String>{};
    for (final ip in machine.ipAddresses) {
      final records = dnsMap[ip] ?? [];
      for (final rec in records) {
        linkedDomainNames.add(rec.zoneName);
      }
    }

    if (linkedDomainNames.isEmpty) return const SizedBox.shrink();

    return domainsAsync.when(
      loading: () => const SizedBox.shrink(),
      error: (_, __) => const SizedBox.shrink(),
      data: (domains) {
        // Match domain objects for the linked names
        final linkedDomains = domains.where((d) => linkedDomainNames.contains(d.name)).toList();
        if (linkedDomains.isEmpty) return const SizedBox.shrink();

        // Check for root A/CNAME validation in the domain context
        final domainWarnings = <String, String>{};
        for (final domain in linkedDomains) {
          final domainRecords = <DnsRecordInfo>[];
          for (final ip in machine.ipAddresses) {
            domainRecords.addAll(dnsMap[ip]?.where((r) => r.zoneName == domain.name) ?? []);
          }
          final hasRootA = domainRecords.any((r) => (r.type == 'A' || r.type == 'AAAA') && (r.name == '@' || r.name == domain.name));
          final hasRootCname = domainRecords.any((r) => r.type == 'CNAME' && (r.name == '@' || r.name == domain.name));
          if (!hasRootA && !hasRootCname) {
            domainWarnings[domain.name] = 'No root A/CNAME record found pointing to this machine';
          }
        }

        return Card(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.language, size: 18, color: AppColors.tertiary),
                    const SizedBox(width: 8),
                    const Text('DOMAINS', style: AppTheme.labelStyle),
                    const Spacer(),
                    Text('${linkedDomains.length} domain${linkedDomains.length != 1 ? 's' : ''}', style: TextStyle(fontSize: 12, color: AppColors.secondary, fontFamily: AppTheme.bodyFont)),
                  ],
                ),
                // Root domain validation warnings (domain context)
                if (domainWarnings.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  ...domainWarnings.entries.map((entry) => Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Container(
                      padding: const EdgeInsets.all(10),
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
                              '${entry.key}: ${entry.value}',
                              style: TextStyle(fontSize: 12, color: AppColors.warning, fontFamily: AppTheme.bodyFont),
                            ),
                          ),
                        ],
                      ),
                    ),
                  )),
                ],
                const SizedBox(height: 16),
                ...linkedDomains.map((domain) => Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: InkWell(
                    onTap: () {
                      if (domain.canManageDns) {
                        ref.read(dnsRecordsProvider.notifier).selectDomain(domain);
                        onNavigateToDns?.call(domain);
                      }
                    },
                    borderRadius: BorderRadius.circular(4),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      decoration: BoxDecoration(
                        color: AppColors.surfaceVariant,
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(color: AppColors.outline),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.language, size: 16, color: AppColors.primary),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(domain.name, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, fontFamily: AppTheme.bodyFont)),
                                const SizedBox(height: 2),
                                Row(
                                  children: [
                                    AppTheme.providerBadge(domain.provider, fontSize: 9),
                                    const SizedBox(width: 6),
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                                      decoration: BoxDecoration(
                                        color: AppTheme.providerColor(domain.effectiveDnsProvider).withValues(alpha: 0.1),
                                        borderRadius: BorderRadius.circular(2),
                                      ),
                                      child: Text(
                                        'DNS: ${domain.effectiveDnsProvider.toUpperCase()}',
                                        style: TextStyle(fontSize: 9, fontWeight: FontWeight.w700, color: AppTheme.providerColor(domain.effectiveDnsProvider), fontFamily: AppTheme.bodyFont),
                                      ),
                                    ),
                                    if (domain.cfStatus != null) ...[
                                      const SizedBox(width: 6),
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                                        decoration: BoxDecoration(
                                          color: (domain.cfStatus == 'active' ? AppColors.success : AppColors.warning).withValues(alpha: 0.1),
                                          borderRadius: BorderRadius.circular(8),
                                        ),
                                        child: Text(
                                          domain.cfStatus!,
                                          style: TextStyle(fontSize: 9, fontWeight: FontWeight.w600, color: domain.cfStatus == 'active' ? AppColors.success : AppColors.warning),
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                              ],
                            ),
                          ),
                          if (domain.canManageDns) ...[
                            const Icon(Icons.open_in_new, size: 14, color: AppColors.tertiary),
                          ] else ...[
                            const Icon(Icons.lock_outline, size: 14, color: AppColors.secondary),
                          ],
                        ],
                      ),
                    ),
                  ),
                )),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _SshSection extends ConsumerWidget {
  final MachineInfo machine;
  const _SshSection({required this.machine});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (machine.ipAddresses.isEmpty) return const SizedBox.shrink();
    final ip = machine.ipAddresses.first;

    // Resolve SSH key from Uncloud config (match connection by IP/hostname,
    // even if no ssh_key_file is specified — the terminal will try default keys)
    final configAsync = ref.watch(uncloudConfigProvider);
    String? sshKeyFile;
    configAsync.whenData((config) {
      if (config == null) return;
      outer:
      for (final ctx in config.contexts.values) {
        for (final conn in ctx.connections) {
          for (final mIp in machine.ipAddresses) {
            if (conn.sshTarget.contains(mIp)) {
              // Found a matching connection — use its key file if specified
              if (conn.sshKeyFile != null) {
                sshKeyFile = conn.resolvedSshKeyFile;
              }
              break outer;
            }
          }
        }
      }
    });

    // For OVH machines, the machine name IS the OVH hostname (e.g. vps-267b8d89.vps.ovh.us)
    // For others, fall back to IP
    final ovhHost = machine.provider.startsWith('ovh') ? machine.name : null;
    final sshHost = ovhHost ?? ip;
    final defaultUser = machine.provider.startsWith('ovh') ? 'debian' : 'root';
    final sshCommandDefault = 'ssh $defaultUser@$sshHost';
    final keyFlag = sshKeyFile != null ? ' -i $sshKeyFile' : '';

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.terminal, size: 18, color: AppColors.tertiary),
                const SizedBox(width: 8),
                const Text('SSH ACCESS', style: AppTheme.labelStyle),
                const Spacer(),
                FilledButton.icon(
                  onPressed: () {
                    final outerContext = context;
                    showDialog(
                      context: context,
                      builder: (ctx) => _SshPasswordDialog(
                        host: sshHost,
                        username: defaultUser,
                        sshKeyFile: sshKeyFile,
                        titleOverride: '$defaultUser@$sshHost',
                        onConnect: (password) {
                          Navigator.pop(ctx);
                          Navigator.of(outerContext).push(
                            MaterialPageRoute(
                              builder: (_) => SshTerminalScreen(
                                host: sshHost,
                                username: defaultUser,
                                sshKeyFile: sshKeyFile,
                                password: password,
                                titleOverride: '$defaultUser@$sshHost',
                              ),
                            ),
                          );
                        },
                      ),
                    );
                  },
                  icon: const Icon(Icons.terminal, size: 16),
                  label: const Text('OPEN TERMINAL'),
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                    textStyle: TextStyle(fontSize: 11, fontFamily: AppTheme.bodyFont, letterSpacing: 0.5),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: AppColors.codeBackground,
                borderRadius: BorderRadius.circular(4),
                border: Border.all(color: AppColors.outline),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(sshCommandDefault, style: TextStyle(fontFamily: AppTheme.bodyFont, fontSize: 14, color: AppColors.codeForeground)),
                      ),
                      IconButton(
                        icon: Icon(Icons.copy, size: 16, color: AppColors.secondary.withValues(alpha: 0.6)),
                        tooltip: 'Copy SSH command',
                        onPressed: () {
                          Clipboard.setData(ClipboardData(text: sshCommandDefault));
                          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Copied: $sshCommandDefault')));
                        },
                      ),
                    ],
                  ),
                  // Show IP fallback when hostname differs from IP
                  if (sshHost != ip) ...[
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Expanded(
                          child: Text('ssh $defaultUser@$ip${keyFlag.isEmpty ? '' : keyFlag}', style: TextStyle(fontFamily: AppTheme.bodyFont, fontSize: 12, color: AppColors.secondary.withValues(alpha: 0.7))),
                        ),
                        IconButton(
                          icon: Icon(Icons.copy, size: 14, color: AppColors.secondary.withValues(alpha: 0.4)),
                          tooltip: 'Copy IP command',
                          onPressed: () {
                            final cmd = 'ssh $defaultUser@$ip${keyFlag.isEmpty ? '' : keyFlag}';
                            Clipboard.setData(ClipboardData(text: cmd));
                            ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Copied: $cmd')));
                          },
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
            if (sshKeyFile != null) ...[
              const SizedBox(height: 8),
              Row(
                children: [
                  const Icon(Icons.vpn_key, size: 14, color: AppColors.success),
                  const SizedBox(width: 6),
                  Text('Key: ', style: TextStyle(fontSize: 12, color: AppColors.secondary, fontFamily: AppTheme.bodyFont)),
                  Expanded(child: Text(sshKeyFile!, style: TextStyle(fontSize: 12, color: AppColors.success, fontFamily: AppTheme.bodyFont), overflow: TextOverflow.ellipsis)),
                ],
              ),
            ] else ...[
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: AppColors.tertiary.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(2),
                  border: Border.all(color: AppColors.tertiary.withValues(alpha: 0.15)),
                ),
                child: Row(
                  children: [
                    Icon(Icons.vpn_key, size: 12, color: AppColors.tertiary.withValues(alpha: 0.7)),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        'Default SSH keys from ~/.ssh/ will be tried automatically',
                        style: TextStyle(fontSize: 11, color: AppColors.secondary, fontFamily: AppTheme.bodyFont),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 8),
            Text(
              ovhHost != null
                  ? 'OVH host $sshHost resolves to $ip. Click OPEN TERMINAL for an in-app SSH session.'
                  : machine.provider.startsWith('ovh')
                      ? 'OVH machines use debian as the default user. Click OPEN TERMINAL for an in-app SSH session.'
                      : 'Click OPEN TERMINAL for an in-app SSH session, or copy the command.',
              style: TextStyle(fontSize: 13, color: AppColors.secondary.withValues(alpha: 0.7), fontFamily: AppTheme.bodyFont),
            ),
          ],
        ),
      ),
    );
  }
}

/// Section showing running Uncloud services on this machine,
/// including psql connect for postgres services.
class _UncloudServicesSection extends ConsumerWidget {
  final MachineInfo machine;
  const _UncloudServicesSection({required this.machine});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final configAsync = ref.watch(uncloudConfigProvider);
    if (!configAsync.hasValue || configAsync.value == null) return const SizedBox.shrink();

    // Check if this machine has a Uncloud association (from DB sync or config match)
    final config = configAsync.value!;
    bool isUcMachine = machine.uncloudMachineId != null;
    if (!isUcMachine) {
      // Fallback: check config by IP
      for (final ctx in config.contexts.values) {
        for (final conn in ctx.connections) {
          for (final ip in machine.ipAddresses) {
            if (conn.sshTarget.contains(ip)) {
              isUcMachine = true;
              break;
            }
          }
          if (isUcMachine) break;
        }
        if (isUcMachine) break;
      }
    }
    if (!isUcMachine) return const SizedBox.shrink();

    // Determine the machine's UC context for --context flag
    final machineContext = machine.uncloudContext ?? _resolveMachineContext(config, machine);

    final containersAsync = machineContext != null
        ? ref.watch(uncloudContainersForIpAndContextProvider((machineContext, machine.ipAddresses.firstOrNull ?? '')))
        : ref.watch(uncloudContainersForIpProvider(machine.ipAddresses.firstOrNull ?? ''));
    final servicesAsync = machineContext != null
        ? ref.watch(uncloudServicesForContextProvider(machineContext))
        : ref.watch(uncloudRunningServicesProvider);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.widgets, size: 18, color: AppColors.tertiary),
                const SizedBox(width: 8),
                const Text('UC SERVICES', style: AppTheme.labelStyle),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.refresh, size: 16),
                  tooltip: 'Refresh services',
                  onPressed: () {
                    if (machineContext != null) {
                      ref.invalidate(uncloudServicesForContextProvider(machineContext));
                      ref.invalidate(uncloudContainersForIpAndContextProvider((machineContext, machine.ipAddresses.firstOrNull ?? '')));
                      ref.invalidate(uncloudMachinesForContextProvider(machineContext));
                    } else {
                      ref.invalidate(uncloudRunningServicesProvider);
                      ref.invalidate(uncloudContainersForIpProvider(machine.ipAddresses.firstOrNull ?? ''));
                      ref.invalidate(uncloudRunningMachinesProvider);
                    }
                  },
                ),
              ],
            ),
            const SizedBox(height: 16),
            servicesAsync.when(
              loading: () => const Center(child: SizedBox(height: 24, child: CircularProgressIndicator(strokeWidth: 2))),
              error: (_, __) => Text('Could not load services', style: TextStyle(fontSize: 13, color: AppColors.danger, fontFamily: AppTheme.bodyFont)),
              data: (services) {
                if (services.isEmpty) {
                  return Text('No services running on this cluster', style: TextStyle(fontSize: 13, color: AppColors.secondary.withValues(alpha: 0.7), fontFamily: AppTheme.bodyFont));
                }

                // Match services to this machine via containers
                final containersForMachine = containersAsync.value ?? [];
                final pgServices = services.where((s) => s.isPostgres).toList();

                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // ── Service list ──
                    const Text('RUNNING', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 1.2, fontFamily: AppTheme.displayFont, color: AppColors.secondary)),
                    const SizedBox(height: 8),
                    ...services.map((svc) => Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        decoration: BoxDecoration(
                          color: AppColors.surfaceVariant,
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(color: AppColors.outline),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              svc.isPostgres ? Icons.storage : Icons.widgets,
                              size: 16,
                              color: svc.isPostgres ? AppColors.success : AppColors.secondary,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(svc.name, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500, fontFamily: AppTheme.bodyFont)),
                                  Text(svc.image, style: TextStyle(fontSize: 11, color: AppColors.secondary.withValues(alpha: 0.7), fontFamily: AppTheme.bodyFont)),
                                ],
                              ),
                            ),
                            if (svc.endpoints.isNotEmpty) ...[
                              const SizedBox(width: 8),
                              Flexible(child: Text(svc.endpoints, style: TextStyle(fontSize: 10, color: AppColors.tertiary, fontFamily: AppTheme.bodyFont), overflow: TextOverflow.ellipsis)),
                            ],
                          ],
                        ),
                      ),
                    )),

                    // ── PSQL connect action ──
                    if (pgServices.isNotEmpty) ...[
                      const SizedBox(height: 16),
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
                                onPressed: () {
                                  // Use the machine's assigned context, or fall back to active context
                                  final ucContext = machineContext ?? config.currentContext;
                                  _openPsqlTerminal(context, ref, pgSvc.name, ucContext);
                                },
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
    );
  }

  /// Resolve the Uncloud context name for this machine from the config.
  /// Checks machine.uncloudContext first, then matches by IP/hostname.
  static String? _resolveMachineContext(UncloudConfig config, MachineInfo machine) {
    // 1. Explicit assignment from DB
    if (machine.uncloudContext != null && machine.uncloudContext!.isNotEmpty) {
      return machine.uncloudContext;
    }
    // 2. Match by machine ID
    if (machine.uncloudMachineId != null) {
      final ctx = config.contextForMachineId(machine.uncloudMachineId!);
      if (ctx != null) return ctx.name;
    }
    // 3. Match by IP
    for (final ctx in config.contexts.values) {
      for (final conn in ctx.connections) {
        for (final ip in machine.ipAddresses) {
          if (conn.sshTarget.contains(ip)) {
            return ctx.name;
          }
        }
      }
    }
    // 4. Match by hostname
    for (final ctx in config.contexts.values) {
      for (final conn in ctx.connections) {
        if (conn.sshTarget.contains(machine.name)) {
          return ctx.name;
        }
      }
    }
    return null;
  }

  void _openPsqlTerminal(BuildContext context, WidgetRef ref, String serviceName, String? contextName) {
    // Build the uc exec command: uc --context <context> exec <service> psql -U postgres
    final cmd = contextName != null
        ? ['uc', '--context', contextName, 'exec', serviceName, 'psql', '-U', 'postgres']
        : ['uc', 'exec', serviceName, 'psql', '-U', 'postgres'];
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => SshTerminalScreen(
          host: '', // Not used for local commands
          username: '',
          localCommand: cmd,
          titleOverride: 'psql://$serviceName${contextName != null ? " [$contextName]" : ""}',
        ),
      ),
    );
  }
}

class _ProductsSection extends ConsumerWidget {
  final MachineInfo machine;
  const _ProductsSection({required this.machine});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final productsAsync = ref.watch(productsProvider);
    // Find products that contain this machine
    final associatedProducts = productsAsync.value
        ?.where((p) => p.resources.any((r) => r.resourceType == 'machine' && r.resourceId == machine.id))
        .toList() ?? [];

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.folder_special, size: 18, color: AppColors.tertiary),
                const SizedBox(width: 8),
                const Text('PRODUCTS', style: AppTheme.labelStyle),
                const Spacer(),
                FilledButton.icon(
                  onPressed: () => _showAddToProductDialog(context, ref),
                  icon: const Icon(Icons.add, size: 16),
                  label: const Text('ADD TO PRODUCT'),
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                    textStyle: TextStyle(fontSize: 11, fontFamily: AppTheme.bodyFont, letterSpacing: 0.5),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            if (associatedProducts.isEmpty)
              const Center(
                child: Column(
                  children: [
                    Icon(Icons.inventory_2_outlined, size: 48, color: AppColors.outline),
                    SizedBox(height: 12),
                    Text('Not yet associated with a product', style: TextStyle(fontSize: 14, color: AppColors.secondary, fontFamily: AppTheme.bodyFont)),
                    SizedBox(height: 4),
                    Text(
                      'Products group machines, domains, DNS, and workers into deployed services.',
                      style: TextStyle(fontSize: 13, color: AppColors.secondary, fontFamily: AppTheme.bodyFont),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              )
            else
              ...associatedProducts.map((product) => Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: AppColors.tertiary.withValues(alpha: 0.05),
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(color: AppColors.tertiary.withValues(alpha: 0.15)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.folder_special, size: 16, color: AppColors.tertiary),
                      const SizedBox(width: 8),
                      Expanded(child: Text(product.name, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500, fontFamily: AppTheme.bodyFont))),
                      Text('${product.resources.length} resources', style: TextStyle(fontSize: 11, color: AppColors.secondary, fontFamily: AppTheme.bodyFont)),
                    ],
                  ),
                ),
              )),
          ],
        ),
      ),
    );
  }

  void _showAddToProductDialog(BuildContext context, WidgetRef ref) {
    showDialog(context: context, builder: (ctx) => _AddMachineToProductDialog(machineId: machine.id));
  }
}

class _AddMachineToProductDialog extends ConsumerStatefulWidget {
  final String machineId;
  const _AddMachineToProductDialog({required this.machineId});

  @override
  ConsumerState<_AddMachineToProductDialog> createState() => _AddMachineToProductDialogState();
}

class _AddMachineToProductDialogState extends ConsumerState<_AddMachineToProductDialog> {
  String? _selectedProductId;
  bool _submitting = false;

  @override
  Widget build(BuildContext context) {
    final productsAsync = ref.watch(productsProvider);

    return AlertDialog(
      title: const Text('ADD TO PRODUCT', style: TextStyle(fontFamily: AppTheme.displayFont, fontSize: 16)),
      content: SizedBox(
        width: 400,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Associate this machine with a product:',
              style: TextStyle(fontSize: 13, color: AppColors.secondary, fontFamily: AppTheme.bodyFont),
            ),
            const SizedBox(height: 16),
            productsAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (_, __) => Text('Error loading products', style: TextStyle(color: AppColors.danger, fontFamily: AppTheme.bodyFont)),
              data: (products) {
                if (products.isEmpty) {
                  return Text('No products yet. Create one first.', style: TextStyle(color: AppColors.secondary, fontFamily: AppTheme.bodyFont));
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
              : const Text('ADD'),
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
            resourceType: 'machine',
            resourceId: widget.machineId,
          );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Machine added to product')));
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
/// Uncloud section showing cluster context, deployed services, and connection info.
class _UncloudSection extends ConsumerWidget {
  final MachineInfo machine;
  const _UncloudSection({required this.machine});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final configAsync = ref.watch(uncloudConfigProvider);
    final composeFilesAsync = ref.watch(uncloudComposeProvider);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.cloud_outlined, size: 18, color: AppColors.tertiary),
                const SizedBox(width: 8),
                const Text('UNCLOUD', style: AppTheme.labelStyle),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.sync, size: 16),
                  tooltip: 'Sync Uncloud machine IDs',
                  onPressed: () {
                    ref.invalidate(uncloudSyncProvider);
                  },
                ),
                OutlinedButton.icon(
                  onPressed: () => _showUncloudInfoDialog(context),
                  icon: const Icon(Icons.help_outline, size: 16),
                  label: const Text('SETUP'),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                    textStyle: TextStyle(fontSize: 11, fontFamily: AppTheme.bodyFont, letterSpacing: 0.5),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            configAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (_, __) => _buildNoConfig(context),
              data: (config) {
                if (config == null) return _buildNoConfig(context);
                return _buildConfigured(context, ref, config, composeFilesAsync);
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildNoConfig(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.cloud_off, size: 48, color: AppColors.outline),
            const SizedBox(height: 12),
            const Text('Not connected to Uncloud', style: TextStyle(fontSize: 14, color: AppColors.secondary, fontFamily: AppTheme.bodyFont)),
            const SizedBox(height: 4),
            Text(
              'Run `uc machine init` to connect this machine to an Uncloud cluster.\n'
              'Uncloud manages container deployment, DNS, and infrastructure as code.',
              style: TextStyle(fontSize: 13, color: AppColors.secondary.withValues(alpha: 0.7), fontFamily: AppTheme.bodyFont),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildConfigured(BuildContext context, WidgetRef ref, UncloudConfig config, AsyncValue<List<UncloudComposeFile>> composeFilesAsync) {
    final activeContext = config.activeContext;
    final machineConnections = <UncloudConnection>[];
    final matchedContextNames = <String>[];
    for (final ctx in config.contexts.values) {
      for (final conn in ctx.connections) {
        bool matched = false;
        // Match by Uncloud machine ID (from DB sync)
        if (machine.uncloudMachineId != null && conn.machineId == machine.uncloudMachineId) {
          matched = true;
        }
        // Match by machine ID format in provider ID
        if (!matched && conn.machineId != null && machine.id.contains(conn.machineId!)) {
          matched = true;
        }
        // Match by IP in SSH target
        if (!matched) {
          for (final ip in machine.ipAddresses) {
            if (conn.sshTarget.contains(ip)) {
              matched = true;
              break;
            }
          }
        }
        // Match by hostname in SSH target
        if (!matched && conn.sshTarget.contains(machine.name)) {
          matched = true;
        }
        if (matched) {
          machineConnections.add(conn);
          if (!matchedContextNames.contains(ctx.name)) {
            matchedContextNames.add(ctx.name);
          }
        }
      }
    }
    // Deduplicate by SSH target
    final uniqueConnections = {for (final c in machineConnections) c.sshTarget: c}.values.toList();

    // Find services deployed to this machine
    final composeFiles = composeFilesAsync.value ?? <UncloudComposeFile>[];
    final deployedServices = <UncloudServiceDef>[];
    for (final file in composeFiles) {
      for (final svc in file.services) {
        if (svc.hasMachineRestriction) {
          // Check if machine name or IPs match
          for (final m in svc.xMachines) {
            if (m == machine.name || machine.ipAddresses.contains(m) || machine.id.contains(m)) {
              deployedServices.add(svc);
            }
          }
        } else {
          // Unrestricted — deployed to all machines in the context
          if (file.xContext == activeContext?.name || file.xContext == null) {
            deployedServices.add(svc);
          }
        }
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ── Uncloud Machine ID (from DB sync) ──
        if (machine.uncloudMachineId != null) ...[
          Row(
            children: [
              const Icon(Icons.fingerprint, size: 14, color: AppColors.success),
              const SizedBox(width: 6),
              const Text('UC MACHINE ID', style: AppTheme.labelStyle),
              const SizedBox(width: 8),
              CodeBlock(text: machine.uncloudMachineId!),
              if (machine.uncloudContext != null) ...[
                const SizedBox(width: 8),
                Text('ctx: ${machine.uncloudContext}', style: TextStyle(fontSize: 11, color: AppColors.secondary, fontFamily: AppTheme.bodyFont)),
              ],
            ],
          ),
          const SizedBox(height: 12),
        ],

        // ── Assign UC Context ──
        _buildAssignContextSection(context, ref, config),

        // ── Cluster info with validation ──
        if (activeContext != null) ...[
          Row(
            children: [
              const Icon(Icons.dns, size: 14, color: AppColors.tertiary),
              const SizedBox(width: 6),
              const Text('CLUSTER', style: AppTheme.labelStyle),
              const SizedBox(width: 8),
              InkWell(
                onTap: () => _showContextDetail(context, ref, activeContext.name, activeContext, true),
                borderRadius: BorderRadius.circular(2),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CodeBlock(text: activeContext.name),
                    const SizedBox(width: 4),
                    Icon(Icons.open_in_new, size: 11, color: AppColors.tertiary.withValues(alpha: 0.7)),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Text('${activeContext.connections.length} connection${activeContext.connections.length != 1 ? 's' : ''}',
                  style: TextStyle(fontSize: 12, color: AppColors.secondary, fontFamily: AppTheme.bodyFont)),
              if (uniqueConnections.isNotEmpty) ...[
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: AppColors.success.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(2),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.check_circle, size: 12, color: AppColors.success),
                      SizedBox(width: 4),
                      Text('VALIDATED', style: TextStyle(fontSize: 9, fontWeight: FontWeight.w700, color: AppColors.success, fontFamily: AppTheme.bodyFont, letterSpacing: 0.5)),
                    ],
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 12),
        ] else if (matchedContextNames.isNotEmpty) ...[
          Row(
            children: [
              const Icon(Icons.dns, size: 14, color: AppColors.warning),
              const SizedBox(width: 6),
              const Text('CLUSTER', style: AppTheme.labelStyle),
              const SizedBox(width: 8),
              ...matchedContextNames.map((name) {
                final ctx = config.contexts[name];
                return Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: InkWell(
                    onTap: ctx != null ? () => _showContextDetail(context, ref, name, ctx, name == config.currentContext) : null,
                    borderRadius: BorderRadius.circular(2),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        CodeBlock(text: name),
                        if (ctx != null) ...[
                          const SizedBox(width: 2),
                          Icon(Icons.open_in_new, size: 10, color: AppColors.warning.withValues(alpha: 0.7)),
                        ],
                      ],
                    ),
                  ),
                );
              }),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: AppColors.warning.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(2),
                ),
                child: const Text('NOT ACTIVE', style: TextStyle(fontSize: 9, fontWeight: FontWeight.w700, color: AppColors.warning, fontFamily: AppTheme.bodyFont, letterSpacing: 0.5)),
              ),
            ],
          ),
          const SizedBox(height: 12),
        ],

        // ── Connections ──
        if (uniqueConnections.isNotEmpty) ...[
          const Text('CONNECTIONS', style: AppTheme.labelStyle),
          const SizedBox(height: 8),
          ...uniqueConnections.map((conn) => Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: AppColors.surfaceVariant,
                borderRadius: BorderRadius.circular(4),
                border: Border.all(color: AppColors.outline),
              ),
              child: Row(
                children: [
                  Icon(_connectionTypeIcon(conn.typeLabel), size: 16, color: AppColors.tertiary),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(conn.sshTarget, style: TextStyle(fontSize: 13, fontFamily: AppTheme.bodyFont, fontWeight: FontWeight.w500)),
                        if (conn.machineId != null)
                          Text('ID: ${conn.machineId}', style: TextStyle(fontSize: 10, fontFamily: AppTheme.bodyFont, color: AppColors.secondary.withValues(alpha: 0.6))),
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
            ),
          )),
          const SizedBox(height: 12),
        ] else ...[
          Text('No matching connections found for this machine',
              style: TextStyle(fontSize: 13, color: AppColors.secondary.withValues(alpha: 0.7), fontFamily: AppTheme.bodyFont)),
          const SizedBox(height: 12),
        ],

        // ── Deployed services ──
        if (deployedServices.isNotEmpty) ...[
          const Text('DEPLOYED SERVICES', style: AppTheme.labelStyle),
          const SizedBox(height: 8),
          ...deployedServices.map((svc) => Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: AppColors.surfaceVariant,
                borderRadius: BorderRadius.circular(4),
                border: Border.all(color: AppColors.outline),
              ),
              child: Row(
                children: [
                  const Icon(Icons.widgets, size: 16, color: AppColors.secondary),
                  const SizedBox(width: 8),
                  Expanded(child: Text(svc.name, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500, fontFamily: AppTheme.bodyFont))),
                  if (svc.image != null) ...[
                    CodeBlock(text: _truncateImage(svc.image!)),
                  ],
                ],
              ),
            ),
          )),
        ],
      ],
    );
  }

  Widget _buildAssignContextSection(BuildContext context, WidgetRef ref, UncloudConfig config) {
    final contexts = config.contexts.keys.toList();
    if (contexts.isEmpty) return const SizedBox.shrink();

    // Find which context this machine belongs to (if any)
    final currentContext = machine.uncloudContext;
    // Also check config-based matching
    final matchedContext = config.contextForMachineId(machine.uncloudMachineId ?? '');
    final displayContext = currentContext ?? matchedContext?.name;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(Icons.alt_route, size: 14, color: AppColors.tertiary),
            const SizedBox(width: 6),
            const Text('ASSIGN CONTEXT', style: AppTheme.labelStyle),
            const Spacer(),
            if (displayContext != null) ...[
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: AppColors.success.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(2),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.check_circle, size: 12, color: AppColors.success),
                    const SizedBox(width: 4),
                    Text(displayContext, style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: AppColors.success, fontFamily: AppTheme.bodyFont)),
                  ],
                ),
              ),
            ],
          ],
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: contexts.map((ctxName) {
            final isAssigned = ctxName == displayContext;
            final isCurrent = ctxName == config.currentContext;
            return InkWell(
              onTap: () => _assignContext(context, ref, ctxName),
              borderRadius: BorderRadius.circular(4),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: isAssigned
                      ? AppColors.tertiary.withValues(alpha: 0.15)
                      : AppColors.surfaceVariant,
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(
                    color: isAssigned
                        ? AppColors.tertiary
                        : isCurrent
                            ? AppColors.success.withValues(alpha: 0.3)
                            : AppColors.outline,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(isAssigned ? Icons.check_circle : (isCurrent ? Icons.circle : Icons.circle_outlined),
                        size: 14, color: isAssigned ? AppColors.tertiary : (isCurrent ? AppColors.success : AppColors.secondary)),
                    const SizedBox(width: 6),
                    Text(ctxName, style: TextStyle(
                      fontSize: 12,
                      fontWeight: isAssigned ? FontWeight.w700 : FontWeight.w500,
                      color: isAssigned ? AppColors.tertiary : AppColors.primary,
                      fontFamily: AppTheme.bodyFont,
                    )),
                    if (isCurrent) ...[
                      const SizedBox(width: 4),
                      Text('active', style: TextStyle(fontSize: 9, color: AppColors.success.withValues(alpha: 0.7), fontFamily: AppTheme.bodyFont)),
                    ],
                  ],
                ),
              ),
            );
          }).toList(),
        ),
        if (displayContext != null) ...[
          const SizedBox(height: 8),
          TextButton.icon(
            onPressed: () => _clearContext(context, ref),
            icon: const Icon(Icons.clear, size: 14),
            label: const Text('Clear assignment'),
            style: TextButton.styleFrom(
              foregroundColor: AppColors.danger,
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              textStyle: TextStyle(fontSize: 11, fontFamily: AppTheme.bodyFont),
            ),
          ),
        ],
        const SizedBox(height: 12),
      ],
    );
  }

  Future<void> _assignContext(BuildContext context, WidgetRef ref, String contextName) async {
    try {
      final db = ref.read(databaseProvider);
      await db.cachedMachineDao.setUncloudId(machine.id, machine.uncloudMachineId, contextName);
      // Refresh providers to reflect changes
      ref.invalidate(machinesProvider);
      ref.invalidate(machineAliasesProvider);
      ref.invalidate(uncloudSyncProvider);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Assigned to UC context: $contextName')),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to assign context: $e'), backgroundColor: AppColors.danger),
        );
      }
    }
  }

  Future<void> _clearContext(BuildContext context, WidgetRef ref) async {
    try {
      final db = ref.read(databaseProvider);
      await db.cachedMachineDao.setUncloudId(machine.id, null, null);
      ref.invalidate(machinesProvider);
      ref.invalidate(machineAliasesProvider);
      ref.invalidate(uncloudSyncProvider);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Cleared UC context assignment')),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to clear context: $e'), backgroundColor: AppColors.danger),
        );
      }
    }
  }

  IconData _connectionTypeIcon(String typeLabel) {
    switch (typeLabel) {
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

  /// Show a dialog with context details: services, machines, domain.
  void _showContextDetail(BuildContext context, WidgetRef ref, String contextName, UncloudContext ctx, bool isActive) {
    showUncloudContextDetailDialog(context: context, contextName: contextName, ctx: ctx, isActive: isActive);
  }

  void _showUncloudInfoDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('UNLOUD SETUP', style: TextStyle(fontFamily: AppTheme.displayFont, fontSize: 16)),
        content: SizedBox(
          width: 450,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Uncloud connects your machines into a cluster and deploys services using a Compose file.',
                style: TextStyle(fontSize: 13, color: AppColors.secondary, fontFamily: AppTheme.bodyFont),
              ),
              const SizedBox(height: 16),
              const Text('Quick Start', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, fontFamily: AppTheme.displayFont)),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.codeBackground,
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: AppColors.outline),
                ),
                child: const Text(
                  '# Install uc CLI\nbrew install psviderski/tap/uncloud\n\n# Initialize cluster from this machine\nuc machine init debian@192.168.1.1\n\n# Deploy a service\nuc deploy',
                  style: TextStyle(fontFamily: AppTheme.bodyFont, fontSize: 12, color: AppColors.codeForeground, height: 1.5),
                ),
              ),
              const SizedBox(height: 16),
              const Text('Config file', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, fontFamily: AppTheme.displayFont)),
              const SizedBox(height: 4),
              Text('~/.config/uncloud/config.yaml', style: TextStyle(fontSize: 12, color: AppColors.secondary, fontFamily: AppTheme.bodyFont)),
              const SizedBox(height: 8),
              const Text(
                'Each machine connection includes an SSH target and an optional machine_id. '
                'The uc CLI manages this file automatically.',
                style: TextStyle(fontSize: 13, color: AppColors.secondary, fontFamily: AppTheme.bodyFont),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Close')),
        ],
      ),
    );
  }
}

String _truncateImage(String image) {
  final parts = image.split(':');
  final tag = parts.length > 1 ? parts.last : image;
  return tag.length > 24 ? '${tag.substring(0, 21)}...' : tag;
}

/// Stat card showing the service type with icon and provider color.
class _ServiceTypeStatCard extends StatelessWidget {
  final MachineInfo machine;
  const _ServiceTypeStatCard({required this.machine});

  @override
  Widget build(BuildContext context) {
    final color = AppTheme.providerColor(machine.provider);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('TYPE', style: AppTheme.labelStyle),
            const SizedBox(height: 8),
            Row(
              children: [
                Icon(AppTheme.serviceTypeIcon(machine.provider), size: 20, color: color),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    machine.serviceTypeLabel,
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: color, fontFamily: AppTheme.displayFont),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Dialog shown before opening an SSH terminal, allowing the user
/// to optionally enter a password for authentication.
class _SshPasswordDialog extends StatefulWidget {
  final String host;
  final String username;
  final String? sshKeyFile;
  final String titleOverride;
  final void Function(String? password) onConnect;

  const _SshPasswordDialog({
    required this.host,
    required this.username,
    this.sshKeyFile,
    required this.titleOverride,
    required this.onConnect,
  });

  @override
  State<_SshPasswordDialog> createState() => _SshPasswordDialogState();
}

class _SshPasswordDialogState extends State<_SshPasswordDialog> {
  final _passwordController = TextEditingController();
  bool _obscurePassword = true;

  @override
  void dispose() {
    _passwordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Row(
        children: [
          const Icon(Icons.terminal, size: 20, color: AppColors.tertiary),
          const SizedBox(width: 8),
          const Text('SSH Authentication', style: TextStyle(fontFamily: AppTheme.displayFont, fontSize: 16)),
        ],
      ),
      content: SizedBox(
        width: 400,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Connect to ${widget.username}@${widget.host}',
              style: TextStyle(fontSize: 13, color: AppColors.secondary.withValues(alpha: 0.7), fontFamily: AppTheme.bodyFont),
            ),
            if (widget.sshKeyFile != null) ...[
              const SizedBox(height: 8),
              Row(
                children: [
                  const Icon(Icons.vpn_key, size: 14, color: AppColors.success),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      'Key: ${widget.sshKeyFile}',
                      style: TextStyle(fontSize: 12, color: AppColors.success, fontFamily: AppTheme.bodyFont),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ] else ...[
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppColors.tertiary.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: AppColors.tertiary.withValues(alpha: 0.2)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.vpn_key, size: 14, color: AppColors.tertiary),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        'Default SSH keys from ~/.ssh/ will be tried automatically (id_ed25519, id_ecdsa, id_rsa)',
                        style: TextStyle(fontSize: 11, color: AppColors.secondary, fontFamily: AppTheme.bodyFont),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 16),
            TextField(
              controller: _passwordController,
              obscureText: _obscurePassword,
              decoration: InputDecoration(
                labelText: 'Password (optional)',
                hintText: 'Leave empty for key-based auth',
                suffixIcon: IconButton(
                  icon: Icon(_obscurePassword ? Icons.visibility_off : Icons.visibility, size: 18),
                  onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                ),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'If SSH key authentication fails, the password will be used as a fallback.',
              style: TextStyle(fontSize: 11, color: AppColors.secondary.withValues(alpha: 0.6), fontFamily: AppTheme.bodyFont),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton.icon(
          onPressed: () {
            final password = _passwordController.text.isEmpty ? null : _passwordController.text;
            widget.onConnect(password);
          },
          icon: const Icon(Icons.terminal, size: 16),
          label: const Text('CONNECT'),
        ),
      ],
    );
  }
}
