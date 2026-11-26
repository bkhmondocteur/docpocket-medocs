import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Modèle d'un médicament du dictionnaire de référence pharmaceutique
class CatalogMedicine {
  final String name;              // Nom complet d'origine (ex: DOLIPRANE 1000mg Comp.sec. Bt 8)
  final String dci;               // DCI (ex: PARACETAMOL)
  final String form;              // Forme galénique (ex: Comprimé sécable)
  final String laboratory;        // Laboratoire (ex: SANOFI)
  final String therapeuticClass;  // Famille thérapeutique
  final String dosage;            // Dosage
  final String price;             // Prix public
  final String? customName;       // Nom personnalisé
  final String? customPackaging;  // Conditionnement personnalisé (ex: "Boîte de 10" ou "Flacon de 100 ml")
  final bool isCustom;            // Indicateur si créé manuellement par l'utilisateur

  const CatalogMedicine({
    required this.name,
    required this.dci,
    required this.form,
    required this.laboratory,
    required this.therapeuticClass,
    required this.dosage,
    required this.price,
    this.customName,
    this.customPackaging,
    this.isCustom = false,
  });

  factory CatalogMedicine.fromMap(Map<String, dynamic> map) {
    return CatalogMedicine(
      name: map['n']?.toString() ?? '',
      dci: map['d']?.toString() ?? '',
      form: map['f']?.toString() ?? '',
      laboratory: map['l']?.toString() ?? '',
      therapeuticClass: map['c']?.toString() ?? '',
      dosage: map['dos']?.toString() ?? '',
      price: map['p']?.toString() ?? '',
      customName: map['cn']?.toString(),
      customPackaging: map['cp']?.toString(),
      isCustom: map['is_custom'] == true,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'n': name,
      'd': dci,
      'f': form,
      'l': laboratory,
      'c': therapeuticClass,
      'dos': dosage,
      'p': price,
      'cn': customName,
      'cp': customPackaging,
      'is_custom': isCustom,
    };
  }

  /// Nom commercial épuré (ex: DOLIPRANE 1000mg)
  String get cleanCommercialName {
    if (isCustom && customName != null && customName!.trim().isNotEmpty) {
      return customName!.trim();
    }
    var clean = name;
    final regex = RegExp(
      r'\s+(Comp|Gel|Susp|Pdre|Sol|Crm|Pde|Srp|Collyre|Gttes|Amp|Supp|Past|Emuls|Glé|Shamp|Caps)\b.*$',
      caseSensitive: false,
    );
    clean = clean.replaceFirst(regex, '');
    clean = clean.trim();
    return clean.isNotEmpty ? clean : name;
  }

  /// Conditionnement extrait : Boîte ou Flacon de combien (ex: "Boîte de 30", "Flacon de 60ml")
  String get packaging {
    if (isCustom && customPackaging != null && customPackaging!.trim().isNotEmpty) {
      return customPackaging!.trim();
    }
    final regex = RegExp(
      r'\b(Bt\s*\d+[^\s,]*|\bFl\s*\d+[^\s,]*|\bTb\s*\d+[^\s,]*|\bFlacon[^\s,]*|\bPoche[^\s,]*|\bTube[^\s,]*|\bAmp\.?\s*\d+[^\s,]*|\bStylos?\s*\d+[^\s,]*)',
      caseSensitive: false,
    );
    final match = regex.firstMatch(name);
    if (match == null) return '';

    final raw = match.group(0)!.trim();
    final btMatch = RegExp(r'^Bt\s*(.+)$', caseSensitive: false).firstMatch(raw);
    if (btMatch != null) return 'Boîte de ${btMatch.group(1)}';

    final flMatch = RegExp(r'^Fl\s*(.+)$', caseSensitive: false).firstMatch(raw);
    if (flMatch != null) return 'Flacon de ${flMatch.group(1)}';

    final tbMatch = RegExp(r'^Tb\s*(.+)$', caseSensitive: false).firstMatch(raw);
    if (tbMatch != null) return 'Tube de ${tbMatch.group(1)}';

    return raw;
  }

  /// Affichage compact médical : Nom commercial + Forme + Conditionnement
  String get cleanDisplayLabel {
    final pkg = packaging;
    final f = form.trim();
    if (pkg.isNotEmpty && f.isNotEmpty) {
      return '$cleanCommercialName - $f ($pkg)';
    } else if (f.isNotEmpty) {
      return '$cleanCommercialName - $f';
    } else if (pkg.isNotEmpty) {
      return '$cleanCommercialName ($pkg)';
    }
    return cleanCommercialName;
  }
}

/// Service de recherche dans la base des médicaments (officielle + personnalisée)
class MedicinesCatalogService {
  static final MedicinesCatalogService instance = MedicinesCatalogService._internal();
  MedicinesCatalogService._internal();

