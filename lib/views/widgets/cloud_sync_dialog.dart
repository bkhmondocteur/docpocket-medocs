import 'package:flutter/material.dart';
import '../../core/constants/app_colors.dart';
import '../../core/services/license_service.dart';
import '../../core/services/supabase_sync_service.dart';

/// Boîte de dialogue pour le suivi et le déclenchement de la synchronisation Cloud
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
  bool _isSyncing = false;

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
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // En-tête
              Row(
                children: [
                  const Icon(Icons.cloud_sync_rounded, color: AppColors.primaryBlue, size: 26),
                  const SizedBox(width: 10),
                  const Expanded(
                    child: Text(
                      'Synchronisation Cloud',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: AppColors.slateDark,
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close_rounded, color: AppColors.slateMedium),
                    onPressed: () => Navigator.of(context).pop(),
                    visualDensity: VisualDensity.compact,
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // État actuel
              Container(
                padding: const EdgeInsets.all(14),
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
                    const SizedBox(height: 8),
                    Text(
                      'Cabinet ID : ${license.activeCabinetId}',
                      style: const TextStyle(fontSize: 12, fontFamily: 'monospace', color: AppColors.slateDark),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Session active : ${license.userDisplayName} (${license.currentSession?.role.label ?? "Non connecté"})',
                      style: const TextStyle(fontSize: 12, color: AppColors.slateMedium),
                    ),
                    if (sync.lastSyncTime != null) ...[
                      const SizedBox(height: 4),
                      Text(
                        'Dernière synchronisation : ${sync.lastSyncTime!.hour.toString().padLeft(2, '0')}:${sync.lastSyncTime!.minute.toString().padLeft(2, '0')}:${sync.lastSyncTime!.second.toString().padLeft(2, '0')}',
                        style: const TextStyle(fontSize: 11.5, color: AppColors.slateMedium, fontStyle: FontStyle.italic),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 18),

              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primaryBlue,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 13),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
                onPressed: _isSyncing ? null : _triggerManualSync,
                icon: _isSyncing
                    ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                    : const Icon(Icons.sync_rounded),
                label: Text(
                  _isSyncing ? 'Synchronisation en cours...' : 'Synchroniser maintenant',
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                ),
              ),
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
    );
  }
}
