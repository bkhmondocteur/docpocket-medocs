import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../core/constants/app_colors.dart';
import '../../core/services/license_service.dart';
import '../../core/services/supabase_sync_service.dart';

/// Boîte de dialogue pour le paramétrage et le suivi de la synchronisation Supabase Cloud
class CloudSyncDialog extends StatefulWidget {
  const CloudSyncDialog({super.key});

  static Future<void> show(BuildContext context) {
    return showDialog<void>(
      context: context,
      builder: (_) => const CloudSyncDialog(),
    );
  }

  @override
  State<CloudSyncDialog> createState() => _CloudSyncDialogState();
}

class _CloudSyncDialogState extends State<CloudSyncDialog> {
  late TextEditingController _urlController;
  late TextEditingController _keyController;
  bool _autoSync = true;
  bool _showCustomConfig = false;
  bool _isSyncing = false;

  @override
  void initState() {
    super.initState();
    final service = SupabaseSyncService.instance;
    _urlController = TextEditingController(text: service.supabaseUrl);
    _keyController = TextEditingController(text: service.supabaseAnonKey);
    _autoSync = service.isAutoSyncEnabled;
  }

  @override
  void dispose() {
    _urlController.dispose();
    _keyController.dispose();
    super.dispose();
  }

  Future<void> _triggerManualSync() async {
    setState(() => _isSyncing = true);
    final success = await SupabaseSyncService.instance.syncStock(actionDescription: 'Synchronisation manuelle');
    if (mounted) {
      setState(() => _isSyncing = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(success ? 'Synchronisation Cloud réussie !' : 'Synchronisation échouée ou hors-ligne.'),
          backgroundColor: success ? AppColors.alertValid : AppColors.alertExpired,
        ),
      );
    }
  }

  Future<void> _saveConfig() async {
    await SupabaseSyncService.instance.saveConfiguration(
      url: _urlController.text.trim(),
      anonKey: _keyController.text.trim(),
      autoSync: _autoSync,
    );
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Configuration Supabase enregistrée !')),
      );
      setState(() => _showCustomConfig = false);
    }
  }

  void _showSqlDialog() {
    final sql = SupabaseSyncService.getSupabaseSetupSql();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Script SQL Supabase'),
        content: SizedBox(
          width: 550,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Copiez ce script et collez-le dans Supabase > SQL Editor puis cliquez sur RUN :',
                style: TextStyle(fontSize: 12.5),
              ),
              const SizedBox(height: 10),
              Container(
                height: 250,
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.grey.shade300),
                ),
                child: SingleChildScrollView(
                  child: SelectableText(sql, style: const TextStyle(fontFamily: 'monospace', fontSize: 11)),
                ),
              ),
            ],
          ),
        ),
        actions: [
          ElevatedButton.icon(
            icon: const Icon(Icons.copy_rounded, size: 16),
            label: const Text('Copier le script SQL'),
            onPressed: () {
              Clipboard.setData(ClipboardData(text: sql));
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Script SQL copié dans le presse-papiers !')),
              );
            },
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Fermer'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final sync = SupabaseSyncService.instance;
    final license = LicenseService.instance;

    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 20),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // En-tête
                const Row(
                  children: [
                    Icon(Icons.cloud_sync_rounded, color: AppColors.primaryBlue, size: 26),
                    SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Synchronisation Cloud',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: AppColors.slateDark,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),

                // État actuel
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: sync.status == SyncStatus.synced ? Colors.green.shade50 : Colors.blue.shade50,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: sync.status == SyncStatus.synced ? Colors.green.shade300 : Colors.blue.shade200,
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Padding(
                            padding: const EdgeInsets.only(top: 2),
                            child: Icon(
                              sync.status == SyncStatus.synced ? Icons.cloud_done_rounded : Icons.cloud_queue_rounded,
                              color: sync.status == SyncStatus.synced ? Colors.green.shade700 : AppColors.primaryBlue,
                              size: 20,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'État : ${sync.lastSyncMessage}',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 13,
                                color: sync.status == SyncStatus.synced ? Colors.green.shade900 : AppColors.primaryDark,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Cabinet ID : ${license.activeCabinetId}',
                        style: const TextStyle(fontSize: 12, fontFamily: 'monospace', color: AppColors.slateDark),
                      ),
                      Text(
                        'Session active : ${license.userDisplayName} (${license.currentSession?.role.label ?? "Non connecté"})',
                        style: const TextStyle(fontSize: 12, color: AppColors.slateMedium),
                      ),
                      if (sync.lastSyncTime != null)
                        Text(
                          'Dernière synchronisation : ${sync.lastSyncTime!.hour.toString().padLeft(2, '0')}:${sync.lastSyncTime!.minute.toString().padLeft(2, '0')}:${sync.lastSyncTime!.second.toString().padLeft(2, '0')}',
                          style: const TextStyle(fontSize: 11.5, color: AppColors.slateMedium, fontStyle: FontStyle.italic),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),

                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primaryBlue,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  onPressed: _isSyncing ? null : _triggerManualSync,
                  icon: _isSyncing
                      ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                      : const Icon(Icons.sync_rounded),
                  label: Text(
                    _isSyncing ? 'Synchronisation en cours...' : 'Synchroniser maintenant',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),

                const SizedBox(height: 14),
                const Divider(),

                // Paramètres personnalisés
                Row(
                  children: [
                    const Expanded(
                      child: Text(
                        'Configuration personnalisée Supabase',
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    IconButton(
                      icon: Icon(_showCustomConfig ? Icons.expand_less : Icons.expand_more),
                      onPressed: () => setState(() => _showCustomConfig = !_showCustomConfig),
                      visualDensity: VisualDensity.compact,
                    ),
                  ],
                ),

                if (_showCustomConfig) ...[
                  const SizedBox(height: 8),
                  TextField(
                    controller: _urlController,
                    decoration: const InputDecoration(
                      labelText: 'URL du projet Supabase',
                      hintText: 'https://votre-projet.supabase.co',
                      border: OutlineInputBorder(),
                      contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: _keyController,
                    obscureText: true,
                    decoration: const InputDecoration(
                      labelText: 'Clé Anonyme Publique (anon key)',
                      hintText: 'eyJhbGciOi...',
                      border: OutlineInputBorder(),
                      contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    ),
                  ),
                  const SizedBox(height: 10),
                  SwitchListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Synchronisation automatique après chaque modification'),
                    value: _autoSync,
                    onChanged: (val) => setState(() => _autoSync = val),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          icon: const Icon(Icons.code_rounded, size: 16),
                          label: const Text('Script SQL', style: TextStyle(fontSize: 12)),
                          onPressed: _showSqlDialog,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: ElevatedButton(
                          style: ElevatedButton.styleFrom(backgroundColor: AppColors.primaryDark),
                          onPressed: _saveConfig,
                          child: const Text('Enregistrer', style: TextStyle(color: Colors.white)),
                        ),
                      ),
                    ],
                  ),
                ],

                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Fermer'),
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
