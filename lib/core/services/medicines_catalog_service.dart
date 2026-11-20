import 'dart:convert';
import 'package:flutter/services.dart';

/// Modèle d'un médicament du dictionnaire de référence pharmaceutique
class CatalogMedicine {
  final String name;              // Nom commercial (ex: DOLIPRANE 1000mg Comp.sec. Bt 8)
  final String dci;               // DCI (ex: PARACETAMOL)
  final String form;              // Forme galénique (ex: Comprimé sécable)
  final String laboratory;        // Laboratoire (ex: SANOFI)
  final String therapeuticClass;  // Famille thérapeutique
  final String dosage;            // Dosage / Présentation
  final String price;             // Prix public (DT)

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
}

/// Service de gestion et de recherche instantanée dans les 5 112 médicaments de la base de référence
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

  /// Recherche instantanée multi-mots clés sur le Nom, la DCI ou le Laboratoire
  Future<List<CatalogMedicine>> search(String query, {int limit = 50}) async {
    final catalog = await loadCatalog();
    final q = query.trim().toLowerCase();

    if (q.isEmpty) {
      return catalog.take(limit).toList();
    }

    final words = q.split(' ').where((w) => w.isNotEmpty).toList();

    final results = catalog.where((med) {
      final text = '${med.name} ${med.dci} ${med.laboratory} ${med.therapeuticClass}'.toLowerCase();
      // Tous les mots de recherche doivent être présents
      return words.every((w) => text.contains(w));
    }).take(limit).toList();

    return results;
  }
}
