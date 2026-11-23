import 'package:flutter/material.dart';
import '../../core/constants/app_colors.dart';
import '../../core/database/database_service.dart';
import '../../models/medicine.dart';
import '../../models/medicine_batch.dart';

/// Boîte de dialogue pour ajouter rapidement des boîtes avec les mêmes caractéristiques
/// sans avoir à rescanner ou ressaisir les informations du médicament
class AddBoxesDialog extends StatefulWidget {
  final Medicine medicine;
  final MedicineBatch? targetBatch;

  const AddBoxesDialog({super.key, required this.medicine, this.targetBatch});

  static Future<bool?> show(
    BuildContext context, {
    required Medicine medicine,
    MedicineBatch? targetBatch,
  }) {
    return showDialog<bool>(
      context: context,
      builder: (_) => AddBoxesDialog(medicine: medicine, targetBatch: targetBatch),
    );
  }

  @override
  State<AddBoxesDialog> createState() => _AddBoxesDialogState();
}

class _AddBoxesDialogState extends State<AddBoxesDialog> {
  late MedicineBatch? _selectedBatch;
  int _additionalQuantity = 1;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    if (widget.targetBatch != null) {
      _selectedBatch = widget.targetBatch;
    } else if (widget.medicine.batches.isNotEmpty) {
      // Sélectionner par défaut le lot le plus récent ou actif
      _selectedBatch = widget.medicine.nextExpiringBatch ?? widget.medicine.batches.first;
    } else {
      _selectedBatch = null;
    }
  }

  Future<void> _submit() async {
    if (_selectedBatch == null) return;

    setState(() => _isLoading = true);

    try {
      await DatabaseService.instance.addBoxesToBatch(
        medicine: widget.medicine,
        batch: _selectedBatch!,
        additionalQuantity: _additionalQuantity,
      );

      if (mounted) {
        Navigator.of(context).pop(true);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '+$_additionalQuantity boîte(s) ajoutée(s) à ${widget.medicine.commercialName} (Lot: ${_selectedBatch!.batchNumber})',
            ),
            backgroundColor: AppColors.alertValid,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erreur : $e'),
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
    final batches = med.batches;

    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 20),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 460),
        child: Padding(
          padding: const EdgeInsets.all(18),
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
                      color: Colors.teal.shade50,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(Icons.add_shopping_cart_rounded, color: Colors.teal.shade800, size: 26),
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
                          'Ajouter des boîtes identiques • ${med.form} ${med.dosage.isNotEmpty ? "• ${med.dosage}" : ""}',
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

              // Sélection du lot si plusieurs lots disponibles
              if (batches.length > 1) ...[
                const Text(
                  'Sélectionnez le lot concerné :',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: AppColors.slateDark),
                ),
                const SizedBox(height: 6),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade50,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.grey.shade300),
                  ),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<MedicineBatch>(
                      isExpanded: true,
                      value: _selectedBatch,
                      items: batches.map((b) {
                        return DropdownMenuItem<MedicineBatch>(
                          value: b,
                          child: Text(
                            'Lot: ${b.batchNumber} (Exp: ${b.expiryDateFormatted}) • En stock : ${b.quantity}',
                            style: const TextStyle(fontSize: 13),
                          ),
                        );
                      }).toList(),
                      onChanged: (newBatch) {
                        if (newBatch != null) setState(() => _selectedBatch = newBatch);
                      },
                    ),
                  ),
                ),
                const SizedBox(height: 16),
              ] else if (_selectedBatch != null) ...[
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.blue.shade50,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.blue.shade200, width: 0.8),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.inventory_2_rounded, color: AppColors.primaryBlue, size: 20),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Lot ciblé : ${_selectedBatch!.batchNumber}',
                              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                            ),
                            Text(
                              'Péremption : ${_selectedBatch!.expiryDateFormatted} • Stock actuel : ${_selectedBatch!.quantity} boîte(s)',
                              style: TextStyle(fontSize: 12, color: Colors.blue.shade900),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
              ],

              // Nombre de boîtes à ajouter
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Boîtes à ajouter :',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: AppColors.slateDark),
                  ),
                  Row(
                    children: [
                      IconButton(
                        icon: const Icon(Icons.remove_circle_outline_rounded, color: AppColors.slateMedium),
                        onPressed: _additionalQuantity > 1 ? () => setState(() => _additionalQuantity--) : null,
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                        decoration: BoxDecoration(
                          color: AppColors.primaryLight,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: AppColors.primaryAccent.withValues(alpha: 0.3)),
                        ),
                        child: Text(
                          '+$_additionalQuantity',
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: AppColors.primaryDark,
                          ),
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.add_circle_outline_rounded, color: AppColors.primaryBlue),
                        onPressed: () => setState(() => _additionalQuantity++),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 8),

              // Raccourcis +1, +2, +5, +10
              Wrap(
                alignment: WrapAlignment.center,
                spacing: 8,
                runSpacing: 6,
                children: [
                  _quickQtyChip('+1 boîte', 1),
                  _quickQtyChip('+2 boîtes', 2),
                  _quickQtyChip('+5 boîtes', 5),
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
                        backgroundColor: Colors.teal.shade700,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      onPressed: _isLoading || _selectedBatch == null ? null : _submit,
                      icon: _isLoading
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                            )
                          : const Icon(Icons.check_circle_rounded, size: 20),
                      label: Text(
                        _isLoading ? 'Mise à jour...' : 'Ajouter (+$_additionalQuantity)',
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
    );
  }

  Widget _quickQtyChip(String label, int val) {
    return InkWell(
      onTap: () => setState(() => _additionalQuantity = val),
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: _additionalQuantity == val ? Colors.teal.shade700 : Colors.grey.shade100,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: _additionalQuantity == val ? Colors.teal.shade700 : Colors.grey.shade300,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.bold,
            color: _additionalQuantity == val ? Colors.white : AppColors.slateDark,
          ),
        ),
      ),
    );
  }
}
