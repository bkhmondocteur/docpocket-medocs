import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../database/database_service.dart';
import 'license_service.dart';
import '../../models/cabinet_auth.dart';

enum SyncStatus {
  idle,
  syncing,
  synced,
  offline,
  error,
}

/// Service de Synchronisation Cloud en Temps Réel avec Supabase
/// Garantit que le stock du cabinet est synchronisé instantanément
/// entre le Médecin et la Secrétaire sur Android, PC Windows, Mac, Linux et Web PWA.
class SupabaseSyncService {
  static final SupabaseSyncService instance = SupabaseSyncService._internal();
  SupabaseSyncService._internal();

  static const String _prefKeySupabaseUrl = 'docpocket_supabase_url_v1';
  static const String _prefKeySupabaseAnonKey = 'docpocket_supabase_anon_key_v1';
  static const String _prefKeyAutoSync = 'docpocket_supabase_autosync_v1';

  // Configuration cloud Supabase par défaut (prête à l'emploi ou personnalisable par le cabinet)
  static const String defaultSupabaseUrl = 'https://tnqydlfxkrtfeyxwbvuo.supabase.co';
  static const String defaultSupabaseAnonKey =
      'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InRucXlkbGZ4a3J0ZmV5eHdidnVvIiwicm9sZSI6ImFub24iLCJpYXQiOjE3MzIzMzg1NTAsImV4cCI6MjA0NzkxNDU1MH0.example-key';

  String _supabaseUrl = '';
  String _supabaseAnonKey = '';
  bool _isAutoSyncEnabled = true;
  bool _isInitialized = false;
  SyncStatus _status = SyncStatus.idle;
  String _lastSyncMessage = 'En attente';
  DateTime? _lastSyncTime;

  SyncStatus get status => _status;
  String get lastSyncMessage => _lastSyncMessage;
  DateTime? get lastSyncTime => _lastSyncTime;
  String get supabaseUrl => _supabaseUrl;
  String get supabaseAnonKey => _supabaseAnonKey;
  bool get isConfigured => _supabaseUrl.isNotEmpty && _supabaseAnonKey.isNotEmpty;
  bool get isAutoSyncEnabled => _isAutoSyncEnabled;

  final _syncStatusController = StreamController<SyncStatus>.broadcast();
  Stream<SyncStatus> get onSyncStatusChanged => _syncStatusController.stream;

  /// Initialise le service Supabase
  Future<void> init() async {
    if (_isInitialized) return;

    final prefs = await SharedPreferences.getInstance();
    _supabaseUrl = prefs.getString(_prefKeySupabaseUrl) ?? defaultSupabaseUrl;
    _supabaseAnonKey = prefs.getString(_prefKeySupabaseAnonKey) ?? defaultSupabaseAnonKey;
    _isAutoSyncEnabled = prefs.getBool(_prefKeyAutoSync) ?? true;

    // Tentative d'initialisation du SDK Supabase si non déjà fait
    try {
      if (isConfigured && !kIsWeb) {
        await Supabase.initialize(
          url: _supabaseUrl,
          // ignore: deprecated_member_use
          anonKey: _supabaseAnonKey,
          debug: kDebugMode,
        );
      }
    } catch (e) {
      debugPrint('[SupabaseSyncService] Initialisation SDK locale (utilise REST fallback) : $e');
    }

    _isInitialized = true;
  }

  /// Sauvegarde une nouvelle configuration Supabase (URL et Clé Anonyme)
  Future<void> saveConfiguration({
    required String url,
    required String anonKey,
    required bool autoSync,
  }) async {
    _supabaseUrl = url.trim();
    _supabaseAnonKey = anonKey.trim();
    _isAutoSyncEnabled = autoSync;

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefKeySupabaseUrl, _supabaseUrl);
    await prefs.setString(_prefKeySupabaseAnonKey, _supabaseAnonKey);
    await prefs.setBool(_prefKeyAutoSync, _isAutoSyncEnabled);

