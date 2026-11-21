import 'package:flutter_test/flutter_test.dart';
import 'package:docpocket_medocs/core/services/backup/backup_storage_interface.dart';

class MockBackupStorage implements BackupStorage {
  final Map<String, String> files = {};
  final List<BackupFileInfo> fileInfos = [];

  @override
  bool get isFileSystemSupported => true;

  @override
  Future<String?> pickDirectory() async => '/mock/backup/dir';

  @override
  Future<String> getDefaultDirectory() async => '/mock/backup/dir';

  @override
  Future<void> saveBackupFile(String dirPath, String filename, String content) async {
    files[filename] = content;
    fileInfos.insert(
      0,
      BackupFileInfo(
        path: '$dirPath/$filename',
        filename: filename,
        date: DateTime.now(),
        sizeBytes: content.length,
      ),
    );
  }

  @override
  Future<List<BackupFileInfo>> listBackupFiles(String dirPath) async {
    return List.from(fileInfos);
  }

  @override
  Future<void> deleteBackupFile(String filePath) async {
    fileInfos.removeWhere((f) => f.path == filePath);
    final fname = filePath.split('/').last;
    files.remove(fname);
  }

  @override
  Future<String> readBackupFile(String filePath) async {
    final fname = filePath.split('/').last;
    return files[fname] ?? '';
  }
}

void main() {
  test('Rotation stricte à 5 sauvegardes maximum (la 6ème écrase la plus ancienne)', () async {
    final storage = MockBackupStorage();
    const maxBackups = 5;

    // Simuler 7 sauvegardes successives
    for (int i = 1; i <= 7; i++) {
      final filename = 'docpocket_backup_20261121_07000$i.json';
      await storage.saveBackupFile('/mock/backup/dir', filename, '{"backup_version": $i}');

      final existing = await storage.listBackupFiles('/mock/backup/dir');
      if (existing.length > maxBackups) {
        for (int j = maxBackups; j < existing.length; j++) {
          await storage.deleteBackupFile(existing[j].path);
        }
      }
    }

    final remaining = await storage.listBackupFiles('/mock/backup/dir');

    // Il doit rester exactement 5 sauvegardes
    expect(remaining.length, equals(5));

    // La plus récente doit être 7
    expect(remaining.first.filename, equals('docpocket_backup_20261121_070007.json'));

    // La plus ancienne restante doit être 3 (les 1 et 2 ont été supprimées par rotation FIFO)
    expect(remaining.last.filename, equals('docpocket_backup_20261121_070003.json'));
  });
}
