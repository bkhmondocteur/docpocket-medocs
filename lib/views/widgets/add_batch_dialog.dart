import 'package:flutter/material.dart';
import '../../core/constants/app_colors.dart';
import '../../core/database/database_service.dart';
import '../../core/formatters/strict_date_formatter.dart';
import '../../models/medicine.dart';
import 'camera_scanner_modal.dart';

/// Boîte de dialogue pour ajouter un nouveau lot à un médicament existant
/// (autre date de péremption et/ou autre numéro de lot)
class AddBatchDialog extends StatefulWidget {
  final Medicine medicine;

  const AddBatchDialog({super.key, required this.medicine});

  static Future<bool?> show(BuildContext context, Medicine medicine) {
    return showDialog<bool>(
      context: context,
      builder: (_) => AddBatchDialog(medicine: medicine),
    );
  }

  @override
  State<AddBatchDialog> createState() => _AddBatchDialogState();
}

class _AddBatchDialogState extends State<AddBatchDialog> {
  final _formKey = GlobalKey<FormState>();
  final _batchController = TextEditingController();
  final _expiryController = TextEditingController();
  int _quantity = 1;
  bool _isLoading = false;

  @override
  void dispose() {
    _batchController.dispose();
    _expiryController.dispose();
    super.dispose();
  }

  Future<void> _scanBarcode() async {
    final code = await CameraScannerModal.show(context);
    if (code != null && code.isNotEmpty && mounted) {
      setState(() {
        _batchController.text = code;
      });
    }
  }

  Future<void> _submit() async {
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
      final batchNo = _batchController.text.trim().isEmpty ? 'SANS-LOT' : _batchController.text.trim();
      final expiry = expiryValidation.parsedDate!;

      await DatabaseService.instance.recordStockEntry(
        medicine: widget.medicine,
        batchNumber: batchNo,
        expiryDate: expiry,
        quantity: _quantity,
        note: 'Ajout nouveau lot ($batchNo)',
      );

      if (mounted) {
        Navigator.of(context).pop(true);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Lot $batchNo (${_expiryController.text}) ajouté : +$_quantity boîte(s)',
            ),
            backgroundColor: AppColors.alertValid,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erreur lors de l\'enregistrement : $e'),
            backgroundColor: AppColors.alertExpired,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final med = widget.medicine;

    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 20),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Form(
            key: _formKey,
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
                        color: AppColors.primaryLight,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.add_box_rounded, color: AppColors.primaryBlue, size: 26),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            med.commercialName,
                            style: const TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.bold,
                              color: AppColors.slateDark,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'Nouveau lot • ${med.form} ${med.dosage.isNotEmpty ? "• ${med.dosage}" : ""}',
                            style: const TextStyle(fontSize: 12, color: AppColors.slateMedium),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 18),

                // Champ Numéro de Lot
                TextFormField(
                  controller: _batchController,
                  decoration: InputDecoration(
                    labelText: 'Numéro de lot',
                    hintText: 'Ex: LOT-2026-X',
                    prefixIcon: const Icon(Icons.tag_rounded, color: AppColors.primaryBlue),
                    suffixIcon: IconButton(
                      icon: const Icon(Icons.qr_code_scanner_rounded, color: AppColors.primaryBlue),
                      tooltip: 'Scanner le code',
                      onPressed: _scanBarcode,
                    ),
                    filled: true,
                    fillColor: Colors.grey.shade50,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                ),
                const SizedBox(height: 14),

                // Champ Date de péremption (MM/AAAA)
                TextFormField(
                  controller: _expiryController,
                  keyboardType: TextInputType.number,
                  inputFormatters: [StrictDateInputFormatter()],
                  decoration: InputDecoration(
                    labelText: 'Péremption (MM/AAAA) *',
                    hintText: 'Ex: 11/2028',
                    prefixIcon: const Icon(Icons.calendar_month_rounded, color: AppColors.primaryBlue),
                    filled: true,
                    fillColor: Colors.grey.shade50,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  validator: (value) {
                    final res = StrictDateValidator.validate(value);
                    return res.isValid ? null : res.errorMessage;
                  },
                ),
                const SizedBox(height: 16),

                // Sélecteur de Quantité
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'Nombre de boîtes :',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: AppColors.slateDark),
                    ),
                    Row(
                      children: [
                        IconButton(
                          icon: const Icon(Icons.remove_circle_outline_rounded, color: AppColors.slateMedium),
                          onPressed: _quantity > 1 ? () => setState(() => _quantity--) : null,
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                          decoration: BoxDecoration(
                            color: AppColors.primaryLight,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: AppColors.primaryAccent.withValues(alpha: 0.3)),
                          ),
                          child: Text(
                            '$_quantity',
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: AppColors.primaryDark,
                            ),
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.add_circle_outline_rounded, color: AppColors.primaryBlue),
                          onPressed: () => setState(() => _quantity++),
                        ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 8),

                // Raccourcis +1, +2, +5, +10
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    _quickQtyChip('+1 boîte', 1),
                    const SizedBox(width: 8),
                    _quickQtyChip('+2 boîtes', 2),
                    const SizedBox(width: 8),
                    _quickQtyChip('+5 boîtes', 5),
                    const SizedBox(width: 8),
                    _quickQtyChip('+10 boîtes', 10),
                  ],
                ),
                const SizedBox(height: 22),

                // Boutons d'action
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: _isLoading ? null : () => Navigator.of(context).pop(false),
                        child: const Text('Annuler'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      flex: 2,
                      child: ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.primaryBlue,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        onPressed: _isLoading ? null : _submit,
                        icon: _isLoading
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                              )
                            : const Icon(Icons.check_circle_rounded, size: 20),
                        label: Text(
                          _isLoading ? 'Enregistrement...' : 'Valider (+$_quantity)',
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _quickQtyChip(String label, int val) {
    return InkWell(
      onTap: () => setState(() => _quantity = val),
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: _quantity == val ? AppColors.primaryBlue : Colors.grey.shade100,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: _quantity == val ? AppColors.primaryBlue : Colors.grey.shade300,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.bold,
            color: _quantity == val ? Colors.white : AppColors.slateDark,
          ),
        ),
      ),
    );
  }
}
