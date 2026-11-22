import 'package:flutter/material.dart';
import '../../core/constants/app_colors.dart';
import '../../core/formatters/strict_date_formatter.dart';
import '../../core/parsers/gs1_datamatrix_parser.dart';
import '../../core/database/database_service.dart';
import '../../core/services/barcode_hardware_listener.dart';
import '../../core/services/medicines_catalog_service.dart';
import '../../models/medicine.dart';
import 'widgets/big_touch_button.dart';
import 'widgets/camera_scanner_modal.dart';
import 'widgets/create_custom_medicine_dialog.dart';
import 'widgets/medicine_catalog_picker.dart';

/// Écran Entrée en Stock (Réception)
/// Affichage épuré : SEULEMENT Nom Commercial, Forme et Boîte/Flacon
class StockEntryView extends StatefulWidget {
  final String? initialBarcode;
  final CatalogMedicine? initialCatalogMedicine;

  const StockEntryView({super.key, this.initialBarcode, this.initialCatalogMedicine});

  @override
  State<StockEntryView> createState() => _StockEntryViewState();
}

class _StockEntryViewState extends State<StockEntryView> {
  final _formKey = GlobalKey<FormState>();

  final _cipController = TextEditingController();
  final _nameController = TextEditingController();
  final _formGaleniqueController = TextEditingController();
  final _packagingController = TextEditingController();

  final _batchController = TextEditingController();
  final _expiryController = TextEditingController();
  final _quantityController = TextEditingController(text: '1');
  final _serialController = TextEditingController();

  final _expiryFocusNode = FocusNode();
  final _quantityFocusNode = FocusNode();

  bool _isAssigned = false;
  Medicine? _existingMedicine;
  String _dci = '';
  String _laboratory = '';
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    BarcodeHardwareListener.instance.addListener(_onBarcodeScanned);

    // Pré-chargement silencieux du catalogue des médicaments
    MedicinesCatalogService.instance.loadCatalog();

