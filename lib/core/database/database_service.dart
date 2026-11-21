import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../../models/medicine.dart';
import '../../models/medicine_batch.dart';
import '../../models/stock_movement.dart';
import '../../models/stock_alert_level.dart';
import '../services/auto_backup_service.dart';

/// Service de stockage local 100% rapide, autonome et universel
/// Compatible Web (PWA / localStorage), Windows, macOS et Mobile
class DatabaseService {
  static final DatabaseService instance = DatabaseService._internal();
  DatabaseService._internal();

  // Version 3 garantie 100% propre sans stock fictif pour cabinet médical
  static const String _prefKeyMedicines = 'docpocket_medocs_medicines_v3';
  static const String _prefKeyMovements = 'docpocket_medocs_movements_v3';
  static const String _prefKeyPurgeFlag = 'docpocket_has_purged_initial_stock_v3';

  final Map<String, Medicine> _medicines = {};
  final List<StockMovement> _movements = [];
  bool _initialized = false;

  Future<void> init() async {
    if (_initialized) return;

    final prefs = await SharedPreferences.getInstance();

    // Nettoyer définitivement toutes les anciennes clés de test / stocks fictifs
    final hasPurged = prefs.getBool(_prefKeyPurgeFlag) ?? false;
    if (!hasPurged) {
      const oldKeys = [
        'docpocket_medicines',
        'docpocket_movements',
        'docpocket_medicines_v1',
        'docpocket_movements_v1',
        'docpocket_medocs_medicines',
        'docpocket_medocs_movements',
        'docpocket_medocs_medicines_v1',
        'docpocket_medocs_movements_v1',
        'docpocket_medocs_medicines_v2',
        'docpocket_medocs_movements_v2',
      ];
      for (final k in oldKeys) {
        await prefs.remove(k);
      }
      await prefs.remove(_prefKeyMedicines);
      await prefs.remove(_prefKeyMovements);
      await prefs.setBool(_prefKeyPurgeFlag, true);
    }

    final savedMeds = prefs.getString(_prefKeyMedicines);
    final savedMoves = prefs.getString(_prefKeyMovements);

    _medicines.clear();
    if (savedMeds != null && savedMeds.isNotEmpty) {
      try {
        final list = json.decode(savedMeds) as List<dynamic>;
        for (final item in list) {
          final map = item as Map<String, dynamic>;
          final batchesJson = map['batches'] as List<dynamic>? ?? [];
          final batches = batchesJson.map((b) => MedicineBatch.fromMap(b as Map<String, dynamic>)).toList();
          final med = Medicine.fromMap(map, batches);
          _medicines[med.cipGtin] = med;
        }
      } catch (_) {
        _medicines.clear();
      }
    }

    _movements.clear();
    if (savedMoves != null && savedMoves.isNotEmpty) {
      try {
        final list = json.decode(savedMoves) as List<dynamic>;
        for (final item in list) {
          _movements.add(StockMovement.fromMap(item as Map<String, dynamic>));
        }
      } catch (_) {
        _movements.clear();
      }
    }

    _initialized = true;
  }

  Future<void> _persist() async {
    final prefs = await SharedPreferences.getInstance();

    final medsJson = _medicines.values
        .map((m) => {
              ...m.toMap(),
              'batches': m.batches.map((b) => b.toMap()).toList(),
            })
        .toList();
    await prefs.setString(_prefKeyMedicines, json.encode(medsJson));

    final movesJson = _movements.map((mov) => mov.toMap()).toList();
    await prefs.setString(_prefKeyMovements, json.encode(movesJson));
  }

  /// Réinitialise l'ensemble des stocks et mouvements pour repartir à zéro
  Future<void> clearAllStock() async {
    _medicines.clear();
    _movements.clear();
    await _persist();
    await AutoBackupService.instance.triggerAutoBackup();
  }