  static const String _prefKeyCustomMeds = 'docpocket_custom_catalog_medicines_v2';
  List<CatalogMedicine>? _catalog;
  final List<CatalogMedicine> _customCatalog = [];
  bool _isLoading = false;

  bool get isLoaded => _catalog != null;
  int get count => _catalog?.length ?? 0;

  /// Retourne la liste des médicaments personnalisés créés par l'utilisateur
  Future<List<CatalogMedicine>> getCustomMedicines() async {
    await loadCatalog();
    return List.unmodifiable(_customCatalog);
  }

  Future<List<CatalogMedicine>> loadCatalog() async {
    if (_catalog != null) return _catalog!;
    if (_isLoading) {
      while (_isLoading) {
        await Future.delayed(const Duration(milliseconds: 50));
      }
      return _catalog ?? [];
    }

    _isLoading = true;
    try {
      // 1. Charger la base officielle tunisienne
      final jsonString = await rootBundle.loadString('assets/data/medicines_database.json');
      final list = json.decode(jsonString) as List<dynamic>;
      final baseCatalog = list.map((item) => CatalogMedicine.fromMap(item as Map<String, dynamic>)).toList();

      // 2. Charger les médicaments personnalisés ajoutés par le médecin
      final prefs = await SharedPreferences.getInstance();
      final customJson = prefs.getString(_prefKeyCustomMeds);
      _customCatalog.clear();
      if (customJson != null && customJson.isNotEmpty) {
        try {
          final customList = json.decode(customJson) as List<dynamic>;
          for (final item in customList) {
            _customCatalog.add(CatalogMedicine.fromMap(item as Map<String, dynamic>));
          }
        } catch (_) {}
      }

      // 3. Fusionner (les médicaments personnalisés sont en tête)
      _catalog = [..._customCatalog, ...baseCatalog];
    } catch (e) {
      _catalog = [..._customCatalog];
    } finally {
      _isLoading = false;
    }

    return _catalog ?? [];
  }

  /// Ajoute un nouveau médicament personnalisé créé par l'utilisateur
  Future<CatalogMedicine> addCustomMedicine({
    required String commercialName,
    required String dci,
    required String form,
    required String packagingOrVolume,
    required String laboratory,
    String therapeuticClass = '',
  }) async {
    await loadCatalog();

    final cleanName = commercialName.trim().toUpperCase();
    final customMed = CatalogMedicine(
      name: '$cleanName $form $packagingOrVolume'.trim(),
      dci: dci.trim(),
      form: form.trim(),
      laboratory: laboratory.trim(),
      therapeuticClass: therapeuticClass.trim(),
      dosage: packagingOrVolume.trim(),
      price: '',
      customName: cleanName,
      customPackaging: packagingOrVolume.trim(),
      isCustom: true,
    );

    // Éviter les doublons exacts dans le catalogue personnalisé
    _customCatalog.removeWhere((m) =>
        m.cleanCommercialName.toLowerCase() == customMed.cleanCommercialName.toLowerCase() &&
        m.form.toLowerCase() == customMed.form.toLowerCase() &&
        m.packaging.toLowerCase() == customMed.packaging.toLowerCase());

    _customCatalog.insert(0, customMed);
    _catalog?.insert(0, customMed);

    try {
      final prefs = await SharedPreferences.getInstance();
      final jsonList = _customCatalog.map((m) => m.toMap()).toList();
      await prefs.setString(_prefKeyCustomMeds, json.encode(jsonList));
    } catch (_) {}

    return customMed;
  }

  /// Modifie un médicament personnalisé existant dans le catalogue
  Future<CatalogMedicine> updateCustomMedicine({
    required CatalogMedicine originalMedicine,
    required String commercialName,
    required String dci,
    required String form,
    required String packagingOrVolume,
    required String laboratory,
    String therapeuticClass = '',
  }) async {
    await loadCatalog();

    final cleanName = commercialName.trim().toUpperCase();
    final updated = CatalogMedicine(
      name: '$cleanName $form $packagingOrVolume'.trim(),
      dci: dci.trim(),
      form: form.trim(),
      laboratory: laboratory.trim(),
      therapeuticClass: therapeuticClass.trim(),
      dosage: packagingOrVolume.trim(),
      price: originalMedicine.price,
      customName: cleanName,
      customPackaging: packagingOrVolume.trim(),
      isCustom: true,
    );

    // Mettre à jour dans _customCatalog
    final customIdx = _customCatalog.indexWhere((m) =>
        m.cleanCommercialName.toLowerCase() == originalMedicine.cleanCommercialName.toLowerCase() &&
        m.form.toLowerCase() == originalMedicine.form.toLowerCase());
    if (customIdx >= 0) {
      _customCatalog[customIdx] = updated;
    } else {
      _customCatalog.insert(0, updated);
    }

    // Mettre à jour dans _catalog
    final catIdx = _catalog?.indexWhere((m) =>
        m.isCustom &&
        m.cleanCommercialName.toLowerCase() == originalMedicine.cleanCommercialName.toLowerCase() &&
        m.form.toLowerCase() == originalMedicine.form.toLowerCase()) ?? -1;
    if (catIdx >= 0 && _catalog != null) {
      _catalog![catIdx] = updated;
    }

    try {
      final prefs = await SharedPreferences.getInstance();
      final jsonList = _customCatalog.map((m) => m.toMap()).toList();
      await prefs.setString(_prefKeyCustomMeds, json.encode(jsonList));
    } catch (_) {}

    return updated;
  }

