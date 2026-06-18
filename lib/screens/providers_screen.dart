import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/models.dart' show ProviderCredentialInfo, ProviderStatus, kOvhEndpointLabels;
import '../providers/app_providers.dart';
import '../theme/app_theme.dart';

/// All supported OVH endpoints with their display labels.
/// Also available as [kOvhEndpointLabels] from models.
const _ovhEndpoints = kOvhEndpointLabels;

class ProvidersScreen extends ConsumerStatefulWidget {
  const ProvidersScreen({super.key});

  @override
  ConsumerState<ProvidersScreen> createState() => _ProvidersScreenState();
}

class _ProvidersScreenState extends ConsumerState<ProvidersScreen> {
  @override
  Widget build(BuildContext context) {
    final credentialsAsync = ref.watch(providerCredentialsProvider);
    final statusAsync = ref.watch(providerStatusProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('API Providers'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: OutlinedButton.icon(
              onPressed: () => _showAddProviderDialog(context),
              icon: const Icon(Icons.add, size: 18),
              label: const Text('Add Provider'),
            ),
          ),
        ],
      ),
      body: credentialsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, _) => Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, size: 48, color: AppColors.danger),
              const SizedBox(height: 16),
              Text('Error: $err', style: const TextStyle(color: AppColors.danger)),
            ],
          ),
        ),
        data: (credentials) {
          return SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Provider status overview
                const Text(
                  'Provider Status',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 4),
                const Text(
                  'Org-scoped credentials for OVH, Hetzner, Namecheap, and Cloudflare — encrypted at rest',
                  style: TextStyle(fontSize: 13, color: AppColors.secondary),
                ),
                const SizedBox(height: 16),
                statusAsync.when(
                  data: (statuses) => _ProviderStatusGrid(
                    statuses: statuses,
                    ovhEndpoints: {
                      for (final c in credentials.where((c) => c.provider == 'ovh'))
                        if (c.ovhEndpoint != null) c.id: c.ovhEndpoint!
                    },
                  ),
                  loading: () => const SizedBox.shrink(),
                  error: (_, __) => const SizedBox.shrink(),
                ),
                const SizedBox(height: 24),

                // Credentials list
                const Text(
                  'Stored Credentials',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 12),
                if (credentials.isEmpty)
                  Center(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 48),
                      child: Column(
                        children: [
                          const Icon(Icons.vpn_key, size: 64, color: AppColors.outline),
                          const SizedBox(height: 16),
                          const Text(
                            'No org-scoped providers configured yet.',
                            style: TextStyle(color: AppColors.secondary),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Credentials are encrypted with AES-256-GCM before storage.',
                            style: TextStyle(fontSize: 12, color: AppColors.secondary.withValues(alpha: 0.7)),
                          ),
                        ],
                      ),
                    ),
                  )
                else
                  ...credentials.map((c) => _CredentialCard(credential: c)),
              ],
            ),
          );
        },
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showAddProviderDialog(context),
        icon: const Icon(Icons.add),
        label: const Text('Add Provider'),
      ),
    );
  }

  void _showAddProviderDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => const _AddProviderDialog(),
    );
  }
}

class _ProviderStatusGrid extends StatelessWidget {
  final Map<String, ProviderStatus> statuses;
  final Map<String, String> ovhEndpoints; // credentialId -> endpoint key

  const _ProviderStatusGrid({required this.statuses, required this.ovhEndpoints});

  @override
  Widget build(BuildContext context) {
    final providers = [
      ('ovh', 'OVH Cloud', Icons.cloud),
      ('hetzner', 'Hetzner Cloud', Icons.dns),
      ('namecheap', 'Namecheap', Icons.language),
      ('cloudflare', 'Cloudflare', Icons.shield),
    ];

    return Wrap(
      spacing: 12,
      runSpacing: 12,
      children: providers.map((p) {
        final status = statuses[p.$1];
        final ovhEndpoint = p.$1 == 'ovh' && ovhEndpoints.isNotEmpty
            ? ovhEndpoints.values.first
            : null;
        return SizedBox(
          width: 240,
          child: Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  Icon(p.$3, size: 20, color: AppTheme.providerColor(p.$1)),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(p.$2, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                        const SizedBox(height: 2),
                        if (status == null || status.source == 'none')
                          const Text('Not configured', style: TextStyle(fontSize: 11, color: AppColors.secondary))
                        else if (status.source == 'db')
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: AppColors.success.withValues(alpha: 0.1),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: const Text('Org Credential', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: AppColors.success)),
                              ),
                              if (ovhEndpoint != null) ...[
                                const SizedBox(height: 4),
                                _OvhRegionChip(endpoint: ovhEndpoint),
                              ],
                            ],
                          )
                        else if (status.source == 'env')
                          const Text('Env Variable', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: AppColors.warning))
                        else
                          const Text('Not configured', style: TextStyle(fontSize: 11, color: AppColors.secondary)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      }).toList(),
    );
  }
}

