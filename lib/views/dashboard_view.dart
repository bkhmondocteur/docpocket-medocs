import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:file_picker/file_picker.dart';
import '../../core/constants/app_colors.dart';
import '../../core/database/database_service.dart';
import '../../core/services/pdf_report_service.dart';
import '../../core/services/barcode_hardware_listener.dart';
import '../../models/medicine.dart';
import '../../models/stock_alert_level.dart';
import 'stock_entry_view.dart';
import 'stock_exit_view.dart';
import 'medicine_detail_view.dart';
import 'widgets/alert_badge.dart';
import 'widgets/big_touch_button.dart';
import 'widgets/camera_scanner_modal.dart';
import 'widgets/medicine_catalog_picker.dart';
import 'widgets/about_dialog.dart';
import 'widgets/auto_backup_dialog.dart';
import 'widgets/add_batch_dialog.dart';
import 'widgets/add_boxes_dialog.dart';
import 'widgets/create_custom_medicine_dialog.dart';
import 'widgets/expiry_notifications_dialog.dart';
import 'widgets/secretary_management_dialog.dart';
import 'widgets/cloud_sync_dialog.dart';
import 'welcome_auth_view.dart';
import '../../core/services/auto_backup_service.dart';
import '../../core/services/expiry_notification_service.dart';
import '../../core/services/medicines_catalog_service.dart';
import '../../core/services/license_service.dart';
import '../../core/services/supabase_sync_service.dart';

/// Tableau de Bord principal de DocPocket Medocs
class DashboardView extends StatefulWidget {
  const DashboardView({super.key});

  @override
  State<DashboardView> createState() => _DashboardViewState();
}

class _DashboardViewState extends State<DashboardView> {
  final _searchController = TextEditingController();
  List<Medicine> _medicines = [];
  List<Medicine> _allMedicines = [];
  ExpirySummary _expirySummary = const ExpirySummary(expired: [], within1Month: [], within3Months: []);
  bool _hasCheckedAutoNotification = false;

  Map<String, int> _stats = {
    'totalMedicines': 0,
    'totalBoxes': 0,
    'countExpired': 0,
    'countWarning': 0,
    'countValid': 0,
  };

  StockAlertLevel? _selectedFilter;
  bool _isLoading = true;
  StreamSubscription<SyncStatus>? _syncSub;

