/// Métadonnées d'un fichier de sauvegarde DocPocket
class BackupFileInfo {
  final String path;
  final String filename;
  final DateTime date;
  final int sizeBytes;

  BackupFileInfo({
    required this.path,
    required this.filename,
    required this.date,
    required this.sizeBytes,
  });

  String get formattedSize {
    if (sizeBytes < 1024) return '$sizeBytes o';
    if (sizeBytes < 1024 * 1024) return '${(sizeBytes / 1024).toStringAsFixed(1)} Ko';
    return '${(sizeBytes / (1024 * 1024)).toStringAsFixed(1)} Mo';
  }

  String get formattedDate {
    final d = date.day.toString().padLeft(2, '0');
    final m = date.month.toString().padLeft(2, '0');
    final y = date.year.toString().padLeft(4, '0');
    final h = date.hour.toString().padLeft(2, '0');
    final min = date.minute.toString().padLeft(2, '0');
    final s = date.second.toString().padLeft(2, '0');
    return '$d/$m/$y à $h:$min:$s';
  }
}

/// Interface universelle de gestion du stockage des sauvegardes
abstract class BackupStorage {
  bool get isFileSystemSupported;
  Future<String?> pickDirectory();
  Future<String> getDefaultDirectory();
  Future<void> saveBackupFile(String dirPath, String filename, String content);
  Future<List<BackupFileInfo>> listBackupFiles(String dirPath);
  Future<void> deleteBackupFile(String filePath);
  Future<String> readBackupFile(String filePath);
}