/// Small chip showing the OVH region/endpoint name.
class _OvhRegionChip extends StatelessWidget {
  final String endpoint;

  const _OvhRegionChip({required this.endpoint});

  @override
  Widget build(BuildContext context) {
    final label = _ovhEndpoints[endpoint] ?? endpoint;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: AppColors.ovh.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.ovh.withValues(alpha: 0.15)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.public, size: 10, color: AppColors.ovh.withValues(alpha: 0.7)),
          const SizedBox(width: 3),
          Flexible(
            child: Text(
              label,
              style: TextStyle(fontSize: 9, fontWeight: FontWeight.w500, color: AppColors.ovh.withValues(alpha: 0.85)),
              overflow: TextOverflow.ellipsis,
              maxLines: 1,
            ),
          ),
        ],
      ),
    );
  }
}

class _CredentialCard extends ConsumerWidget {
  final ProviderCredentialInfo credential;

  const _CredentialCard({required this.credential});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final providerColor = AppTheme.providerColor(credential.provider);
    final providerLabel = credential.providerLabel;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: providerColor.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: providerColor.withValues(alpha: 0.2)),
                        ),
                        child: Text(
                          providerLabel.toUpperCase(),
                          style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: providerColor),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(credential.label, style: const TextStyle(fontWeight: FontWeight.w500)),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: AppColors.success.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.shield, size: 12, color: AppColors.success),
                            SizedBox(width: 2),
                            Text('Encrypted', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: AppColors.success)),
                          ],
                        ),
                      ),
                    ],
                  ),
                  // Show OVH region prominently
                  if (credential.ovhEndpoint != null) ...[
                    const SizedBox(height: 8),
                    _OvhRegionChip(endpoint: credential.ovhEndpoint!),
                  ],
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 16,
                    runSpacing: 4,
                    children: credential.maskedFields.entries.map((e) => Text(
                          '${e.key}: ${e.value}',
                          style: const TextStyle(fontSize: 11, fontFamily: 'monospace'),
                        )).toList(),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Added ${_formatDate(credential.createdAt)} · Updated ${_formatDate(credential.updatedAt)}',
                    style: const TextStyle(fontSize: 11, color: AppColors.secondary),
                  ),
                ],
              ),
            ),
            IconButton(
              icon: const Icon(Icons.delete_outline, color: AppColors.danger, size: 20),
              onPressed: () => _confirmDelete(context, ref),
            ),
          ],
        ),
      ),
    );
  }

  String _formatDate(DateTime date) {
    return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
  }

  void _confirmDelete(BuildContext context, WidgetRef ref) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Remove Provider Credential'),
        content: const Text('Are you sure you want to remove this provider credential?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.danger),
            onPressed: () async {
              Navigator.pop(ctx);
              try {
                await ref.read(providerCredentialsProvider.notifier).deleteCredential(credential.id);
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Provider removed')),
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
            child: const Text('Remove'),
          ),
        ],
      ),
    );
  }
}

class _AddProviderDialog extends ConsumerStatefulWidget {
  const _AddProviderDialog();

  @override
  ConsumerState<_AddProviderDialog> createState() => _AddProviderDialogState();
}

