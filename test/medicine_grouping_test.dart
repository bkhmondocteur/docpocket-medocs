import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:docpocket_medocs/core/database/database_service.dart';
import 'package:docpocket_medocs/models/medicine.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await DatabaseService.instance.init();
    await DatabaseService.instance.clearAllStock();
  });

  test('Regroupement automatique des médicaments identiques et gestion multi-lots', () async {
    final now = DateTime.now();

    final med1 = Medicine(
      id: 'med_esocare_1',
      cipGtin: 'GTIN_111',
      commercialName: 'Esocare 20',
      dci: 'Esoméprazole',
      dosage: 'Boîte de 7',
      form: 'Gélule',
      therapeuticClass: 'Gastro-entérologie',
      laboratory: 'SIMED',
      createdAt: now,
      updatedAt: now,
    );

    // 1. Première entrée : 1 boîte du lot LOT-A (Exp: 11/2028)
    await DatabaseService.instance.recordStockEntry(
      medicine: med1,
      batchNumber: 'LOT-A',
      expiryDate: DateTime(2028, 11, 30),
      quantity: 1,
    );

    var meds = await DatabaseService.instance.getAllMedicines();
    expect(meds.length, equals(1));
    expect(meds.first.commercialName, equals('Esocare 20'));
    expect(meds.first.totalStock, equals(1));
    expect(meds.first.batches.length, equals(1));

    // 2. Cas A : Même médicament, même caractéristiques, même lot (LOT-A) -> +2 boîtes
    final medSame = Medicine(
      id: 'med_esocare_temp',
      cipGtin: 'GTIN_TEMP',
      commercialName: 'Esocare 20',
      dci: '',
      dosage: 'Boîte de 7',
      form: 'Gélule',
      therapeuticClass: '',
      laboratory: '',
      createdAt: now,
      updatedAt: now,
    );

    await DatabaseService.instance.recordStockEntry(
      medicine: medSame,
      batchNumber: 'LOT-A',
      expiryDate: DateTime(2028, 11, 30),
      quantity: 2,
    );

    meds = await DatabaseService.instance.getAllMedicines();
    // Toujours UNE SEULE carte de médicament
    expect(meds.length, equals(1));
    // Le stock total passe à 3 (1 + 2)
    expect(meds.first.totalStock, equals(3));
    // Toujours 1 seul lot actif (LOT-A avec quantité 3)
    expect(meds.first.batches.length, equals(1));
    expect(meds.first.batches.first.quantity, equals(3));

    // 3. Cas B : Même médicament mais nouveau lot (LOT-B, Exp: 05/2029, 5 boîtes)
    await DatabaseService.instance.recordStockEntry(
      medicine: medSame,
      batchNumber: 'LOT-B',
      expiryDate: DateTime(2029, 5, 31),
      quantity: 5,
    );

    meds = await DatabaseService.instance.getAllMedicines();
    // Toujours UNE SEULE carte de médicament
    expect(meds.length, equals(1));
    // Le stock total passe à 8 (3 + 5)
    expect(meds.first.totalStock, equals(8));
    // Deux lots distincts sur la même carte
    expect(meds.first.batches.length, equals(2));

    // 4. Test de l'ajout rapide de boîtes directement à un lot existant
    final targetBatch = meds.first.batches.firstWhere((b) => b.batchNumber == 'LOT-A');
    await DatabaseService.instance.addBoxesToBatch(
      medicine: meds.first,
      batch: targetBatch,
      additionalQuantity: 4,
    );

    meds = await DatabaseService.instance.getAllMedicines();
    // Le stock total passe à 12 (8 + 4)
    expect(meds.first.totalStock, equals(12));
    final updatedLotA = meds.first.batches.firstWhere((b) => b.batchNumber == 'LOT-A');
    expect(updatedLotA.quantity, equals(7)); // 3 + 4
  });
}
