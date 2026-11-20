import 'package:flutter/material.dart';
import '../../core/constants/app_colors.dart';
import '../../core/parsers/gs1_datamatrix_parser.dart';
import '../../core/database/database_service.dart';
import '../../core/services/barcode_hardware_listener.dart';
import '../../models/medicine.dart';
import 'widgets/alert_badge.dart';
import 'widgets/big_touch_button.dart';
import 'widgets/camera_scanner_modal.dart';

/// Écran Sortie de Stock / Remise d'échantillons au patient (Méthode FEFO)
class StockExitView extends StatefulWidget {
  final Medicine? initialMedicine;

  const StockExitView({super.key, this.initialMedicine});

  @override
  State<StockExitView> createState() => _StockExitViewState();
}

class _StockExitViewState extends State<StockExitView> {
  final _searchController = TextEditingController();
  final _patientController = TextEditingController();
  final _quantityController = TextEditingController(text: '1');

  List<Medicine> _availableMedicines = [];
  Medicine? _selectedMedicine;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _selectedMedicine = widget.initialMedicine;
    BarcodeHardwareListener.instance.addListener(_onBarcodeScanned);
    _loadMedicines();
  }

  @override
  void dispose() {
    BarcodeHardwareListener.instance.removeListener(_onBarcodeScanned);
    _searchController.dispose();
    _patientController.dispose();
    _quantityController.dispose();
    super.dispose();
  }

  Future<void> _loadMedicines() async {
    setState(() => _isLoading = true);
    final list = await DatabaseService.instance.getAllMedicines();
    // Ne garder que les médicaments avec du stock > 0
    _availableMedicines = list.where((m) => m.totalStock > 0).toList();
    setState(() => _isLoading = false);
  }

  void _onBarcodeScanned(String rawBarcode) {
    if (!mounted) return;
    _processBarcode(rawBarcode);
  }

  Future<void> _processBarcode(String rawBarcode) async {
    final parsed = Gs1DataMatrixParser.parse(rawBarcode);
    final gtin = parsed.gtin ?? rawBarcode.trim();

    final found = await DatabaseService.instance.getMedicineByGtin(gtin);
    if (found != null && mounted) {
      setState(() {
        _selectedMedicine = found;
        _searchController.text = found.commercialName;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Médicament sélectionné : ${found.commercialName} (Stock: ${found.totalStock})'),
          backgroundColor: AppColors.primaryBlue,
          duration: const Duration(seconds: 2),
        ),
      );
    } else if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Code $gtin non trouvé dans le stock actif'),
          backgroundColor: AppColors.alertExpired,
        ),
      );
    }
  }

  Future<void> _openCameraScanner() async {
    final scanned = await CameraScannerModal.show(context);
    if (scanned != null && mounted) {
      _processBarcode(scanned);
    }
  }

  void _adjustQuantity(int delta) {
    int current = int.tryParse(_quantityController.text) ?? 1;
    final maxAvailable = _selectedMedicine?.totalStock ?? 1;
    current = (current + delta).clamp(1, maxAvailable);
    _quantityController.text = current.toString();
  }

  Future<void> _confirmExit() async {
    if (_selectedMedicine == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Veuillez scanner ou choisir un médicament.'),
          backgroundColor: AppColors.alertExpired,
        ),
      );
      return;
    }

    final qty = int.tryParse(_quantityController.text.trim()) ?? 1;
    if (qty <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('La quantité doit être supérieure à 0.'),
          backgroundColor: AppColors.alertExpired,
        ),
      );
      return;
    }

    if (qty > _selectedMedicine!.totalStock) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Stock insuffisant (${_selectedMedicine!.totalStock} disponible(s)).'),
          backgroundColor: AppColors.alertExpired,
        ),
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      final patient = _patientController.text.trim();
      final deductions = await DatabaseService.instance.recordStockExitFefo(
        medicine: _selectedMedicine!,
        quantityToDeduct: qty,
        patientIdentifier: patient.isEmpty ? null : patient,
        note: patient.isEmpty ? 'Remise consultation' : 'Remise patient ($patient)',
      );

      final summary = deductions.entries
          .map((e) => '${e.value}x boîte(s) du lot ${e.key.batchNumber}')
          .join(', ');

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Remise effectuée : $summary (Patient: ${patient.isEmpty ? "Anonyme" : patient})',
            ),
            backgroundColor: AppColors.alertValid,
            duration: const Duration(seconds: 4),
          ),
        );
        Navigator.of(context).pop(true);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erreur: $e'), backgroundColor: AppColors.alertExpired),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Sortie / Remise au Patient', style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: AppColors.primaryDark,
        foregroundColor: Colors.white,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.qr_code_scanner_rounded, size: 28),
            tooltip: 'Scanner par caméra',
            onPressed: _openCameraScanner,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Bandeau scanner douchette
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    decoration: BoxDecoration(
                      color: AppColors.primaryLight,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: AppColors.primaryAccent.withOpacity(0.3)),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.barcode_reader, color: AppColors.primaryDark, size: 28),
                        const SizedBox(width: 12),
                        const Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Scan direct de la boîte (Douchette USB)',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: AppColors.primaryDark,
                                  fontSize: 14,
                                ),
                              ),
                              Text(
                                'Scannez pour sélectionner instantanément le médicament.',
                                style: TextStyle(color: AppColors.slateMedium, fontSize: 12),
                              ),
                            ],
                          ),
                        ),
                        ElevatedButton.icon(
                          onPressed: _openCameraScanner,
                          icon: const Icon(Icons.camera_alt_rounded, size: 18),
                          label: const Text('Caméra'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.primaryDark,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),

                  // Sélection par recherche ou liste déroulante
                  Card(
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    elevation: 1.5,
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Sélectionner le médicament',
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.bold,
                              color: AppColors.slateDark,
                            ),
                          ),
                          const SizedBox(height: 12),
                          DropdownButtonFormField<Medicine>(
                            value: _selectedMedicine,
                            isExpanded: true,
                            decoration: InputDecoration(
                              labelText: 'Médicament en stock',
                              prefixIcon: const Icon(Icons.medication_rounded, color: AppColors.primaryDark),
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                            ),
                            items: _availableMedicines.map((m) {
                              return DropdownMenuItem<Medicine>(
                                value: m,
                                child: Text(
                                  '${m.commercialName} ${m.dosage} (${m.totalStock} boîte${m.totalStock > 1 ? "s" : ""})',
                                  overflow: TextOverflow.ellipsis,
                                ),
                              );
                            }).toList(),
                            onChanged: (med) {
                              setState(() {
                                _selectedMedicine = med;
                                _quantityController.text = '1';
                              });
                            },
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Affichage de l'algorithme FEFO pour le médicament choisi
                  if (_selectedMedicine != null) ...[
                    Card(
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                        side: BorderSide(color: AppColors.primaryBlue.withOpacity(0.3), width: 1.5),
                      ),
                      elevation: 2,
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        _selectedMedicine!.commercialName,
                                        style: const TextStyle(
                                          fontSize: 20,
                                          fontWeight: FontWeight.bold,
                                          color: AppColors.slateDark,
                                        ),
                                      ),
                                      Text(
                                        '${_selectedMedicine!.dci} • ${_selectedMedicine!.dosage}',
                                        style: const TextStyle(fontSize: 13, color: AppColors.slateMedium),
                                      ),
                                    ],
                                  ),
                                ),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                                  decoration: BoxDecoration(
                                    color: AppColors.primaryLight,
                                    borderRadius: BorderRadius.circular(20),
                                  ),
                                  child: Text(
                                    '${_selectedMedicine!.totalStock} en stock',
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                      color: AppColors.primaryDark,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const Divider(height: 24),

                            // Méthode FEFO explicitée
                            const Row(
                              children: [
                                Icon(Icons.auto_awesome_rounded, color: AppColors.primaryAccent, size: 20),
                                SizedBox(width: 8),
                                Text(
                                  'Priorité FEFO (First Expired, First Out) :',
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    color: AppColors.primaryDark,
                                    fontSize: 13.5,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 10),

                            // Liste des lots disponibles par ordre d'expiration
                            ..._selectedMedicine!.fefoOrderedBatches.map((batch) {
                              final isFirst = batch == _selectedMedicine!.nextExpiringBatch;
                              return Container(
                                margin: const EdgeInsets.only(bottom: 8),
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                decoration: BoxDecoration(
                                  color: isFirst ? AppColors.primaryLight.withOpacity(0.5) : Colors.white,
                                  borderRadius: BorderRadius.circular(10),
                                  border: Border.all(
                                    color: isFirst ? AppColors.primaryBlue : AppColors.slateLight,
                                    width: isFirst ? 1.5 : 1.0,
                                  ),
                                ),
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    Row(
                                      children: [
                                        if (isFirst)
                                          const Padding(
                                            padding: EdgeInsets.only(right: 8),
                                            child: Icon(Icons.arrow_right_alt_rounded, color: AppColors.primaryBlue),
                                          ),
                                        Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              'Lot : ${batch.batchNumber}',
                                              style: TextStyle(
                                                fontWeight: isFirst ? FontWeight.bold : FontWeight.w500,
                                                color: AppColors.slateDark,
                                              ),
                                            ),
                                            Text(
                                              'Périme le : ${batch.expiryDateFormatted}',
                                              style: const TextStyle(fontSize: 12, color: AppColors.slateMedium),
                                            ),
                                          ],
                                        ),
                                      ],
                                    ),
                                    Row(
                                      children: [
                                        Text(
                                          '${batch.quantity} dispo',
                                          style: const TextStyle(fontWeight: FontWeight.bold),
                                        ),
                                        const SizedBox(width: 8),
                                        AlertBadge(level: batch.alertLevel, compact: true),
                                      ],
                                    ),
                                  ],
                                ),
                              );
                            }),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Traçabilité Patient (optionnel / rappel lot)
                    Card(
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      elevation: 1.5,
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Row(
                              children: [
                                Icon(Icons.person_pin_rounded, color: AppColors.primaryDark),
                                SizedBox(width: 8),
                                Text(
                                  'Traçabilité Patient (Optionnel)',
                                  style: TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.bold,
                                    color: AppColors.slateDark,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            const Text(
                              'Nom ou initiales du patient pour traçabilité sanitaire en cas de rappel de lot.',
                              style: TextStyle(fontSize: 12, color: AppColors.slateMedium),
                            ),
                            const SizedBox(height: 12),
                            TextFormField(
                              controller: _patientController,
                              decoration: const InputDecoration(
                                labelText: 'Nom ou Initiales (ex: DUPONT J. ou D.J.)',
                                prefixIcon: Icon(Icons.badge_outlined),
                                hintText: 'Optionnel',
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Sélecteur tactile de quantité
                    Card(
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      elevation: 1.5,
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Nombre de boîtes remises',
                              style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.bold,
                                color: AppColors.slateDark,
                              ),
                            ),
                            const SizedBox(height: 16),
                            Row(
                              children: [
                                IconButton.filledTonal(
                                  icon: const Icon(Icons.remove_rounded, size: 28),
                                  onPressed: () => _adjustQuantity(-1),
                                  style: IconButton.styleFrom(
                                    padding: const EdgeInsets.all(14),
                                    backgroundColor: AppColors.slateLight,
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: TextFormField(
                                    controller: _quantityController,
                                    keyboardType: TextInputType.number,
                                    textAlign: TextAlign.center,
                                    style: const TextStyle(
                                      fontSize: 26,
                                      fontWeight: FontWeight.bold,
                                      color: AppColors.primaryDark,
                                    ),
                                    decoration: InputDecoration(
                                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                                      contentPadding: const EdgeInsets.symmetric(vertical: 10),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                IconButton.filledTonal(
                                  icon: const Icon(Icons.add_rounded, size: 28),
                                  onPressed: () => _adjustQuantity(1),
                                  style: IconButton.styleFrom(
                                    padding: const EdgeInsets.all(14),
                                    backgroundColor: AppColors.primaryLight,
                                    foregroundColor: AppColors.primaryDark,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 28),

                    // Gros bouton tactile de remise immédiate
                    BigTouchButton(
                      label: 'Confirmer la Remise au Patient',
                      subtitle: 'Décrémente automatiquement le lot le plus proche (FEFO)',
                      icon: Icons.output_rounded,
                      color: AppColors.primaryDark,
                      onPressed: _confirmExit,
                    ),
                  ],
                ],
              ),
            ),
    );
  }
}
