import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import '../../models/medicine.dart';
import '../../models/medicine_batch.dart';
import '../../models/stock_movement.dart';
import '../../models/stock_alert_level.dart';
import '../services/auto_backup_service.dart';
import '../services/license_service.dart';
import '../services/medicines_catalog_service.dart';
import '../services/supabase_sync_service.dart';

/// Service de stockage local 100% rapide, autonome, universel et persistant
/// Les données de stock sont protégées contre toute suppression lors des mises à jour
/// grâce à une triple redondance (SharedPreferences, miroir disque et backups rotatifs).
class DatabaseService {
  static final DatabaseService instance = DatabaseService._internal();
  DatabaseService._internal();

  static const String _prefKeyMedicines = 'docpocket_medocs_medicines_v3';
  static const String _prefKeyMovements = 'docpocket_medocs_movements_v3';
  static const String _prefKeyDeletedMedicines = 'docpocket_medocs_deleted_medicines_v1';

  final Map<String, Medicine> _medicines = {};
  final List<StockMovement> _movements = [];
  final Map<String, DateTime> _deletedMedicines = {};
  bool _initialized = false;

  Future<void> init() async {
    if (_initialized) return;

    final prefs = await SharedPreferences.getInstance();

    // 1. Lire la clé principale actuelle
    var savedMeds = prefs.getString(_prefKeyMedicines);
    var savedMoves = prefs.getString(_prefKeyMovements);

    // 2. Si vide dans SharedPreferences, chercher dans les clés de versions antérieures (migration douce)
    if (savedMeds == null || savedMeds.isEmpty || savedMeds == '[]') {
      const legacyMedKeys = [
        'docpocket_medocs_medicines_v2',
        'docpocket_medocs_medicines_v1',
        'docpocket_medocs_medicines',
        'docpocket_medicines_v1',
        'docpocket_medicines',
      ];
      for (final key in legacyMedKeys) {
        final legacyData = prefs.getString(key);
        if (legacyData != null && legacyData.isNotEmpty && legacyData != '[]') {
          savedMeds = legacyData;
          debugPrint('[DatabaseService] Récupération et migration du stock depuis l\'ancienne clé : $key');
          break;
        }
      }
    }

    if (savedMoves == null || savedMoves.isEmpty || savedMoves == '[]') {
      const legacyMoveKeys = [
        'docpocket_medocs_movements_v2',
        'docpocket_medocs_movements_v1',
        'docpocket_medocs_movements',
        'docpocket_movements_v1',
        'docpocket_movements',
      ];
      for (final key in legacyMoveKeys) {
        final legacyData = prefs.getString(key);
        if (legacyData != null && legacyData.isNotEmpty && legacyData != '[]') {
          savedMoves = legacyData;
          break;
        }
      }
    }

    // 3. Si toujours vide sur plateforme mobile/desktop, chercher dans le miroir de persistance disque
    if ((savedMeds == null || savedMeds.isEmpty || savedMeds == '[]') && !kIsWeb) {
      try {
        final docDir = await getApplicationDocumentsDirectory();
        final mirrorFile = File(p.join(docDir.path, 'docpocket_database_mirror.json'));
        if (await mirrorFile.exists()) {
          final content = await mirrorFile.readAsString();
          if (content.isNotEmpty) {
            final mirrorData = json.decode(content) as Map<String, dynamic>;
            final mirrorMeds = mirrorData['medicines'];
            final mirrorMoves = mirrorData['movements'];
            if (mirrorMeds != null) savedMeds = json.encode(mirrorMeds);
            if (mirrorMoves != null) savedMoves = json.encode(mirrorMoves);
            debugPrint('[DatabaseService] Récupération automatique du stock depuis le miroir disque.');
          }
        }
      } catch (e) {
        debugPrint('[DatabaseService] Erreur lecture miroir disque : $e');
      }
    }

    // 4. Si toujours vide, chercher dans les sauvegardes automatiques rotatives
    if ((savedMeds == null || savedMeds.isEmpty || savedMeds == '[]') && !kIsWeb) {
      try {
        final docDir = await getApplicationDocumentsDirectory();
        final backupDir = Directory(p.join(docDir.path, 'DocPocket_Backups'));
        if (await backupDir.exists()) {
          final files = backupDir.listSync().whereType<File>().where((f) => f.path.endsWith('.json')).toList();
          if (files.isNotEmpty) {
            files.sort((a, b) => b.lastModifiedSync().compareTo(a.lastModifiedSync()));
            final latestFile = files.first;
            final content = await latestFile.readAsString();
            final jsonBackup = json.decode(content) as Map<String, dynamic>;
            final backupMeds = jsonBackup['medicines'];
            final backupMoves = jsonBackup['movements'];
            if (backupMeds != null) savedMeds = json.encode(backupMeds);
            if (backupMoves != null) savedMoves = json.encode(backupMoves);
            debugPrint('[DatabaseService] Récupération de secours depuis le fichier backup : ${latestFile.path}');
          }
        }
      } catch (e) {
        debugPrint('[DatabaseService] Erreur restauration depuis backup : $e');
      }
    }

    // 5. Désérialisation des médicaments
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
      } catch (e) {
        debugPrint('[DatabaseService] Erreur parsing médicaments : $e');
      }
    }

    // 6. Désérialisation des mouvements
    _movements.clear();
    if (savedMoves != null && savedMoves.isNotEmpty) {
      try {
        final list = json.decode(savedMoves) as List<dynamic>;
        for (final item in list) {
          _movements.add(StockMovement.fromMap(item as Map<String, dynamic>));
        }
      } catch (e) {
        debugPrint('[DatabaseService] Erreur parsing mouvements : $e');
      }
    }

    // 7. Désérialisation des suppressions (tombstones)
    _deletedMedicines.clear();
    final savedDeleted = prefs.getString(_prefKeyDeletedMedicines);
    if (savedDeleted != null && savedDeleted.isNotEmpty) {
      try {
        final decoded = json.decode(savedDeleted) as Map<String, dynamic>;
        for (final entry in decoded.entries) {
          final dt = DateTime.tryParse(entry.value.toString());
          if (dt != null) {
            _deletedMedicines[entry.key] = dt;
          }
        }
      } catch (e) {
        debugPrint('[DatabaseService] Erreur parsing suppressions : $e');
      }
    }
    // Nettoyer les tombstones expirées (> 90 jours)
    final purgeLimit = DateTime.now().subtract(const Duration(days: 90));
    _deletedMedicines.removeWhere((_, date) => date.isBefore(purgeLimit));

    // Si des données ont été restaurées, synchroniser immédiatement les deux couches de persistance
    if (_medicines.isNotEmpty) {
      await _persist();
    }

    _initialized = true;
  }

  Future<void> _persist({bool triggerCloudSync = true}) async {
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

    final deletedJson = _deletedMedicines.map((k, v) => MapEntry(k, v.toIso8601String()));
    await prefs.setString(_prefKeyDeletedMedicines, json.encode(deletedJson));

    // Couche de redondance : miroir persistant sur disque
    if (!kIsWeb) {
      try {
        final docDir = await getApplicationDocumentsDirectory();
        final mirrorFile = File(p.join(docDir.path, 'docpocket_database_mirror.json'));
        final data = {
          'version': 3,
          'savedAt': DateTime.now().toIso8601String(),
          'medicines': medsJson,
          'movements': movesJson,
          'deletedMedicines': deletedJson,
        };
        await mirrorFile.writeAsString(json.encode(data), flush: true);
      } catch (e) {
        debugPrint('[DatabaseService] Erreur écriture miroir disque : $e');
      }
    }

    // Synchronisation en arrière-plan avec Supabase Cloud si activée
    if (triggerCloudSync && SupabaseSyncService.instance.isAutoSyncEnabled && LicenseService.instance.isAuthenticated) {
      SupabaseSyncService.instance.syncStock();
    }
  }

  /// Réinitialise l'ensemble des stocks et mouvements pour repartir à zéro
  Future<void> clearAllStock() async {
    _medicines.clear();
    _movements.clear();
    await _persist();
    if (!kIsWeb) {
      try {
        final docDir = await getApplicationDocumentsDirectory();
        final mirrorFile = File(p.join(docDir.path, 'docpocket_database_mirror.json'));
        if (await mirrorFile.exists()) {
          await mirrorFile.delete();
        }
      } catch (_) {}
    }
    await AutoBackupService.instance.triggerAutoBackup();
    if (SupabaseSyncService.instance.isAutoSyncEnabled && LicenseService.instance.isAuthenticated) {
      SupabaseSyncService.instance.syncStock(actionDescription: 'Remise à zéro du stock par le Médecin');
    }
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

  static String normalizeKey(String s) {
    return s.toLowerCase().trim().replaceAll(RegExp(r'\s+'), ' ');
  }

  /// Recherche un médicament existant par GTIN ou par identité pharmaceutique
  /// (même nom commercial, même forme galénique, même conditionnement/dosage)
  Medicine? findExistingMedicine({
    required String commercialName,
    required String form,
    required String dosage,
    String? cipGtin,
  }) {
    if (cipGtin != null && cipGtin.trim().isNotEmpty && !cipGtin.startsWith('CODE_')) {
      final byGtin = _medicines[cipGtin.trim()];
      if (byGtin != null) return byGtin;
    }

    final normName = normalizeKey(commercialName);
    final normForm = normalizeKey(form);
    final normDosage = normalizeKey(dosage);

    if (normName.isEmpty) return null;

    for (final med in _medicines.values) {
      final mName = normalizeKey(med.commercialName);
      final mForm = normalizeKey(med.form);
      final mDosage = normalizeKey(med.dosage);

      if (mName == normName && mForm == normForm && mDosage == normDosage) {
        return med;
      }
    }
    return null;
  }

  // --------------------------------------------------------------------------
  // ÉCRITURE
  // --------------------------------------------------------------------------
  Future<void> saveMedicine(Medicine medicine) async {
    await init();
    final updated = medicine.copyWith(updatedAt: DateTime.now());
    _medicines[medicine.cipGtin] = updated;
    _deletedMedicines.remove(medicine.cipGtin);
    _deletedMedicines.remove(medicine.commercialName.toLowerCase().trim());
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
        _medicines[med.cipGtin] = med.copyWith(updatedAt: DateTime.now());
        _deletedMedicines.remove(med.cipGtin);
        _deletedMedicines.remove(med.commercialName.toLowerCase().trim());
        break;
      }
    }
    await _persist();
  }

  /// Met à jour les informations d'un médicament (ex: nom commercial en majuscules, forme, dosage, laboratoire)
  Future<void> updateMedicineInfo({
    required String cipGtin,
    required String commercialName,
    required String dci,
    required String form,
    required String dosage,
    required String laboratory,
  }) async {
    await init();
    final existing = _medicines[cipGtin];
    if (existing == null) return;

    final updated = existing.copyWith(
      commercialName: commercialName.trim().toUpperCase(),
      dci: dci.trim(),
      form: form.trim(),
      dosage: dosage.trim(),
      laboratory: laboratory.trim(),
      updatedAt: DateTime.now(),
    );

    _medicines[cipGtin] = updated;
    _deletedMedicines.remove(cipGtin);
    _deletedMedicines.remove(updated.commercialName.toLowerCase().trim());
    await _persist();
    await AutoBackupService.instance.triggerAutoBackup();
  }

  /// Enregistre une suppression de médicament (tombstone) et synchronise avec Supabase
  Future<void> recordMedicineDeletion(String identifier) async {
    await init();
    final now = DateTime.now();
    final cleanId = identifier.trim().toLowerCase();
    _deletedMedicines[cleanId] = now;
    _deletedMedicines[identifier.trim()] = now;
    await _persist();
  }

  /// Supprime définitivement un médicament et ses mouvements du stock du cabinet
  Future<void> deleteMedicine(String cipGtin) async {
    await init();
    final now = DateTime.now();
    final med = _medicines.remove(cipGtin);
    _deletedMedicines[cipGtin] = now;
    if (med != null) {
      _deletedMedicines[med.commercialName.toLowerCase().trim()] = now;
      _deletedMedicines[normalizeKey(med.commercialName)] = now;
      _movements.removeWhere((mov) => mov.medicineId == med.id);

      // Si ce médicament figure dans le catalogue personnalisé, le retirer également
      try {
        final customMeds = await MedicinesCatalogService.instance.getCustomMedicines();
        final inCustom = customMeds.cast<CatalogMedicine?>().firstWhere(
          (m) => m != null && m.cleanCommercialName.toLowerCase() == med.commercialName.toLowerCase(),
          orElse: () => null,
        );
        if (inCustom != null) {
          await MedicinesCatalogService.instance.deleteCustomMedicine(inCustom);
        }
      } catch (_) {}
    }
    await _persist();
    await AutoBackupService.instance.triggerAutoBackup();
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

    // 1. Détecter si le médicament existe déjà (même nom, même forme, même conditionnement)
    Medicine targetMedicine = medicine;
    final existingMed = findExistingMedicine(
      commercialName: medicine.commercialName,
      form: medicine.form,
      dosage: medicine.dosage,
      cipGtin: medicine.cipGtin,
    );

    if (existingMed != null) {
      targetMedicine = existingMed;
    } else {
      _medicines[targetMedicine.cipGtin] = targetMedicine;
    }

    // 2. Traiter le lot : lot existant ou nouveau lot
    final cleanBatchNumber = batchNumber.trim().isEmpty ? 'SANS-LOT' : batchNumber.trim();
    MedicineBatch? targetBatch;
    for (final b in targetMedicine.batches) {
      if (b.batchNumber.toLowerCase().trim() == cleanBatchNumber.toLowerCase().trim()) {
        targetBatch = b;
        break;
      }
    }

    if (targetBatch != null) {
      // Cas A : Lot identique -> on incrémente le nombre de boîtes
      final updated = targetBatch.copyWith(
        quantity: targetBatch.quantity + quantity,
        initialQuantity: targetBatch.initialQuantity + quantity,
        expiryDate: expiryDate,
      );
      await saveBatch(updated);
    } else {
      // Cas B : Nouveau lot rattaché au médicament existant
      final newBatch = MedicineBatch(
        id: 'batch_${DateTime.now().millisecondsSinceEpoch}',
        medicineId: targetMedicine.id,
        batchNumber: cleanBatchNumber,
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
      medicineId: targetMedicine.id,
      batchId: targetBatch?.id,
      type: MovementType.entry,
      quantity: quantity,
      movementDate: now,
      medicineNameSnapshot: targetMedicine.commercialName,
      batchNumberSnapshot: cleanBatchNumber,
      note: note ?? (targetBatch != null ? 'Ajout boîtes identiques' : 'Réception nouveau lot'),
    );
    await recordMovement(movement);
    await AutoBackupService.instance.triggerAutoBackup();
  }

  /// Ajoute manuellement des boîtes à un lot existant avec les mêmes caractéristiques
  Future<void> addBoxesToBatch({
    required Medicine medicine,
    required MedicineBatch batch,
    required int additionalQuantity,
    String? note,
  }) async {
    await init();
    final now = DateTime.now();

    final updated = batch.copyWith(
      quantity: batch.quantity + additionalQuantity,
      initialQuantity: batch.initialQuantity + additionalQuantity,
    );
    await saveBatch(updated);

    final movement = StockMovement(
      id: 'mov_${DateTime.now().millisecondsSinceEpoch}',
      medicineId: medicine.id,
      batchId: batch.id,
      type: MovementType.entry,
      quantity: additionalQuantity,
      movementDate: now,
      medicineNameSnapshot: medicine.commercialName,
      batchNumberSnapshot: batch.batchNumber,
      note: note ?? 'Ajout manuel (+$additionalQuantity boîte(s))',
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
    final customMeds = await MedicinesCatalogService.instance.getCustomMedicines();

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
      'deletedMedicines': _deletedMedicines.map((k, v) => MapEntry(k, v.toIso8601String())),
      'customMedicines': customMeds.map((m) => m.toMap()).toList(),
    };

    return const JsonEncoder.withIndent('  ').convert(exportData);
  }

  Future<void> importBackupJson(String jsonString, {bool replace = true}) async {
    final decoded = json.decode(jsonString) as Map<String, dynamic>;
    final medsJson = decoded['medicines'] as List<dynamic>? ?? [];

    if (replace) {
      _medicines.clear();
      _movements.clear();
      _deletedMedicines.clear();
    }

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

    final deletedMap = decoded['deletedMedicines'] as Map<String, dynamic>? ?? {};
    for (final entry in deletedMap.entries) {
      final dt = DateTime.tryParse(entry.value.toString());
      if (dt != null) {
        _deletedMedicines[entry.key] = dt;
      }
    }

    final customMeds = decoded['customMedicines'] as List<dynamic>? ?? [];
    if (customMeds.isNotEmpty) {
      await MedicinesCatalogService.instance.mergeRemoteCustomMedicines(customMeds);
    }

    await _persist(triggerCloudSync: false);
    await AutoBackupService.instance.triggerAutoBackup();
  }

  /// Fusionne intelligemment le stock distant Cloud avec le stock local
  /// Gère les suppressions (tombstones) et les modifications avec résolution Last-Write-Wins (dernière modification)
  /// Retourne true si des modifications locales ont eu lieu
  Future<bool> mergeRemoteStockJson(String remoteJson, {String? remoteAction}) async {
    await init();
    try {
      final decoded = json.decode(remoteJson) as Map<String, dynamic>;
      final medsJson = decoded['medicines'] as List<dynamic>? ?? [];
      final movesJson = decoded['movements'] as List<dynamic>? ?? [];
      final remoteDeletedMap = decoded['deletedMedicines'] as Map<String, dynamic>? ?? {};
      final remoteCustomMeds = decoded['customMedicines'] as List<dynamic>? ?? [];

      // Si l'action distante est une remise à zéro explicite par le Médecin
      final isClearAction = remoteAction != null && remoteAction.contains('Remise à zéro');
      if (isClearAction) {
        if (_medicines.isNotEmpty || _movements.isNotEmpty) {
          _medicines.clear();
          _movements.clear();
          _deletedMedicines.clear();
          await _persist(triggerCloudSync: false);
          return true;
        }
        return false;
      }

      bool hasChanges = false;

      // 1. Fusionner les suppressions distantes (Tombstones)
      for (final entry in remoteDeletedMap.entries) {
        final remoteDeletedAt = DateTime.tryParse(entry.value.toString());
        if (remoteDeletedAt != null) {
          final localDeletedAt = _deletedMedicines[entry.key];
          if (localDeletedAt == null || remoteDeletedAt.isAfter(localDeletedAt)) {
            _deletedMedicines[entry.key] = remoteDeletedAt;
          }
        }
      }

      // 2. Appliquer les suppressions sur le stock local
      for (final cip in _deletedMedicines.keys.toList()) {
        final deletedAt = _deletedMedicines[cip]!;
        final localMed = _medicines[cip] ?? _medicines.values.cast<Medicine?>().firstWhere(
          (m) => m != null && (m.commercialName.toLowerCase().trim() == cip.toLowerCase().trim() ||
                               normalizeKey(m.commercialName) == cip),
          orElse: () => null,
        );

        if (localMed != null) {
          if (!localMed.updatedAt.isAfter(deletedAt)) {
            _medicines.remove(localMed.cipGtin);
            _movements.removeWhere((mov) => mov.medicineId == localMed.id);
            hasChanges = true;
          } else {
            // Recréé ou modifié localement après la date de suppression
            _deletedMedicines.remove(cip);
            hasChanges = true;
          }
        }
      }

      // 3. Fusion des médicaments et lots (Règle Last-Write-Wins basée sur updatedAt)
      for (final item in medsJson) {
        final map = item as Map<String, dynamic>;
        final batchesJson = map['batches'] as List<dynamic>? ?? [];
        final remoteBatches = batchesJson.map((b) => MedicineBatch.fromMap(b as Map<String, dynamic>)).toList();
        final remoteMed = Medicine.fromMap(map, remoteBatches);

        // Vérifier si ce médicament a été supprimé
        final deletedAt = _deletedMedicines[remoteMed.cipGtin] ??
            _deletedMedicines[remoteMed.commercialName.toLowerCase().trim()] ??
            _deletedMedicines[normalizeKey(remoteMed.commercialName)];

        if (deletedAt != null) {
          if (!remoteMed.updatedAt.isAfter(deletedAt)) {
            // Supprimé plus récemment que sa date de modification distante -> ne pas réimporter !
            continue;
          } else {
            // Mis à jour à distance après la date de suppression -> ressusciter
            _deletedMedicines.remove(remoteMed.cipGtin);
            _deletedMedicines.remove(remoteMed.commercialName.toLowerCase().trim());
          }
        }

        if (!_medicines.containsKey(remoteMed.cipGtin)) {
          // Absent en local -> ajout
          _medicines[remoteMed.cipGtin] = remoteMed;
          hasChanges = true;
        } else {
          final localMed = _medicines[remoteMed.cipGtin]!;

          // Comparaison Last-Write-Wins entre version locale et version distante
          if (remoteMed.updatedAt.isAfter(localMed.updatedAt)) {
            // La version distante est PLUS RÉCENTE : remplacer complètement
            _medicines[remoteMed.cipGtin] = remoteMed;
            hasChanges = true;
          } else if (localMed.updatedAt.isAfter(remoteMed.updatedAt)) {
            // La version locale est PLUS RÉCENTE : conserver locale
          } else {
            // Même date de modification : fusion des lots
            final localBatches = List<MedicineBatch>.from(localMed.batches);
            bool medUpdated = false;

            for (final rb in remoteBatches) {
              final matchIdx = localBatches.indexWhere((b) =>
                  b.id == rb.id ||
                  b.batchNumber.toLowerCase().trim() == rb.batchNumber.toLowerCase().trim());

              if (matchIdx == -1) {
                localBatches.add(rb);
                medUpdated = true;
              } else {
                final lb = localBatches[matchIdx];
                if (rb.receivedDate.isAfter(lb.receivedDate) || rb.quantity != lb.quantity) {
                  localBatches[matchIdx] = rb;
                  medUpdated = true;
                }
              }
            }

            if (medUpdated) {
              _medicines[remoteMed.cipGtin] = localMed.copyWith(batches: localBatches);
              hasChanges = true;
            }
          }
        }
      }

      // 4. Fusion des mouvements de stock (unicité par ID de mouvement)
      final existingMoveIds = _movements.map((m) => m.id).toSet();
      for (final item in movesJson) {
        final move = StockMovement.fromMap(item as Map<String, dynamic>);
        if (!existingMoveIds.contains(move.id)) {
          final medExists = _medicines.values.any((m) => m.id == move.medicineId);
          if (medExists) {
            _movements.add(move);
            existingMoveIds.add(move.id);
            hasChanges = true;
          }
        }
      }
      _movements.sort((a, b) => b.movementDate.compareTo(a.movementDate));

      // 5. Synchroniser le catalogue de médicaments personnalisés
      if (remoteCustomMeds.isNotEmpty) {
        await MedicinesCatalogService.instance.mergeRemoteCustomMedicines(
          remoteCustomMeds,
          deletedKeys: _deletedMedicines.keys.toSet(),
        );
      }

      if (hasChanges) {
        await _persist(triggerCloudSync: false);
      }

      return hasChanges;
    } catch (e) {
      debugPrint('[DatabaseService] Erreur mergeRemoteStockJson : $e');
      return false;
    }
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
