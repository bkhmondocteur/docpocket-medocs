import 'dart:convert';
import 'package:flutter/material.dart';
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
import '../../core/services/auto_backup_service.dart';

/// Tableau de Bord principal de DocPocket Medocs
class DashboardView extends StatefulWidget {
  const DashboardView({super.key});

  @override
  State<DashboardView> createState() => _DashboardViewState();
}

class _DashboardViewState extends State<DashboardView> {
  final _searchController = TextEditingController();
  List<Medicine> _medicines = [];
  Map<String, int> _stats = {
    'totalMedicines': 0,
    'totalBoxes': 0,
    'countExpired': 0,
    'countWarning': 0,
    'countValid': 0,
  };

  StockAlertLevel? _selectedFilter;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    BarcodeHardwareListener.instance.startListening();
    BarcodeHardwareListener.instance.addListener(_onGlobalBarcodeScanned);
    _loadData();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await _checkAutoBackupPrompt();
    });
  }

  Future<void> _checkAutoBackupPrompt() async {
    await AutoBackupService.instance.init();
    if (!AutoBackupService.instance.hasPromptedForBackup && mounted) {
      await AutoBackupDialog.show(context, isFirstLaunch: true);
    }
  }

  @override
  void dispose() {
    BarcodeHardwareListener.instance.removeListener(_onGlobalBarcodeScanned);
    BarcodeHardwareListener.instance.stopListening();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    final meds = await DatabaseService.instance.getAllMedicines(
      searchQuery: _searchController.text,
      alertFilter: _selectedFilter,
    );
    final stats = await DatabaseService.instance.getDashboardStats();

    if (mounted) {
      setState(() {
        _medicines = meds;
        _stats = stats;
        _isLoading = false;
      });
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
    try {
      final files = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['json'],
      );

      if (files.isNotEmpty) {
        final bytes = await files.first.readAsBytes();
        final content = utf8.decode(bytes);

        if (content.isNotEmpty) {
          await DatabaseService.instance.importBackupJson(content);
          await _loadData();
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0.5,
        shadowColor: Colors.black.withValues(alpha: 0.08),
        titleSpacing: 14,
        title: Row(
          children: [
            Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(10),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.06),
                    blurRadius: 4,
                    offset: const Offset(0, 1),
                  ),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: Image.asset(
                  'assets/images/logo.png',
                  width: 36,
                  height: 36,
                  fit: BoxFit.cover,
                  errorBuilder: (context, error, stackTrace) => const Icon(
                    Icons.medication_liquid_rounded,
                    color: AppColors.primaryBlue,
                    size: 30,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 10),
            const Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'DocPocket Medocs',
                    style: TextStyle(
                      color: AppColors.slateDark,
                      fontWeight: FontWeight.w800,
                      fontSize: 16.5,
                      letterSpacing: -0.2,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    'Gestion des échantillons',
                    style: TextStyle(
                      color: AppColors.slateMedium,
                      fontSize: 11,
                      fontWeight: FontWeight.w500,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          Container(
            margin: const EdgeInsets.symmetric(vertical: 9),
            decoration: BoxDecoration(
              color: AppColors.primaryLight,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: AppColors.primaryAccent.withValues(alpha: 0.3)),
            ),
            child: IconButton(
              icon: const Icon(Icons.qr_code_scanner_rounded, color: AppColors.primaryDark, size: 21),
              tooltip: 'Scanner caméra',
              visualDensity: VisualDensity.compact,
              padding: const EdgeInsets.all(7),
              constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
              onPressed: () async {
                final code = await CameraScannerModal.show(context);
                if (code != null && mounted) {
                  _showQuickScanDialog(code);
                }
              },
            ),
          ),
          const SizedBox(width: 2),
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert_rounded, color: AppColors.slateDark),
            tooltip: 'Menu & Outils',
            onSelected: (val) {
              switch (val) {
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
                  _importBackupJson();
                  break;
                case 'export_csv':
                  _exportCsv();
                  break;
                case 'clear_stock':
                  _confirmClearStock();
                  break;
              }
            },
            itemBuilder: (ctx) => [
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
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _loadData,
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
                      label: 'Entrée en stock',
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
                      label: 'Sortie / Remise',
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
              const SizedBox(height: 20),

              // Synthèse & Badges d'alertes cliquables
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    _filterChip(
                      label: 'Tout le stock (${_stats["totalBoxes"]} boîtes)',
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
                  prefixIcon: const Icon(Icons.search_rounded, color: AppColors.primaryBlue),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  suffixIcon: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (_searchController.text.isNotEmpty)
                        IconButton(
                          icon: const Icon(Icons.clear_rounded, size: 18),
                          tooltip: 'Effacer la recherche',
                          onPressed: () {
                            _searchController.clear();
                            _loadData();
                          },
                        ),
                      IconButton(
                        icon: const Icon(Icons.qr_code_scanner_rounded, color: AppColors.primaryBlue, size: 20),
                        tooltip: 'Scanner code-barres / QR',
                        onPressed: () async {
                          final code = await CameraScannerModal.show(context);
                          if (code != null && mounted) {
                            _showQuickScanDialog(code);
                          }
                        },
                      ),
                      const SizedBox(width: 4),
                    ],
                  ),
                  filled: true,
                  fillColor: Colors.white,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide.none,
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
                    padding: const EdgeInsets.all(32),
                    child: Column(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: Colors.blue.shade50,
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(Icons.inventory_2_outlined, size: 48, color: AppColors.primaryBlue),
                        ),
                        const SizedBox(height: 16),
                        const Text(
                          'Aucun échantillon en stock',
                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 17, color: AppColors.slateDark),
                        ),
                        const SizedBox(height: 6),
                        const Text(
                          'Scannez un code-barres / Datamatrix ou enregistrez une réception de délégué.',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: AppColors.slateMedium, fontSize: 13),
                        ),
                        const SizedBox(height: 20),
                        ElevatedButton.icon(
                          onPressed: () {
                            Navigator.of(context).push(
                              MaterialPageRoute(builder: (_) => const StockEntryView()),
                            ).then((_) => _loadData());
                          },
                          icon: const Icon(Icons.add_rounded, color: Colors.white, size: 20),
                          label: const Text(
                            'Enregistrer une entrée',
                            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14),
                          ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.primaryBlue,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 12),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            elevation: 2,
                          ),
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
                            '+ Boîte identique',
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
                            '+ Nouveau lot',
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