class _AddProviderDialogState extends ConsumerState<_AddProviderDialog> {
  String _provider = 'ovh';
  final _labelController = TextEditingController();
  String _ovhEndpoint = 'ovh-eu';
  final _ovhAppKeyController = TextEditingController();
  final _ovhAppSecretController = TextEditingController();
  final _ovhConsumerKeyController = TextEditingController();
  final _ovhClientIdController = TextEditingController();
  final _ovhClientSecretController = TextEditingController();
  bool _ovhUseOAuth2 = false;
  final _hetznerTokenController = TextEditingController();
  final _ncApiUserController = TextEditingController();
  final _ncApiKeyController = TextEditingController();
  final _ncClientIpController = TextEditingController();
  final _cfApiTokenController = TextEditingController();
  final _cfAccountIdController = TextEditingController();
  bool _submitting = false;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Row(
        children: [
          Icon(Icons.shield, color: AppColors.primary),
          SizedBox(width: 8),
          Text('Add API Provider'),
        ],
      ),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Credentials are encrypted with AES-256-GCM before storage.',
                style: TextStyle(fontSize: 13, color: AppColors.secondary),
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                initialValue: _provider,
                decoration: const InputDecoration(labelText: 'Provider'),
                items: [
                  DropdownMenuItem(value: 'ovh', child: Text('OVH Cloud')),
                  DropdownMenuItem(value: 'hetzner', child: Text('Hetzner Cloud')),
                  DropdownMenuItem(value: 'namecheap', child: Text('Namecheap')),
                  DropdownMenuItem(value: 'cloudflare', child: Text('Cloudflare')),
                ],
                onChanged: (v) => setState(() => _provider = v!),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _labelController,
                decoration: const InputDecoration(
                  labelText: 'Label',
                  hintText: 'My OVH Account',
                ),
              ),
              const SizedBox(height: 16),
              if (_provider == 'ovh') ...[
                DropdownButtonFormField<String>(
                  initialValue: _ovhEndpoint,
                  decoration: const InputDecoration(
                    labelText: 'Region / Endpoint',
                    prefixIcon: Icon(Icons.public, size: 18),
                  ),
                  items: _ovhEndpoints.entries
                      .map((e) => DropdownMenuItem(value: e.key, child: Text(e.value)))
                      .toList(),
                  onChanged: (v) => setState(() => _ovhEndpoint = v ?? 'ovh-eu'),
                ),
                const SizedBox(height: 12),
                SwitchListTile(
                  title: const Text('Use OAuth2 (Client Credentials)'),
                  subtitle: const Text('Alternative to Application Key authentication'),
                  value: _ovhUseOAuth2,
                  onChanged: (v) => setState(() => _ovhUseOAuth2 = v),
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                ),
                if (_ovhUseOAuth2) ...[
                  const SizedBox(height: 8),
                  TextField(controller: _ovhClientIdController, decoration: const InputDecoration(labelText: 'Client ID')),
                  const SizedBox(height: 8),
                  TextField(controller: _ovhClientSecretController, decoration: const InputDecoration(labelText: 'Client Secret'), obscureText: true),
                ] else ...[
                  const SizedBox(height: 8),
                  TextField(controller: _ovhAppKeyController, decoration: const InputDecoration(labelText: 'Application Key')),
                  const SizedBox(height: 8),
                  TextField(controller: _ovhAppSecretController, decoration: const InputDecoration(labelText: 'Application Secret'), obscureText: true),
                  const SizedBox(height: 8),
                  TextField(controller: _ovhConsumerKeyController, decoration: const InputDecoration(labelText: 'Consumer Key')),
                ],
              ],
              if (_provider == 'hetzner') ...[
                TextField(controller: _hetznerTokenController, decoration: const InputDecoration(labelText: 'API Token'), obscureText: true),
              ],
              if (_provider == 'namecheap') ...[
                TextField(controller: _ncApiUserController, decoration: const InputDecoration(labelText: 'API User')),
                const SizedBox(height: 8),
                TextField(controller: _ncApiKeyController, decoration: const InputDecoration(labelText: 'API Key'), obscureText: true),
                const SizedBox(height: 8),
                TextField(controller: _ncClientIpController, decoration: const InputDecoration(labelText: 'Client IP')),
              ],
              if (_provider == 'cloudflare') ...[
                TextField(controller: _cfApiTokenController, decoration: const InputDecoration(labelText: 'API Token'), obscureText: true),
                const SizedBox(height: 8),
                TextField(controller: _cfAccountIdController, decoration: const InputDecoration(labelText: 'Account ID (optional)')),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(
          onPressed: _submitting ? null : _handleSubmit,
          child: _submitting
              ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
              : const Text('Add Provider'),
        ),
      ],
    );
  }

  Map<String, String> _getCredentials() {
    switch (_provider) {
      case 'ovh':
        final creds = {'endpoint': _ovhEndpoint};
        if (_ovhUseOAuth2) {
          creds['clientId'] = _ovhClientIdController.text;
          creds['clientSecret'] = _ovhClientSecretController.text;
        } else {
          creds['applicationKey'] = _ovhAppKeyController.text;
          creds['applicationSecret'] = _ovhAppSecretController.text;
          creds['consumerKey'] = _ovhConsumerKeyController.text;
        }
        return creds;
      case 'hetzner':
        return {'apiToken': _hetznerTokenController.text};
      case 'namecheap':
        return {
          'apiUser': _ncApiUserController.text,
          'apiKey': _ncApiKeyController.text,
          'clientIp': _ncClientIpController.text,
        };
      case 'cloudflare':
        final creds = {'apiToken': _cfApiTokenController.text};
        if (_cfAccountIdController.text.isNotEmpty) {
          creds['accountId'] = _cfAccountIdController.text;
        }
        return creds;
      default:
        return {};
    }
  }

  Future<void> _handleSubmit() async {
    final credentials = _getCredentials();
    // For OVH, endpoint is always set; check the non-endpoint values
    final hasRealValues = _provider == 'ovh'
        ? credentials.entries.any((e) => e.key != 'endpoint' && e.value.isNotEmpty)
        : credentials.values.any((v) => v.isNotEmpty);
    if (!hasRealValues) return;

    setState(() => _submitting = true);
    try {
      await ref.read(providerCredentialsProvider.notifier).createCredential(
            provider: _provider,
            label: _labelController.text.isEmpty
                ? { 'ovh': 'OVH Cloud', 'hetzner': 'Hetzner Cloud', 'namecheap': 'Namecheap', 'cloudflare': 'Cloudflare' }[_provider]!
                : _labelController.text,
            credentials: credentials,
          );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Provider added — credentials encrypted ✓')),
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