import 'dart:io';

import 'package:mizapos_mobile/services/database_runtime_profile.dart';
import 'package:mizapos_mobile/services/database_service.dart';
import 'package:mizapos_mobile/utils/app_data_paths.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

Directory? _isolatedTestDbDir;
DatabaseRuntimeProfile? _isolatedTestProfile;

/// يوجّه [DatabaseService] إلى SQLite معزول — لا يمس مسار الإنتاج.
Future<void> setUpIsolatedTestDatabase({
  DatabaseRuntimeProfile profile = DatabaseRuntimeProfile.unitTest,
}) async {
  assert(
    profile == DatabaseRuntimeProfile.integrationTest ||
        profile == DatabaseRuntimeProfile.unitTest,
  );
  await tearDownIsolatedTestDatabase();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;
  _isolatedTestProfile = profile;
  _isolatedTestDbDir =
      await Directory.systemTemp.createTemp('mizapos_test_sqlite_');
  if (profile == DatabaseRuntimeProfile.integrationTest) {
    DatabaseService.setIntegrationTestDatabaseDirectory(_isolatedTestDbDir!.path);
  } else {
    DatabaseService.setTestDatabaseDirectory(_isolatedTestDbDir!.path);
  }
  await initAppDataDirectory();
}

/// يحذف ملف SQLite المعزول ويعيد فتح مخطط فارغاً (نفس مجلد الاختبار).
Future<void> resetIsolatedTestDatabaseFile() async {
  await DatabaseService.closeConnectionForTesting();
  if (_isolatedTestDbDir == null || _isolatedTestProfile == null) {
    throw StateError(
      'resetIsolatedTestDatabaseFile requires setUpIsolatedTestDatabase first.',
    );
  }
  final dbFile = File(
    '${_isolatedTestDbDir!.path}${Platform.pathSeparator}mizapos.db',
  );
  if (await dbFile.exists()) {
    await dbFile.delete();
  }
  if (_isolatedTestProfile == DatabaseRuntimeProfile.integrationTest) {
    DatabaseService.setIntegrationTestDatabaseDirectory(_isolatedTestDbDir!.path);
  } else {
    DatabaseService.setTestDatabaseDirectory(_isolatedTestDbDir!.path);
  }
}

Future<void> tearDownIsolatedTestDatabase() async {
  await DatabaseService.closeAndResetForTesting();
  if (_isolatedTestDbDir != null) {
    try {
      await _isolatedTestDbDir!.delete(recursive: true);
    } on Object {
      /* ignore */
    }
    _isolatedTestDbDir = null;
  }
  _isolatedTestProfile = null;
}
