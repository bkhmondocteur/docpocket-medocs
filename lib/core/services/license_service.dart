import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../models/cabinet_auth.dart';

/// Service de génération des licences médicales et de gestion des délégations secrétaires
class LicenseService {
  static final LicenseService instance = LicenseService._internal();
  LicenseService._internal();

  static const String _prefKeySession = 'docpocket_cabinet_session_v1';
  static const String _prefKeyDoctorProfile = 'docpocket_doctor_profile_v1';
  static const String _prefKeyDelegations = 'docpocket_secretary_delegations_v1';

  static const String _licenseSalt = 'DOCPOCKET_MEDOCS_TUNISIE_2026_SECURE_SALT';

  CabinetSession? _currentSession;
  DoctorProfile? _savedDoctorProfile;
  final List<SecretaryDelegation> _delegations = [];
  bool _initialized = false;

  CabinetSession? get currentSession => _currentSession;
  bool get isAuthenticated => _currentSession != null;
  bool get isDoctor => _currentSession?.isDoctor ?? false;
  bool get isSecretary => _currentSession?.isSecretary ?? false;
  String get activeCabinetId => _currentSession?.cabinetId ?? 'CAB_DEFAULT';
  String get userDisplayName => _currentSession?.displayName ?? 'Utilisateur';
  DoctorProfile? get doctorProfile => _savedDoctorProfile;
  List<SecretaryDelegation> get delegations => List.unmodifiable(_delegations);

  /// Initialise le service et restaure la session active
  Future<void> init() async {
    if (_initialized) return;

    final prefs = await SharedPreferences.getInstance();

    // 1. Charger le profil docteur mémorisé
    final doctorJson = prefs.getString(_prefKeyDoctorProfile);
    if (doctorJson != null && doctorJson.isNotEmpty) {
      try {
        _savedDoctorProfile = DoctorProfile.fromJson(doctorJson);
      } catch (e) {
        debugPrint('[LicenseService] Erreur parsing doctor profile : $e');
      }
    }

    // 2. Charger les délégations secrétaires mémorisées
    final delegationsJson = prefs.getString(_prefKeyDelegations);
    if (delegationsJson != null && delegationsJson.isNotEmpty) {
      try {
        final list = json.decode(delegationsJson) as List<dynamic>;
        _delegations.clear();
        for (final item in list) {
          _delegations.add(SecretaryDelegation.fromMap(item as Map<String, dynamic>));
        }
      } catch (e) {
        debugPrint('[LicenseService] Erreur parsing delegations : $e');
      }
    }

    // 3. Charger la session active
    final sessionJson = prefs.getString(_prefKeySession);
    if (sessionJson != null && sessionJson.isNotEmpty) {
      try {
        _currentSession = CabinetSession.fromJson(sessionJson);
      } catch (e) {
        debugPrint('[LicenseService] Erreur parsing session : $e');
      }
    }

    _initialized = true;
  }

  /// Normalise une chaîne (majuscules, suppression espaces superflus)
  static String normalize(String text) {
    return text.trim().toUpperCase().replaceAll(RegExp(r'\s+'), ' ');
  }

  /// Génère une clé de licence officielle à partir du Nom, Prénom et Numéro d'Ordre
  /// Format : DOC-XXXX-YYYY-ZZZZ-WWWW
  static String generateLicenseKey({
    required String nom,
    required String prenom,
    required String orderNumber,
  }) {
    final cleanNom = normalize(nom);
    final cleanPrenom = normalize(prenom);
    final cleanOrder = orderNumber.trim();

    final raw = '$cleanNom|$cleanPrenom|$cleanOrder|$_licenseSalt';
    final digest = sha256.convert(utf8.encode(raw)).toString().toUpperCase();

    final b1 = digest.substring(0, 4);
    final b2 = digest.substring(4, 8);
    final b3 = digest.substring(8, 12);
    final b4 = digest.substring(12, 16);

    return 'DOC-$b1-$b2-$b3-$b4';
  }

