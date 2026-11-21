import 'package:flutter/material.dart';
import '../../core/constants/app_colors.dart';
import '../../core/services/auto_backup_service.dart';
import '../../core/services/backup/backup_storage_interface.dart';

/// Boîte de dialogue de configuration et de gestion des sauvegardes automatiques
class AutoBackupDialog extends StatefulWidget {
  final bool isFirstLaunch;

  const AutoBackupDialog({super.key, this.isFirstLaunch = false});

  static Future<void> show(BuildContext context, {bool isFirstLaunch = false}) {
    return showDialog(
      context: context,
      barrierDismissible: !isFirstLaunch,
      builder: (_) => AutoBackupDialog(isFirstLaunch: isFirstLaunch),
    );
  }

  @override
  State<AutoBackupDialog> createState() => _AutoBackupDialogState();
}

class _AutoBackupDialogState extends State<AutoBackupDialog> {
  List<BackupFileInfo> _backups = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadBackups();
  }

  Future<void> _loadBackups() async {
    setState(() => _isLoading = true);
    final list = await AutoBackupService.instance.getExistingBackups();
    if (mounted) {
      setState(() {
        _backups = list;
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final currentDir = AutoBackupService.instance.currentBackupDirectory;
    final isWeb = !AutoBackupService.instance.isFileSystemSupported;

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 540, maxHeight: 680),
        child: Padding(
          padding: const EdgeInsets.all(22),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // En-tête
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: AppColors.alertValid.withValues(alpha: 0.12),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.security_rounded, color: AppColors.alertValid, size: 28),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.isFirstLaunch
                              ? 'Sécurisation de vos données'
                              : 'Sauvegardes automatiques (5 max)',
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: AppColors.slateDark,
                          ),
                        ),
                        const SizedBox(height: 2),
                        const Text(
                          'Rotation automatique : la 6ème écrase la plus ancienne',
                          style: TextStyle(fontSize: 12, color: AppColors.slateMedium),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // Explication
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.blue.shade50,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.blue.shade200, width: 0.8),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.info_outline_rounded, size: 20, color: Colors.blue.shade800),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        widget.isFirstLaunch
                            ? 'Dès maintenant, chaque entrée, sortie ou modification de stock sera automatiquement archivée. '
                                'Veuillez choisir le dossier où stocker vos 5 dernières sauvegardes.'
                            : 'DocPocket Medocs sauvegarde automatiquement tout votre stock à chaque opération. '
                                'Seules les 5 versions les plus récentes sont conservées pour économiser l\'espace.',
                        style: TextStyle(fontSize: 12.5, color: Colors.blue.shade900, height: 1.3),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),

              // Carte du dossier actuel
              Card(
                elevation: 0,
                color: Colors.grey.shade100,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                  side: BorderSide(color: Colors.grey.shade300),
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Row(
                            children: [
                              Icon(Icons.folder_open_rounded, size: 18, color: AppColors.primaryBlue),
                              SizedBox(width: 8),
                              Text(
                                'Dossier de sauvegarde :',
                                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                              ),
                            ],
                          ),
                          if (!isWeb)
                            TextButton.icon(
                              style: TextButton.styleFrom(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                visualDensity: VisualDensity.compact,
                              ),
                              onPressed: () async {
                                final messenger = ScaffoldMessenger.of(context);
                                final changed = await AutoBackupService.instance.chooseBackupDirectory(context);
                                if (changed && mounted) {
                                  _loadBackups();
                                  messenger.showSnackBar(
                                    const SnackBar(
                                      content: Text('Dossier de sauvegarde mis à jour !'),
                                      backgroundColor: AppColors.alertValid,
                                    ),
                                  );
                                }
                              },
                              icon: const Icon(Icons.edit_location_alt_rounded, size: 16),
                              label: const Text('Modifier', style: TextStyle(fontSize: 12)),
                            ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      SelectableText(
                        currentDir ?? 'Dossier sécurisé de l\'application',
                        style: const TextStyle(
                          fontSize: 12,
                          color: AppColors.slateDark,
                          fontFamily: 'monospace',
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 14),

              // Liste des sauvegardes actuelles
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Historique des sauvegardes (${_backups.length}/5)',
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13.5, color: AppColors.slateDark),
                  ),
                  if (_isLoading)
                    const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2)),
                ],
              ),
              const SizedBox(height: 8),

              Expanded(
                child: _isLoading
                    ? const Center(child: CircularProgressIndicator())
                    : _backups.isEmpty
                        ? Center(
                            child: Padding(
                              padding: const EdgeInsets.all(16),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.history_rounded, size: 40, color: Colors.grey.shade400),
                                  const SizedBox(height: 8),
                                  const Text(
                                    'Aucune sauvegarde créée pour l\'instant.\nElle se déclenchera dès la première action.',
                                    textAlign: TextAlign.center,
                                    style: TextStyle(fontSize: 12, color: AppColors.slateMedium),
                                  ),
                                ],
                              ),
                            ),
                          )
                        : ListView.separated(
                            shrinkWrap: true,
                            itemCount: _backups.length,
                            separatorBuilder: (context, index) => const SizedBox(height: 6),
                            itemBuilder: (context, index) {
                              final item = _backups[index];
                              final isLatest = index == 0;

                              return Container(
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                decoration: BoxDecoration(
                                  color: isLatest ? Colors.green.shade50 : Colors.white,
                                  borderRadius: BorderRadius.circular(10),
                                  border: Border.all(
                                    color: isLatest ? Colors.green.shade300 : Colors.grey.shade200,
                                    width: isLatest ? 1.2 : 1,
                                  ),
                                ),
                                child: Row(
                                  children: [
                                    Icon(
                                      isLatest ? Icons.check_circle_rounded : Icons.history_rounded,
                                      color: isLatest ? AppColors.alertValid : AppColors.slateMedium,
                                      size: 20,
                                    ),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Row(
                                            children: [
                                              Text(
                                                item.formattedDate,
                                                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12.5),
                                              ),
                                              if (isLatest) ...[
                                                const SizedBox(width: 6),
                                                Container(
                                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
                                                  decoration: BoxDecoration(
                                                    color: AppColors.alertValid,
                                                    borderRadius: BorderRadius.circular(4),
                                                  ),
                                                  child: const Text(
                                                    'RÉCENTE',
                                                    style: TextStyle(
                                                      color: Colors.white,
                                                      fontSize: 9.5,
                                                      fontWeight: FontWeight.bold,
                                                    ),
                                                  ),
                                                ),
                                              ],
                                            ],
                                          ),
                                          const SizedBox(height: 2),
                                          Text(
                                            '${item.filename} • ${item.formattedSize}',
                                            style: const TextStyle(fontSize: 10.5, color: AppColors.slateMedium),
                                          ),
                                        ],
                                      ),
                                    ),
                                    TextButton(
                                      style: TextButton.styleFrom(
                                        visualDensity: VisualDensity.compact,
                                        padding: const EdgeInsets.symmetric(horizontal: 8),
                                      ),
                                      onPressed: () => _confirmRestore(item),
                                      child: const Text('Restaurer', style: TextStyle(fontSize: 11.5)),
                                    ),
                                  ],
                                ),
                              );
                            },
                          ),
              ),
              const SizedBox(height: 16),

              // Actions du bas
              if (widget.isFirstLaunch)
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () async {
                          final nav = Navigator.of(context);
                          await AutoBackupService.instance.setHasPrompted(true);
                          await AutoBackupService.instance.triggerAutoBackup();
                          if (mounted) nav.pop();
                        },
                        child: const Text('Dossier par défaut', style: TextStyle(fontSize: 12.5)),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.primaryBlue,
                          foregroundColor: Colors.white,
                        ),
                        onPressed: () async {
                          final nav = Navigator.of(context);
                          final ok = await AutoBackupService.instance.chooseBackupDirectory(context);
                          if (ok && mounted) {
                            nav.pop();
                          }
                        },
                        icon: const Icon(Icons.folder_open_rounded, size: 18),
                        label: const Text('Choisir mon dossier', style: TextStyle(fontSize: 12.5)),
                      ),
                    ),
                  ],
                )
              else
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () async {
                          final messenger = ScaffoldMessenger.of(context);
                          await AutoBackupService.instance.triggerAutoBackup();
                          await _loadBackups();
                          if (mounted) {
                            messenger.showSnackBar(
                              const SnackBar(
                                content: Text('Sauvegarde effectuée avec succès !'),
                                backgroundColor: AppColors.alertValid,
                              ),
                            );
                          }
                        },
                        icon: const Icon(Icons.save_rounded, size: 18),
                        label: const Text('Sauvegarder maintenant'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primaryDark,
                        foregroundColor: Colors.white,
                      ),
                      onPressed: () => Navigator.of(context).pop(),
                      child: const Text('Fermer'),
                    ),
                  ],
                ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _confirmRestore(BackupFileInfo item) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: AppColors.alertWarning),
            SizedBox(width: 8),
            Text('Restaurer la sauvegarde ?'),
          ],
        ),
        content: Text(
          'Voulez-vous restaurer les données sauvegardées le ${item.formattedDate} ?\n\n'
          'Le stock actuel sera remplacé par le contenu de cette sauvegarde.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Annuler')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.primaryBlue),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Oui, restaurer', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (confirm == true && mounted) {
      final nav = Navigator.of(context);
      final messenger = ScaffoldMessenger.of(context);
      final success = await AutoBackupService.instance.restoreBackup(item);
      if (mounted) {
        if (success) {
          nav.pop();
          messenger.showSnackBar(
            SnackBar(
              content: Text('Sauvegarde du ${item.formattedDate} restaurée avec succès !'),
              backgroundColor: AppColors.alertValid,
            ),
          );
        } else {
          messenger.showSnackBar(
            const SnackBar(
              content: Text('Échec de la restauration de la sauvegarde.'),
              backgroundColor: AppColors.alertExpired,
            ),
          );
        }
      }
    }
  }
}
