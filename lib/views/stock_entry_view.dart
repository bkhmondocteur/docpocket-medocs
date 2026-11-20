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
import 'widgets/medicine_catalog_picker.dart';

/// Écran Entrée en Stock (Réception) avec assignation directe à la base de données médicaments
class StockEntryView extends StatefulWidget {
  final String? initialBarcode;

  const StockEntryView({super.key, this.initialBarcode});

  @override
  State<StockEntryView> createState() => _StockEntryViewState();
}

class _StockEntryViewState extends State<StockEntryView> {
  final _formKey = GlobalKey<FormState>();

  final _cipController = TextEditingController();
  final _nameController = TextEditingController();
  final _dciController = TextEditingController();
  final _dosageController = TextEditingController();
  final _formGaleniqueController = TextEditingController();
  final _classController = TextEditingController();
  final _labController = TextEditingController();

  final _batchController = TextEditingController();
  final _expiryController = TextEditingController();
  final _quantityController = TextEditingController(text: '1');
  final _serialController = TextEditingController();

  final _expiryFocusNode = FocusNode();
  final _quantityFocusNode = FocusNode();

  bool _isAssigned = false;
  Medicine? _existingMedicine;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    BarcodeHardwareListener.instance.addListener(_onBarcodeScanned);

    // Pré-charger le catalogue des 5 112 médicaments
    MedicinesCatalogService.instance.loadCatalog();

