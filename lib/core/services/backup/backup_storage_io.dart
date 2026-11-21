import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import 'backup_storage_interface.dart';

BackupStorage getBackupStorage() => BackupStorageIo();

class BackupStorageIo implements BackupStorage {
  @override
  bool get isFileSystemSupported => true;

  @override
  Future<String?> pickDirectory() async {
    try {
      // ignore: deprecated_member_use
      final selected = await FilePicker.getDirectoryPath(
        dialogTitle: 'Sélectionnez le dossier de sauvegarde DocPocket',
      );
      return selected;
    } catch (_) {
      return null;
    }
  }

  @override
  Future<String> getDefaultDirectory() async {
    try {
      final appDocDir = await getApplicationDocumentsDirectory();
      final backupDir = Directory(p.join(appDocDir.path, 'DocPocket_Backups'));
      if (!await backupDir.exists()) {
        await backupDir.create(recursive: true);
      }
      return backupDir.path;
    } catch (_) {
      // Fallback au dossier temporaire si inaccessible
      final temp = await getTemporaryDirectory();
      return temp.path;
    }
  }

  @override
  Future<void> saveBackupFile(String dirPath, String filename, String content) async {
    final dir = Directory(dirPath);
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    final file = File(p.join(dirPath, filename));
    await file.writeAsString(content, flush: true);
  }

  @override
  Future<List<BackupFileInfo>> listBackupFiles(String dirPath) async {
    final dir = Directory(dirPath);
    if (!await dir.exists()) return [];

    final list = <BackupFileInfo>[];
    try {
      final entities = dir.listSync();
      for (final entity in entities) {
        if (entity is File) {
          final name = p.basename(entity.path);
          if (name.startsWith('docpocket_backup_') && name.endsWith('.json')) {
            final stat = entity.statSync();
            list.add(BackupFileInfo(
              path: entity.path,
              filename: name,
              date: stat.modified,
              sizeBytes: stat.size,
            ));
          }
        }
      }
    } catch (_) {
      return [];
    }

    // Tri décroissant : de la plus récente à la plus ancienne
    list.sort((a, b) => b.date.compareTo(a.date));
    return list;
  }

  @override
  Future<void> deleteBackupFile(String filePath) async {
    try {
      final file = File(filePath);
      if (await file.exists()) {
        await file.delete();
      }
    } catch (_) {}
  }

  @override
  Future<String> readBackupFile(String filePath) async {
    final file = File(filePath);
    return await file.readAsString();
  }
}
