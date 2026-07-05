import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:mizapos_mobile/services/accounting_service.dart';
import 'package:mizapos_mobile/services/cloud/storage/cloud_secure_storage.dart';
import 'package:mizapos_mobile/services/cloud/sync/background/models/sync_status_snapshot.dart';
import 'package:mizapos_mobile/services/cloud/sync/master_sync_constants.dart';
import 'package:mizapos_mobile/services/cloud/sync/products_sync_repository.dart';
import 'package:mizapos_mobile/services/database_service.dart';
import 'package:mizapos_mobile/services/device_binding.dart';
import 'package:sqflite/sqflite.dart';

/// قراءة/تحديث حالة المزامنة — outbox + sync_meta + runtime flags.
class SyncStatusService extends ChangeNotifier {
  SyncStatusService({
    DatabaseService? databaseService,
    AccountingService? accountingService,
    CloudSecureStorage? storage,
  })  : _databaseService = databaseService ?? DatabaseService(),
        _accountingService = accountingService,
        _storage = storage;

  final DatabaseService _databaseService;
  final AccountingService? _accountingService;
  final CloudSecureStorage? _storage;

  bool _isSyncing = false;
  int _retryCount = 0;
  SyncRuntimeState _runtimeState = SyncRuntimeState.idle;
  String? _lastError;
  DateTime? _lastPushAt;
  DateTime? _lastPullAt;

  bool get isSyncing => _isSyncing;
  int get retryCount => _retryCount;
  SyncRuntimeState get runtimeState => _runtimeState;

  void setSyncing(bool value) {
    if (_isSyncing == value) return;
    _isSyncing = value;
    notifyListeners();
  }

  void setRetryCount(int value) {
    if (_retryCount == value) return;
    _retryCount = value;
    notifyListeners();
  }

  void setRuntimeState(SyncRuntimeState state, {String? error}) {
    _runtimeState = state;
    _lastError = error;
    notifyListeners();
  }

  Future<void> recordPushSuccess(DateTime at) async {
    _lastPushAt = at;
    final ctx = await _resolveTenantContext();
    if (ctx != null) {
      await _writeMetaTimestamp(
        organizationId: ctx.companyId,
        branchId: ctx.branchId,
        lastPushedAt: at,
      );
    }
    notifyListeners();
  }

  Future<void> recordPullSuccess(DateTime at) async {
    _lastPullAt = at;
    notifyListeners();
  }

  Future<int> countPending() => _countByState(ProductsSyncRepository.syncStatePending);

  Future<int> countFailed() => _countByState(ProductsSyncRepository.syncStateFailed);

  Future<int> countSynced() => _countByState(ProductsSyncRepository.syncStateSynced);

  Future<SyncStatusSnapshot> snapshot() async {
    final ctx = await _resolveTenantContext();
    DateTime? pushAt = _lastPushAt;
    DateTime? pullAt = _lastPullAt;
    if (ctx != null) {
      final meta = await _readMetaTimestamps(ctx.companyId, ctx.branchId);
      pushAt ??= meta.lastPushedAt;
      pullAt ??= meta.lastPulledAt;
    }

    return SyncStatusSnapshot(
      pendingCount: await countPending(),
      syncedCount: await countSynced(),
      failedCount: await countFailed(),
      isSyncing: _isSyncing,
      retryCount: _retryCount,
      lastPushAt: pushAt,
      lastPullAt: pullAt,
      currentState: _runtimeState,
      lastError: _lastError,
    );
  }

  Future<void> resetRetryableFailedToPending() async {
    final db = await _databaseService.database;
    final now = DateTime.now().toIso8601String();
    for (final entityType in MasterSyncConstants.allSyncEntityTypes) {
      await db.rawUpdate(
        '''
        UPDATE sync_outbox
        SET sync_state = ?, last_sync_error = NULL, updated_at = ?
        WHERE sync_state = ?
          AND entity_type = ?
          AND (
            last_sync_error IS NULL
            OR last_sync_error NOT IN ('unauthorized', 'forbidden', 'validation_error', 'validation_failed', 'invalid_request', 'invalid_payload', 'bad_request')
          )
        ''',
        [
          ProductsSyncRepository.syncStatePending,
          now,
          ProductsSyncRepository.syncStateFailed,
          entityType,
        ],
      );
    }
    notifyListeners();
  }

  Future<int> _countByState(String state) async {
    final db = await _databaseService.database;
    final placeholders =
        List.filled(MasterSyncConstants.allSyncEntityTypes.length, '?').join(',');
    final rows = await db.rawQuery(
      'SELECT COUNT(*) AS c FROM sync_outbox WHERE sync_state = ? AND entity_type IN ($placeholders)',
      [state, ...MasterSyncConstants.allSyncEntityTypes],
    );
    return (rows.first['c'] as int?) ?? 0;
  }

  Future<SyncTenantContext?> _resolveTenantContext() async {
    final session = _accountingService?.session;
    final companyFromStorage = await _storage?.readCompanyId();
    final branchFromStorage = await _storage?.readBranchId();
    final companyId = (companyFromStorage?.trim().isNotEmpty ?? false)
        ? companyFromStorage!.trim()
        : session?.organizationId;
    final branchId = (branchFromStorage?.trim().isNotEmpty ?? false)
        ? branchFromStorage!.trim()
        : session?.branchId;
    if (companyId == null ||
        branchId == null ||
        companyId.isEmpty ||
        branchId.isEmpty) {
      return null;
    }
    return SyncTenantContext(companyId: companyId, branchId: branchId);
  }