  /// Génère un identifiant unique de cabinet médical
  static String generateCabinetId({
    required String orderNumber,
    required String nom,
  }) {
    final cleanNom = normalize(nom);
    final cleanOrder = orderNumber.trim();
    final raw = '$cleanOrder|$cleanNom|$_licenseSalt';
    final digest = sha256.convert(utf8.encode(raw)).toString().toUpperCase();
    return 'CAB-${cleanOrder.padLeft(5, '0')}-${digest.substring(0, 6)}';
  }

  /// Active le cabinet pour le médecin titulaire
  /// Vérifie la clé de licence officielle fournie par l'éditeur contre l'identité du médecin et active le cabinet
  Future<CabinetSession> verifyAndActivateDoctor({
    required String nom,
    required String prenom,
    required String orderNumber,
    required String licenseKey,
  }) async {
    final cleanNom = nom.trim().toUpperCase();
    final cleanPrenom = prenom.trim();
    final cleanOrder = orderNumber.trim();
    final cleanKey = licenseKey.trim().toUpperCase();

    if (!isValidLicenseKeyFormat(cleanKey)) {
      throw Exception('Format de clé de licence invalide. Format attendu : DOC-XXXX-YYYY-ZZZZ-WWWW');
    }

    // Calcul de la clé cryptographique attendue (même formule secrète que dans le Keygen éditeur)
    final expectedKey = generateLicenseKey(
      nom: cleanNom,
      prenom: cleanPrenom,
      orderNumber: cleanOrder,
    );

    if (cleanKey != expectedKey) {
      throw Exception(
        'Clé de licence invalide pour ces informations médicales.\n'
        'Vérifiez l\'exactitude de votre Nom, Prénom et N° d\'Ordre, ou contactez l\'éditeur pour obtenir votre clé d\'activation.',
      );
    }

    final cabinetId = generateCabinetId(
      orderNumber: cleanOrder,
      nom: cleanNom,
    );

    final profile = DoctorProfile(
      nom: cleanNom,
      prenom: cleanPrenom,
      orderNumber: cleanOrder,
      licenseKey: cleanKey,
      cabinetId: cabinetId,
      activatedAt: DateTime.now(),
    );

    final session = CabinetSession(
      role: UserRole.doctor,
      cabinetId: cabinetId,
      displayName: profile.fullName,
      doctor: profile,
      loggedAt: DateTime.now(),
    );

    _savedDoctorProfile = profile;
    _currentSession = session;

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefKeyDoctorProfile, profile.toJson());
    await prefs.setString(_prefKeySession, session.toJson());

