import 'package:flutter_test/flutter_test.dart';
import 'package:docpocket_medocs/models/medicine.dart';
import 'package:docpocket_medocs/models/medicine_batch.dart';
import 'package:docpocket_medocs/core/services/expiry_notification_service.dart';

void main() {
  test('Calcul et catégorisation des alertes de péremption avec stock > 0', () {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    // Lot 1 : Périmé depuis 10 jours, quantité = 3 -> Doit être classé dans expired
    final batchExpired = MedicineBatch(
      id: 'b1',
      medicineId: 'med1',
      batchNumber: 'LOT_EXP',
      expiryDate: today.subtract(const Duration(days: 10)),
      quantity: 3,
      initialQuantity: 5,
      receivedDate: today.subtract(const Duration(days: 60)),
    );

    // Lot 2 : Périme dans 15 jours (< 1 mois), quantité = 2 -> Doit être classé dans within1Month
    final batch1Month = MedicineBatch(
      id: 'b2',
      medicineId: 'med1',
      batchNumber: 'LOT_1M',
      expiryDate: today.add(const Duration(days: 15)),
      quantity: 2,
      initialQuantity: 2,
      receivedDate: today.subtract(const Duration(days: 30)),
    );

    // Lot 3 : Périme dans 60 jours (< 3 mois), quantité = 5 -> Doit être classé dans within3Months
    final batch3Months = MedicineBatch(
      id: 'b3',
      medicineId: 'med2',
      batchNumber: 'LOT_3M',
      expiryDate: today.add(const Duration(days: 60)),
      quantity: 5,
      initialQuantity: 10,
      receivedDate: today.subtract(const Duration(days: 10)),
    );

    // Lot 4 : Périmé depuis 20 jours mais quantité = 0 -> DOIT ÊTRE STRICTEMENT IGNORÉ
    final batchZeroStockExpired = MedicineBatch(
      id: 'b4',
      medicineId: 'med2',
      batchNumber: 'LOT_ZERO',
      expiryDate: today.subtract(const Duration(days: 20)),
      quantity: 0,
      initialQuantity: 4,
      receivedDate: today.subtract(const Duration(days: 90)),
    );

    // Lot 5 : Valide dans 180 jours (> 3 mois), quantité = 8 -> Aucune alerte
    final batchValid = MedicineBatch(
      id: 'b5',
      medicineId: 'med3',
      batchNumber: 'LOT_VALID',
      expiryDate: today.add(const Duration(days: 180)),
      quantity: 8,
      initialQuantity: 8,
      receivedDate: today,
    );

    final med1 = Medicine(
      id: 'med1',
      cipGtin: '3400930000001',
      commercialName: 'Doliprane 1000mg',
      dci: 'Paracétamol',
      dosage: '1000 mg',
      form: 'Comprimé',
      therapeuticClass: 'Antalgique',
      laboratory: 'Sanofi',
      createdAt: today,
      updatedAt: today,
      batches: [batchExpired, batch1Month],
    );

    final med2 = Medicine(
      id: 'med2',
      cipGtin: '3400930000002',
      commercialName: 'Augmentin 1g',
      dci: 'Amoxicilline',
      dosage: '1 g',
      form: 'Poudre',
      therapeuticClass: 'Antibiotique',
      laboratory: 'GSK',
      createdAt: today,
      updatedAt: today,
      batches: [batch3Months, batchZeroStockExpired],
    );

    final med3 = Medicine(
      id: 'med3',
      cipGtin: '3400930000003',
      commercialName: 'Inexium 40mg',
      dci: 'Esoméprazole',
      dosage: '40 mg',
      form: 'Gélule',
      therapeuticClass: 'Antiulcéreux',
      laboratory: 'AstraZeneca',
      createdAt: today,
      updatedAt: today,
      batches: [batchValid],
    );

    final summary = ExpiryNotificationService.instance.computeSummary([med1, med2, med3]);

    expect(summary.hasAlerts, isTrue);
    expect(summary.totalCount, equals(3)); // 1 expiré, 1 dans <1 mois, 1 dans <3 mois (le lot à 0 est exclu)
    expect(summary.expired.length, equals(1));
    expect(summary.expired.first.batch.batchNumber, equals('LOT_EXP'));
    expect(summary.totalBoxesExpired, equals(3));

    expect(summary.within1Month.length, equals(1));
    expect(summary.within1Month.first.batch.batchNumber, equals('LOT_1M'));
    expect(summary.totalBoxes1Month, equals(2));

    expect(summary.within3Months.length, equals(1));
    expect(summary.within3Months.first.batch.batchNumber, equals('LOT_3M'));
    expect(summary.totalBoxes3Months, equals(5));

    expect(summary.totalBoxesAlerted, equals(10));
  });
}
