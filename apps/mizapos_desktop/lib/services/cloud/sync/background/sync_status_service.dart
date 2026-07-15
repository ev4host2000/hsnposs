import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:mizapos_desktop/services/accounting_service.dart';
import 'package:mizapos_desktop/services/cloud/storage/cloud_secure_storage.dart';
import 'package:mizapos_desktop/services/cloud/sync/background/models/failed_outbox_detail.dart';
import 'package:mizapos_desktop/services/cloud/sync/background/models/sync_progress_report.dart';
import 'package:mizapos_desktop/services/cloud/sync/background/models/sync_status_snapshot.dart';
import 'package:mizapos_desktop/services/cloud/sync/master_sync_constants.dart';
import 'package:mizapos_desktop/services/cloud/sync/products_sync_repository.dart';
import 'package:mizapos_desktop/services/cloud/sync/sync_meta_writer.dart';
import 'package:mizapos_desktop/services/cloud/sync/sync_outbox_claimer.dart';
import 'package:mizapos_desktop/services/database_service.dart';
import 'package:mizapos_desktop/services/device_binding.dart';

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
  SyncProgressReport? _progress;

  bool get isSyncing => _isSyncing;
  int get retryCount => _retryCount;
  SyncRuntimeState get runtimeState => _runtimeState;
  SyncProgressReport? get progress => _progress;

  void setProgress(SyncProgressReport? report) {
    _progress = report;
    notifyListeners();
  }

  void clearProgress() {
    if (_progress == null) return;
    _progress = null;
    notifyListeners();
  }

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

  Future<int> countPending() => _countByStates(const [
        ProductsSyncRepository.syncStatePending,
        SyncOutboxClaimer.syncStateInFlight,
      ]);

  Future<int> countFailed() => _countByState(ProductsSyncRepository.syncStateFailed);

  Future<List<FailedOutboxDetail>> fetchFailedDetails({int limit = 50}) async {
    final db = await _databaseService.database;
    final placeholders =
        List.filled(MasterSyncConstants.allSyncEntityTypes.length, '?').join(',');
    final rows = await db.rawQuery(
      '''
      SELECT entity_type, operation, entity_id, last_sync_error, updated_at
      FROM sync_outbox
      WHERE sync_state = ? AND entity_type IN ($placeholders)
      ORDER BY updated_at DESC
      LIMIT ?
      ''',
      [
        ProductsSyncRepository.syncStateFailed,
        ...MasterSyncConstants.allSyncEntityTypes,
        limit,
      ],
    );
    return rows
        .map(
          (row) => FailedOutboxDetail(
            entityType: (row['entity_type'] ?? '').toString(),
            operation: (row['operation'] ?? '').toString(),
            entityId: (row['entity_id'] ?? '').toString(),
            error: (row['last_sync_error'] ?? '').toString().trim().isEmpty
                ? 'unknown'
                : (row['last_sync_error'] ?? '').toString(),
            updatedAt: _parseDate(row['updated_at']),
          ),
        )
        .toList();
  }

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
      deferredPullCount: ctx == null
          ? 0
          : await countDeferredPull(
              organizationId: ctx.companyId,
              branchId: ctx.branchId,
            ),
      isSyncing: _isSyncing,
      retryCount: _retryCount,
      lastPushAt: pushAt,
      lastPullAt: pullAt,
      currentState: _runtimeState,
      lastError: _lastError,
      progress: _progress,
    );
  }

  Future<int> countDeferredPull({
    required String organizationId,
    required String branchId,
  }) async {
    try {
      final db = await _databaseService.database;
      final rows = await db.rawQuery(
        'SELECT COUNT(*) AS c FROM sync_deferred_pull '
        'WHERE organization_id = ? AND branch_id = ?',
        [organizationId, branchId],
      );
      return (rows.first['c'] as int?) ?? 0;
    } on Object {
      return 0;
    }
  }

  Future<int> countDeferredPullActive() async {
    final ctx = await _resolveTenantContext();
    if (ctx == null) return 0;
    return countDeferredPull(
      organizationId: ctx.companyId,
      branchId: ctx.branchId,
    );
  }

  Future<void> recoverStaleOutboxClaims() async {
    final db = await _databaseService.database;
    await SyncOutboxClaimer.recoverStaleInFlight(
      db,
      pendingState: ProductsSyncRepository.syncStatePending,
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
            OR last_sync_error NOT IN ('unauthorized', 'forbidden', 'validation_error', 'validation_failed', 'invalid_request', 'invalid_payload', 'bad_request', 'version_conflict')
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
    return _countByStates([state]);
  }

  Future<int> _countByStates(List<String> states) async {
    if (states.isEmpty) return 0;
    final db = await _databaseService.database;
    final entityPlaceholders =
        List.filled(MasterSyncConstants.allSyncEntityTypes.length, '?').join(',');
    final statePlaceholders = List.filled(states.length, '?').join(',');
    final rows = await db.rawQuery(
      'SELECT COUNT(*) AS c FROM sync_outbox '
      'WHERE sync_state IN ($statePlaceholders) '
      'AND entity_type IN ($entityPlaceholders)',
      [...states, ...MasterSyncConstants.allSyncEntityTypes],
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
    await SyncMetaWriter.upsertTimestamps(
      db,
      organizationId: organizationId,
      branchId: branchId,
      scopeKey: ProductsSyncRepository.scopeKeyProducts,
      lastPushedAt: lastPushedAt,
      lastPulledAt: lastPulledAt,
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
