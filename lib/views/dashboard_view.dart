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
        elevation: 0,
        titleSpacing: 16,
        title: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Image.asset(
                'assets/images/logo.png',
                width: 38,
                height: 38,
                fit: BoxFit.cover,
                errorBuilder: (context, error, stackTrace) => const Icon(
                  Icons.medication_liquid_rounded,
                  color: AppColors.primaryBlue,
                  size: 32,
                ),
              ),
            ),
            const SizedBox(width: 12),
            const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'DocPocket Medocs',
                  style: TextStyle(
                    color: AppColors.slateDark,
                    fontWeight: FontWeight.bold,
                    fontSize: 18,
                  ),
                ),
                Text(
                  'Gestion des échantillons médicaux',
                  style: TextStyle(color: AppColors.slateMedium, fontSize: 11.5),
                ),
              ],
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.qr_code_scanner_rounded, color: AppColors.primaryBlue, size: 26),
            tooltip: 'Scanner par caméra',
            onPressed: () async {
              final code = await CameraScannerModal.show(context);
              if (code != null && mounted) {
                _showQuickScanDialog(code);
              }
            },
          ),
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert_rounded, color: AppColors.slateDark),
            tooltip: 'Outils & Rapports',
            onSelected: (val) {
              switch (val) {
                case 'pdf_inventory':
                  PdfReportService.printInventoryReport(_medicines);
                  break;
                case 'pdf_alerts':
                  PdfReportService.printAlertsReport(_medicines);
                  break;
                case 'catalog':
                  MedicineCatalogPickerDialog.show(context);
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
              }
            },
            itemBuilder: (ctx) => [
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
                    Text('Dictionnaire Médicaments (5 112)'),
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
                      subtitle: 'Réception délégués',
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
                      subtitle: 'Priorité FEFO patient',
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
                    const SizedBox(width: 8),
                    _filterChip(
                      label: 'Périmés (${_stats["countExpired"]})',
                      isSelected: _selectedFilter == StockAlertLevel.expired,
                      color: AppColors.alertExpired,
                      onTap: () {
                        setState(() => _selectedFilter = StockAlertLevel.expired);
                        _loadData();
                      },
                    ),
                    const SizedBox(width: 8),
                    _filterChip(
                      label: 'Périme < 90j (${_stats["countWarning"]})',
                      isSelected: _selectedFilter == StockAlertLevel.warning,
                      color: AppColors.alertWarning,
                      onTap: () {
                        setState(() => _selectedFilter = StockAlertLevel.warning);
                        _loadData();
                      },
                    ),
                    const SizedBox(width: 8),
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
              const SizedBox(height: 16),

              // Barre de recherche instantanée
              TextField(
                controller: _searchController,
                decoration: InputDecoration(
                  hintText: 'Rechercher par nom, DCI, classe thérapeutique, n° de lot...',
                  prefixIcon: const Icon(Icons.search_rounded, color: AppColors.primaryBlue),
                  suffixIcon: _searchController.text.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.clear_rounded),
                          onPressed: () {
                            _searchController.clear();
                            _loadData();
                          },
                        )
                      : null,
                  filled: true,
                  fillColor: Colors.white,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
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
                        const Icon(Icons.inventory_2_outlined, size: 56, color: AppColors.slateMedium),
                        const SizedBox(height: 12),
                        const Text(
                          'Aucun échantillon ne correspond à vos critères.',
                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                        ),
                        const SizedBox(height: 6),
                        const Text(
                          'Scannez une boîte avec votre douchette USB pour commencer.',
                          style: TextStyle(color: AppColors.slateMedium),
                        ),
                        const SizedBox(height: 16),
                        ElevatedButton.icon(
                          onPressed: () {
                            Navigator.of(context).push(
                              MaterialPageRoute(builder: (_) => const StockEntryView()),
                            ).then((_) => _loadData());
                          },
                          icon: const Icon(Icons.add_rounded),
                          label: const Text('Enregistrer une entrée'),
                          style: ElevatedButton.styleFrom(backgroundColor: AppColors.primaryBlue),
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
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? color : Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: color, width: 1.5),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: isSelected ? Colors.white : color,
            fontWeight: FontWeight.bold,
            fontSize: 12.5,
          ),
        ),
      ),
    );
  }

  Widget _medicineCard(Medicine med) {
    final nextBatch = med.nextExpiringBatch;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
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
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${med.commercialName} ${med.dosage}',
                          style: const TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.bold,
                            color: AppColors.slateDark,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          '${med.dci} • ${med.form}',
                          style: const TextStyle(fontSize: 13, color: AppColors.slateMedium),
                        ),
                      ],
                    ),
                  ),
                  AlertBadge(level: med.overallAlertLevel),
                ],
              ),
              const Divider(height: 20),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Laboratoire : ${med.laboratory.isEmpty ? "-" : med.laboratory}',
                        style: const TextStyle(fontSize: 12, color: AppColors.slateMedium),
                      ),
                      if (nextBatch != null)
                        Text(
                          'Prochaine péremption : ${nextBatch.expiryDateFormatted} (Lot: ${nextBatch.batchNumber})',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: nextBatch.alertLevel.color,
                          ),
                        ),
                    ],
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                    decoration: BoxDecoration(
                      color: AppColors.primaryLight,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      '${med.totalStock} boîte(s)',
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                        color: AppColors.primaryDark,
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
}
