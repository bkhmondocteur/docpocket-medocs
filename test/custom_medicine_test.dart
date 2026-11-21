import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:docpocket_medocs/core/services/medicines_catalog_service.dart';
import 'package:docpocket_medocs/core/database/database_service.dart';
import 'package:docpocket_medocs/models/medicine.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await DatabaseService.instance.init();
    await DatabaseService.instance.clearAllStock();
  });

  test('Ajout d\'un médicament non répertorié avec les 5 champs et persistance catalogue', () async {
    final catalogService = MedicinesCatalogService.instance;

    // 1. Ajouter un médicament avec les 5 caractéristiques exigées
    final customMed = await catalogService.addCustomMedicine(
      commercialName: 'Esocare 20',
      dci: 'Esoméprazole',
      form: 'Gélule',
      packagingOrVolume: 'Boîte de 7',
      laboratory: 'SIMED',
    );

    expect(customMed.isCustom, isTrue);
    expect(customMed.cleanCommercialName, equals('Esocare 20'));
    expect(customMed.dci, equals('Esoméprazole'));
    expect(customMed.form, equals('Gélule'));
    expect(customMed.packaging, equals('Boîte de 7'));
    expect(customMed.laboratory, equals('SIMED'));

    // 2. Recherche par nom commercial
    final searchByName = await catalogService.search('esocare');
    expect(searchByName.isNotEmpty, isTrue);
    expect(searchByName.first.cleanCommercialName, equals('Esocare 20'));

    // 3. Recherche par DCI
    final searchByDci = await catalogService.search('esoméprazole');
    expect(searchByDci.isNotEmpty, isTrue);
    expect(searchByDci.first.cleanCommercialName, equals('Esocare 20'));

    // 4. Recherche par Laboratoire
    final searchByLab = await catalogService.search('simed');
    expect(searchByLab.isNotEmpty, isTrue);
    expect(searchByLab.first.cleanCommercialName, equals('Esocare 20'));

    // 5. Enregistrement en stock de ce médicament personnalisé
    final now = DateTime.now();
    final med = Medicine(
      id: 'med_custom_1',
      cipGtin: 'CODE_CUSTOM_123',
      commercialName: customMed.cleanCommercialName,
      dci: customMed.dci,
      dosage: customMed.packaging,
      form: customMed.form,
      therapeuticClass: customMed.therapeuticClass,
      laboratory: customMed.laboratory,
      createdAt: now,
      updatedAt: now,
    );

    await DatabaseService.instance.recordStockEntry(
      medicine: med,
      batchNumber: 'LOT-CUST-1',
      expiryDate: DateTime(2028, 11, 30),
      quantity: 3,
    );

    final allMeds = await DatabaseService.instance.getAllMedicines();
    expect(allMeds.length, equals(1));
    expect(allMeds.first.commercialName, equals('Esocare 20'));
    expect(allMeds.first.dci, equals('Esoméprazole'));
    expect(allMeds.first.form, equals('Gélule'));
    expect(allMeds.first.dosage, equals('Boîte de 7'));
    expect(allMeds.first.laboratory, equals('SIMED'));
    expect(allMeds.first.totalStock, equals(3));
  });
}