  Future<_MetaTimestamps> _readMetaTimestamps(
    String organizationId,
    String branchId,
  ) async {
    final db = await _databaseService.database;
    final rows = await db.query(
      'sync_meta',
      columns: const ['last_pushed_at', 'last_pulled_at'],
      where: 'organization_id = ? AND branch_id = ? AND scope_key = ?',
      whereArgs: [
        organizationId,
        branchId,
        ProductsSyncRepository.scopeKeyProducts,
      ],
      limit: 1,
    );
    if (rows.isEmpty) {
      return const _MetaTimestamps();
    }
    return _MetaTimestamps(
      lastPushedAt: _parseDate(rows.first['last_pushed_at']),
      lastPulledAt: _parseDate(rows.first['last_pulled_at']),
    );
  }

  Future<void> _writeMetaTimestamp({
    required String organizationId,
    required String branchId,
    DateTime? lastPushedAt,
    DateTime? lastPulledAt,
  }) async {
    final db = await _databaseService.database;
    final existing = await db.query(
      'sync_meta',
      where: 'organization_id = ? AND branch_id = ? AND scope_key = ?',
      whereArgs: [
        organizationId,
        branchId,
        ProductsSyncRepository.scopeKeyProducts,
      ],
      limit: 1,
    );

    final now = DateTime.now().toIso8601String();
    if (existing.isEmpty) {
      await db.insert('sync_meta', {
        'organization_id': organizationId,
        'branch_id': branchId,
        'scope_key': ProductsSyncRepository.scopeKeyProducts,
        'last_pulled_sequence': 0,
        'last_pushed_sequence': 0,
        'cloud_version_catalog': 0,
        'cloud_version_invoices': 0,
        'cloud_version_users': 0,
        if (lastPushedAt != null) 'last_pushed_at': lastPushedAt.toIso8601String(),
        if (lastPulledAt != null) 'last_pulled_at': lastPulledAt.toIso8601String(),
        'updated_at': now,
      });
      return;
    }

    final row = Map<String, Object?>.from(existing.first);
    if (lastPushedAt != null) {
      row['last_pushed_at'] = lastPushedAt.toIso8601String();
    }
    if (lastPulledAt != null) {
      row['last_pulled_at'] = lastPulledAt.toIso8601String();
    }
    row['updated_at'] = now;
    await db.insert(
      'sync_meta',
      row,
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  DateTime? _parseDate(Object? raw) {
    if (raw == null) return null;
    return DateTime.tryParse(raw.toString());
  }
}

class SyncTenantContext {
  const SyncTenantContext({
    required this.companyId,
    required this.branchId,
  });

  final String companyId;
  final String branchId;
}

class _MetaTimestamps {
  const _MetaTimestamps({this.lastPushedAt, this.lastPulledAt});

  final DateTime? lastPushedAt;
  final DateTime? lastPulledAt;
}

/// tenant + device IDs لبدء push/pull.
class SyncContextResolver {
  SyncContextResolver({
    required CloudSecureStorage storage,
    AccountingService? accountingService,
    DatabaseService? databaseService,
  })  : _storage = storage,
        _accountingService = accountingService,
        _databaseService = databaseService ?? DatabaseService();

  final CloudSecureStorage _storage;
  final AccountingService? _accountingService;
  final DatabaseService _databaseService;

  Future<SyncRunContext?> resolve() async {
    final session = _accountingService?.session;
    final companyId = await _readCompanyId(session);
    final branchId = await _readBranchId(session);
    if (companyId == null || branchId == null) return null;

    final deviceId = await _resolveDeviceId();
    if (deviceId.isEmpty) return null;

    final accessToken = await _storage.readAccessToken();
    if (accessToken == null || accessToken.isEmpty) return null;

    return SyncRunContext(
      companyId: companyId,
      branchId: branchId,
      deviceId: deviceId,
    );
  }

  Future<String?> _readCompanyId(dynamic session) async {
    final fromStorage = await _storage.readCompanyId();
    if (fromStorage != null && fromStorage.trim().isNotEmpty) {
      return fromStorage.trim();
    }
    return session?.organizationId?.toString();
  }

  Future<String?> _readBranchId(dynamic session) async {
    final fromStorage = await _storage.readBranchId();
    if (fromStorage != null && fromStorage.trim().isNotEmpty) {
      return fromStorage.trim();
    }
    return session?.branchId?.toString();
  }

  Future<String> _resolveDeviceId() async {
    final fromStorage = await _storage.readDeviceId();
    if (fromStorage != null && fromStorage.trim().isNotEmpty) {
      return fromStorage.trim();
    }

    final db = await _databaseService.database;
    final installationId = await DeviceBinding.readInstallationId();
    final selfRows = await db.query(
      'sync_devices',
      columns: const ['cloud_device_id'],
      where: 'is_self = 1 AND cloud_device_id IS NOT NULL AND cloud_device_id != ?',
      whereArgs: [''],
      limit: 1,
    );
    if (selfRows.isNotEmpty) {
      final id = (selfRows.first['cloud_device_id'] ?? '').toString().trim();
      if (id.isNotEmpty) return id;
    }

    return installationId;
  }
}

class SyncRunContext {
  const SyncRunContext({
    required this.companyId,
    required this.branchId,
    required this.deviceId,
  });

  final String companyId;
  final String branchId;
  final String deviceId;
}
