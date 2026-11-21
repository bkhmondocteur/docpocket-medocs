import 'backup_storage_interface.dart';
import 'backup_storage_stub.dart'
    if (dart.library.io) 'backup_storage_io.dart'
    if (dart.library.html) 'backup_storage_web.dart';

BackupStorage getPlatformBackupStorage() => getBackupStorage();
