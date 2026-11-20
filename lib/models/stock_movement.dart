import '../core/formatters/strict_date_formatter.dart';

enum MovementType {
  entry,   // Entrée en stock (Réception délégué)
  exit,    // Sortie / Remise au patient
  expired, // Sortie pour mise au rebut / périmé
}

extension MovementTypeExt on MovementType {
  String get label {
    switch (this) {
      case MovementType.entry:
        return 'Entrée (Réception)';
      case MovementType.exit:
        return 'Remise patient';
      case MovementType.expired:
        return 'Mise au rebut (Périmé)';
    }
  }

  String get code {
    switch (this) {
      case MovementType.entry:
        return 'ENTREE';
      case MovementType.exit:
        return 'SORTIE';
      case MovementType.expired:
        return 'REBUT';
    }
  }

  static MovementType fromCode(String code) {
    switch (code) {
      case 'ENTREE':
        return MovementType.entry;
      case 'SORTIE':
        return MovementType.exit;
      case 'REBUT':
        return MovementType.expired;
      default:
        return MovementType.exit;
    }
  }
}

/// Enregistrement de traçabilité médicale pour chaque mouvement de boîte
class StockMovement {
  final String id;
  final String medicineId;
  final String? batchId;
  final MovementType type;
  final int quantity;
  final DateTime movementDate;
  final String? patientIdentifier; // Nom ou initiales du patient (traçabilité rappel lot)
  final String medicineNameSnapshot;
  final String batchNumberSnapshot;
  final String? note;

  StockMovement({
    required this.id,
    required this.medicineId,
    this.batchId,
    required this.type,
    required this.quantity,
    required this.movementDate,
    this.patientIdentifier,
    required this.medicineNameSnapshot,
    required this.batchNumberSnapshot,
    this.note,
  });

  String get movementDateFormatted => StrictDateValidator.format(movementDate);

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'medicine_id': medicineId,
      'batch_id': batchId,
      'type': type.code,
      'quantity': quantity,
      'movement_date': movementDate.toIso8601String(),
      'patient_identifier': patientIdentifier,
      'medicine_name_snapshot': medicineNameSnapshot,
      'batch_number_snapshot': batchNumberSnapshot,
      'note': note,
    };
  }

  factory StockMovement.fromMap(Map<String, dynamic> map) {
    return StockMovement(
      id: map['id']?.toString() ?? '',
      medicineId: map['medicine_id']?.toString() ?? '',
      batchId: map['batch_id']?.toString(),
      type: MovementTypeExt.fromCode(map['type']?.toString() ?? 'SORTIE'),
      quantity: (map['quantity'] as num?)?.toInt() ?? 0,
      movementDate: DateTime.parse(map['movement_date']),
      patientIdentifier: map['patient_identifier']?.toString(),
      medicineNameSnapshot: map['medicine_name_snapshot']?.toString() ?? '',
      batchNumberSnapshot: map['batch_number_snapshot']?.toString() ?? '',
      note: map['note']?.toString(),
    );
  }
}
