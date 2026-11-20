import 'package:flutter/material.dart';
import '../../core/constants/app_colors.dart';
import '../../core/formatters/strict_date_formatter.dart';
import '../../core/parsers/gs1_datamatrix_parser.dart';
import '../../core/database/database_service.dart';
import '../../core/services/barcode_hardware_listener.dart';
import '../../models/medicine.dart';
import 'widgets/big_touch_button.dart';
import 'widgets/camera_scanner_modal.dart';

/// Écran Entrée en Stock (Réception d'échantillons délégués médicaux)
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

  bool _isNewMedicine = false;
  Medicine? _existingMedicine;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    BarcodeHardwareListener.instance.addListener(_onBarcodeScanned);

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

    final gtin = parsed.gtin ?? rawBarcode;
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

    // Rechercher si le GTIN est déjà mémorisé
    final found = await DatabaseService.instance.getMedicineByGtin(gtin);

    if (found != null) {
      // Produit connu
      _existingMedicine = found;
      _isNewMedicine = false;
      _nameController.text = found.commercialName;
      _dciController.text = found.dci;
      _dosageController.text = found.dosage;
      _formGaleniqueController.text = found.form;
      _classController.text = found.therapeuticClass;
      _labController.text = found.laboratory;

      // Si EAN-13 classique (pas de date GS1), focus automatique sur la date de péremption !
      if (parsed.requiresManualExpiry) {
        _expiryFocusNode.requestFocus();
      } else {
        _quantityFocusNode.requestFocus();
      }
    } else {
      // Produit inconnu -> ouverture fiche création rapide
      _existingMedicine = null;
      _isNewMedicine = true;
      _nameController.clear();
      _dciController.clear();
      _dosageController.clear();
      _formGaleniqueController.clear();
      _classController.clear();
      _labController.clear();

      if (parsed.requiresManualExpiry) {
        _expiryFocusNode.requestFocus();
      }
    }

    setState(() => _isLoading = false);
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
    if (!_formKey.currentState!.validate()) return;

    final expiryValidation = StrictDateValidator.validate(_expiryController.text);
    if (!expiryValidation.isValid) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(expiryValidation.errorMessage ?? 'Date invalide'),
          backgroundColor: AppColors.alertExpired,
        ),
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      final now = DateTime.now();
      final gtin = _cipController.text.trim();

      final medicine = _existingMedicine ??
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
              'Entrée enregistrée : +$qty boîte(s) de ${medicine.commercialName} (Lot: $batchNo)',
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
                    // Bannière d'écoute de la douchette
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      decoration: BoxDecoration(
                        color: AppColors.primaryLight,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: AppColors.primaryAccent.withOpacity(0.3)),
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
                                  'Douchette USB active & prête',
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    color: AppColors.primaryDark,
                                    fontSize: 14,
                                  ),
                                ),
                                Text(
                                  'Scannez directement la boîte ou utilisez l\'icône caméra.',
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
                    const SizedBox(height: 20),

                    // Champ Code GTIN / CIP
                    TextFormField(
                      controller: _cipController,
                      decoration: InputDecoration(
                        labelText: 'Code GTIN / CIP *',
                        prefixIcon: const Icon(Icons.qr_code_2_rounded, color: AppColors.primaryBlue),
                        suffixIcon: IconButton(
                          icon: const Icon(Icons.search_rounded),
                          onPressed: () => _processBarcode(_cipController.text),
                        ),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                        filled: true,
                        fillColor: Colors.white,
                      ),
                      validator: (v) => (v == null || v.trim().isEmpty) ? 'Le GTIN / CIP est obligatoire' : null,
                    ),
                    const SizedBox(height: 16),

                    // État de reconnaissance du produit
                    if (_cipController.text.isNotEmpty)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                        decoration: BoxDecoration(
                          color: _isNewMedicine ? AppColors.alertWarningLight : AppColors.alertValidLight,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              _isNewMedicine ? Icons.add_circle_outline_rounded : Icons.check_circle_rounded,
                              size: 18,
                              color: _isNewMedicine ? AppColors.alertWarning : AppColors.alertValid,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              _isNewMedicine
                                  ? 'Nouveau médicament : création rapide requise'
                                  : 'Médicament mémorisé identifié',
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.bold,
                                color: _isNewMedicine ? AppColors.alertWarning : AppColors.alertValid,
                              ),
                            ),
                          ],
                        ),
                      ),
                    const SizedBox(height: 16),

                    // Carte d'identification du médicament
                    Card(
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      elevation: 1.5,
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Informations du Médicament',
                              style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.bold,
                                color: AppColors.slateDark,
                              ),
                            ),
                            const Divider(height: 24),
                            TextFormField(
                              controller: _nameController,
                              decoration: const InputDecoration(
                                labelText: 'Nom commercial * (ex: Doliprane)',
                                prefixIcon: Icon(Icons.medication_rounded),
                              ),
                              validator: (v) => (v == null || v.trim().isEmpty) ? 'Le nom commercial est requis' : null,
                            ),
                            const SizedBox(height: 12),
                            Row(
                              children: [
                                Expanded(
                                  child: TextFormField(
                                    controller: _dciController,
                                    decoration: const InputDecoration(
                                      labelText: 'DCI * (ex: Paracétamol)',
                                    ),
                                    validator: (v) => (v == null || v.trim().isEmpty) ? 'La DCI est requise' : null,
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: TextFormField(
                                    controller: _dosageController,
                                    decoration: const InputDecoration(
                                      labelText: 'Dosage (ex: 1000 mg)',
                                    ),
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
                                    decoration: const InputDecoration(
                                      labelText: 'Forme (ex: Comprimé)',
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: TextFormField(
                                    controller: _classController,
                                    decoration: const InputDecoration(
                                      labelText: 'Classe thérapeutique',
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            TextFormField(
                              controller: _labController,
                              decoration: const InputDecoration(
                                labelText: 'Laboratoire fabricant (ex: Sanofi)',
                                prefixIcon: Icon(Icons.business_rounded),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Carte du lot et date de péremption
                    Card(
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      elevation: 1.5,
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Lot & Péremption (Extraction DataMatrix / Saisie)',
                              style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.bold,
                                color: AppColors.slateDark,
                              ),
                            ),
                            const Divider(height: 24),
                            Row(
                              children: [
                                Expanded(
                                  child: TextFormField(
                                    controller: _batchController,
                                    decoration: const InputDecoration(
                                      labelText: 'N° de Lot *',
                                      prefixIcon: Icon(Icons.tag_rounded),
                                    ),
                                    validator: (v) => (v == null || v.trim().isEmpty) ? 'Le numéro de lot est requis' : null,
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
                                      hintText: '15/06/2026',
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
                                labelText: 'N° de Série unitaire (Optionnel / GS1 AI 21)',
                                prefixIcon: Icon(Icons.fingerprint_rounded),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Sélecteur de quantité tactile
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
                            // Boutons d'ajout rapide par lot
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
                    const SizedBox(height: 28),

                    // Gros bouton tactile de validation
                    BigTouchButton(
                      label: 'Valider l\'Entrée en Stock',
                      subtitle: 'Incrémente le stock et enregistre la traçabilité',
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
