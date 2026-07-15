import 'package:sqflite/sqflite.dart';

import 'package:mizapos_desktop/services/cloud/models/cloud_device.dart';
import 'package:mizapos_desktop/services/database_service.dart';

/// كتابة صف «هذا الجهاز» في جدول sync_devices المحلي.
class CloudDeviceLocalStore {
  CloudDeviceLocalStore._();

  static Future<void> upsertSelfDevice({
    required CloudDevice device,
    required String organizationId,
    required String branchId,
    required String installationId,
    String? deviceName,
    String? platform,
    String? osName,
    String? appVersion,
  }) async {
    final db = await DatabaseService().database;
    final now = DateTime.now().toUtc().toIso8601String();
    final cloudId = device.id.trim();
    if (cloudId.isEmpty) return;

    await db.transaction((txn) async {
      await txn.update(
        'sync_devices',
        {'is_self': 0},
        where: 'organization_id = ? AND is_self = 1',
        whereArgs: [organizationId],
      );

      await txn.insert(
        'sync_devices',
        {
          'id': installationId,
          'organization_id': organizationId,
          'branch_id': branchId,
          'installation_id': installationId,
          'cloud_device_id': cloudId,
          'device_name': deviceName ?? device.deviceName,
          'platform': platform ?? device.platform,
          'os_name': osName ?? device.osName,
          'app_version': appVersion ?? device.appVersion,
          'status': device.status.isNotEmpty ? device.status : 'active',
          'is_self': 1,
          'registered_at': device.registeredAt.isNotEmpty
              ? device.registeredAt
              : now,
          'last_seen_at': now,
          'updated_at': now,
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    });
  }
}
