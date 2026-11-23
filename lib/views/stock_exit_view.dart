import 'package:flutter/material.dart';
import '../../core/constants/app_colors.dart';
import '../../core/parsers/gs1_datamatrix_parser.dart';
import '../../core/database/database_service.dart';
import '../../core/services/barcode_hardware_listener.dart';
import '../../models/medicine.dart';
import 'stock_entry_view.dart';
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

  List<Medicine> get _filteredMedicines {
    final q = _searchController.text.trim().toLowerCase();
    if (q.isEmpty) return _availableMedicines;
    return _availableMedicines.where((m) {
      final matchName = m.commercialName.toLowerCase().contains(q);
      final matchForm = m.form.toLowerCase().contains(q);
      final matchPkg = m.dosage.toLowerCase().contains(q);
      final matchBatch = m.batches.any((b) => b.batchNumber.toLowerCase().contains(q));
      return matchName || matchForm || matchPkg || matchBatch;
    }).toList();
  }

  void _onBarcodeScanned(String rawBarcode) {
    if (!mounted) return;
    _processBarcode(rawBarcode);
  }

  Future<void> _processBarcode(String rawBarcode) async {
    final parsed = Gs1DataMatrixParser.parse(rawBarcode);
    final gtin = parsed.gtin ?? rawBarcode.trim();

    final found = await DatabaseService.instance.getMedicineByGtin(gtin);
    if (found != null && found.totalStock > 0 && mounted) {
      setState(() {
        _selectedMedicine = found;
        _quantityController.text = '1';
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Sélectionné : ${found.commercialName} (${found.totalStock} disponible(s))'),
          backgroundColor: AppColors.primaryBlue,
          duration: const Duration(seconds: 2),
        ),
      );
    } else if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            found == null
                ? 'Code $gtin non trouvé dans le catalogue'
                : '${found.commercialName} est en rupture (stock : 0)',
          ),
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
        title: const Text('Sortie de Stock', style: TextStyle(fontWeight: FontWeight.bold)),
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
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Bandeau scanner douchette
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    decoration: BoxDecoration(
                      color: AppColors.primaryLight,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: AppColors.primaryAccent.withValues(alpha: 0.3)),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.barcode_reader, color: AppColors.primaryDark, size: 26),
                        const SizedBox(width: 10),
                        const Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Scan direct de la boîte (Douchette USB)',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: AppColors.primaryDark,
                                  fontSize: 13.5,
                                ),
                              ),
                              Text(
                                'Scannez pour sélectionner instantanément le médicament.',
                                style: TextStyle(color: AppColors.slateMedium, fontSize: 11.5),
                              ),
                            ],
                          ),
                        ),
                        ElevatedButton.icon(
                          onPressed: _openCameraScanner,
                          icon: const Icon(Icons.camera_alt_rounded, size: 16),
                          label: const Text('Caméra', style: TextStyle(fontSize: 12.5)),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.primaryDark,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Si le stock est totalement vide
                  if (_availableMedicines.isEmpty)
                    Card(
                      elevation: 0,
                      color: Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      child: Padding(
                        padding: const EdgeInsets.all(28),
                        child: Column(
                          children: [
                            const Icon(Icons.inventory_2_outlined, size: 50, color: AppColors.slateMedium),
                            const SizedBox(height: 12),
                            const Text(
                              'Aucun échantillon en stock',
                              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                            ),
                            const SizedBox(height: 6),
                            const Text(
                              'Pour effectuer une sortie patient, commencez par enregistrer une entrée en stock.',
                              textAlign: TextAlign.center,
                              style: TextStyle(color: AppColors.slateMedium, fontSize: 13),
                            ),
                            const SizedBox(height: 16),
                            ElevatedButton.icon(
                              onPressed: () {
                                Navigator.of(context).pushReplacement(
                                  MaterialPageRoute(builder: (_) => const StockEntryView()),
                                );
                              },
                              icon: const Icon(Icons.add_rounded),
                              label: const Text('Enregistrer une entrée'),
                              style: ElevatedButton.styleFrom(backgroundColor: AppColors.primaryBlue),
                            ),
                          ],
                        ),
                      ),
                    )
                  // Si aucun médicament n'est encore sélectionné : Afficher la barre de recherche et la liste des stocks
                  else if (_selectedMedicine == null)
                    Card(
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      elevation: 1.5,
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                const Text(
                                  'Choisir le médicament en stock',
                                  style: TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.bold,
                                    color: AppColors.slateDark,
                                  ),
                                ),
                                Text(
                                  '${_availableMedicines.length} référence(s)',
                                  style: const TextStyle(fontSize: 12, color: AppColors.slateMedium),
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),

                            // CHAMP DE RECHERCHE RAPIDE EN SORTIE
                            TextField(
                              controller: _searchController,
                              autofocus: false,
                              decoration: InputDecoration(
                                hintText: 'Rechercher par nom, forme...',
                                prefixIcon: const Icon(Icons.search_rounded, color: AppColors.primaryDark),
                                contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                                suffixIcon: _searchController.text.isNotEmpty
                                    ? IconButton(
                                        icon: const Icon(Icons.clear_rounded),
                                        onPressed: () {
                                          setState(() => _searchController.clear());
                                        },
                                      )
                                    : null,
                                filled: true,
                                fillColor: AppColors.slateLight.withValues(alpha: 0.4),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                  borderSide: BorderSide.none,
                                ),
                              ),
                              onChanged: (_) => setState(() {}),
                            ),
                            const SizedBox(height: 10),

                            // LISTE DES RÉSULTATS
                            if (_filteredMedicines.isEmpty)
                              const Padding(
                                padding: EdgeInsets.symmetric(vertical: 24),
                                child: Center(
                                  child: Text(
                                    'Aucun échantillon ne correspond à la recherche.',
                                    style: TextStyle(color: AppColors.slateMedium),
                                  ),
                                ),
                              )
                            else
                              ListView.separated(
                                shrinkWrap: true,
                                physics: const NeverScrollableScrollPhysics(),
                                itemCount: _filteredMedicines.length,
                                separatorBuilder: (context, index) => const Divider(height: 1),
                                itemBuilder: (context, index) {
                                  final med = _filteredMedicines[index];
                                  final form = med.form.trim();
                                  final packaging = med.dosage.trim();

                                  return ListTile(
                                    contentPadding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                                    leading: Container(
                                      padding: const EdgeInsets.all(8),
                                      decoration: BoxDecoration(
                                        color: AppColors.primaryLight,
                                        borderRadius: BorderRadius.circular(10),
                                      ),
                                      child: const Icon(
                                        Icons.medication_rounded,
                                        color: AppColors.primaryDark,
                                        size: 22,
                                      ),
                                    ),
                                    title: Text(
                                      med.commercialName,
                                      style: const TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 15,
                                        color: AppColors.slateDark,
                                      ),
                                    ),
                                    subtitle: Padding(
                                      padding: const EdgeInsets.only(top: 4),
                                      child: Wrap(
                                        spacing: 6,
                                        runSpacing: 4,
                                        children: [
                                          if (form.isNotEmpty)
                                            Container(
                                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                              decoration: BoxDecoration(
                                                color: Colors.blue.shade50,
                                                borderRadius: BorderRadius.circular(5),
                                                border: Border.all(color: Colors.blue.shade200, width: 0.8),
                                              ),
                                              child: Text(
                                                form,
                                                style: TextStyle(
                                                  fontSize: 11,
                                                  fontWeight: FontWeight.w600,
                                                  color: Colors.blue.shade900,
                                                ),
                                              ),
                                            ),
                                          if (packaging.isNotEmpty)
                                            Container(
                                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                              decoration: BoxDecoration(
                                                color: Colors.teal.shade50,
                                                borderRadius: BorderRadius.circular(5),
                                                border: Border.all(color: Colors.teal.shade200, width: 0.8),
                                              ),
                                              child: Text(
                                                packaging,
                                                style: TextStyle(
                                                  fontSize: 11,
                                                  fontWeight: FontWeight.bold,
                                                  color: Colors.teal.shade900,
                                                ),
                                              ),
                                            ),
                                        ],
                                      ),
                                    ),
                                    trailing: Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                                      decoration: BoxDecoration(
                                        color: AppColors.primaryLight,
                                        borderRadius: BorderRadius.circular(10),
                                      ),
                                      child: Text(
                                        '${med.totalStock} boîte${med.totalStock > 1 ? "s" : ""}',
                                        style: const TextStyle(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 12.5,
                                          color: AppColors.primaryDark,
                                        ),
                                      ),
                                    ),
                                    onTap: () {
                                      setState(() {
                                        _selectedMedicine = med;
                                        _quantityController.text = '1';
                                      });
                                    },
                                  );
                                },
                              ),
                          ],
                        ),
                      ),
                    )
                  // Si un médicament est sélectionné : Affichage épuré + FEFO + Confirmation
                  else ...[
                    Card(
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                        side: BorderSide(color: AppColors.primaryBlue.withValues(alpha: 0.4), width: 1.5),
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
                                Row(
                                  children: [
                                    const Icon(Icons.check_circle_rounded, color: AppColors.primaryDark, size: 20),
                                    const SizedBox(width: 8),
                                    const Text(
                                      'Médicament sélectionné',
                                      style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                        color: AppColors.primaryDark,
                                        fontSize: 13,
                                      ),
                                    ),
                                  ],
                                ),
                                TextButton.icon(
                                  onPressed: () {
                                    setState(() => _selectedMedicine = null);
                                  },
                                  icon: const Icon(Icons.swap_horiz_rounded, size: 18),
                                  label: const Text('Changer'),
                                  style: TextButton.styleFrom(
                                    foregroundColor: AppColors.primaryBlue,
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                  ),
                                ),
                              ],
                            ),
                            const Divider(height: 14),

                            // NOM COMMERCIAL ÉPURÉ
                            Text(
                              _selectedMedicine!.commercialName,
                              style: const TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                color: AppColors.slateDark,
                              ),
                            ),
                            const SizedBox(height: 6),

                            // FORME & BOÎTE / FLACON DE COMBIEN
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Expanded(
                                  child: Wrap(
                                    spacing: 6,
                                    runSpacing: 4,
                                    children: [
                                      if (_selectedMedicine!.form.trim().isNotEmpty)
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                          decoration: BoxDecoration(
                                            color: Colors.blue.shade50,
                                            borderRadius: BorderRadius.circular(6),
                                            border: Border.all(color: Colors.blue.shade200, width: 0.8),
                                          ),
                                          child: Text(
                                            _selectedMedicine!.form.trim(),
                                            style: TextStyle(
                                              fontSize: 12,
                                              fontWeight: FontWeight.w600,
                                              color: Colors.blue.shade900,
                                            ),
                                          ),
                                        ),
                                      if (_selectedMedicine!.dosage.trim().isNotEmpty)
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                          decoration: BoxDecoration(
                                            color: Colors.teal.shade50,
                                            borderRadius: BorderRadius.circular(6),
                                            border: Border.all(color: Colors.teal.shade200, width: 0.8),
                                          ),
                                          child: Text(
                                            _selectedMedicine!.dosage.trim(),
                                            style: TextStyle(
                                              fontSize: 12,
                                              fontWeight: FontWeight.bold,
                                              color: Colors.teal.shade900,
                                            ),
                                          ),
                                        ),
                                    ],
                                  ),
                                ),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                                  decoration: BoxDecoration(
                                    color: AppColors.primaryLight,
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: Text(
                                    '${_selectedMedicine!.totalStock} en stock',
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 13,
                                      color: AppColors.primaryDark,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const Divider(height: 20),

                            // Méthode FEFO explicitée
                            const Row(
                              children: [
                                Icon(Icons.auto_awesome_rounded, color: AppColors.primaryAccent, size: 18),
                                SizedBox(width: 8),
                                Text(
                                  'Priorité FEFO (Lot le plus proche en 1er) :',
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    color: AppColors.primaryDark,
                                    fontSize: 13,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),

                            // Liste des lots disponibles par ordre d'expiration
                            ..._selectedMedicine!.fefoOrderedBatches.map((batch) {
                              final isFirst = batch == _selectedMedicine!.nextExpiringBatch;
                              return Container(
                                margin: const EdgeInsets.only(bottom: 6),
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                                decoration: BoxDecoration(
                                  color: isFirst ? AppColors.primaryLight.withValues(alpha: 0.5) : Colors.white,
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(
                                    color: isFirst ? AppColors.primaryBlue : AppColors.slateLight,
                                    width: isFirst ? 1.4 : 0.8,
                                  ),
                                ),
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    Row(
                                      children: [
                                        if (isFirst)
                                          const Padding(
                                            padding: EdgeInsets.only(right: 6),
                                            child: Icon(Icons.arrow_right_alt_rounded, color: AppColors.primaryBlue),
                                          ),
                                        Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              'Lot : ${batch.batchNumber}',
                                              style: TextStyle(
                                                fontWeight: isFirst ? FontWeight.bold : FontWeight.w500,
                                                fontSize: 13,
                                                color: AppColors.slateDark,
                                              ),
                                            ),
                                            Text(
                                              'Périme le : ${batch.expiryDateFormatted}',
                                              style: const TextStyle(fontSize: 11.5, color: AppColors.slateMedium),
                                            ),
                                          ],
                                        ),
                                      ],
                                    ),
                                    Row(
                                      children: [
                                        Text(
                                          '${batch.quantity} dispo',
                                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
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
                    const SizedBox(height: 14),

                    // Traçabilité Patient (optionnel)
                    Card(
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      elevation: 1.5,
                      child: Padding(
                        padding: const EdgeInsets.all(14),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Row(
                              children: [
                                Icon(Icons.person_pin_rounded, color: AppColors.primaryDark, size: 20),
                                SizedBox(width: 8),
                                Text(
                                  'Traçabilité Patient (Optionnel)',
                                  style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.bold,
                                    color: AppColors.slateDark,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 4),
                            const Text(
                              'Nom ou initiales du patient pour traçabilité en cas de rappel de lot.',
                              style: TextStyle(fontSize: 11.5, color: AppColors.slateMedium),
                            ),
                            const SizedBox(height: 10),
                            TextFormField(
                              controller: _patientController,
                              decoration: const InputDecoration(
                                labelText: 'Patient (Nom ou Initiales)',
                                prefixIcon: Icon(Icons.badge_outlined, size: 20),
                                hintText: 'ex: DUPONT J. (Optionnel)',
                                contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),

                    // Sélecteur tactile de quantité
                    Card(
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      elevation: 1.5,
                      child: Padding(
                        padding: const EdgeInsets.all(14),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Nombre de boîtes remises',
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.bold,
                                color: AppColors.slateDark,
                              ),
                            ),
                            const SizedBox(height: 12),
                            Row(
                              children: [
                                IconButton.filledTonal(
                                  icon: const Icon(Icons.remove_rounded, size: 24),
                                  onPressed: () => _adjustQuantity(-1),
                                  style: IconButton.styleFrom(
                                    padding: const EdgeInsets.all(10),
                                    backgroundColor: AppColors.slateLight,
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: TextFormField(
                                    controller: _quantityController,
                                    keyboardType: TextInputType.number,
                                    textAlign: TextAlign.center,
                                    style: const TextStyle(
                                      fontSize: 22,
                                      fontWeight: FontWeight.bold,
                                      color: AppColors.primaryDark,
                                    ),
                                    decoration: InputDecoration(
                                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                                      contentPadding: const EdgeInsets.symmetric(vertical: 8),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 10),
                                IconButton.filledTonal(
                                  icon: const Icon(Icons.add_rounded, size: 24),
                                  onPressed: () => _adjustQuantity(1),
                                  style: IconButton.styleFrom(
                                    padding: const EdgeInsets.all(10),
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
                    const SizedBox(height: 20),

                    // Gros bouton tactile de remise immédiate
                    BigTouchButton(
                      label: 'Confirmer la Remise au Patient',
                      subtitle: 'Décrémente le lot le plus proche selon la règle FEFO',
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
