import 'dart:convert';
import 'package:flutter/foundation.dart';
import '../../models/medicine.dart';
import '../../models/medicine_batch.dart';
import '../../models/stock_movement.dart';
import '../../models/stock_alert_level.dart';

// Imports conditionnels pour SQLite sur Desktop / Mobile
import 'package:sqflite/sqflite.dart' as sqflite;
import 'package:sqflite_common_ffi/sqflite_ffi.dart' as ffi;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'dart:io' as io;

/// Service de stockage local 100% rapide et autonome (SQLite sur Desktop/Mobile, In-Memory/Web sur PWA)
class DatabaseService {
  static final DatabaseService instance = DatabaseService._internal();
  DatabaseService._internal();

  sqflite.Database? _sqliteDb;

  // Cache mémoire utilisé sur Web (PWA) et comme cache synchronisé
  final Map<String, Medicine> _memoryMedicines = {};
  final List<StockMovement> _memoryMovements = [];
  bool _initialized = false;

  Future<void> init() async {
    if (_initialized) return;

    if (kIsWeb) {
      await _initWeb();
    } else {
      await _initSqlite();
    }
    _initialized = true;
  }

  // --------------------------------------------------------------------------
  // INITIALISATION SQLITE (Desktop Windows / macOS / Mobile Android)
  // --------------------------------------------------------------------------
  Future<void> _initSqlite() async {
    if (io.Platform.isWindows || io.Platform.isMacOS || io.Platform.isLinux) {
      ffi.sqfliteFfiInit();
      sqflite.databaseFactory = ffi.databaseFactoryFfi;
    }

    final docsDir = await getApplicationDocumentsDirectory();
    final dbPath = p.join(docsDir.path, 'docpocket_medocs.db');

    _sqliteDb = await sqflite.openDatabase(
      dbPath,
      version: 1,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE medicines (
            id TEXT PRIMARY KEY,
            cip_gtin TEXT UNIQUE NOT NULL,
            commercial_name TEXT NOT NULL,
            dci TEXT NOT NULL,
            dosage TEXT NOT NULL,
            form TEXT NOT NULL,
            therapeutic_class TEXT NOT NULL,
            laboratory TEXT NOT NULL,
            created_at TEXT NOT NULL,
            updated_at TEXT NOT NULL
          );
        ''');

        await db.execute('''
          CREATE TABLE batches (
            id TEXT PRIMARY KEY,
            medicine_id TEXT NOT NULL,
            batch_number TEXT NOT NULL,
            expiry_date TEXT NOT NULL,
            quantity INTEGER NOT NULL,
            initial_quantity INTEGER NOT NULL,
            received_date TEXT NOT NULL,
            serial_number TEXT,
            FOREIGN KEY (medicine_id) REFERENCES medicines(id) ON DELETE CASCADE
          );
        ''');

        await db.execute('''
          CREATE TABLE movements (
            id TEXT PRIMARY KEY,
            medicine_id TEXT NOT NULL,
            batch_id TEXT,
            type TEXT NOT NULL,
            quantity INTEGER NOT NULL,
            movement_date TEXT NOT NULL,
            patient_identifier TEXT,
            medicine_name_snapshot TEXT NOT NULL,
            batch_number_snapshot TEXT NOT NULL,
            note TEXT
          );
        ''');

        await db.execute('CREATE INDEX idx_medicines_gtin ON medicines(cip_gtin);');
        await db.execute('CREATE INDEX idx_batches_expiry ON batches(expiry_date);');
      },
    );

    // Initialiser les données de démonstration si la base est vide
    final count = sqflite.Sqflite.firstIntValue(
      await _sqliteDb!.rawQuery('SELECT COUNT(*) FROM medicines'),
    );
    if (count == 0) {
      await _seedInitialData();
    }
  }

  // --------------------------------------------------------------------------
  // INITIALISATION WEB / PWA
  // --------------------------------------------------------------------------
  Future<void> _initWeb() async {
    // Si vide, insérer des exemples médicaux réalistes
    if (_memoryMedicines.isEmpty) {
      await _seedInitialData();
    }
  }

  // --------------------------------------------------------------------------
  // JEU DE DONNÉES INITIAL (ÉCHANTILLONS MÉDICAUX TYPE)
  // --------------------------------------------------------------------------
  Future<void> _seedInitialData() async {
    final now = DateTime.now();

    final samples = [
      Medicine(
        id: 'med_1',
        cipGtin: '3400930000014',
        commercialName: 'Doliprane',
        dci: 'Paracétamol',
        dosage: '1000 mg',
        form: 'Comprimé',
        therapeuticClass: 'Antalgique / Antipyrétique',
        laboratory: 'Sanofi',
        createdAt: now,
        updatedAt: now,
        batches: [
          MedicineBatch(
            id: 'b_1a',
            medicineId: 'med_1',
            batchNumber: 'LOT-2024-A',
            expiryDate: now.subtract(const Duration(days: 10)), // Périmé
            quantity: 3,
            initialQuantity: 10,
            receivedDate: now.subtract(const Duration(days: 400)),
          ),
          MedicineBatch(
            id: 'b_1b',
            medicineId: 'med_1',
            batchNumber: 'LOT-2025-X',
            expiryDate: now.add(const Duration(days: 45)), // Périme < 90j
            quantity: 8,
            initialQuantity: 15,
            receivedDate: now.subtract(const Duration(days: 90)),
          ),
          MedicineBatch(
            id: 'b_1c',
            medicineId: 'med_1',
            batchNumber: 'LOT-2027-Z',
            expiryDate: now.add(const Duration(days: 450)), // Valide
            quantity: 20,
            initialQuantity: 20,
            receivedDate: now,
          ),
        ],
      ),
      Medicine(
        id: 'med_2',
        cipGtin: '3400930000021',
        commercialName: 'Augmentin',
        dci: 'Amoxicilline / Acide clavulanique',
        dosage: '1 g / 125 mg',
        form: 'Sachet poudre',
        therapeuticClass: 'Antibiotique (Pénicilline)',
        laboratory: 'GSK',
        createdAt: now,
        updatedAt: now,
        batches: [
          MedicineBatch(
            id: 'b_2a',
            medicineId: 'med_2',
            batchNumber: 'AUG-8874',
            expiryDate: now.add(const Duration(days: 60)), // Périme < 90j
            quantity: 6,
            initialQuantity: 12,
            receivedDate: now.subtract(const Duration(days: 30)),
          ),
          MedicineBatch(
            id: 'b_2b',
            medicineId: 'med_2',
            batchNumber: 'AUG-9912',
            expiryDate: now.add(const Duration(days: 380)), // Valide
            quantity: 15,
            initialQuantity: 15,
            receivedDate: now,
          ),
        ],
      ),
      Medicine(
        id: 'med_3',
        cipGtin: '3400930000038',
        commercialName: 'Kardegic',
        dci: 'Acétylsalicylate de DL-lysine',
        dosage: '75 mg',
        form: 'Sachet',
        therapeuticClass: 'Antiagrégant plaquettaire',
        laboratory: 'Sanofi',
        createdAt: now,
        updatedAt: now,
        batches: [
          MedicineBatch(
            id: 'b_3a',
            medicineId: 'med_3',
            batchNumber: 'KARD-451',
            expiryDate: now.add(const Duration(days: 240)), // Valide
            quantity: 12,
            initialQuantity: 12,
            receivedDate: now,
          ),
        ],
      ),
    ];

    for (final med in samples) {
      await saveMedicine(med);
      for (final b in med.batches) {
        await saveBatch(b);
      }
    }
  }

  // --------------------------------------------------------------------------
  // LECTURE & RECHERCHE DES MÉDICAMENTS
  // --------------------------------------------------------------------------
  Future<List<Medicine>> getAllMedicines({
    String? searchQuery,
    StockAlertLevel? alertFilter,
  }) async {
    await init();

    List<Medicine> list = [];

    if (!kIsWeb && _sqliteDb != null) {
      final rows = await _sqliteDb!.query(
        'medicines',
        orderBy: 'commercial_name ASC',
      );

      for (final r in rows) {
        final medId = r['id'].toString();
        final batchRows = await _sqliteDb!.query(
          'batches',
          where: 'medicine_id = ?',
          whereArgs: [medId],
          orderBy: 'expiry_date ASC',
        );
        final batches = batchRows.map((b) => MedicineBatch.fromMap(b)).toList();
        list.add(Medicine.fromMap(r, batches));
      }
    } else {
      list = _memoryMedicines.values.toList();
      list.sort((a, b) => a.commercialName.compareTo(b.commercialName));
    }

    // Filtrage par recherche
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

    // Filtrage par alerte sémantique
    if (alertFilter != null) {
      list = list.where((m) => m.overallAlertLevel == alertFilter).toList();
    }

    return list;
  }

  /// Recherche un médicament par son code CIP / GTIN
  Future<Medicine?> getMedicineByGtin(String gtin) async {
    await init();
    final cleanGtin = gtin.trim();

    if (!kIsWeb && _sqliteDb != null) {
      final rows = await _sqliteDb!.query(
        'medicines',
        where: 'cip_gtin = ?',
        whereArgs: [cleanGtin],
      );
      if (rows.isEmpty) return null;

      final medId = rows.first['id'].toString();
      final batchRows = await _sqliteDb!.query(
        'batches',
        where: 'medicine_id = ?',
        whereArgs: [medId],
        orderBy: 'expiry_date ASC',
      );
      final batches = batchRows.map((b) => MedicineBatch.fromMap(b)).toList();
      return Medicine.fromMap(rows.first, batches);
    } else {
      return _memoryMedicines[cleanGtin];
    }
  }

  // --------------------------------------------------------------------------
  // ÉCRITURE : MÉDICAMENTS & LOTS
  // --------------------------------------------------------------------------
  Future<void> saveMedicine(Medicine medicine) async {
    await init();

    if (!kIsWeb && _sqliteDb != null) {
      await _sqliteDb!.insert(
        'medicines',
        medicine.toMap(),
        conflictAlgorithm: sqflite.ConflictAlgorithm.replace,
      );
    }

    _memoryMedicines[medicine.cipGtin] = medicine;
  }

  Future<void> saveBatch(MedicineBatch batch) async {
    await init();

    if (!kIsWeb && _sqliteDb != null) {
      await _sqliteDb!.insert(
        'batches',
        batch.toMap(),
        conflictAlgorithm: sqflite.ConflictAlgorithm.replace,
      );
    }

    // Mise à jour synchrone de la mémoire
    for (final med in _memoryMedicines.values) {
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
  }

  // --------------------------------------------------------------------------
  // FLUX ENTRÉE EN STOCK (RÉCEPTION DÉLÉGUÉ)
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

    // 1. Sauvegarder la fiche médicament (si nouvelle ou mise à jour)
    await saveMedicine(medicine);

    // 2. Vérifier si ce numéro de lot existe déjà pour ce médicament
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

    // 3. Enregistrer le mouvement de traçabilité
    final movement = StockMovement(
      id: 'mov_${DateTime.now().millisecondsSinceEpoch}',
      medicineId: medicine.id,
      batchId: targetBatch?.id,
      type: MovementType.entry,
      quantity: quantity,
      movementDate: now,
      medicineNameSnapshot: medicine.commercialName,
      batchNumberSnapshot: batchNumber,
      note: note ?? 'Réception délégué médical',
    );
    await recordMovement(movement);
  }

  // --------------------------------------------------------------------------
  // FLUX SORTIE DU STOCK (REMISE AU PATIENT - MÉTHODE FEFO)
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

    return deductions;
  }

  // --------------------------------------------------------------------------
  // GESTION DES MOUVEMENTS & TRAÇABILITÉ
  // --------------------------------------------------------------------------
  Future<void> recordMovement(StockMovement movement) async {
    await init();

    if (!kIsWeb && _sqliteDb != null) {
      await _sqliteDb!.insert('movements', movement.toMap());
    }
    _memoryMovements.insert(0, movement);
  }

  Future<List<StockMovement>> getMovements({String? medicineId}) async {
    await init();

    if (!kIsWeb && _sqliteDb != null) {
      final rows = await _sqliteDb!.query(
        'movements',
        where: medicineId != null ? 'medicine_id = ?' : null,
        whereArgs: medicineId != null ? [medicineId] : null,
        orderBy: 'movement_date DESC',
        limit: 100,
      );
      return rows.map((m) => StockMovement.fromMap(m)).toList();
    } else {
      if (medicineId != null) {
        return _memoryMovements.where((m) => m.medicineId == medicineId).toList();
      }
      return _memoryMovements;
    }
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
  // EXPORT / IMPORT SAUVEGARDE JSON & CSV
  // --------------------------------------------------------------------------
  Future<String> exportBackupJson() async {
    final medicines = await getAllMedicines();
    final movements = await getMovements();

    final exportData = {
      'version': '1.0',
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
      await saveMedicine(med);
      for (final b in batches) {
        await saveBatch(b);
      }
    }
  }

  Future<String> exportInventoryCsv() async {
    final medicines = await getAllMedicines();
    final buffer = StringBuffer();

    // En-tête CSV
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
