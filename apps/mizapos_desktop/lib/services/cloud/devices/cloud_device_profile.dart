import 'dart:io';

import 'package:mizapos_desktop/services/cloud/core/cloud_runtime.dart';
import 'package:mizapos_desktop/services/cloud/devices/cloud_device_local_store.dart';
import 'package:mizapos_desktop/services/cloud/storage/cloud_secure_storage.dart';
import 'package:mizapos_desktop/services/database_service.dart';
import 'package:mizapos_desktop/services/device_binding.dart';

/// اسم الجهاز ومعرّفه للعرض في شاشة Miza Cloud.
class CloudDeviceProfile {
  const CloudDeviceProfile({this.deviceName, this.deviceId});

  final String? deviceName;
  final String? deviceId;
}

/// يقرأ sync_devices ويستكمل الاسم من السحابة أو اسم افتراضي محلي.
class CloudDeviceProfileLoader {
  CloudDeviceProfileLoader._();

  static Future<CloudDeviceProfile> load({
    CloudSecureStorage? storage,
    bool fetchRemoteName = true,
  }) async {
    final secureStorage = storage ?? CloudRuntime.instance?.storage;
    String? deviceId = await secureStorage?.readDeviceId();
    final installationId = await DeviceBinding.readInstallationId();

    String? deviceName;
    String? platform;
    String? organizationId;
    String? branchId;
    String? selfRowId;

    try {
      final db = await DatabaseService().database;
      final rows = await db.query(
        'sync_devices',
        columns: const [
          'id',
          'device_name',
          'cloud_device_id',
          'platform',
          'organization_id',
          'branch_id',
        ],
        where: 'is_self = 1',
        limit: 1,
      );
      if (rows.isNotEmpty) {
        final row = rows.first;
        selfRowId = (row['id'] ?? '').toString();
        final name = (row['device_name'] ?? '').toString().trim();
        if (name.isNotEmpty) deviceName = name;
        final cloudId = (row['cloud_device_id'] ?? '').toString().trim();
        if (cloudId.isNotEmpty) deviceId ??= cloudId;
        platform = (row['platform'] ?? '').toString().trim();
        organizationId = (row['organization_id'] ?? '').toString().trim();
        branchId = (row['branch_id'] ?? '').toString().trim();
      }

      if (deviceName == null && deviceId != null && deviceId.isNotEmpty) {
        final byCloud = await db.query(
          'sync_devices',
          columns: const ['id', 'device_name', 'platform', 'organization_id', 'branch_id'],
          where: 'cloud_device_id = ?',
          whereArgs: [deviceId],
          limit: 1,
        );
        if (byCloud.isNotEmpty) {
          final row = byCloud.first;
          selfRowId ??= (row['id'] ?? '').toString();
          final name = (row['device_name'] ?? '').toString().trim();
          if (name.isNotEmpty) deviceName = name;
          platform ??= (row['platform'] ?? '').toString().trim();
          organizationId ??= (row['organization_id'] ?? '').toString().trim();
          branchId ??= (row['branch_id'] ?? '').toString().trim();
        }
      }
    } on Object {
      // عرض ما توفر من التخزين الآمن فقط.
    }

    organizationId ??= (await secureStorage?.readCompanyId())?.trim();
    branchId ??= (await secureStorage?.readBranchId())?.trim();

    if (fetchRemoteName &&
        (deviceName == null || deviceName.isEmpty) &&
        deviceId != null &&
        deviceId.isNotEmpty) {
      try {
        final runtime = CloudRuntime.instance;
        final cloudDevice = await runtime?.deviceManager.fetchMe();
        final remoteName = cloudDevice?.deviceName?.trim();
        if (remoteName != null && remoteName.isNotEmpty) {
          deviceName = remoteName;
          if (organizationId != null &&
              organizationId.isNotEmpty &&
              branchId != null &&
              branchId.isNotEmpty &&
              cloudDevice != null) {
            await CloudDeviceLocalStore.upsertSelfDevice(
              device: cloudDevice,
              organizationId: organizationId,
              branchId: branchId,
              installationId: installationId,
              deviceName: remoteName,
              platform: platform,
            );
          }
        }
      } on Object {
        // تجاهل — نستخدم الاسم الافتراضي.
      }
    }

    deviceName ??= _defaultDisplayName(platform: platform);

    if (deviceName.isNotEmpty &&
        selfRowId != null &&
        selfRowId.isNotEmpty) {
      try {
        final db = await DatabaseService().database;
        await db.update(
          'sync_devices',
          {
            'device_name': deviceName,
            'updated_at': DateTime.now().toUtc().toIso8601String(),
          },
          where: 'id = ?',
          whereArgs: [selfRowId],
        );
      } on Object {
        // لا يؤثر على العرض.
      }
    }

    return CloudDeviceProfile(deviceName: deviceName, deviceId: deviceId);
  }

  static String _defaultDisplayName({String? platform}) {
    final normalized = (platform ?? DeviceBinding.readDevicePlatform()).toLowerCase();
    if (normalized == 'android' || Platform.isAndroid) {
      return 'Android';
    }
    final computerName = Platform.environment['COMPUTERNAME']?.trim();
    if (computerName != null && computerName.isNotEmpty) {
      return computerName;
    }
    return 'Windows';
  }
}