  // --------------------------------------------------------------------------
  // LECTURE & RECHERCHE
  // --------------------------------------------------------------------------
  Future<List<Medicine>> getAllMedicines({
    String? searchQuery,
    StockAlertLevel? alertFilter,
  }) async {
    await init();

    var list = _medicines.values.toList();
    list.sort((a, b) => a.commercialName.compareTo(b.commercialName));

    if (searchQuery != null && searchQuery.trim().isNotEmpty) {
      final q = searchQuery.toLowerCase().trim();
      list = list.where((m) {
        final matchName = m.commercialName.toLowerCase().contains(q);
        final matchDci = m.dci.toLowerCase().contains(q);
        final matchClass = m.therapeuticClass.toLowerCase().contains(q);
        final matchLab = m.laboratory.toLowerCase().contains(q);
        final matchGtin = m.cipGtin.toLowerCase().contains(q);
        final matchBatch = m.batches.any((b) => b.batchNumber.toLowerCase().contains(q));
        return matchName || matchDci || matchClass || matchLab || matchGtin || matchBatch;
      }).toList();
    }

    if (alertFilter != null) {
      list = list.where((m) => m.overallAlertLevel == alertFilter).toList();
    }

    return list;
  }

  Future<Medicine?> getMedicineByGtin(String gtin) async {
    await init();
    final cleanGtin = gtin.trim();
    return _medicines[cleanGtin];
  }

  // --------------------------------------------------------------------------
  // ÉCRITURE
  // --------------------------------------------------------------------------
  Future<void> saveMedicine(Medicine medicine) async {
    await init();
    _medicines[medicine.cipGtin] = medicine;
    await _persist();
  }

  Future<void> saveBatch(MedicineBatch batch) async {
    await init();
    for (final med in _medicines.values) {
      if (med.id == batch.medicineId) {
        final existingIdx = med.batches.indexWhere((b) => b.id == batch.id);
        if (existingIdx >= 0) {
          med.batches[existingIdx] = batch;
        } else {
          med.batches.add(batch);
        }
        break;
      }
    }
    await _persist();
  }

  // --------------------------------------------------------------------------
  // FLUX ENTRÉE EN STOCK
  // --------------------------------------------------------------------------
  Future<void> recordStockEntry({
    required Medicine medicine,
    required String batchNumber,
    required DateTime expiryDate,
    required int quantity,
    String? serialNumber,
    String? note,
  }) async {
    await init();
    final now = DateTime.now();

    // 1. Sauvegarder la fiche médicament
    await saveMedicine(medicine);

    // 2. Traiter le lot
    MedicineBatch? targetBatch;
    for (final b in medicine.batches) {
      if (b.batchNumber.toLowerCase().trim() == batchNumber.toLowerCase().trim()) {
        targetBatch = b;
        break;
      }
    }

    if (targetBatch != null) {
      final updated = targetBatch.copyWith(
        quantity: targetBatch.quantity + quantity,
        initialQuantity: targetBatch.initialQuantity + quantity,
      );
      await saveBatch(updated);
    } else {
      final newBatch = MedicineBatch(
        id: 'batch_${DateTime.now().millisecondsSinceEpoch}',
        medicineId: medicine.id,
        batchNumber: batchNumber,
        expiryDate: expiryDate,
        quantity: quantity,
        initialQuantity: quantity,
        receivedDate: now,
        serialNumber: serialNumber,
      );
      await saveBatch(newBatch);
    }

    // 3. Mouvement de traçabilité
    final movement = StockMovement(
      id: 'mov_${DateTime.now().millisecondsSinceEpoch}',
      medicineId: medicine.id,
      batchId: targetBatch?.id,
      type: MovementType.entry,
      quantity: quantity,
      movementDate: now,
      medicineNameSnapshot: medicine.commercialName,
      batchNumberSnapshot: batchNumber,
      note: note ?? 'Réception délégué (${medicine.laboratory})',
    );
    await recordMovement(movement);
    await AutoBackupService.instance.triggerAutoBackup();
  }

  // --------------------------------------------------------------------------
  // FLUX SORTIE DU STOCK (FEFO)
  // --------------------------------------------------------------------------
  Future<Map<MedicineBatch, int>> recordStockExitFefo({
    required Medicine medicine,
    required int quantityToDeduct,
    String? patientIdentifier,
    String? note,
  }) async {
    await init();
    final now = DateTime.now();

    final deductions = medicine.deductStockFefo(quantityToDeduct);

    for (final entry in deductions.entries) {
      final batch = entry.key;
      final deductedQty = entry.value;

      await saveBatch(batch);

      final movement = StockMovement(
        id: 'mov_${DateTime.now().millisecondsSinceEpoch}_${batch.id}',
        medicineId: medicine.id,
        batchId: batch.id,
        type: MovementType.exit,
        quantity: deductedQty,
        movementDate: now,
        patientIdentifier: patientIdentifier,
        medicineNameSnapshot: medicine.commercialName,
        batchNumberSnapshot: batch.batchNumber,
        note: note ?? 'Remise patient',
      );
      await recordMovement(movement);
    }

    await AutoBackupService.instance.triggerAutoBackup();
    return deductions;
  }

