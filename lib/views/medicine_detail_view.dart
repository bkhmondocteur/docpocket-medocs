import 'package:flutter/material.dart';
import '../../core/constants/app_colors.dart';
import '../../models/medicine.dart';
import '../../models/stock_alert_level.dart';
import '../../models/stock_movement.dart';
import '../../core/database/database_service.dart';
import 'widgets/alert_badge.dart';

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

                  // Liste des Lots
                  const Text(
                    'Lots et Échéances de Péremption',
                    style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.bold,
                      color: AppColors.slateDark,
                    ),
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
                        child: ListTile(
                          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                          leading: CircleAvatar(
                            backgroundColor: batch.alertLevel.backgroundColor,
                            child: Icon(batch.alertLevel.icon, color: batch.alertLevel.color),
                          ),
                          title: Text(
                            'Lot : ${batch.batchNumber}',
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                          subtitle: Text(
                            'Péremption : ${batch.expiryDateFormatted} '
                            '(${batch.remainingDays > 0 ? "dans ${batch.remainingDays}j" : "PÉRIMÉ"})',
                          ),
                          trailing: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Text(
                                '${batch.quantity} boîte(s)',
                                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                              ),
                              AlertBadge(level: batch.alertLevel, compact: true),
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
        children: [
          Text(label, style: const TextStyle(color: AppColors.slateMedium, fontSize: 13.5)),
          Text(
            value.isEmpty ? '-' : value,
            style: const TextStyle(fontWeight: FontWeight.w600, color: AppColors.slateDark, fontSize: 13.5),
          ),
        ],
      ),
    );
  }
}
