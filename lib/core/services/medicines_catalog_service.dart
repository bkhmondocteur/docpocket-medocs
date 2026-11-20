import 'dart:convert';
import 'package:flutter/services.dart';

/// Modèle d'un médicament du dictionnaire de référence pharmaceutique
class CatalogMedicine {
  final String name;              // Nom complet d'origine (ex: DOLIPRANE 1000mg Comp.sec. Bt 8)
  final String dci;               // DCI (ex: PARACETAMOL)
  final String form;              // Forme galénique (ex: Comprimé sécable)
  final String laboratory;        // Laboratoire (ex: SANOFI)
  final String therapeuticClass;  // Famille thérapeutique
  final String dosage;            // Dosage
  final String price;             // Prix public

  const CatalogMedicine({
    required this.name,
    required this.dci,
    required this.form,
    required this.laboratory,
    required this.therapeuticClass,
    required this.dosage,
    required this.price,
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
    );
  }

  /// Nom commercial épuré (ex: DOLIPRANE 1000mg)
  String get cleanCommercialName {
    // Si dosage explicite et absent du début du nom, on garde la racine
    var clean = name;
    // Supprimer les suffixes de forme abrégée et conditionnement (ex: Comp. Bt 30, Susp.or. Fl 60ml)
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

/// Service de recherche dans la base des médicaments
class MedicinesCatalogService {
  static final MedicinesCatalogService instance = MedicinesCatalogService._internal();
  MedicinesCatalogService._internal();

  List<CatalogMedicine>? _catalog;
  bool _isLoading = false;

  bool get isLoaded => _catalog != null;
  int get count => _catalog?.length ?? 0;

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
      final jsonString = await rootBundle.loadString('assets/data/medicines_database.json');
      final list = json.decode(jsonString) as List<dynamic>;
      _catalog = list.map((item) => CatalogMedicine.fromMap(item as Map<String, dynamic>)).toList();
    } catch (e) {
      _catalog = [];
    } finally {
      _isLoading = false;
    }

    return _catalog ?? [];
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
      final text = '${med.name} ${med.cleanCommercialName} ${med.dci} ${med.form}'.toLowerCase();
      return words.every((w) => text.contains(w));
    }).take(limit).toList();
  }
}