  // --------------------------------------------------------------------------
  // TRAÇABILITÉ
  // --------------------------------------------------------------------------
  Future<void> recordMovement(StockMovement movement) async {
    await init();
    _movements.insert(0, movement);
    await _persist();
  }

  Future<List<StockMovement>> getMovements({String? medicineId}) async {
    await init();
    if (medicineId != null) {
      return _movements.where((m) => m.medicineId == medicineId).toList();
    }
    return _movements;
  }

  // --------------------------------------------------------------------------
  // STATISTIQUES DU TABLEAU DE BORD
  // --------------------------------------------------------------------------
  Future<Map<String, int>> getDashboardStats() async {
    final all = await getAllMedicines();

    int totalBoxes = 0;
    int countExpired = 0;
    int countWarning = 0;
    int countValid = 0;

    for (final m in all) {
      totalBoxes += m.totalStock;
      for (final b in m.batches) {
        if (b.quantity > 0) {
          switch (b.alertLevel) {
            case StockAlertLevel.expired:
              countExpired += b.quantity;
              break;
            case StockAlertLevel.warning:
              countWarning += b.quantity;
              break;
            case StockAlertLevel.valid:
              countValid += b.quantity;
              break;
          }
        }
      }
    }

    return {
      'totalMedicines': all.length,
      'totalBoxes': totalBoxes,
      'countExpired': countExpired,
      'countWarning': countWarning,
      'countValid': countValid,
    };
  }

  // --------------------------------------------------------------------------
  // EXPORT / IMPORT JSON & CSV
  // --------------------------------------------------------------------------
  Future<String> exportBackupJson() async {
    final medicines = await getAllMedicines();
    final movements = await getMovements();

    final exportData = {
      'version': '2.0',
      'appName': 'DocPocket Medocs',
      'exportDate': DateTime.now().toIso8601String(),
      'medicines': medicines
          .map((m) => {
                ...m.toMap(),
                'batches': m.batches.map((b) => b.toMap()).toList(),
              })
          .toList(),
      'movements': movements.map((mov) => mov.toMap()).toList(),
    };

    return const JsonEncoder.withIndent('  ').convert(exportData);
  }

  Future<void> importBackupJson(String jsonString) async {
    final decoded = json.decode(jsonString) as Map<String, dynamic>;
    final medsJson = decoded['medicines'] as List<dynamic>? ?? [];

    for (final item in medsJson) {
      final map = item as Map<String, dynamic>;
      final batchesJson = map['batches'] as List<dynamic>? ?? [];
      final batches = batchesJson.map((b) => MedicineBatch.fromMap(b as Map<String, dynamic>)).toList();
      final med = Medicine.fromMap(map, batches);
      _medicines[med.cipGtin] = med;
    }

    final movesJson = decoded['movements'] as List<dynamic>? ?? [];
    for (final item in movesJson) {
      _movements.add(StockMovement.fromMap(item as Map<String, dynamic>));
    }

    await _persist();
    await AutoBackupService.instance.triggerAutoBackup();
  }

  Future<String> exportInventoryCsv() async {
    final medicines = await getAllMedicines();
    final buffer = StringBuffer();

    buffer.writeln(
      'CIP/GTIN,Nom commercial,DCI,Dosage,Forme,Classe thérapeutique,Laboratoire,N° Lot,Date de péremption,Quantité en stock,Alerte',
    );

    for (final m in medicines) {
      if (m.batches.isEmpty) {
        buffer.writeln(
          '"${m.cipGtin}","${m.commercialName}","${m.dci}","${m.dosage}","${m.form}","${m.therapeuticClass}","${m.laboratory}","-","-",0,"Vide"',
        );
      } else {
        for (final b in m.batches) {
          buffer.writeln(
            '"${m.cipGtin}","${m.commercialName}","${m.dci}","${m.dosage}","${m.form}","${m.therapeuticClass}","${m.laboratory}","${b.batchNumber}","${b.expiryDateFormatted}",${b.quantity},"${b.alertLevel.label}"',
          );
        }
      }
    }

    return buffer.toString();
  }
}
