import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

/// يحدّد أي ملف SQLite يُستخدم — منفصل بالكامل بين الإنتاج والتطوير والاختبارات.
enum DatabaseRuntimeProfile {
  production,
  development,
  integrationTest,
  unitTest,
}

/// إعداد مسار قاعدة البيانات حسب البيئة.
class DatabaseRuntimeConfig {
  DatabaseRuntimeConfig._();

  static DatabaseRuntimeProfile _profile = DatabaseRuntimeProfile.production;
  static String? _testDirectoryOverride;

  static DatabaseRuntimeProfile get activeProfile =>
      _testDirectoryOverride != null ? _profile : _resolveFromEnvironment();

  static bool get isTestProfile =>
      activeProfile == DatabaseRuntimeProfile.integrationTest ||
      activeProfile == DatabaseRuntimeProfile.unitTest;

  static bool get isProductionProfile =>
      activeProfile == DatabaseRuntimeProfile.production;

  /// `--dart-define=MIZAPOS_DB_PROFILE=development|production`
  static DatabaseRuntimeProfile _resolveFromEnvironment() {
    const fromDefine = String.fromEnvironment('MIZAPOS_DB_PROFILE');
    switch (fromDefine.trim().toLowerCase()) {
      case 'development':
      case 'dev':
        return DatabaseRuntimeProfile.development;
      case 'production':
      case 'prod':
        return DatabaseRuntimeProfile.production;
      default:
        return DatabaseRuntimeProfile.production;
    }
  }

  static void configureForTesting({
    required DatabaseRuntimeProfile profile,
    required String directory,
  }) {
    assert(
      profile == DatabaseRuntimeProfile.integrationTest ||
          profile == DatabaseRuntimeProfile.unitTest,
      'Only test profiles may override the database directory.',
    );
    final normalized = Directory(directory).absolute.path.toLowerCase();
    if (normalized.contains('mizapos${Platform.pathSeparator}data') &&
        !normalized.contains('dev-data') &&
        !normalized.contains('test_sqlite')) {
      throw StateError(
        'Refusing to run tests against production database path: $directory',
      );
    }
    _profile = profile;
    _testDirectoryOverride = directory.trim();
  }

  static void resetForTesting() {
    _profile = DatabaseRuntimeProfile.production;
    _testDirectoryOverride = null;
  }

  /// مجلد ملف `mizapos.db` — لا يُسمح للاختبارات باستخدام مسار الإنتاج.
  static Future<String> databaseDirectory() async {
    final profile = activeProfile;
    if (profile == DatabaseRuntimeProfile.integrationTest ||
        profile == DatabaseRuntimeProfile.unitTest) {
      final override = _testDirectoryOverride;
      if (override == null || override.isEmpty) {
        throw StateError(
          'Test profile $profile requires configureForTesting(directory: ...).',
        );
      }
      final dir = Directory(override);
      if (!dir.existsSync()) {
        await dir.create(recursive: true);
      }
      return override;
    }
    if (profile == DatabaseRuntimeProfile.development) {
      return _persistentSubdirectory('dev-data');
    }
    return _persistentSubdirectory('data');
  }

  static Future<String> databaseFilePath() async {
    return p.join(await databaseDirectory(), 'mizapos.db');
  }

  static String profileLabel(DatabaseRuntimeProfile profile) {
    switch (profile) {
      case DatabaseRuntimeProfile.production:
        return 'production';
      case DatabaseRuntimeProfile.development:
        return 'development';
      case DatabaseRuntimeProfile.integrationTest:
        return 'integration_test';
      case DatabaseRuntimeProfile.unitTest:
        return 'unit_test';
    }
  }

  static Future<String> _persistentSubdirectory(String subdir) async {
    if (Platform.isWindows) {
      final base = Platform.environment['LOCALAPPDATA'] ??
          Platform.environment['APPDATA'] ??
          Directory.current.path;
      final dir = p.join(base, 'MizaPos', subdir);
      await Directory(dir).create(recursive: true);
      return dir;
    }
    if (Platform.isLinux || Platform.isMacOS) {
      final home = Platform.environment['HOME'] ?? Directory.current.path;
      final folder = subdir == 'data' ? 'data' : 'dev-data';
      final dir = p.join(home, '.mizapos', folder);
      await Directory(dir).create(recursive: true);
      return dir;
    }
    return await getDatabasesPath();
  }
}