    if (widget.initialBarcode != null) {
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
    _dciController.dispose();
    _dosageController.dispose();
    _formGaleniqueController.dispose();
    _classController.dispose();
    _labController.dispose();
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

    // Vérifier si le GTIN est déjà assigné à un médicament dans le stock
    final found = await DatabaseService.instance.getMedicineByGtin(gtin);

    if (found != null) {
      _applyMedicine(found);
      if (parsed.requiresManualExpiry) {
        _expiryFocusNode.requestFocus();
      } else {
        _quantityFocusNode.requestFocus();
      }
    } else {
      // Code non encore assigné : proposer immédiatement la sélection dans le catalogue
      _isAssigned = false;
      _existingMedicine = null;
      _nameController.clear();
      _dciController.clear();
      _dosageController.clear();
      _formGaleniqueController.clear();
      _classController.clear();
      _labController.clear();

      setState(() => _isLoading = false);

      // Ouvrir automatiquement la recherche dans le catalogue
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
    _dciController.text = med.dci;
    _dosageController.text = med.dosage;
    _formGaleniqueController.text = med.form;
    _classController.text = med.therapeuticClass;
    _labController.text = med.laboratory;
  }

  Future<void> _openCatalogPicker() async {
    final selected = await MedicineCatalogPickerDialog.show(context, initialQuery: _nameController.text);
    if (selected != null && mounted) {
      setState(() {
        final now = DateTime.now();
        final gtin = _cipController.text.trim().isEmpty ? 'CODE_${now.millisecondsSinceEpoch}' : _cipController.text.trim();

        _cipController.text = gtin;
        _nameController.text = selected.name;
        _dciController.text = selected.dci;
        _dosageController.text = selected.dosage;
        _formGaleniqueController.text = selected.form;
        _classController.text = selected.therapeuticClass;
        _labController.text = selected.laboratory;
        _isAssigned = true;

        _existingMedicine = Medicine(
          id: 'med_${DateTime.now().millisecondsSinceEpoch}',
          cipGtin: gtin,
          commercialName: selected.name,
          dci: selected.dci,
          dosage: selected.dosage,
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
          content: Text('Veuillez assigner ce code à un médicament de la base de données.'),
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
            dci: _dciController.text.trim(),
            dosage: _dosageController.text.trim(),
            form: _formGaleniqueController.text.trim(),
            therapeuticClass: _classController.text.trim(),
            laboratory: _labController.text.trim(),
            updatedAt: now,
          ) ??
          Medicine(
            id: 'med_${DateTime.now().millisecondsSinceEpoch}',
            cipGtin: gtin,
            commercialName: _nameController.text.trim(),
            dci: _dciController.text.trim(),
            dosage: _dosageController.text.trim(),
            form: _formGaleniqueController.text.trim(),
            therapeuticClass: _classController.text.trim(),
            laboratory: _labController.text.trim(),
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
        note: 'Réception délégué (${medicine.laboratory})',
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Enregistré : +$qty boîte(s) de ${medicine.commercialName} (Lot: $batchNo - Exp: ${_expiryController.text})',
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
                          const Icon(Icons.barcode_reader, color: AppColors.primaryBlue, size: 30),
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
                                    fontSize: 14.5,
                                  ),
                                ),
                                Text(
                                  'Scannez avec la douchette USB ou la caméra pour démarrer.',
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
                    const SizedBox(height: 18),

                    // Champ Code GTIN / CIP scanné
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
                      validator: (v) => (v == null || v.trim().isEmpty) ? 'Le code est requis' : null,
                    ),
                    const SizedBox(height: 14),

                    // Bouton d'assignation au catalogue
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: _isAssigned ? AppColors.alertValidLight : AppColors.alertWarningLight,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: (_isAssigned ? AppColors.alertValid : AppColors.alertWarning).withValues(alpha: 0.4),
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(
                                _isAssigned ? Icons.check_circle_rounded : Icons.info_outline_rounded,
                                color: _isAssigned ? AppColors.alertValid : AppColors.alertWarning,
                                size: 22,
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  _isAssigned
                                      ? 'Médicament assigné : ${_nameController.text}'
                                      : 'Code non assigné : choisissez le médicament dans la base',
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 14,
                                    color: _isAssigned ? AppColors.alertValid : AppColors.alertWarning,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          SizedBox(
                            width: double.infinity,
                            child: ElevatedButton.icon(
                              onPressed: _openCatalogPicker,
                              icon: const Icon(Icons.manage_search_rounded),
                              label: Text(
                                _isAssigned
                                    ? 'Changer le médicament assigné (5 063 dans la base)'
                                    : 'Assigner à un médicament de la base (5 063 médicaments)',
                                style: const TextStyle(fontWeight: FontWeight.bold),
                              ),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: _isAssigned ? AppColors.slateDark : AppColors.primaryBlue,
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(vertical: 12),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Fiche du médicament sélectionné
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
                                  'Détails du Médicament',
                                  style: TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.bold,
                                    color: AppColors.slateDark,
                                  ),
                                ),
                                if (_isAssigned)
                                  const Text(
                                    'Base officielle',
                                    style: TextStyle(
                                      color: AppColors.primaryBlue,
                                      fontWeight: FontWeight.w600,
                                      fontSize: 12,
                                    ),
                                  ),
                              ],
                            ),
                            const Divider(height: 20),
                            TextFormField(
                              controller: _nameController,
                              readOnly: _isAssigned,
                              decoration: const InputDecoration(
                                labelText: 'Nom commercial *',
                                prefixIcon: Icon(Icons.medication_rounded),
                              ),
                              validator: (v) => (v == null || v.trim().isEmpty) ? 'Le nom est obligatoire' : null,
                            ),
                            const SizedBox(height: 12),
                            Row(
                              children: [
                                Expanded(
                                  child: TextFormField(
                                    controller: _dciController,
                                    readOnly: _isAssigned,
                                    decoration: const InputDecoration(labelText: 'DCI (Principe actif)'),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: TextFormField(
                                    controller: _dosageController,
                                    readOnly: _isAssigned,
                                    decoration: const InputDecoration(labelText: 'Dosage / Présentation'),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            Row(
                              children: [
                                Expanded(
                                  child: TextFormField(
                                    controller: _formGaleniqueController,
                                    readOnly: _isAssigned,
                                    decoration: const InputDecoration(labelText: 'Forme galénique'),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: TextFormField(
                                    controller: _labController,
                                    readOnly: _isAssigned,
                                    decoration: const InputDecoration(labelText: 'Laboratoire'),
                                  ),
                                ),
                              ],
                            ),
                            if (_classController.text.isNotEmpty) ...[
                              const SizedBox(height: 12),
                              TextFormField(
                                controller: _classController,
                                readOnly: _isAssigned,
                                decoration: const InputDecoration(labelText: 'Classe thérapeutique'),
                              ),
                            ],
                          ],
                        ),
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
                                    validator: (v) => (v == null || v.trim().isEmpty) ? 'Numéro de lot requis' : null,
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
                                      labelText: 'Péremption * (jj/mm/aaaa)',
                                      hintText: '31/12/2026',
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
                                labelText: 'Numéro de série unitaire (Optionnel)',
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

                    // Gros bouton tactile de validation
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
