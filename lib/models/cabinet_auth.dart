import 'dart:convert';

/// Rôle de l'utilisateur dans DocPocket Medocs
enum UserRole {
  doctor,
  secretary;

  String get label {
    switch (this) {
      case UserRole.doctor:
        return 'Médecin';
      case UserRole.secretary:
        return 'Secrétaire';
    }
  }

  String get iconEmoji {
    switch (this) {
      case UserRole.doctor:
        return '🩺';
      case UserRole.secretary:
        return '💼';
    }
  }
}

/// Profil du médecin titulaire
class DoctorProfile {
  final String nom;
  final String prenom;
  final String orderNumber;
  final String licenseKey;
  final String cabinetId;
  final DateTime activatedAt;

  const DoctorProfile({
    required this.nom,
    required this.prenom,
    required this.orderNumber,
    required this.licenseKey,
    required this.cabinetId,
    required this.activatedAt,
  });

  String get fullName => 'Dr. ${nom.trim().toUpperCase()} ${prenom.trim()}';

  Map<String, dynamic> toMap() => {
        'nom': nom,
        'prenom': prenom,
        'orderNumber': orderNumber,
        'licenseKey': licenseKey,
        'cabinetId': cabinetId,
        'activatedAt': activatedAt.toIso8601String(),
      };

  factory DoctorProfile.fromMap(Map<String, dynamic> map) => DoctorProfile(
        nom: map['nom'] as String? ?? '',
        prenom: map['prenom'] as String? ?? '',
        orderNumber: map['orderNumber'] as String? ?? '',
        licenseKey: map['licenseKey'] as String? ?? '',
        cabinetId: map['cabinetId'] as String? ?? '',
        activatedAt: DateTime.tryParse(map['activatedAt'] as String? ?? '') ?? DateTime.now(),
      );

  String toJson() => json.encode(toMap());
  factory DoctorProfile.fromJson(String str) => DoctorProfile.fromMap(json.decode(str) as Map<String, dynamic>);
}

/// Délégation accordée à une secrétaire
class SecretaryDelegation {
  final String id;
  final String cabinetId;
  final String secretaryName;
  final String accessCode;
  final bool isActive;
  final DateTime createdAt;

  const SecretaryDelegation({
    required this.id,
    required this.cabinetId,
    required this.secretaryName,
    required this.accessCode,
    this.isActive = true,
    required this.createdAt,
  });

  Map<String, dynamic> toMap() => {
        'id': id,
        'cabinetId': cabinetId,
        'secretaryName': secretaryName,
        'accessCode': accessCode,
        'isActive': isActive,
        'createdAt': createdAt.toIso8601String(),
      };

  factory SecretaryDelegation.fromMap(Map<String, dynamic> map) => SecretaryDelegation(
        id: map['id'] as String? ?? '',
        cabinetId: map['cabinetId'] as String? ?? '',
        secretaryName: map['secretaryName'] as String? ?? '',
        accessCode: map['accessCode'] as String? ?? '',
        isActive: map['isActive'] as bool? ?? true,
        createdAt: DateTime.tryParse(map['createdAt'] as String? ?? '') ?? DateTime.now(),
      );
}

/// Session active de l'utilisateur sur l'appareil
class CabinetSession {
  final UserRole role;
  final String cabinetId;
  final String displayName;
  final DoctorProfile? doctor;
  final SecretaryDelegation? secretary;
  final DateTime loggedAt;

  const CabinetSession({
    required this.role,
    required this.cabinetId,
    required this.displayName,
    this.doctor,
    this.secretary,
    required this.loggedAt,
  });

  bool get isDoctor => role == UserRole.doctor;
  bool get isSecretary => role == UserRole.secretary;

  Map<String, dynamic> toMap() => {
        'role': role.name,
        'cabinetId': cabinetId,
        'displayName': displayName,
        'doctor': doctor?.toMap(),
        'secretary': secretary?.toMap(),
        'loggedAt': loggedAt.toIso8601String(),
      };

  factory CabinetSession.fromMap(Map<String, dynamic> map) => CabinetSession(
        role: map['role'] == 'secretary' ? UserRole.secretary : UserRole.doctor,
        cabinetId: map['cabinetId'] as String? ?? '',
        displayName: map['displayName'] as String? ?? '',
        doctor: map['doctor'] != null ? DoctorProfile.fromMap(map['doctor'] as Map<String, dynamic>) : null,
        secretary: map['secretary'] != null ? SecretaryDelegation.fromMap(map['secretary'] as Map<String, dynamic>) : null,
        loggedAt: DateTime.tryParse(map['loggedAt'] as String? ?? '') ?? DateTime.now(),
      );

  String toJson() => json.encode(toMap());
  factory CabinetSession.fromJson(String str) => CabinetSession.fromMap(json.decode(str) as Map<String, dynamic>);
}