    if (widget.initialCatalogMedicine != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _applyCatalogMedicine(widget.initialCatalogMedicine!);
      });
    } else if (widget.initialBarcode != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _processBarcode(widget.initialBarcode!);
      });
    }
  }

  @override
  void dispose() {
    BarcodeHardwareListener.instance.removeListener(_onBarcodeScanned);
    _cipController.dispose();
    _nameController.dispose();
    _formGaleniqueController.dispose();
    _packagingController.dispose();
    _batchController.dispose();
    _expiryController.dispose();
    _quantityController.dispose();
    _serialController.dispose();
    _expiryFocusNode.dispose();
    _quantityFocusNode.dispose();
    super.dispose();
  }

  void _onBarcodeScanned(String rawBarcode) {
    if (!mounted) return;
    _processBarcode(rawBarcode);
  }

  Future<void> _processBarcode(String rawBarcode) async {
    setState(() => _isLoading = true);

    final parsed = Gs1DataMatrixParser.parse(rawBarcode);
    final gtin = parsed.gtin ?? rawBarcode.trim();
    _cipController.text = gtin;

    if (parsed.lotNumber != null) {
      _batchController.text = parsed.lotNumber!;
    }
    if (parsed.expiryDateFormatted != null) {
      _expiryController.text = parsed.expiryDateFormatted!;
    }
    if (parsed.serialNumber != null) {
      _serialController.text = parsed.serialNumber!;
    }

    // Vérifier si le code est déjà mémorisé dans le cabinet
    final found = await DatabaseService.instance.getMedicineByGtin(gtin);

    if (found != null) {
      _applyMedicine(found);
      if (parsed.requiresManualExpiry) {
        _expiryFocusNode.requestFocus();
      } else {
        _quantityFocusNode.requestFocus();
      }
    } else {
      // Code non encore assigné : ouvrir directement la sélection de la base
      _isAssigned = false;
      _existingMedicine = null;
      _nameController.clear();
      _formGaleniqueController.clear();
      _packagingController.clear();

      setState(() => _isLoading = false);

      WidgetsBinding.instance.addPostFrameCallback((_) {
        _openCatalogPicker();
      });
      return;
    }

    setState(() => _isLoading = false);
  }

  void _applyMedicine(Medicine med) {
    _existingMedicine = med;
    _isAssigned = true;
    _nameController.text = med.commercialName;
    _formGaleniqueController.text = med.form;
    _packagingController.text = med.dosage; // Contient le conditionnement (Boîte ou Flacon)
    _dci = med.dci;
    _laboratory = med.laboratory;
  }

  void _applyCatalogMedicine(CatalogMedicine selected) {
    setState(() {
      final now = DateTime.now();
      final gtin = _cipController.text.trim().isEmpty ? 'CODE_${now.millisecondsSinceEpoch}' : _cipController.text.trim();

      _cipController.text = gtin;
      _nameController.text = selected.cleanCommercialName;
      _formGaleniqueController.text = selected.form;
      _packagingController.text = selected.packaging;
      _dci = selected.dci;
      _laboratory = selected.laboratory;
      _isAssigned = true;

      final match = DatabaseService.instance.findExistingMedicine(
        commercialName: selected.cleanCommercialName,
        form: selected.form,
        dosage: selected.packaging,
        cipGtin: gtin,
      );

      _existingMedicine = match ??
          Medicine(
            id: 'med_${DateTime.now().millisecondsSinceEpoch}',
            cipGtin: gtin,
            commercialName: selected.cleanCommercialName,
            dci: selected.dci,
            dosage: selected.packaging,
            form: selected.form,
            therapeuticClass: selected.therapeuticClass,
            laboratory: selected.laboratory,
            createdAt: now,
            updatedAt: now,
          );
    });

    if (_expiryController.text.isEmpty) {
      _expiryFocusNode.requestFocus();
    } else {
      _quantityFocusNode.requestFocus();
    }
  }

  Future<void> _openCatalogPicker() async {
    final selected = await MedicineCatalogPickerDialog.show(context, initialQuery: _nameController.text);
    if (selected != null && mounted) {
      _applyCatalogMedicine(selected);
    }
  }

  Future<void> _openCreateCustomMedicineDialog() async {
    final created = await CreateCustomMedicineDialog.show(
      context,
      initialName: _nameController.text.trim().isNotEmpty ? _nameController.text.trim() : null,
    );
    if (created != null && mounted) {
      _applyCatalogMedicine(created);
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
    current = (current + delta).clamp(1, 999);
    _quantityController.text = current.toString();
  }

  Future<void> _saveEntry() async {
    if (_cipController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Veuillez scanner un code-barres ou QR code.'),
          backgroundColor: AppColors.alertExpired,
        ),
      );
      return;
    }

    if (!_isAssigned || _nameController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Veuillez choisir un médicament dans la base de données.'),
          backgroundColor: AppColors.alertWarning,
        ),
      );
      return;
    }

    if (!_formKey.currentState!.validate()) return;

    final expiryValidation = StrictDateValidator.validate(_expiryController.text);
    if (!expiryValidation.isValid) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(expiryValidation.errorMessage ?? 'Date de péremption invalide'),
          backgroundColor: AppColors.alertExpired,
        ),
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      final now = DateTime.now();
      final gtin = _cipController.text.trim();

      final medicine = _existingMedicine?.copyWith(
            commercialName: _nameController.text.trim(),
            form: _formGaleniqueController.text.trim(),
            dosage: _packagingController.text.trim(),
            dci: _dci.isNotEmpty ? _dci : _existingMedicine?.dci,
            laboratory: _laboratory.isNotEmpty ? _laboratory : _existingMedicine?.laboratory,
            updatedAt: now,
          ) ??
          Medicine(
            id: 'med_${DateTime.now().millisecondsSinceEpoch}',
            cipGtin: gtin,
            commercialName: _nameController.text.trim(),
            dci: _dci,
            dosage: _packagingController.text.trim(),
            form: _formGaleniqueController.text.trim(),
            therapeuticClass: '',
            laboratory: _laboratory,
            createdAt: now,
            updatedAt: now,
          );

      final qty = int.parse(_quantityController.text.trim());
      final batchNo = _batchController.text.trim().isEmpty ? 'SANS-LOT' : _batchController.text.trim();

      await DatabaseService.instance.recordStockEntry(
        medicine: medicine,
        batchNumber: batchNo,
        expiryDate: expiryValidation.parsedDate!,
        quantity: qty,
        serialNumber: _serialController.text.trim().isEmpty ? null : _serialController.text.trim(),
        note: 'Réception échantillon',
      );

      if (mounted) {
        final pkg = _packagingController.text.isNotEmpty ? ' (${_packagingController.text})' : '';
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Enregistré : +$qty de ${medicine.commercialName}$pkg [Lot: $batchNo • Exp: ${_expiryController.text}]',
            ),
            backgroundColor: AppColors.alertValid,
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
        title: const Text('Entrée en Stock (Réception)', style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: AppColors.primaryBlue,
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
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Bandeau scanner
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      decoration: BoxDecoration(
                        color: AppColors.primaryLight,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: AppColors.primaryAccent.withValues(alpha: 0.3)),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.barcode_reader, color: AppColors.primaryBlue, size: 28),
                          const SizedBox(width: 12),
                          const Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Scanner le Code-barres ou QR code',
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    color: AppColors.primaryDark,
                                    fontSize: 14,
                                  ),
                                ),
                                Text(
                                  'Douchette USB ou caméra mobile active',
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
                              backgroundColor: AppColors.primaryBlue,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Champ Code
                    TextFormField(
                      controller: _cipController,
                      decoration: InputDecoration(
                        labelText: 'Code Scanné (Code-barres / DataMatrix / QR) *',
                        prefixIcon: const Icon(Icons.qr_code_2_rounded, color: AppColors.primaryBlue),
                        suffixIcon: IconButton(
                          icon: const Icon(Icons.search_rounded),
                          tooltip: 'Identifier',
                          onPressed: () => _processBarcode(_cipController.text),
                        ),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                        filled: true,
                        fillColor: Colors.white,
                      ),
                      validator: (v) => (v == null || v.trim().isEmpty) ? 'Code obligatoire' : null,
                    ),
                    const SizedBox(height: 14),

                    // Section Assignation épurée : SEULEMENT Nom Commercial, Forme et Boîte/Flacon
                    if (_isAssigned)
                      Card(
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                          side: BorderSide(color: AppColors.alertValid.withValues(alpha: 0.5), width: 1.5),
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
                                      const Icon(Icons.check_circle_rounded, color: AppColors.alertValid, size: 22),
                                      const SizedBox(width: 8),
                                      Text(
                                        'Médicament Assigné',
                                        style: TextStyle(
                                          fontWeight: FontWeight.bold,
                                          color: Colors.green.shade800,
                                          fontSize: 13,
                                        ),
                                      ),
                                    ],
                                  ),
                                  Row(
                                    children: [
                                      TextButton.icon(
                                        onPressed: _openCatalogPicker,
                                        icon: const Icon(Icons.swap_horiz_rounded, size: 18),
                                        label: const Text('Changer'),
                                        style: TextButton.styleFrom(
                                          foregroundColor: AppColors.primaryBlue,
                                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                        ),
                                      ),
                                      const SizedBox(width: 4),
                                      TextButton.icon(
                                        onPressed: _openCreateCustomMedicineDialog,
                                        icon: const Icon(Icons.add_rounded, size: 18),
                                        label: const Text('Nouveau'),
                                        style: TextButton.styleFrom(
                                          foregroundColor: AppColors.primaryDark,
                                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                              const Divider(height: 16),

                              // 1. NOM COMMERCIAL
                              Text(
                                _nameController.text,
                                style: const TextStyle(
                                  fontSize: 19,
                                  fontWeight: FontWeight.bold,
                                  color: AppColors.slateDark,
                                ),
                              ),
                              const SizedBox(height: 8),

                              // 2. FORME & 3. BOITE OU FLACON DE COMBIEN (+ DCI / Labo)
                              Wrap(
                                spacing: 8,
                                runSpacing: 6,
                                children: [
                                  if (_formGaleniqueController.text.isNotEmpty)
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                      decoration: BoxDecoration(
                                        color: Colors.blue.shade50,
                                        borderRadius: BorderRadius.circular(8),
                                        border: Border.all(color: Colors.blue.shade200),
                                      ),
                                      child: Text(
                                        _formGaleniqueController.text,
                                        style: TextStyle(
                                          color: Colors.blue.shade900,
                                          fontWeight: FontWeight.w600,
                                          fontSize: 13,
                                        ),
                                      ),
                                    ),
                                  if (_packagingController.text.isNotEmpty)
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                      decoration: BoxDecoration(
                                        color: Colors.teal.shade50,
                                        borderRadius: BorderRadius.circular(8),
                                        border: Border.all(color: Colors.teal.shade200),
                                      ),
                                      child: Text(
                                        _packagingController.text,
                                        style: TextStyle(
                                          color: Colors.teal.shade900,
                                          fontWeight: FontWeight.bold,
                                          fontSize: 13,
                                        ),
                                      ),
                                    ),
                                  if (_dci.isNotEmpty)
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                      decoration: BoxDecoration(
                                        color: Colors.purple.shade50,
                                        borderRadius: BorderRadius.circular(8),
                                        border: Border.all(color: Colors.purple.shade200),
                                      ),
                                      child: Text(
                                        'DCI: $_dci',
                                        style: TextStyle(
                                          color: Colors.purple.shade900,
                                          fontSize: 12,
                                        ),
                                      ),
                                    ),
                                  if (_laboratory.isNotEmpty)
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                      decoration: BoxDecoration(
                                        color: Colors.indigo.shade50,
                                        borderRadius: BorderRadius.circular(8),
                                        border: Border.all(color: Colors.indigo.shade200),
                                      ),
                                      child: Text(
                                        'Lab: $_laboratory',
                                        style: TextStyle(
                                          color: Colors.indigo.shade900,
                                          fontSize: 12,
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      )
                    else
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: AppColors.alertWarningLight,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: AppColors.alertWarning.withValues(alpha: 0.4)),
                        ),
                        child: Column(
                          children: [
                            const Row(
                              children: [
                                Icon(Icons.info_outline_rounded, color: AppColors.alertWarning),
                                SizedBox(width: 10),
                                Expanded(
                                  child: Text(
                                    'Code non assigné : sélectionnez le médicament dans la base ou créez-le s\'il est introuvable.',
                                    style: TextStyle(fontWeight: FontWeight.bold, color: AppColors.alertWarning),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            SizedBox(
                              width: double.infinity,
                              child: ElevatedButton.icon(
                                onPressed: _openCatalogPicker,
                                icon: const Icon(Icons.manage_search_rounded),
                                label: const Text(
                                  'Choisir le médicament dans la base',
                                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                                ),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: AppColors.primaryBlue,
                                  foregroundColor: Colors.white,
                                  padding: const EdgeInsets.symmetric(vertical: 13),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                ),
                              ),
                            ),
                            const SizedBox(height: 8),
                            SizedBox(
                              width: double.infinity,
                              child: OutlinedButton.icon(
                                onPressed: _openCreateCustomMedicineDialog,
                                icon: const Icon(Icons.add_circle_outline_rounded),
                                label: const Text(
                                  'Médicament hors base ? Ajouter manuellement',
                                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                                ),
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: AppColors.primaryBlue,
                                  side: const BorderSide(color: AppColors.primaryBlue, width: 1.5),
                                  padding: const EdgeInsets.symmetric(vertical: 12),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    const SizedBox(height: 16),

                    // Carte Lot et Péremption
                    Card(
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      elevation: 1.5,
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Numéro de Lot & Date de Péremption',
                              style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.bold,
                                color: AppColors.slateDark,
                              ),
                            ),
                            const Divider(height: 20),
                            Row(
                              children: [
                                Expanded(
                                  child: TextFormField(
                                    controller: _batchController,
                                    decoration: const InputDecoration(
                                      labelText: 'Numéro de lot *',
                                      hintText: 'ex: LOT-2026-X',
                                      prefixIcon: Icon(Icons.tag_rounded),
                                    ),
                                    validator: (v) => (v == null || v.trim().isEmpty) ? 'N° de lot requis' : null,
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: TextFormField(
                                    controller: _expiryController,
                                    focusNode: _expiryFocusNode,
                                    keyboardType: TextInputType.number,
                                    inputFormatters: [StrictDateInputFormatter()],
                                    decoration: const InputDecoration(
                                      labelText: 'Péremption * (MM/AAAA)',
                                      hintText: 'ex: 11/2028',
                                      prefixIcon: Icon(Icons.calendar_month_rounded),
                                    ),
                                    validator: (v) {
                                      final res = StrictDateValidator.validate(v);
                                      return res.isValid ? null : res.errorMessage;
                                    },
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            TextFormField(
                              controller: _serialController,
                              decoration: const InputDecoration(
                                labelText: 'N° de Série unitaire (Optionnel / DataMatrix)',
                                prefixIcon: Icon(Icons.fingerprint_rounded),
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
                              'Quantité reçue (Nombre de boîtes)',
                              style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.bold,
                                color: AppColors.slateDark,
                              ),
                            ),
                            const SizedBox(height: 14),
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
                                    focusNode: _quantityFocusNode,
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
                                    validator: (v) {
                                      final val = int.tryParse(v ?? '');
                                      if (val == null || val <= 0) return 'Quantité > 0 requise';
                                      return null;
                                    },
                                  ),
                                ),
                                const SizedBox(width: 12),
                                IconButton.filledTonal(
                                  icon: const Icon(Icons.add_rounded, size: 28),
                                  onPressed: () => _adjustQuantity(1),
                                  style: IconButton.styleFrom(
                                    padding: const EdgeInsets.all(14),
                                    backgroundColor: AppColors.primaryLight,
                                    foregroundColor: AppColors.primaryBlue,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                OutlinedButton(
                                  onPressed: () => _adjustQuantity(5),
                                  child: const Text('+5 boîtes'),
                                ),
                                const SizedBox(width: 10),
                                OutlinedButton(
                                  onPressed: () => _adjustQuantity(10),
                                  child: const Text('+10 boîtes'),
                                ),
                                const SizedBox(width: 10),
                                OutlinedButton(
                                  onPressed: () => _adjustQuantity(20),
                                  child: const Text('+20 boîtes'),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 26),

                    // Validation
                    BigTouchButton(
                      label: 'Valider l\'Entrée en Stock',
                      subtitle: 'Incrémente le stock avec le lot et la date de péremption',
                      icon: Icons.check_circle_rounded,
                      color: AppColors.primaryBlue,
                      onPressed: _saveEntry,
                    ),
                    const SizedBox(height: 20),
                  ],
                ),
              ),
            ),
    );
  }
}