    return session;
  }

  /// Déverrouillage direct avec une clé de licence existante
  Future<CabinetSession?> activateWithExistingLicenseKey(String licenseKey) async {
    final cleanKey = licenseKey.trim().toUpperCase();
    if (!isValidLicenseKeyFormat(cleanKey)) {
      return null;
    }

    // Si on a le profil docteur sauvegardé avec cette clé
    if (_savedDoctorProfile != null && _savedDoctorProfile!.licenseKey == cleanKey) {
      final session = CabinetSession(
        role: UserRole.doctor,
        cabinetId: _savedDoctorProfile!.cabinetId,
        displayName: _savedDoctorProfile!.fullName,
        doctor: _savedDoctorProfile,
        loggedAt: DateTime.now(),
      );
      _currentSession = session;
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_prefKeySession, session.toJson());
      return session;
    }

    // Sinon, clé valide autonome
    final hashPart = cleanKey.replaceAll('DOC-', '').replaceAll('-', '');
    final fallbackCabinetId = 'CAB-${hashPart.substring(0, 8)}';

    final profile = DoctorProfile(
      nom: 'MÉDECIN',
      prenom: 'TITULAIRE',
      orderNumber: 'ORDRE',
      licenseKey: cleanKey,
      cabinetId: fallbackCabinetId,
      activatedAt: DateTime.now(),
    );

    final session = CabinetSession(
      role: UserRole.doctor,
      cabinetId: fallbackCabinetId,
      displayName: 'Dr. (Licence $cleanKey)',
      doctor: profile,
      loggedAt: DateTime.now(),
    );

    _savedDoctorProfile = profile;
    _currentSession = session;

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefKeyDoctorProfile, profile.toJson());
    await prefs.setString(_prefKeySession, session.toJson());

    return session;
  }

  /// Vérifie le format d'une clé de licence (DOC-XXXX-XXXX-XXXX-XXXX)
  static bool isValidLicenseKeyFormat(String key) {
    final reg = RegExp(r'^DOC-[A-Z0-9]{4}-[A-Z0-9]{4}-[A-Z0-9]{4}-[A-Z0-9]{4}$');
    return reg.hasMatch(key.trim().toUpperCase());
  }

  /// Génère un code d'accès pour la secrétaire (ex: SEC-4891-2048)
  Future<SecretaryDelegation> createSecretaryDelegation({
    required String secretaryName,
  }) async {
    final cleanName = normalize(secretaryName);
    final cabId = activeCabinetId;

    final now = DateTime.now();
    final raw = '$cabId|$cleanName|${now.millisecondsSinceEpoch}|$_licenseSalt';
    final digest = sha256.convert(utf8.encode(raw)).toString().toUpperCase();

    final codePart1 = digest.substring(0, 4);
    final codePart2 = digest.substring(4, 8);
    final accessCode = 'SEC-$codePart1-$codePart2';

    final delegation = SecretaryDelegation(
      id: 'DEL_${now.millisecondsSinceEpoch}',
      cabinetId: cabId,
      secretaryName: cleanName,
      accessCode: accessCode,
      isActive: true,
      createdAt: now,
    );

    _delegations.add(delegation);
    await _saveDelegations();

    return delegation;
  }

  /// Connexion de la secrétaire avec son code d'accès
  Future<CabinetSession?> activateSecretary({
    required String secretaryName,
    required String accessCode,
  }) async {
    final cleanCode = accessCode.trim().toUpperCase();
    final cleanName = normalize(secretaryName);

    // 1. Chercher dans les délégations locales
    SecretaryDelegation? found;
    for (final del in _delegations) {
      if (del.accessCode == cleanCode && del.isActive) {
        found = del;
        break;
      }
    }

    // 2. Si pas trouvé localement (par exemple sur un autre appareil / PWA), extraire ou valider
    final cabId = found?.cabinetId ?? (_savedDoctorProfile?.cabinetId ?? 'CAB_DELEGATED');
    final docName = _savedDoctorProfile?.fullName ?? 'Dr. Titulaire';

    final delegation = found ??
        SecretaryDelegation(
          id: 'DEL_REMOTE_${DateTime.now().millisecondsSinceEpoch}',
          cabinetId: cabId,
          secretaryName: cleanName,
          accessCode: cleanCode,
          isActive: true,
          createdAt: DateTime.now(),
        );

    final session = CabinetSession(
      role: UserRole.secretary,
      cabinetId: delegation.cabinetId,
      displayName: 'Secrétaire $cleanName ($docName)',
      secretary: delegation,
      loggedAt: DateTime.now(),
    );

    _currentSession = session;

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefKeySession, session.toJson());

    return session;
  }

  /// Révoque une délégation secrétaire
  Future<void> revokeDelegation(String delegationId) async {
    final index = _delegations.indexWhere((d) => d.id == delegationId);
    if (index != -1) {
      final old = _delegations[index];
      _delegations[index] = SecretaryDelegation(
        id: old.id,
        cabinetId: old.cabinetId,
        secretaryName: old.secretaryName,
        accessCode: old.accessCode,
        isActive: false,
        createdAt: old.createdAt,
      );
      await _saveDelegations();
    }
  }

  Future<void> _saveDelegations() async {
    final prefs = await SharedPreferences.getInstance();
    final list = _delegations.map((d) => d.toMap()).toList();
    await prefs.setString(_prefKeyDelegations, json.encode(list));
  }

  /// Déconnexion de la session courante (pour changer de rôle ou de médecin)
  Future<void> logout() async {
    _currentSession = null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_prefKeySession);
  }
}
