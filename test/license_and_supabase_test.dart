import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:docpocket_medocs/core/services/license_service.dart';
import 'package:docpocket_medocs/core/services/supabase_sync_service.dart';
import 'package:docpocket_medocs/models/cabinet_auth.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
  });

  group('LicenseService - Génération de Clé et Délégation Secrétaire', () {
    test('Génération déterministe et format de la clé de licence médicale', () {
      final key1 = LicenseService.generateLicenseKey(
        nom: 'Ben Khalifa',
        prenom: 'Mohamed',
        orderNumber: '12345',
      );

      final key2 = LicenseService.generateLicenseKey(
        nom: 'BEN KHALIFA',
        prenom: 'MOHAMED',
        orderNumber: '12345',
      );

      expect(key1, equals(key2));
      expect(LicenseService.isValidLicenseKeyFormat(key1), isTrue);
      expect(key1.startsWith('DOC-'), isTrue);
      expect(key1.split('-').length, equals(5)); // DOC + 4 blocs de 4
    });

    test('Activation du profil Médecin avec clé de licence valide et rejet si clé erronée', () async {
      final licenseService = LicenseService.instance;
      await licenseService.init();

      // Clé officielle calculée par le Keygen éditeur
      final validKey = LicenseService.generateLicenseKey(
        nom: 'Ben Khalifa',
        prenom: 'Mohamed',
        orderNumber: '12345',
      );

      // 1. Rejet si clé erronée
      expect(
        () => licenseService.verifyAndActivateDoctor(
          nom: 'Ben Khalifa',
          prenom: 'Mohamed',
          orderNumber: '12345',
          licenseKey: 'DOC-0000-0000-0000-0000',
        ),
        throwsException,
      );

      // 2. Succès si clé valide
      final session = await licenseService.verifyAndActivateDoctor(
        nom: 'Ben Khalifa',
        prenom: 'Mohamed',
        orderNumber: '12345',
        licenseKey: validKey,
      );

      expect(session.role, equals(UserRole.doctor));
      expect(session.isDoctor, isTrue);
      expect(session.isSecretary, isFalse);
      expect(session.displayName, equals('Dr. BEN KHALIFA Mohamed'));
      expect(session.cabinetId.startsWith('CAB-12345'), isTrue);
      expect(licenseService.isAuthenticated, isTrue);
      expect(licenseService.activeCabinetId, equals(session.cabinetId));
    });

    test('Génération du code d\'accès Secrétaire et connexion Secrétaire', () async {
      final licenseService = LicenseService.instance;
      await licenseService.init();

      final validKey = LicenseService.generateLicenseKey(
        nom: 'Ben Khalifa',
        prenom: 'Mohamed',
        orderNumber: '12345',
      );

      await licenseService.verifyAndActivateDoctor(
        nom: 'Ben Khalifa',
        prenom: 'Mohamed',
        orderNumber: '12345',
        licenseKey: validKey,
      );

      final delegation = await licenseService.createSecretaryDelegation(
        secretaryName: 'Sonia Ben Ali',
      );

      expect(delegation.secretaryName, equals('SONIA BEN ALI'));
      expect(delegation.accessCode.startsWith('SEC-'), isTrue);
      expect(delegation.isActive, isTrue);
      expect(licenseService.delegations.length, equals(1));

      // Connexion de la secrétaire avec ce code
      final secSession = await licenseService.activateSecretary(
        secretaryName: 'Sonia Ben Ali',
        accessCode: delegation.accessCode,
      );

      expect(secSession, isNotNull);
      expect(secSession!.role, equals(UserRole.secretary));
      expect(secSession.isSecretary, isTrue);
      expect(secSession.isDoctor, isFalse);
      expect(secSession.cabinetId, equals(licenseService.activeCabinetId));
    });
  });

  group('SupabaseSyncService - Configuration et Script SQL', () {
    test('Initialisation et génération du script SQL Supabase', () async {
      final sync = SupabaseSyncService.instance;
      await sync.init();

      expect(sync.isConfigured, isTrue);
      expect(sync.isAutoSyncEnabled, isTrue);

      final sql = SupabaseSyncService.getSupabaseSetupSql();
      expect(sql.contains('CREATE TABLE IF NOT EXISTS public.cabinet_stock'), isTrue);
      expect(sql.contains('CREATE TABLE IF NOT EXISTS public.cabinet_delegations'), isTrue);
      expect(sql.contains('ENABLE ROW LEVEL SECURITY'), isTrue);
    });
  });
}
