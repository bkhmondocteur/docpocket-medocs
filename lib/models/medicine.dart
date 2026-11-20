import 'medicine_batch.dart';
import 'stock_alert_level.dart';

/// Fiche Médicament mémorisée avec ses caractéristiques pharmaceutiques
class Medicine {
  final String id;
  final String cipGtin;              // Code GTIN-14 / CIP-13 unique
  final String commercialName;       // Nom commercial (ex: Doliprane)
  final String dci;                  // Dénomination Commune Internationale (ex: Paracétamol)
  final String dosage;               // Dosage (ex: 1000 mg)
  final String form;                 // Forme galénique (ex: Comprimé, Gélule, Sirop...)
  final String therapeuticClass;     // Classe thérapeutique (ex: Antalgique)
  final String laboratory;           // Laboratoire fabricant (ex: Sanofi)
  final DateTime createdAt;
  final DateTime updatedAt;
  final List<MedicineBatch> batches;

  Medicine({
    required this.id,
    required this.cipGtin,
    required this.commercialName,
    required this.dci,
    required this.dosage,
    required this.form,
    required this.therapeuticClass,
    required this.laboratory,
    required this.createdAt,
    required this.updatedAt,
    List<MedicineBatch>? batches,
  }) : batches = batches ?? [];

  /// Stock total disponible toutes boîtes confondues
  int get totalStock => batches.fold(0, (sum, b) => sum + b.quantity);

  /// Niveau d'alerte le plus critique parmi les lots actuellement en stock
  StockAlertLevel get overallAlertLevel {
    final activeBatches = batches.where((b) => b.quantity > 0).toList();
    if (activeBatches.isEmpty) return StockAlertLevel.valid;

    if (activeBatches.any((b) => b.alertLevel == StockAlertLevel.expired)) {
      return StockAlertLevel.expired;
    }
    if (activeBatches.any((b) => b.alertLevel == StockAlertLevel.warning)) {
      return StockAlertLevel.warning;
    }
    return StockAlertLevel.valid;
  }

  /// Lots ordonnés selon la règle FEFO (First Expired, First Out)
  List<MedicineBatch> get fefoOrderedBatches {
    final active = batches.where((b) => b.quantity > 0).toList();
    active.sort((a, b) => a.expiryDate.compareTo(b.expiryDate));
    return active;
  }

  /// Lot dont la péremption est la plus proche
  MedicineBatch? get nextExpiringBatch {
    final ordered = fefoOrderedBatches;
    return ordered.isNotEmpty ? ordered.first : null;
  }

  /// Décrémentation FEFO automatique
  /// Renvoie la répartition des déductions par lot : {Lot: QuantitéDéduite}
  Map<MedicineBatch, int> deductStockFefo(int quantityToDeduct) {
    if (quantityToDeduct <= 0) return {};
    if (totalStock < quantityToDeduct) {
      throw Exception('Stock insuffisant ($totalStock disponible(s), $quantityToDeduct demandée(s))');
    }

    final result = <MedicineBatch, int>{};
    int remaining = quantityToDeduct;
    final ordered = fefoOrderedBatches;

    for (final batch in ordered) {
      if (remaining == 0) break;
      final deduct = batch.quantity >= remaining ? remaining : batch.quantity;
      batch.quantity -= deduct;
      result[batch] = deduct;
      remaining -= deduct;
    }

    return result;
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'cip_gtin': cipGtin,
      'commercial_name': commercialName,
      'dci': dci,
      'dosage': dosage,
      'form': form,
      'therapeutic_class': therapeuticClass,
      'laboratory': laboratory,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
    };
  }

  factory Medicine.fromMap(Map<String, dynamic> map, [List<MedicineBatch>? batches]) {
    return Medicine(
      id: map['id']?.toString() ?? '',
      cipGtin: map['cip_gtin']?.toString() ?? '',
      commercialName: map['commercial_name']?.toString() ?? '',
      dci: map['dci']?.toString() ?? '',
      dosage: map['dosage']?.toString() ?? '',
      form: map['form']?.toString() ?? '',
      therapeuticClass: map['therapeutic_class']?.toString() ?? '',
      laboratory: map['laboratory']?.toString() ?? '',
      createdAt: map['created_at'] != null ? DateTime.parse(map['created_at']) : DateTime.now(),
      updatedAt: map['updated_at'] != null ? DateTime.parse(map['updated_at']) : DateTime.now(),
      batches: batches ?? [],
    );
  }

  Medicine copyWith({
    String? id,
    String? cipGtin,
    String? commercialName,
    String? dci,
    String? dosage,
    String? form,
    String? therapeuticClass,
    String? laboratory,
    DateTime? createdAt,
    DateTime? updatedAt,
    List<MedicineBatch>? batches,
  }) {
    return Medicine(
      id: id ?? this.id,
      cipGtin: cipGtin ?? this.cipGtin,
      commercialName: commercialName ?? this.commercialName,
      dci: dci ?? this.dci,
      dosage: dosage ?? this.dosage,
      form: form ?? this.form,
      therapeuticClass: therapeuticClass ?? this.therapeuticClass,
      laboratory: laboratory ?? this.laboratory,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      batches: batches ?? this.batches,
    );
  }
}