  @override
  void initState() {
    super.initState();
    BarcodeHardwareListener.instance.startListening();
    BarcodeHardwareListener.instance.addListener(_onGlobalBarcodeScanned);
    _syncSub = SupabaseSyncService.instance.onSyncStatusChanged.listen((status) {
      if (status == SyncStatus.synced && mounted) {
        _loadData();
      } else if (mounted) {
        setState(() {});
      }
    });
    _loadData();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await _checkAutoBackupPrompt();
    });
  }

  Future<void> _handleRefresh() async {
    if (SupabaseSyncService.instance.isConfigured) {
      await SupabaseSyncService.instance.syncStock(actionDescription: 'Actualisation manuelle');
    }
    await _loadData();
  }

  Future<void> _checkAutoBackupPrompt() async {
    await AutoBackupService.instance.init();
    if (!AutoBackupService.instance.hasPromptedForBackup && mounted) {
      await AutoBackupDialog.show(context, isFirstLaunch: true);
    }
  }

  @override
  void dispose() {
    _syncSub?.cancel();
    BarcodeHardwareListener.instance.removeListener(_onGlobalBarcodeScanned);
    BarcodeHardwareListener.instance.stopListening();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    final allMeds = await DatabaseService.instance.getAllMedicines();
    final summary = ExpiryNotificationService.instance.computeSummary(allMeds);

    final meds = await DatabaseService.instance.getAllMedicines(
      searchQuery: _searchController.text,
      alertFilter: _selectedFilter,
    );
    final stats = await DatabaseService.instance.getDashboardStats();

    if (mounted) {
      setState(() {
        _allMedicines = allMeds;
        _expirySummary = summary;
        _medicines = meds;
        _stats = stats;
        _isLoading = false;
      });

      // Vérification et notification automatique à l'ouverture
      if (!_hasCheckedAutoNotification) {
        _hasCheckedAutoNotification = true;
        final autoNotify = await ExpiryNotificationService.instance.isAutoNotifyEnabled();
        if (autoNotify && summary.hasAlerts) {
          await ExpiryNotificationService.instance.sendSystemNotification(allMeds);
        }
      }
    }
  }

  void _onGlobalBarcodeScanned(String rawBarcode) {
    if (!mounted) return;
    // Si la douchette scanne depuis l'écran principal, ouvrir la sélection rapide
    _showQuickScanDialog(rawBarcode);
  }

  void _showQuickScanDialog(String barcode) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.barcode_reader, color: AppColors.primaryBlue),
            SizedBox(width: 8),
            Text('Code scanné'),
          ],
        ),
        content: Text('Code détecté : $barcode\nQue souhaitez-vous effectuer ?'),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.of(ctx).pop();
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => StockEntryView(initialBarcode: barcode)),
              ).then((_) => _loadData());
            },
            child: const Text('Entrée Réception'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.primaryDark),
            onPressed: () {
              Navigator.of(ctx).pop();
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const StockExitView()),
              ).then((_) => _loadData());
            },
            child: const Text('Sortie Patient (FEFO)'),
          ),
        ],
      ),
    );
  }

  Future<void> _exportBackupJson() async {
    final jsonStr = await DatabaseService.instance.exportBackupJson();
    if (!mounted) return;

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Sauvegarde JSON générée'),
        content: SizedBox(
          width: 500,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('Voici le contenu de votre sauvegarde (données locales sécurisées) :'),
              const SizedBox(height: 10),
              Container(
                height: 200,
                padding: const EdgeInsets.all(8),
                color: Colors.grey.shade100,
                child: SingleChildScrollView(
                  child: SelectableText(jsonStr, style: const TextStyle(fontSize: 11, fontFamily: 'monospace')),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('Fermer')),
        ],
      ),
    );
  }

  Future<void> _importBackupJson() async {
    if (!LicenseService.instance.isDoctor) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Action réservée exclusivement au Médecin titulaire.'),
            backgroundColor: AppColors.alertExpired,
          ),
        );
      }
      return;
    }

    try {
      final files = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['json'],
      );

      if (files.isNotEmpty) {
        final bytes = await files.first.readAsBytes();
        final content = utf8.decode(bytes);

        if (content.isNotEmpty) {
          await DatabaseService.instance.importBackupJson(content, replace: true);
          await _loadData();
          if (SupabaseSyncService.instance.isConfigured) {
            await SupabaseSyncService.instance.syncStock(
              actionDescription: 'Restauration sauvegarde JSON par le Médecin',
            );
          }
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Sauvegarde restaurée avec succès !'),
                backgroundColor: AppColors.alertValid,
              ),
            );
          }
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erreur import: $e'), backgroundColor: AppColors.alertExpired),
        );
      }
    }
  }

  Future<void> _exportCsv() async {
    final csvContent = await DatabaseService.instance.exportInventoryCsv();
    if (!mounted) return;

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Export Inventaire CSV'),
        content: SizedBox(
          width: 500,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('Données au format CSV (tableur Excel / LibreOffice) :'),
              const SizedBox(height: 10),
              Container(
                height: 200,
                padding: const EdgeInsets.all(8),
                color: Colors.grey.shade100,
                child: SingleChildScrollView(
                  child: SelectableText(csvContent, style: const TextStyle(fontSize: 11, fontFamily: 'monospace')),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('Fermer')),
        ],
      ),
    );
  }

  void _showDoctorLicenseDialog() {
    final doc = LicenseService.instance.doctorProfile;
    if (doc == null) return;

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(
          children: [
            Icon(Icons.vpn_key_rounded, color: AppColors.primaryBlue),
            SizedBox(width: 10),
            Text('Ma Clé de Licence'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Médecin : ${doc.fullName}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
            const SizedBox(height: 4),
            Text('Numéro d\'Ordre : ${doc.orderNumber}', style: const TextStyle(color: AppColors.slateMedium, fontSize: 13)),
            Text('Cabinet ID : ${doc.cabinetId}', style: const TextStyle(color: AppColors.slateMedium, fontSize: 13)),
            const SizedBox(height: 12),
            const Text('Clé de Licence officielle :', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
            const SizedBox(height: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.blue.shade50,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.blue.shade200),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: SelectableText(
                      doc.licenseKey,
                      style: const TextStyle(
                        fontFamily: 'monospace',
                        fontWeight: FontWeight.bold,
                        fontSize: 13.5,
                        color: AppColors.primaryDark,
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.copy_rounded, color: AppColors.primaryBlue, size: 20),
                    tooltip: 'Copier la clé',
                    onPressed: () {
                      Clipboard.setData(ClipboardData(text: doc.licenseKey));
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Clé de licence copiée dans le presse-papiers !')),
                      );
                    },
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('Fermer')),
        ],
      ),
    );
  }

  Future<void> _handleLogout() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Déconnexion'),
        content: const Text('Souhaitez-vous fermer la session active ? Vos stocks restent conservés et synchronisés.'),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Annuler')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Déconnexion'),
          ),
        ],
      ),
    );

    if (confirm == true && mounted) {
      await LicenseService.instance.logout();
      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const WelcomeAuthView()),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0.5,
        shadowColor: Colors.black.withValues(alpha: 0.08),
        leadingWidth: 42,
        leading: Padding(
          padding: const EdgeInsets.only(left: 8),
          child: Center(
            child: Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(9),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.08),
                    blurRadius: 4,
                    offset: const Offset(0, 1),
                  ),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(9),
                child: Image.asset(
                  'assets/images/logo.png',
                  width: 34,
                  height: 34,
                  fit: BoxFit.cover,
                  errorBuilder: (context, error, stackTrace) => const Icon(
                    Icons.medication_liquid_rounded,
                    color: AppColors.primaryBlue,
                    size: 26,
                  ),
                ),
              ),
            ),
          ),
        ),
        titleSpacing: 4,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'DocPocket Médocs',
              style: TextStyle(
                color: AppColors.slateDark,
                fontWeight: FontWeight.w800,
                fontSize: 15,
                letterSpacing: -0.3,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 1),
            Text(
              LicenseService.instance.userDisplayName,
              style: const TextStyle(
                color: AppColors.primaryBlue,
                fontSize: 10.5,
                fontWeight: FontWeight.w600,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
        actions: [
          IconButton(
            visualDensity: const VisualDensity(horizontal: -2, vertical: -2),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
            icon: Icon(
              Icons.cloud_sync_rounded,
              color: SupabaseSyncService.instance.status == SyncStatus.synced
                  ? AppColors.alertValid
                  : (SupabaseSyncService.instance.status == SyncStatus.syncing
                      ? Colors.orange.shade700
                      : AppColors.slateDark),
              size: 21,
            ),
            tooltip: 'Supabase Cloud : ${SupabaseSyncService.instance.lastSyncMessage}',
            onPressed: () {
              CloudSyncDialog.show(context).then((_) => _loadData());
            },
          ),
          IconButton(
            visualDensity: const VisualDensity(horizontal: -2, vertical: -2),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
            icon: Badge(
              isLabelVisible: _expirySummary.hasAlerts,
              label: Text('${_expirySummary.totalCount}'),
              backgroundColor: _expirySummary.expired.isNotEmpty ? AppColors.alertExpired : Colors.orange.shade800,
              child: const Icon(Icons.notifications_outlined, color: AppColors.slateDark, size: 21),
            ),
            tooltip: 'Alertes péremptions (${_expirySummary.totalCount})',
            onPressed: () {
              ExpiryNotificationsDialog.show(
                context,
                medicines: _allMedicines,
                onDataChanged: _loadData,
              );
            },
          ),
          Container(
            margin: const EdgeInsets.symmetric(vertical: 9, horizontal: 2),
            decoration: BoxDecoration(
              color: AppColors.primaryLight,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: AppColors.primaryAccent.withValues(alpha: 0.35)),
            ),
            child: IconButton(
              icon: const Icon(Icons.qr_code_scanner_rounded, color: AppColors.primaryDark, size: 19),
              tooltip: 'Scanner caméra',
              visualDensity: const VisualDensity(horizontal: -2, vertical: -2),
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
              onPressed: () async {
                final code = await CameraScannerModal.show(context);
                if (code != null && mounted) {
                  _showQuickScanDialog(code);
                }
              },
            ),
          ),
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert_rounded, color: AppColors.slateDark, size: 21),
            tooltip: 'Menu & Outils',
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 28, minHeight: 32),
            onSelected: (val) {
              switch (val) {
                case 'secretary':
                  SecretaryManagementDialog.show(context);
                  break;
                case 'cloud_sync':
                  CloudSyncDialog.show(context).then((_) => _loadData());
                  break;
                case 'license_key':
                  _showDoctorLicenseDialog();
                  break;
                case 'logout':
                  _handleLogout();
                  break;
                case 'expiry_alerts':
                  ExpiryNotificationsDialog.show(
                    context,
                    medicines: _allMedicines,
                    onDataChanged: _loadData,
                  );
                  break;
                case 'about':
                  AboutDocPocketDialog.show(context);
                  break;
                case 'auto_backup':
                  AutoBackupDialog.show(context, isFirstLaunch: false).then((_) => _loadData());
                  break;
                case 'pdf_inventory':
                  PdfReportService.printInventoryReport(_medicines);
                  break;
                case 'pdf_alerts':
                  PdfReportService.printAlertsReport(_medicines);
                  break;
                case 'catalog':
                  MedicineCatalogPickerDialog.show(context);
                  break;
                case 'custom_med':
                  CreateCustomMedicineDialog.show(context);
                  break;
                case 'export_json':
                  _exportBackupJson();
                  break;
                case 'import_json':
                  if (LicenseService.instance.isDoctor) {
                    _importBackupJson();
                  }
                  break;
                case 'export_csv':
                  _exportCsv();
                  break;
                case 'clear_stock':
                  if (LicenseService.instance.isDoctor) {
                    _confirmClearStock();
                  }
                  break;
              }
            },
            itemBuilder: (ctx) => [
              if (LicenseService.instance.isDoctor)
                const PopupMenuItem(
                  value: 'secretary',
                  child: Row(
                    children: [
                      Icon(Icons.badge_rounded, color: AppColors.primaryBlue),
                      SizedBox(width: 10),
                      Text('Gestion Accès Secrétaire'),
                    ],
                  ),
                ),
              const PopupMenuItem(
                value: 'cloud_sync',
                child: Row(
                  children: [
                    Icon(Icons.cloud_sync_rounded, color: AppColors.primaryBlue),
                    SizedBox(width: 10),
                    Text('Synchronisation Cloud'),
                  ],
                ),
              ),
              if (LicenseService.instance.isDoctor)
                const PopupMenuItem(
                  value: 'license_key',
                  child: Row(
                    children: [
                      Icon(Icons.vpn_key_rounded, color: AppColors.primaryDark),
                      SizedBox(width: 10),
                      Text('Ma Clé de Licence'),
                    ],
                  ),
                ),
              const PopupMenuDivider(),
              PopupMenuItem(
                value: 'expiry_alerts',
                child: Row(
                  children: [
                    Icon(
                      Icons.notifications_active_rounded,
                      color: _expirySummary.hasAlerts ? Colors.orange.shade800 : AppColors.primaryBlue,
                    ),
                    const SizedBox(width: 10),
                    Text('Alertes Péremptions (${_expirySummary.totalCount})'),
                  ],
                ),
              ),
              const PopupMenuItem(
                value: 'about',
                child: Row(
                  children: [
                    Icon(Icons.info_outline_rounded, color: AppColors.primaryBlue),
                    SizedBox(width: 10),
                    Text('À propos & Mises à jour (APK)'),
                  ],
                ),
              ),
              const PopupMenuItem(
                value: 'auto_backup',
                child: Row(
                  children: [
                    Icon(Icons.security_rounded, color: AppColors.alertValid),
                    SizedBox(width: 10),
                    Text('Sauvegardes automatiques (5 max)'),
                  ],
                ),
              ),
              const PopupMenuDivider(),
              const PopupMenuItem(
                value: 'pdf_inventory',
                child: Row(
                  children: [
                    Icon(Icons.picture_as_pdf_rounded, color: AppColors.primaryBlue),
                    SizedBox(width: 10),
                    Text('Imprimer Rapport de Stock (PDF)'),
                  ],
                ),
              ),
              const PopupMenuItem(
                value: 'pdf_alerts',
                child: Row(
                  children: [
                    Icon(Icons.warning_amber_rounded, color: AppColors.alertExpired),
                    SizedBox(width: 10),
                    Text('Imprimer Alertes Péremptions (PDF)'),
                  ],
                ),
              ),
              const PopupMenuItem(
                value: 'catalog',
                child: Row(
                  children: [
                    Icon(Icons.menu_book_rounded, color: AppColors.primaryDark),
                    SizedBox(width: 10),
                    Text('Dictionnaire Médicaments (5 063)'),
                  ],
                ),
              ),
              const PopupMenuItem(
                value: 'custom_med',
                child: Row(
                  children: [
                    Icon(Icons.playlist_add_rounded, color: AppColors.primaryBlue),
                    SizedBox(width: 10),
                    Text('Ajouter médicament hors base'),
                  ],
                ),
              ),
              const PopupMenuDivider(),
              const PopupMenuItem(
                value: 'export_csv',
                child: Row(
                  children: [
                    Icon(Icons.table_chart_rounded, color: Colors.teal),
                    SizedBox(width: 10),
                    Text('Exporter Inventaire (CSV)'),
                  ],
                ),
              ),
              const PopupMenuItem(
                value: 'export_json',
                child: Row(
                  children: [
                    Icon(Icons.save_rounded, color: AppColors.slateMedium),
                    SizedBox(width: 10),
                    Text('Sauvegarder les données (JSON)'),
                  ],
                ),
              ),
              if (LicenseService.instance.isDoctor) ...[
                const PopupMenuItem(
                  value: 'import_json',
                  child: Row(
                    children: [
                      Icon(Icons.file_upload_rounded, color: AppColors.slateMedium),
                      SizedBox(width: 10),
                      Text('Restaurer une sauvegarde (JSON)'),
                    ],
                  ),
                ),
                const PopupMenuDivider(),
                const PopupMenuItem(
                  value: 'clear_stock',
                  child: Row(
                    children: [
                      Icon(Icons.delete_sweep_rounded, color: AppColors.alertExpired),
                      SizedBox(width: 10),
                      Text('Vider le stock (remise à zéro)', style: TextStyle(color: AppColors.alertExpired)),
                    ],
                  ),
                ),
              ],
              const PopupMenuDivider(),
              const PopupMenuItem(
                value: 'logout',
                child: Row(
                  children: [
                    Icon(Icons.logout_rounded, color: Colors.red),
                    SizedBox(width: 10),
                    Text('Déconnexion / Changer de rôle', style: TextStyle(color: Colors.red)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _handleRefresh,
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Gros boutons d'actions tactiles rapides
              Row(
                children: [
                  Expanded(
                    child: BigTouchButton(
                      label: 'Entrée Stock',
                      subtitle: 'Réception délégué',
                      icon: Icons.add_box_rounded,
                      color: AppColors.primaryBlue,
                      onPressed: () {
                        Navigator.of(context).push(
                          MaterialPageRoute(builder: (_) => const StockEntryView()),
                        ).then((_) => _loadData());
                      },
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: BigTouchButton(
                      label: 'Sortie Stock',
                      subtitle: 'Délivrance FEFO',
                      icon: Icons.output_rounded,
                      color: AppColors.primaryDark,
                      onPressed: () {
                        Navigator.of(context).push(
                          MaterialPageRoute(builder: (_) => const StockExitView()),
                        ).then((_) => _loadData());
                      },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // Bannière interactive d'alertes péremptions (stock > 0)
              if (_expirySummary.hasAlerts) ...[
                InkWell(
                  onTap: () {
                    ExpiryNotificationsDialog.show(
                      context,
                      medicines: _allMedicines,
                      onDataChanged: _loadData,
                    );
                  },
                  borderRadius: BorderRadius.circular(14),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
                    decoration: BoxDecoration(
                      color: _expirySummary.expired.isNotEmpty ? Colors.red.shade50 : Colors.orange.shade50,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: _expirySummary.expired.isNotEmpty ? Colors.red.shade200 : Colors.orange.shade200,
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          _expirySummary.expired.isNotEmpty ? Icons.warning_rounded : Icons.notifications_active_rounded,
                          color: _expirySummary.expired.isNotEmpty ? AppColors.alertExpired : Colors.orange.shade800,
                          size: 22,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '${_expirySummary.totalCount} alerte${_expirySummary.totalCount > 1 ? "s" : ""} de péremption (${_expirySummary.totalBoxesAlerted} boîte${_expirySummary.totalBoxesAlerted > 1 ? "s" : ""})',
                                style: TextStyle(
                                  fontSize: 12.5,
                                  fontWeight: FontWeight.bold,
                                  color: _expirySummary.expired.isNotEmpty ? AppColors.alertExpired : Colors.orange.shade900,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                '${_expirySummary.expired.length} périmé(s) • ${_expirySummary.within1Month.length} < 1 mois • ${_expirySummary.within3Months.length} < 3 mois',
                                style: TextStyle(
                                  fontSize: 11,
                                  color: Colors.grey.shade700,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: _expirySummary.expired.isNotEmpty ? Colors.red.shade200 : Colors.orange.shade200,
                            ),
                          ),
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text('Gérer', style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold, color: AppColors.primaryBlue)),
                              SizedBox(width: 2),
                              Icon(Icons.arrow_forward_ios_rounded, size: 10, color: AppColors.primaryBlue),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
              ],

              // Synthèse & Badges d'alertes cliquables
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                physics: const BouncingScrollPhysics(),
                child: Row(
                  children: [
                    _filterChip(
                      label: 'Tout (${_stats["totalBoxes"]} btes)',
                      isSelected: _selectedFilter == null,
                      color: AppColors.primaryBlue,
                      onTap: () {
                        setState(() => _selectedFilter = null);
                        _loadData();
                      },
                    ),
                    const SizedBox(width: 6),
                    _filterChip(
                      label: 'Périmés (${_stats["countExpired"]})',
                      isSelected: _selectedFilter == StockAlertLevel.expired,
                      color: AppColors.alertExpired,
                      onTap: () {
                        setState(() => _selectedFilter = StockAlertLevel.expired);
                        _loadData();
                      },
                    ),
                    const SizedBox(width: 6),
                    _filterChip(
                      label: 'Périme < 90j (${_stats["countWarning"]})',
                      isSelected: _selectedFilter == StockAlertLevel.warning,
                      color: AppColors.alertWarning,
                      onTap: () {
                        setState(() => _selectedFilter = StockAlertLevel.warning);
                        _loadData();
                      },
                    ),
                    const SizedBox(width: 6),
                    _filterChip(
                      label: 'Valides (${_stats["countValid"]})',
                      isSelected: _selectedFilter == StockAlertLevel.valid,
                      color: AppColors.alertValid,
                      onTap: () {
                        setState(() => _selectedFilter = StockAlertLevel.valid);
                        _loadData();
                      },
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),

              // Barre de recherche instantanée avec bouton de scan intégré
              TextField(
                controller: _searchController,
                decoration: InputDecoration(
                  hintText: 'Rechercher ou scanner (nom, DCI, lot)...',
                  hintStyle: const TextStyle(color: AppColors.slateMedium, fontSize: 13.5),
                  prefixIcon: const Icon(Icons.search_rounded, color: AppColors.primaryBlue),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
                  suffixIcon: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (_searchController.text.isNotEmpty)
                        IconButton(
                          icon: const Icon(Icons.clear_rounded, size: 18, color: AppColors.slateMedium),
                          tooltip: 'Effacer la recherche',
                          onPressed: () {
                            _searchController.clear();
                            _loadData();
                          },
                        ),
                      Container(
                        margin: const EdgeInsets.only(right: 8),
                        decoration: BoxDecoration(
                          color: AppColors.primaryLight,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: AppColors.primaryAccent.withValues(alpha: 0.3)),
                        ),
                        child: IconButton(
                          icon: const Icon(Icons.qr_code_scanner_rounded, color: AppColors.primaryDark, size: 19),
                          tooltip: 'Scanner code-barres / QR',
                          visualDensity: VisualDensity.compact,
                          padding: const EdgeInsets.all(6),
                          constraints: const BoxConstraints(minWidth: 34, minHeight: 34),
                          onPressed: () async {
                            final code = await CameraScannerModal.show(context);
                            if (code != null && mounted) {
                              _showQuickScanDialog(code);
                            }
                          },
                        ),
                      ),
                    ],
                  ),
                  filled: true,
                  fillColor: Colors.white,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide(color: Colors.grey.shade200),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide(color: Colors.grey.shade200),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: const BorderSide(color: AppColors.primaryBlue, width: 1.5),
                  ),
                ),
                onChanged: (_) => _loadData(),
              ),
              const SizedBox(height: 20),

              // Liste des médicaments en stock
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Échantillons en stock (${_medicines.length})',
                    style: const TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.bold,
                      color: AppColors.slateDark,
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.refresh_rounded),
                    tooltip: 'Actualiser',
                    onPressed: _loadData,
                  ),
                ],
              ),
              const SizedBox(height: 10),

              if (_isLoading)
                const Center(child: Padding(padding: EdgeInsets.all(40), child: CircularProgressIndicator()))
              else if (_medicines.isEmpty)
                Card(
                  elevation: 0,
                  color: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  child: Padding(
                    padding: const EdgeInsets.all(28),
                    child: Column(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: Colors.blue.shade50,
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            _searchController.text.isNotEmpty || _selectedFilter != null
                                ? Icons.search_off_rounded
                                : Icons.inventory_2_outlined,
                            size: 46,
                            color: AppColors.primaryBlue,
                          ),
                        ),
                        const SizedBox(height: 16),
                        Text(
                          _searchController.text.isNotEmpty || _selectedFilter != null
                              ? 'Aucun résultat correspondant'
                              : 'Aucun échantillon en stock',
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16.5, color: AppColors.slateDark),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          _searchController.text.isNotEmpty || _selectedFilter != null
                              ? 'Aucun médicament ne correspond à vos filtres actuels. Modifiez votre recherche ou réinitialisez.'
                              : 'Scannez une boîte avec votre douchette USB ou caméra, ou enregistrez une réception de délégué.',
                          textAlign: TextAlign.center,
                          style: const TextStyle(color: AppColors.slateMedium, fontSize: 13),
                        ),
                        const SizedBox(height: 20),
                        if (_searchController.text.isNotEmpty || _selectedFilter != null)
                          Wrap(
                            spacing: 10,
                            runSpacing: 10,
                            alignment: WrapAlignment.center,
                            children: [
                              if (_searchController.text.trim().isNotEmpty)
                                ElevatedButton.icon(
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: AppColors.primaryBlue,
                                    foregroundColor: Colors.white,
                                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                  ),
                                  icon: const Icon(Icons.add_circle_outline_rounded, size: 18),
                                  label: Text(
                                    'Ajouter "${_searchController.text.trim()}" en stock',
                                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                                  ),
                                  onPressed: () async {
                                    final query = _searchController.text.trim();
                                    final catalogMatches = await MedicinesCatalogService.instance.search(query);
                                    if (!mounted) return;
                                    CatalogMedicine? chosen;
                                    if (catalogMatches.isNotEmpty) {
                                      chosen = await MedicineCatalogPickerDialog.show(this.context, initialQuery: query);
                                    } else {
                                      chosen = await CreateCustomMedicineDialog.show(this.context, initialName: query);
                                    }
                                    if (chosen != null && mounted) {
                                      Navigator.of(this.context).push(
                                        MaterialPageRoute(
                                          builder: (_) => StockEntryView(initialCatalogMedicine: chosen),
                                        ),
                                      ).then((_) {
                                        _searchController.clear();
                                        _loadData();
                                      });
                                    }
                                  },
                                ),
                              OutlinedButton.icon(
                                onPressed: () {
                                  _searchController.clear();
                                  setState(() => _selectedFilter = null);
                                  _loadData();
                                },
                                icon: const Icon(Icons.refresh_rounded, size: 18),
                                label: const Text('Réinitialiser les filtres'),
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: AppColors.primaryBlue,
                                  side: const BorderSide(color: AppColors.primaryBlue),
                                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                ),
                              ),
                            ],
                          )
                        else
                          Wrap(
                            spacing: 12,
                            runSpacing: 10,
                            alignment: WrapAlignment.center,
                            children: [
                              ElevatedButton.icon(
                                onPressed: () {
                                  Navigator.of(context).push(
                                    MaterialPageRoute(builder: (_) => const StockEntryView()),
                                  ).then((_) => _loadData());
                                },
                                icon: const Icon(Icons.add_rounded, color: Colors.white, size: 19),
                                label: const Text(
                                  'Enregistrer une entrée',
                                  style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13.5),
                                ),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: AppColors.primaryBlue,
                                  foregroundColor: Colors.white,
                                  padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                  elevation: 2,
                                ),
                              ),
                              OutlinedButton.icon(
                                onPressed: () async {
                                  final code = await CameraScannerModal.show(context);
                                  if (code != null && mounted) {
                                    _showQuickScanDialog(code);
                                  }
                                },
                                icon: const Icon(Icons.qr_code_scanner_rounded, size: 19),
                                label: const Text(
                                  'Scanner un code',
                                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13.5),
                                ),
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: AppColors.primaryBlue,
                                  side: const BorderSide(color: AppColors.primaryBlue, width: 1.2),
                                  padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                ),
                              ),
                            ],
                          ),
                      ],
                    ),
                  ),
                )
              else
                ListView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: _medicines.length,
                  itemBuilder: (context, index) {
                    final med = _medicines[index];
                    return _medicineCard(med);
                  },
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _filterChip({
    required String label,
    required bool isSelected,
    required Color color,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected ? color : Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: color, width: 1.2),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: isSelected ? Colors.white : color,
            fontWeight: FontWeight.bold,
            fontSize: 11.5,
          ),
        ),
      ),
    );
  }

  Widget _medicineCard(Medicine med) {
    final nextBatch = med.nextExpiringBatch;
    final form = med.form.trim();
    final packaging = med.dosage.trim();

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      elevation: 1.5,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () {
          Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => MedicineDetailView(medicine: med)),
          ).then((_) => _loadData());
        },
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Ligne 1 : Nom Commercial & Badges Forme / Packaging, et Badge Alerte
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          med.commercialName,
                          style: const TextStyle(
                            fontSize: 16.5,
                            fontWeight: FontWeight.bold,
                            color: AppColors.slateDark,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        if (form.isNotEmpty || packaging.isNotEmpty) ...[
                          const SizedBox(height: 5),
                          Wrap(
                            spacing: 6,
                            runSpacing: 4,
                            children: [
                              if (form.isNotEmpty)
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2.5),
                                  decoration: BoxDecoration(
                                    color: Colors.blue.shade50,
                                    borderRadius: BorderRadius.circular(6),
                                    border: Border.all(color: Colors.blue.shade200, width: 0.8),
                                  ),
                                  child: Text(
                                    form,
                                    style: TextStyle(
                                      fontSize: 11.5,
                                      fontWeight: FontWeight.w600,
                                      color: Colors.blue.shade900,
                                    ),
                                  ),
                                ),
                              if (packaging.isNotEmpty)
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2.5),
                                  decoration: BoxDecoration(
                                    color: Colors.teal.shade50,
                                    borderRadius: BorderRadius.circular(6),
                                    border: Border.all(color: Colors.teal.shade200, width: 0.8),
                                  ),
                                  child: Text(
                                    packaging,
                                    style: TextStyle(
                                      fontSize: 11.5,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.teal.shade900,
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  AlertBadge(level: med.overallAlertLevel),
                ],
              ),
              const SizedBox(height: 10),
              const Divider(height: 1),
              const SizedBox(height: 10),

              // Ligne 2 : Date péremption & lot (Expanded) ET Quantité restante (pill)
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: nextBatch != null
                        ? Row(
                            children: [
                              Icon(
                                Icons.event_available_rounded,
                                size: 16,
                                color: nextBatch.alertLevel.color,
                              ),
                              const SizedBox(width: 5),
                              Expanded(
                                child: Text(
                                  'Exp : ${nextBatch.expiryDateFormatted}  (Lot: ${nextBatch.batchNumber})',
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                    color: nextBatch.alertLevel.color,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          )
                        : const Text(
                            'Aucun lot actif',
                            style: TextStyle(fontSize: 12, color: AppColors.slateMedium),
                          ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4.5),
                    decoration: BoxDecoration(
                      color: AppColors.primaryLight,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: AppColors.primaryAccent.withValues(alpha: 0.3)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.inventory_2_rounded, size: 14, color: AppColors.primaryDark),
                        const SizedBox(width: 4),
                        Text(
                          '${med.totalStock} boîte${med.totalStock > 1 ? "s" : ""}',
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                            color: AppColors.primaryDark,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),

              // Rangée d'actions rapides : + Boîte identique et + Nouveau lot
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  InkWell(
                    onTap: () async {
                      final updated = await AddBoxesDialog.show(context, medicine: med);
                      if (updated == true) _loadData();
                    },
                    borderRadius: BorderRadius.circular(8),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
                      decoration: BoxDecoration(
                        color: Colors.teal.shade50,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.teal.shade300, width: 0.9),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.add_circle_outline_rounded, size: 15, color: Colors.teal.shade800),
                          const SizedBox(width: 4),
                          Text(
                            'Boîte identique',
                            style: TextStyle(
                              fontSize: 11.5,
                              fontWeight: FontWeight.bold,
                              color: Colors.teal.shade900,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  InkWell(
                    onTap: () async {
                      final updated = await AddBatchDialog.show(context, med);
                      if (updated == true) _loadData();
                    },
                    borderRadius: BorderRadius.circular(8),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
                      decoration: BoxDecoration(
                        color: AppColors.primaryLight,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: AppColors.primaryAccent.withValues(alpha: 0.4), width: 0.9),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.add_rounded, size: 15, color: AppColors.primaryDark),
                          SizedBox(width: 4),
                          Text(
                            'Nouveau lot',
                            style: TextStyle(
                              fontSize: 11.5,
                              fontWeight: FontWeight.bold,
                              color: AppColors.primaryDark,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _confirmClearStock() async {
    if (!LicenseService.instance.isDoctor) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Action réservée exclusivement au Médecin titulaire.'),
            backgroundColor: AppColors.alertExpired,
          ),
        );
      }
      return;
    }

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: AppColors.alertExpired),
            SizedBox(width: 8),
            Text('Vider tout le stock ?'),
          ],
        ),
        content: const Text(
          'Cette action efface définitivement tous les échantillons et mouvements enregistrés. Le stock repartira à zéro.\n\nÊtes-vous sûr de vouloir continuer ?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Annuler'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.alertExpired),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Oui, vider le stock', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (confirm == true && mounted) {
      await DatabaseService.instance.clearAllStock();
      await _loadData();
      if (SupabaseSyncService.instance.isConfigured) {
        await SupabaseSyncService.instance.syncStock(
          actionDescription: 'Remise à zéro du stock par le Médecin',
        );
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Le stock a été réinitialisé à zéro.'),
            backgroundColor: AppColors.primaryBlue,
          ),
        );
      }
    }
  }
}
