import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../database/database_service.dart';
import 'backup/backup_storage.dart';
import 'backup/backup_storage_interface.dart';

/// Service de sauvegarde automatique rotative sécurisée pour DocPocket Medocs
/// - Suggère le choix d'un dossier dès le premier lancement
/// - Déclenche automatiquement une sauvegarde après chaque entrée, sortie ou modification
/// - Conserve strictement jusqu'à 5 sauvegardes (la 6ème écrase/supprime la plus ancienne)
class AutoBackupService extends ChangeNotifier {
  static final AutoBackupService instance = AutoBackupService._internal();
  AutoBackupService._internal();

  static const String _prefKeyBackupDir = 'docpocket_backup_directory_path';
  static const String _prefKeyPrompted = 'docpocket_backup_has_prompted_v2';
  static const int maxBackups = 5;

  final BackupStorage _storage = getPlatformBackupStorage();

  String? _backupDirectoryPath;
  bool _hasPrompted = false;
  bool _isBackingUp = false;
  DateTime? _lastBackupTime;
  String? _lastBackupFilename;

  bool get isFileSystemSupported => _storage.isFileSystemSupported;
  bool get hasPromptedForBackup => _hasPrompted;
  String? get currentBackupDirectory => _backupDirectoryPath;
  DateTime? get lastBackupTime => _lastBackupTime;
  String? get lastBackupFilename => _lastBackupFilename;
  bool get isBackingUp => _isBackingUp;

  /// Initialise le service et charge la configuration
  Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    _backupDirectoryPath = prefs.getString(_prefKeyBackupDir);
    _hasPrompted = prefs.getBool(_prefKeyPrompted) ?? false;

    // Si aucun dossier n'a été spécifié par l'utilisateur, définir le dossier sécurisé par défaut
    if (_backupDirectoryPath == null || _backupDirectoryPath!.trim().isEmpty) {
      try {
        _backupDirectoryPath = await _storage.getDefaultDirectory();
      } catch (_) {}
    }
  }

  /// Enregistre que la suggestion a été présentée
  Future<void> setHasPrompted(bool value) async {
    _hasPrompted = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefKeyPrompted, value);
    notifyListeners();
  }

  /// Permet à l'utilisateur de choisir un dossier via l'explorateur
  Future<bool> chooseBackupDirectory(BuildContext context) async {
    if (!_storage.isFileSystemSupported) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Version Web : les sauvegardes sont gérées automatiquement dans le navigateur.'),
          backgroundColor: Colors.teal,
        ),
      );
      await setHasPrompted(true);
      return true;
    }

    final selected = await _storage.pickDirectory();
    if (selected != null && selected.trim().isNotEmpty) {
      _backupDirectoryPath = selected.trim();
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_prefKeyBackupDir, _backupDirectoryPath!);
      await setHasPrompted(true);

      // Exécuter immédiatement une sauvegarde pour initialiser le dossier
      await triggerAutoBackup();
      notifyListeners();
      return true;
    }
    return false;
  }

  /// Déclenche la sauvegarde automatique avec rotation stricte sur 5 fichiers
  Future<void> triggerAutoBackup() async {
    if (_isBackingUp) return;
    _isBackingUp = true;

    try {
      if (_backupDirectoryPath == null || _backupDirectoryPath!.trim().isEmpty) {
        _backupDirectoryPath = await _storage.getDefaultDirectory();
      }
      final targetDir = _backupDirectoryPath!;

      // 1. Générer le snapshot JSON complet
      final content = await DatabaseService.instance.exportBackupJson();

      // 2. Nom de fichier horodaté précis
      final now = DateTime.now();
      final dateStr = DateFormat('yyyyMMdd_HHmmss').format(now);
      final filename = 'docpocket_backup_$dateStr.json';

      // 3. Enregistrer le nouveau fichier
      await _storage.saveBackupFile(targetDir, filename, content);
      _lastBackupTime = now;
      _lastBackupFilename = filename;

      // 4. Rotation stricte : lister et trier les fichiers
      final existingFiles = await _storage.listBackupFiles(targetDir);

      // Si le nombre de sauvegardes dépasse 5, supprimer les plus anciennes
      if (existingFiles.length > maxBackups) {
        for (int i = maxBackups; i < existingFiles.length; i++) {
          await _storage.deleteBackupFile(existingFiles[i].path);
        }
      }

      notifyListeners();
    } catch (e) {
      debugPrint('[AutoBackupService] Erreur lors de la sauvegarde automatique : $e');
    } finally {
      _isBackingUp = false;
    }
  }

  /// Retourne la liste des sauvegardes existantes (jusqu'à 5)
  Future<List<BackupFileInfo>> getExistingBackups() async {
    if (_backupDirectoryPath == null || _backupDirectoryPath!.trim().isEmpty) {
      _backupDirectoryPath = await _storage.getDefaultDirectory();
    }
    return await _storage.listBackupFiles(_backupDirectoryPath!);
  }

  /// Restaure les données à partir d'une sauvegarde
  Future<bool> restoreBackup(BackupFileInfo fileInfo) async {
    try {
      final jsonStr = await _storage.readBackupFile(fileInfo.path);
      if (jsonStr.trim().isEmpty) return false;

      await DatabaseService.instance.importBackupJson(jsonStr);
      // Après restauration, déclencher une nouvelle sauvegarde
      await triggerAutoBackup();
      notifyListeners();
      return true;
    } catch (e) {
      debugPrint('[AutoBackupService] Erreur restauration : $e');
      return false;
    }
  }
}