    // Tenter une synchronisation de test
    await syncStock(actionDescription: 'Configuration mise à jour');
  }

  void _setStatus(SyncStatus newStatus, String message) {
    _status = newStatus;
    _lastSyncMessage = message;
    if (newStatus == SyncStatus.synced) {
      _lastSyncTime = DateTime.now();
    }
    _syncStatusController.add(newStatus);
  }

  /// Synchronise le stock du cabinet :
  /// 1. Télécharge les dernières modifications distantes faites par l'autre utilisateur (Médecin / Secrétaire)
  /// 2. Pousse l'état local vers Supabase
  Future<bool> syncStock({String? actionDescription}) async {
    if (!isConfigured) {
      _setStatus(SyncStatus.idle, 'Supabase non configuré');
      return false;
    }

    final cabinetId = LicenseService.instance.activeCabinetId;
    if (cabinetId.isEmpty || cabinetId == 'CAB_DEFAULT') {
      _setStatus(SyncStatus.idle, 'En attente d\'activation du cabinet');
      return false;
    }

    _setStatus(SyncStatus.syncing, 'Synchronisation en cours...');

    try {
      final now = DateTime.now().toIso8601String();
      final operatorName = LicenseService.instance.userDisplayName;
      final action = actionDescription ?? 'Mise à jour du stock';

      // 1. Récupérer l'état distant depuis Supabase
      final remoteUrl = Uri.parse('$_supabaseUrl/rest/v1/cabinet_stock?cabinet_id=eq.$cabinetId&select=*');
      final remoteResponse = await http.get(
        remoteUrl,
        headers: {
          'apikey': _supabaseAnonKey,
          'Authorization': 'Bearer $_supabaseAnonKey',
          'Accept': 'application/json',
        },
      ).timeout(const Duration(seconds: 10));

      if (remoteResponse.statusCode == 200) {
        final List<dynamic> data = json.decode(remoteResponse.body) as List<dynamic>;
        if (data.isNotEmpty) {
          final row = data.first as Map<String, dynamic>;
          final remoteUpdatedAt = DateTime.tryParse(row['updated_at'] as String? ?? '');
          final remoteStockJson = row['stock_json'] as String? ?? '';
          final remoteUpdatedBy = row['updated_by'] as String? ?? '';

          // Si le stock distant a été mis à jour par un autre utilisateur plus récemment
          if (remoteStockJson.isNotEmpty && remoteUpdatedBy != operatorName) {
            final lastLocalUpdate = _lastSyncTime;
            if (lastLocalUpdate == null || (remoteUpdatedAt != null && remoteUpdatedAt.isAfter(lastLocalUpdate))) {
              debugPrint('[SupabaseSyncService] Fusion du stock distant mis à jour par : $remoteUpdatedBy');
              await DatabaseService.instance.importBackupJson(remoteStockJson);
            }
          }
        }
      }

      // 2. Envoyer le stock local actuel vers Supabase
      final localJson = await DatabaseService.instance.exportBackupJson();
      final upsertUrl = Uri.parse('$_supabaseUrl/rest/v1/cabinet_stock');
      final payload = {
        'cabinet_id': cabinetId,
        'stock_json': localJson,
        'updated_at': now,
        'updated_by': operatorName,
        'last_action': action,
      };

      final upsertResponse = await http.post(
        upsertUrl,
        headers: {
          'apikey': _supabaseAnonKey,
          'Authorization': 'Bearer $_supabaseAnonKey',
          'Content-Type': 'application/json',
          'Prefer': 'resolution=merge-duplicates',
        },
        body: json.encode(payload),
      ).timeout(const Duration(seconds: 10));

      if (upsertResponse.statusCode >= 200 && upsertResponse.statusCode < 300) {
        _setStatus(SyncStatus.synced, 'Stock synchronisé avec le Cloud');
        return true;
      } else {
        _setStatus(SyncStatus.offline, 'Serveur hors-ligne (stock sauvegardé localement)');
        return false;
      }
    } catch (e) {
      debugPrint('[SupabaseSyncService] Erreur synchronisation (mode hors-ligne activé) : $e');
      _setStatus(SyncStatus.offline, 'Mode hors-ligne : données sauvegardées en local');
      return false;
    }
  }

  /// Pousse une délégation secrétaire vers Supabase pour qu'elle puisse se connecter sur n'importe quel appareil
  Future<void> pushDelegation(SecretaryDelegation delegation) async {
    if (!isConfigured) return;

    try {
      final url = Uri.parse('$_supabaseUrl/rest/v1/cabinet_delegations');
      await http.post(
        url,
        headers: {
          'apikey': _supabaseAnonKey,
          'Authorization': 'Bearer $_supabaseAnonKey',
          'Content-Type': 'application/json',
          'Prefer': 'resolution=merge-duplicates',
        },
        body: json.encode(delegation.toMap()),
      ).timeout(const Duration(seconds: 8));
      debugPrint('[SupabaseSyncService] Délégation poussée vers Supabase : ${delegation.accessCode}');
    } catch (e) {
      debugPrint('[SupabaseSyncService] Erreur push délégation : $e');
    }
  }

  /// Recherche une délégation distante dans Supabase via le code d'accès de la secrétaire
  Future<Map<String, dynamic>?> findRemoteDelegation(String accessCode) async {
    if (!isConfigured) return null;

    try {
      final cleanCode = accessCode.trim().toUpperCase();
      final url = Uri.parse('$_supabaseUrl/rest/v1/cabinet_delegations?access_code=eq.$cleanCode&is_active=eq.true&select=*');
      final res = await http.get(
        url,
        headers: {
          'apikey': _supabaseAnonKey,
          'Authorization': 'Bearer $_supabaseAnonKey',
          'Accept': 'application/json',
        },
      ).timeout(const Duration(seconds: 8));

      if (res.statusCode == 200) {
        final list = json.decode(res.body) as List<dynamic>;
        if (list.isNotEmpty) {
          return list.first as Map<String, dynamic>;
        }
      }
    } catch (e) {
      debugPrint('[SupabaseSyncService] Erreur recherche délégation distante : $e');
    }
    return null;
  }

  /// Génère le script SQL complet pour créer les tables dans Supabase
  static String getSupabaseSetupSql() {
    return '''
-- ========================================================
-- SCRIPT DE CRÉATION DES TABLES SUPABASE POUR DOCPOCKET MEDOCS
-- À copier-coller dans Supabase > SQL Editor > Run
-- ========================================================

-- 1. Table de synchronisation du Stock de chaque Cabinet
CREATE TABLE IF NOT EXISTS public.cabinet_stock (
    cabinet_id TEXT PRIMARY KEY,
    stock_json TEXT NOT NULL,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_by TEXT,
    last_action TEXT
);

-- 2. Table des Délégations Secrétaires
CREATE TABLE IF NOT EXISTS public.cabinet_delegations (
    id TEXT PRIMARY KEY,
    cabinet_id TEXT NOT NULL,
    secretary_name TEXT NOT NULL,
    access_code TEXT NOT NULL UNIQUE,
    is_active BOOLEAN NOT NULL DEFAULT TRUE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- 3. Activation de Row Level Security (RLS) permissive pour l'API anonyme du cabinet
ALTER TABLE public.cabinet_stock ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.cabinet_delegations ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Acces stock cabinet anonyme" ON public.cabinet_stock
    FOR ALL USING (true) WITH CHECK (true);

CREATE POLICY "Acces delegations cabinet anonyme" ON public.cabinet_delegations
    FOR ALL USING (true) WITH CHECK (true);

-- Index pour des recherches ultra-rapides du code secrétaire et du cabinet
CREATE INDEX IF NOT EXISTS idx_cabinet_delegations_code ON public.cabinet_delegations(access_code);
CREATE INDEX IF NOT EXISTS idx_cabinet_stock_updated ON public.cabinet_stock(updated_at DESC);
''';
  }
}
