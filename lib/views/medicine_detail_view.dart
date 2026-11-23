import 'package:flutter/material.dart';
import '../../core/constants/app_colors.dart';
import '../../models/medicine.dart';
import '../../models/stock_alert_level.dart';
import '../../models/stock_movement.dart';
import '../../core/database/database_service.dart';
import 'widgets/alert_badge.dart';
import 'widgets/add_batch_dialog.dart';
import 'widgets/add_boxes_dialog.dart';

/// Fiche détaillée du médicament avec historique des lots et des mouvements
class MedicineDetailView extends StatefulWidget {
  final Medicine medicine;

  const MedicineDetailView({super.key, required this.medicine});

  @override
  State<MedicineDetailView> createState() => _MedicineDetailViewState();
}

class _MedicineDetailViewState extends State<MedicineDetailView> {
  late Medicine _medicine;
  List<StockMovement> _movements = [];
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _medicine = widget.medicine;
    _loadHistory();
  }

  Future<void> _loadHistory() async {
    setState(() => _isLoading = true);
    final moves = await DatabaseService.instance.getMovements(medicineId: _medicine.id);
    final updatedMed = await DatabaseService.instance.getMedicineByGtin(_medicine.cipGtin);
    if (mounted) {
      setState(() {
        _movements = moves;
        if (updatedMed != null) _medicine = updatedMed;
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Text(_medicine.commercialName, style: const TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: AppColors.primaryBlue,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Carte Résumé Médicament
                  Card(
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    elevation: 2,
                    child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Expanded(
                                child: Text(
                                  '${_medicine.commercialName} ${_medicine.dosage}',
                                  style: const TextStyle(
                                    fontSize: 22,
                                    fontWeight: FontWeight.bold,
                                    color: AppColors.slateDark,
                                  ),
                                ),
                              ),
                              AlertBadge(level: _medicine.overallAlertLevel),
                            ],
                          ),
                          const SizedBox(height: 6),
                          Text(
                            'DCI : ${_medicine.dci}',
                            style: const TextStyle(
                              fontSize: 15,
                              color: AppColors.primaryBlue,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const Divider(height: 24),
                          _infoRow('Forme galénique', _medicine.form),
                          _infoRow('Classe thérapeutique', _medicine.therapeuticClass),
                          _infoRow('Laboratoire fabricant', _medicine.laboratory),
                          _infoRow('Code GTIN / CIP', _medicine.cipGtin),
                          const Divider(height: 24),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Text(
                                'Total en Stock :',
                                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                              ),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                                decoration: BoxDecoration(
                                  color: AppColors.primaryLight,
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Text(
                                  '${_medicine.totalStock} boîte(s)',
                                  style: const TextStyle(
                                    fontSize: 16,
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
                  const SizedBox(height: 20),

                  // Liste des Lots avec bouton d'ajout de lot
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'Lots & Péremptions',
                        style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.bold,
                          color: AppColors.slateDark,
                        ),
                      ),
                      ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.primaryBlue,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                          visualDensity: VisualDensity.compact,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        ),
                        onPressed: () async {
                          final res = await AddBatchDialog.show(context, _medicine);
                          if (res == true) _loadHistory();
                        },
                        icon: const Icon(Icons.add_rounded, size: 16),
                        label: const Text('Nouveau lot', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  if (_medicine.batches.isEmpty)
                    const Card(
                      child: Padding(
                        padding: EdgeInsets.all(16),
                        child: Text('Aucun lot enregistré pour ce médicament.'),
                      ),
                    )
                  else
                    ..._medicine.fefoOrderedBatches.map((batch) {
                      return Card(
                        margin: const EdgeInsets.only(bottom: 10),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                          child: Row(
                            children: [
                              CircleAvatar(
                                backgroundColor: batch.alertLevel.backgroundColor,
                                child: Icon(batch.alertLevel.icon, color: batch.alertLevel.color),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        Text(
                                          'Lot : ${batch.batchNumber}',
                                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                                        ),
                                        const SizedBox(width: 6),
                                        AlertBadge(level: batch.alertLevel, compact: true),
                                      ],
                                    ),
                                    const SizedBox(height: 3),
                                    Text(
                                      'Péremption : ${batch.expiryDateFormatted} '
                                      '(${batch.remainingDays > 0 ? "dans ${batch.remainingDays}j" : "PÉRIMÉ"})',
                                      style: TextStyle(fontSize: 12, color: batch.alertLevel.color),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 8),
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: [
                                  Text(
                                    '${batch.quantity} boîte(s)',
                                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                                  ),
                                  const SizedBox(height: 4),
                                  InkWell(
                                    onTap: () async {
                                      final res = await AddBoxesDialog.show(
                                        context,
                                        medicine: _medicine,
                                        targetBatch: batch,
                                      );
                                      if (res == true) _loadHistory();
                                    },
                                    borderRadius: BorderRadius.circular(6),
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                      decoration: BoxDecoration(
                                        color: Colors.teal.shade50,
                                        borderRadius: BorderRadius.circular(6),
                                        border: Border.all(color: Colors.teal.shade300, width: 0.8),
                                      ),
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Icon(Icons.add_circle_outline_rounded, size: 13, color: Colors.teal.shade800),
                                          const SizedBox(width: 3),
                                          Text(
                                            'Ajouter boîte',
                                            style: TextStyle(
                                              fontSize: 11,
                                              fontWeight: FontWeight.bold,
                                              color: Colors.teal.shade900,
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
                      );
                    }),
                  const SizedBox(height: 20),

                  // Historique des Mouvements
                  const Text(
                    'Historique de Traçabilité',
                    style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.bold,
                      color: AppColors.slateDark,
                    ),
                  ),
                  const SizedBox(height: 10),
                  if (_movements.isEmpty)
                    const Card(
                      child: Padding(
                        padding: EdgeInsets.all(16),
                        child: Text('Aucun mouvement enregistré pour le moment.'),
                      ),
                    )
                  else
                    ListView.builder(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: _movements.length,
                      itemBuilder: (context, idx) {
                        final mov = _movements[idx];
                        final isEntry = mov.type == MovementType.entry;

                        return Card(
                          margin: const EdgeInsets.only(bottom: 8),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          child: ListTile(
                            leading: CircleAvatar(
                              backgroundColor: isEntry ? AppColors.alertValidLight : AppColors.primaryLight,
                              child: Icon(
                                isEntry ? Icons.arrow_downward_rounded : Icons.arrow_upward_rounded,
                                color: isEntry ? AppColors.alertValid : AppColors.primaryDark,
                              ),
                            ),
                            title: Text(
                              '${mov.type.label} : ${mov.quantity} boîte(s)',
                              style: const TextStyle(fontWeight: FontWeight.bold),
                            ),
                            subtitle: Text(
                              'Date : ${mov.movementDateFormatted}'
                              '${mov.patientIdentifier != null ? " • Patient : ${mov.patientIdentifier}" : ""}'
                              '${mov.note != null ? " • ${mov.note}" : ""}',
                            ),
                          ),
                        );
                      },
                    ),
                ],
              ),
            ),
    );
  }

  Widget _infoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(color: AppColors.slateMedium, fontSize: 13.5)),
          const SizedBox(width: 12),
          Flexible(
            child: Text(
              value.isEmpty ? '-' : value,
              textAlign: TextAlign.end,
              style: const TextStyle(fontWeight: FontWeight.w600, color: AppColors.slateDark, fontSize: 13.5),
            ),
          ),
        ],
      ),
    );
  }
}
