import 'stock_alert_level.dart';
import '../core/formatters/strict_date_formatter.dart';

/// Représente un lot spécifique d'échantillons en stock avec sa date de péremption
class MedicineBatch {
  final String id;
  final String medicineId;
  final String batchNumber;
  final DateTime expiryDate;
  int quantity;
  final int initialQuantity;
  final DateTime receivedDate;
  final String? serialNumber;

  MedicineBatch({
    required this.id,
    required this.medicineId,
    required this.batchNumber,
    required this.expiryDate,
    required this.quantity,
    required this.initialQuantity,
    required this.receivedDate,
    this.serialNumber,
  });

  /// Niveau d'alerte sémantique pour ce lot
  StockAlertLevel get alertLevel {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final expiry = DateTime(expiryDate.year, expiryDate.month, expiryDate.day);

    if (expiry.isBefore(today) || expiry.isAtSameMomentAs(today)) {
      return StockAlertLevel.expired;
    }

    final diffDays = expiry.difference(today).inDays;
    if (diffDays <= 90) {
      return StockAlertLevel.warning;
    }

    return StockAlertLevel.valid;
  }

  /// Nombre de jours restants avant péremption (négatif si déjà périmé)
  int get remainingDays {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final expiry = DateTime(expiryDate.year, expiryDate.month, expiryDate.day);
    return expiry.difference(today).inDays;
  }

  String get expiryDateFormatted => StrictDateValidator.format(expiryDate);
  String get receivedDateFormatted => StrictDateValidator.format(receivedDate);

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'medicine_id': medicineId,
      'batch_number': batchNumber,
      'expiry_date': expiryDate.toIso8601String(),
      'quantity': quantity,
      'initial_quantity': initialQuantity,
      'received_date': receivedDate.toIso8601String(),
      'serial_number': serialNumber,
    };
  }

  factory MedicineBatch.fromMap(Map<String, dynamic> map) {
    return MedicineBatch(
      id: map['id']?.toString() ?? '',
      medicineId: map['medicine_id']?.toString() ?? '',
      batchNumber: map['batch_number']?.toString() ?? '',
      expiryDate: DateTime.parse(map['expiry_date']),
      quantity: (map['quantity'] as num?)?.toInt() ?? 0,
      initialQuantity: (map['initial_quantity'] as num?)?.toInt() ?? 0,
      receivedDate: DateTime.parse(map['received_date']),
      serialNumber: map['serial_number']?.toString(),
    );
  }

  MedicineBatch copyWith({
    String? id,
    String? medicineId,
    String? batchNumber,
    DateTime? expiryDate,
    int? quantity,
    int? initialQuantity,
    DateTime? receivedDate,
    String? serialNumber,
  }) {
    return MedicineBatch(
      id: id ?? this.id,
      medicineId: medicineId ?? this.medicineId,
      batchNumber: batchNumber ?? this.batchNumber,
      expiryDate: expiryDate ?? this.expiryDate,
      quantity: quantity ?? this.quantity,
      initialQuantity: initialQuantity ?? this.initialQuantity,
      receivedDate: receivedDate ?? this.receivedDate,
      serialNumber: serialNumber ?? this.serialNumber,
    );
  }
}
