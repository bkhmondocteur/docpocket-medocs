import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'backup_storage_interface.dart';

BackupStorage getBackupStorage() => BackupStorageWeb();

class BackupStorageWeb implements BackupStorage {
  static const String _webBackupsKey = 'docpocket_web_backups_metadata';

  @override
  bool get isFileSystemSupported => false;

  @override
  Future<String?> pickDirectory() async => 'Stockage local du navigateur (Web)';

  @override
  Future<String> getDefaultDirectory() async => 'Stockage local du navigateur (Web)';

  @override
  Future<void> saveBackupFile(String dirPath, String filename, String content) async {
    final prefs = await SharedPreferences.getInstance();
    final existing = await listBackupFiles(dirPath);

    final rawList = <Map<String, dynamic>>[];
    rawList.add({
      'path': filename,
      'filename': filename,
      'date': DateTime.now().toIso8601String(),
      'size': utf8.encode(content).length,
    });
    await prefs.setString('web_backup_content_$filename', content);

    for (final b in existing) {
      rawList.add({
        'path': b.filename,
        'filename': b.filename,
        'date': b.date.toIso8601String(),
        'size': b.sizeBytes,
      });
    }

    // Garder strictement 5 sauvegardes maximum (la 6ème est supprimée)
    if (rawList.length > 5) {
      for (int i = 5; i < rawList.length; i++) {
        final oldFile = rawList[i]['filename'] as String;
        await prefs.remove('web_backup_content_$oldFile');
      }
      rawList.removeRange(5, rawList.length);
    }

    await prefs.setString(_webBackupsKey, json.encode(rawList));
  }

  @override
  Future<List<BackupFileInfo>> listBackupFiles(String dirPath) async {
    final prefs = await SharedPreferences.getInstance();
    final jsonStr = prefs.getString(_webBackupsKey);
    if (jsonStr == null || jsonStr.isEmpty) return [];

    try {
      final list = json.decode(jsonStr) as List<dynamic>;
      final result = <BackupFileInfo>[];
      for (final item in list) {
        final map = item as Map<String, dynamic>;
        result.add(BackupFileInfo(
          path: map['path'] as String,
          filename: map['filename'] as String,
          date: DateTime.parse(map['date'] as String),
          sizeBytes: map['size'] as int? ?? 0,
        ));
      }
      result.sort((a, b) => b.date.compareTo(a.date));
      return result;
    } catch (_) {
      return [];
    }
  }

  @override
  Future<void> deleteBackupFile(String filePath) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('web_backup_content_$filePath');
    final files = await listBackupFiles('');
    files.removeWhere((f) => f.path == filePath || f.filename == filePath);
    final meta = files.map((f) => {
      'path': f.path,
      'filename': f.filename,
      'date': f.date.toIso8601String(),
      'size': f.sizeBytes,
    }).toList();
    await prefs.setString(_webBackupsKey, json.encode(meta));
  }

  @override
  Future<String> readBackupFile(String filePath) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('web_backup_content_$filePath') ?? '';
  }
}