  /// Supprime un médicament personnalisé du catalogue
  Future<void> deleteCustomMedicine(CatalogMedicine medicine) async {
    await loadCatalog();

    final cleanName = medicine.cleanCommercialName.toLowerCase().trim();
    _customCatalog.removeWhere((m) =>
        m.cleanCommercialName.toLowerCase().trim() == cleanName &&
        m.form.toLowerCase().trim() == medicine.form.toLowerCase().trim());

    _catalog?.removeWhere((m) =>
        m.isCustom &&
        m.cleanCommercialName.toLowerCase().trim() == cleanName &&
        m.form.toLowerCase().trim() == medicine.form.toLowerCase().trim());

    try {
      final prefs = await SharedPreferences.getInstance();
      final jsonList = _customCatalog.map((m) => m.toMap()).toList();
      await prefs.setString(_prefKeyCustomMeds, json.encode(jsonList));
    } catch (_) {}
  }

  /// Fusionne les médicaments personnalisés distants en tenant compte des suppressions
  Future<void> mergeRemoteCustomMedicines(
    List<dynamic> remoteList, {
    Set<String>? deletedKeys,
  }) async {
    await loadCatalog();
    bool changed = false;

    for (final item in remoteList) {
      try {
        final med = CatalogMedicine.fromMap(item as Map<String, dynamic>);
        final cleanName = med.cleanCommercialName.toLowerCase().trim();

        // Si le médicament figure dans les suppressions
        final isDeleted = deletedKeys != null &&
            deletedKeys.any((k) =>
                k.toLowerCase().trim() == cleanName ||
                k.toLowerCase().trim() == med.name.toLowerCase().trim());

        if (isDeleted) {
          _customCatalog.removeWhere((m) =>
              m.cleanCommercialName.toLowerCase().trim() == cleanName &&
              m.form.toLowerCase().trim() == med.form.toLowerCase().trim());
          _catalog?.removeWhere((m) =>
              m.isCustom &&
              m.cleanCommercialName.toLowerCase().trim() == cleanName &&
              m.form.toLowerCase().trim() == med.form.toLowerCase().trim());
          changed = true;
          continue;
        }

        final existingIdx = _customCatalog.indexWhere((m) =>
            m.cleanCommercialName.toLowerCase().trim() == cleanName &&
            m.form.toLowerCase().trim() == med.form.toLowerCase().trim());

        if (existingIdx == -1) {
          _customCatalog.insert(0, med);
          _catalog?.insert(0, med);
          changed = true;
        } else {
          _customCatalog[existingIdx] = med;
          final catIdx = _catalog?.indexWhere((m) =>
              m.isCustom &&
              m.cleanCommercialName.toLowerCase().trim() == cleanName &&
              m.form.toLowerCase().trim() == med.form.toLowerCase().trim()) ?? -1;
          if (catIdx >= 0 && _catalog != null) {
            _catalog![catIdx] = med;
          }
        }
      } catch (_) {}
    }

    if (changed) {
      try {
        final prefs = await SharedPreferences.getInstance();
        final jsonList = _customCatalog.map((m) => m.toMap()).toList();
        await prefs.setString(_prefKeyCustomMeds, json.encode(jsonList));
      } catch (_) {}
    }
  }

  /// Recherche par nom commercial, DCI ou laboratoire
  Future<List<CatalogMedicine>> search(String query, {int limit = 60}) async {
    final catalog = await loadCatalog();
    final q = query.trim().toLowerCase();

    if (q.isEmpty) {
      return catalog.take(limit).toList();
    }

    final words = q.split(' ').where((w) => w.isNotEmpty).toList();

    return catalog.where((med) {
      final text = '${med.name} ${med.cleanCommercialName} ${med.dci} ${med.form} ${med.laboratory}'.toLowerCase();
      return words.every((w) => text.contains(w));
    }).take(limit).toList();
  }
}
