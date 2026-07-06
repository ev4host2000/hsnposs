import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:mizapos_desktop/security/password_crypto.dart';
import 'package:mizapos_desktop/services/database_runtime_profile.dart';
import 'package:mizapos_desktop/services/license_gate.dart';
import 'package:mizapos_desktop/utils/app_data_paths.dart';
import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';

class DatabaseService {
  static final DatabaseService _instance = DatabaseService._internal();
  static Database? _database;
  bool _runtimeSchemaPatchesDone = false;

  /// معرّف مؤسسة اختبار التزامن — لا يُستخدم في بيانات الإنتاج المحلية.
  static const knownTestOrganizationId =
      '550e8400-e29b-41d4-a716-446655440000';

  DatabaseService._internal();

  factory DatabaseService() {
    return _instance;
  }

  Future<Database> get database async {
    if (_database != null) {
      await _applyRuntimeSchemaPatches(_database!);
      return _database!;
    }
    _database = await _initDatabase();
    await _applyRuntimeSchemaPatches(_database!);
    return _database!;
  }

  Future<void> _applyRuntimeSchemaPatches(Database db) async {
    if (_runtimeSchemaPatchesDone) return;
    await _addColumnIfMissing(
      db,
      'users',
      'distributorCloudEnabled',
      'INTEGER NOT NULL DEFAULT 0',
    );
    await _ensureFieldTruckTables(db);
    _runtimeSchemaPatchesDone = true;
  }

  /// إغلاق اتصال SQLite قبل إنهاء العملية (يسرّع الخروج على Windows).
  Future<void> closeDatabase() async {
    final db = _database;
    if (db == null) return;
    _database = null;
    _runtimeSchemaPatchesDone = false;
    try {
      await db.close();
    } on Object {
      /* ignore */
    }
  }

  /// بعد إنشاء المؤسسة/المالك (أو عند أول تشغيل) — يضمن صف «زائر».
  Future<void> ensureGuestUserIfMissing() async {
    final db = await database;
    await _ensureGuestUserRow(db);
  }

  /// حذف ملف قاعدة البيانات وإنشاء قاعدة فارغة جديدة (إعادة ضبط كامل).
  Future<void> wipeAndRecreateDatabase() async {
    if (_database != null) {
      await _database!.close();
      _database = null;
    }
    final path = await _resolveDatabasePath();
    final file = File(path);
    if (await file.exists()) {
      await file.delete();
    }
    _database = await _initDatabase();
  }

  Future<String> resolvedDatabasePath() => _resolveDatabasePath();

  Future<Database> _initDatabase() async {
    final path = await _resolveDatabasePath();
    return await openDatabase(
      path,
      version: 46,
      onCreate: _onCreate,
      onUpgrade: _onUpgrade,
    );
  }

  /// مجلد دائم لقاعدة البيانات — لا يُحذف بـ `flutter clean`.
  Future<String> _persistentDatabaseDirectory() async {
    return DatabaseRuntimeConfig.databaseDirectory();
  }

  /// نسخ أقدم قاعدة من مسارات التطوير القديمة إن كانت أنسب من الملف الجديد الفارغ.
  Future<void> _importLegacyDatabaseIfSmaller(String targetPath) async {
    if (DatabaseRuntimeConfig.isTestProfile) {
      return;
    }
    if (DatabaseRuntimeConfig.activeProfile ==
        DatabaseRuntimeProfile.development) {
      return;
    }
    final target = File(targetPath);
    final targetLen = await target.exists() ? await target.length() : 0;

    final legacyCandidates = <String>[
      join(
        Directory.current.path,
        '.dart_tool',
        'sqflite_common_ffi',
        'databases',
        'mizapos.db',
      ),
      join(
        Directory.current.path,
        '.dart_tool',
        'sqflite_common_ffi',
        'databases',
        'hsnposs.db',
      ),
      join(await getDatabasesPath(), 'mizapos.db'),
      join(await getDatabasesPath(), 'hsnposs.db'),
    ];

    String? bestPath;
    var bestLen = targetLen;
    for (final p in legacyCandidates) {
      final f = File(p);
      if (!await f.exists()) continue;
      final len = await f.length();
      if (len > bestLen + 4096) {
        bestLen = len;
        bestPath = p;
      }
    }

    if (bestPath == null) return;
    try {
      await File(bestPath).copy(targetPath);
    } catch (_) {
      /* قفل أو صلاحيات — نُكمل بالملف الحالي */
    }
  }

  /// يُرجع مسار قاعدة البيانات «mizapos.db» في مجلد دائم، مع ترحيل
  /// hsnposs.db القديم ونسخ أي نسخة تطوير أغنى عند الحاجة.
  Future<String> _resolveDatabasePath() async {
    final dir = await _persistentDatabaseDirectory();
    final newPath = join(dir, 'mizapos.db');
    final oldPath = join(dir, 'hsnposs.db');
    final newFile = File(newPath);
    final oldFile = File(oldPath);

    if (!await newFile.exists() && await oldFile.exists()) {
      try {
        await oldFile.rename(newPath);
      } on FileSystemException {
        return oldPath;
      }
    }

    if (!await newFile.exists()) {
      await _importLegacyDatabaseIfSmaller(newPath);
    } else {
      final len = await newFile.length();
      // قاعدة جديدة فارغة تقريباً — جرّب استيراد نسخة تطوير أقدم إن وُجدت.
      if (len < 120 * 1024) {
        await _importLegacyDatabaseIfSmaller(newPath);
      }
    }

    if (await newFile.exists()) return newPath;
    if (await oldFile.exists()) {
      try {
        await oldFile.rename(newPath);
        return newPath;
      } on FileSystemException {
        return oldPath;
      }
    }
    return newPath;
  }

  Future<void> _onCreate(Database db, int version) async {
    await _createV2Schema(db);
    if (version > 2) {
      await _onUpgrade(db, 2, version);
    }
  }

  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      await _dropLegacyTables(db);
      await _createV2Schema(db);
    }
    if (oldVersion < 3) {
      await _migrateToV3(db);
    }
    if (oldVersion < 4) {
      await _migrateToV4(db);
    }
    if (oldVersion < 5) {
      await _migrateToV5(db);
    }
    if (oldVersion < 6) {
      await _migrateToV6(db);
    }
    if (oldVersion < 7) {
      await _migrateToV7(db);
    }
    if (oldVersion < 8) {
      await _migrateToV8(db);
    }
    if (oldVersion < 9) {
      await _migrateToV9(db);
    }
    if (oldVersion < 10) {
      await _migrateToV10(db);
    }
    if (oldVersion < 11) {
      await _migrateToV11(db);
    }
    if (oldVersion < 12) {
      await _migrateToV12(db);
    }
    if (oldVersion < 13) {
      await _migrateToV13(db);
    }
    if (oldVersion < 14) {
      await _migrateToV14(db);
    }
    if (oldVersion < 15) {
      await _migrateToV15(db);
    }
    if (oldVersion < 16) {
      await _migrateToV16(db);
    }
    if (oldVersion < 17) {
      await _migrateToV17(db);
    }
    if (oldVersion < 18) {
      await _migrateToV18(db);
    }
    if (oldVersion < 19) {
      await _migrateToV19(db);
    }
    if (oldVersion < 20) {
      await _migrateToV20(db);
    }
    if (oldVersion < 21) {
      await _migrateToV21(db);
    }
    if (oldVersion < 22) {
      await _migrateToV22(db);
    }
    if (oldVersion < 23) {
      await _migrateToV23(db);
    }
    if (oldVersion < 24) {
      await _migrateToV24(db);
    }
    if (oldVersion < 25) {
      await _migrateToV25(db);
    }
    if (oldVersion < 26) {
      await _migrateToV26(db);
    }
    if (oldVersion < 27) {
      await _migrateToV27(db);
    }
    if (oldVersion < 28) {
      await _migrateToV28(db);
    }
    if (oldVersion < 29) {
      await _migrateToV29(db);
    }
    if (oldVersion < 30) {
      await _migrateToV30(db);
    }
    if (oldVersion < 31) {
      await _migrateToV31(db);
    }
    if (oldVersion < 32) {
      await _migrateToV32(db);
    }
    if (oldVersion < 33) {
      await _migrateToV33(db);
    }
    if (oldVersion < 34) {
      await _migrateToV34(db);
    }
    if (oldVersion < 35) {
      await _migrateToV35(db);
    }
    if (oldVersion < 36) {
      await _migrateToV36(db);
    }
    if (oldVersion < 37) {
      await _migrateToV37(db);
    }
    if (oldVersion < 38) {
      await _migrateToV38(db);
    }
    if (oldVersion < 39) {
      await _migrateToV39(db);
    }
    if (oldVersion < 40) {
      await _migrateToV40(db);
    }
    if (oldVersion < 41) {
      await _migrateToV41(db);
    }
    if (oldVersion < 42) {
      await _migrateToV42(db);
    }
    if (oldVersion < 43) {
      await _migrateToV43(db);
    }
    if (oldVersion < 44) {
      await _migrateToV44(db);
    }
    if (oldVersion < 45) {
      await _migrateToV45(db);
    }
    if (oldVersion < 46) {
      await _migrateToV46(db);
    }
  }

  Future<void> _migrateToV46(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS sync_outbox (
        id TEXT PRIMARY KEY,
        organization_id TEXT NOT NULL,
        branch_id TEXT NOT NULL,
        entity_type TEXT NOT NULL,
        entity_id TEXT NOT NULL,
        operation TEXT NOT NULL,
        sync_state TEXT NOT NULL DEFAULT 'pending',
        payload_json TEXT NOT NULL,
        client_row_version INTEGER NOT NULL DEFAULT 1,
        idempotency_key TEXT NOT NULL,
        cloud_batch_id TEXT,
        installation_id TEXT,
        last_sync_error TEXT,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        synced_at TEXT
      )
    ''');
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_sync_outbox_push '
      'ON sync_outbox(sync_state, created_at)',
    );
    await db.execute(
      'CREATE UNIQUE INDEX IF NOT EXISTS uq_sync_outbox_idempotency '
      'ON sync_outbox(installation_id, idempotency_key)',
    );
    await db.execute('''
      CREATE TABLE IF NOT EXISTS inventoryAdjustments (
        id TEXT PRIMARY KEY,
        organizationId TEXT NOT NULL,
        branchId TEXT NOT NULL,
        productId TEXT NOT NULL,
        quantityDelta REAL NOT NULL,
        adjustmentReason TEXT NOT NULL,
        adjustmentDate TEXT NOT NULL,
        notes TEXT,
        createdBy TEXT NOT NULL,
        adjustmentStatus TEXT NOT NULL DEFAULT 'draft',
        transactionVersion INTEGER NOT NULL DEFAULT 0,
        rowVersion INTEGER NOT NULL DEFAULT 1,
        postedAt TEXT
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS openingStocks (
        id TEXT PRIMARY KEY,
        organizationId TEXT NOT NULL,
        branchId TEXT NOT NULL,
        productId TEXT NOT NULL,
        openingQuantity REAL NOT NULL,
        openingDate TEXT NOT NULL,
        notes TEXT,
        openingStatus TEXT NOT NULL DEFAULT 'draft',
        createdBy TEXT NOT NULL,
        transactionVersion INTEGER NOT NULL DEFAULT 0,
        rowVersion INTEGER NOT NULL DEFAULT 1,
        postedAt TEXT
      )
    ''');
  }

  Future<void> _migrateToV45(Database db) async {
    await _addColumnIfMissing(db, 'users', 'teamSubscriptionEmail', 'TEXT');
    final owners = await db.query(
      'users',
      columns: ['organizationId', 'email', 'username'],
      where: "lower(trim(role)) = 'owner'",
    );
    final ownersByOrg = <String, List<String>>{};
    for (final row in owners) {
      final org = (row['organizationId'] as String?)?.trim() ?? '';
      if (org.isEmpty) continue;
      final emailRaw = (row['email'] as String?)?.trim() ?? '';
      final usernameRaw = (row['username'] as String?)?.trim() ?? '';
      final em = emailRaw.contains('@')
          ? emailRaw.toLowerCase()
          : (usernameRaw.contains('@')
              ? usernameRaw.toLowerCase()
              : '');
      if (!em.contains('@') ||
          em.endsWith('@legacy.mizapos') ||
          em.endsWith('@local.mizapos')) {
        continue;
      }
      ownersByOrg.putIfAbsent(org, () => []).add(em.trim().toLowerCase());
    }
    for (final entry in ownersByOrg.entries) {
      if (entry.value.length != 1) continue;
      final ownerEmail = entry.value.first;
      await db.rawUpdate(
        '''
        UPDATE users
        SET teamSubscriptionEmail = ?
        WHERE organizationId = ?
          AND lower(trim(role)) NOT IN ('owner', 'guest')
          AND (
            teamSubscriptionEmail IS NULL
            OR length(trim(teamSubscriptionEmail)) = 0
          )
        ''',
        [ownerEmail, entry.key],
      );
    }
  }

  Future<void> _migrateToV44(Database db) async {
    await _addColumnIfMissing(
      db,
      'users',
      'distributorCloudEnabled',
      'INTEGER NOT NULL DEFAULT 0',
    );
    await db.execute('''
      UPDATE users
      SET distributorCloudEnabled = 1
      WHERE lower(trim(role)) = 'distributor'
    ''');
  }

  Future<void> _migrateToV43(Database db) async {
    await _addColumnIfMissing(db, 'users', 'distributorCloudUntil', 'TEXT');
    await _addColumnIfMissing(db, 'users', 'maxDistributorSeats', 'INTEGER');
    await _addColumnIfMissing(
      db,
      'users',
      'usedDistributorSeats',
      'INTEGER NOT NULL DEFAULT 0',
    );
  }

  Future<void> _migrateToV42(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS field_returns_outbox (
        id TEXT PRIMARY KEY,
        server_return_id TEXT,
        field_order_id TEXT NOT NULL,
        client_order_id TEXT NOT NULL,
        organization_id TEXT NOT NULL,
        branch_id TEXT NOT NULL,
        distributor_user_id TEXT NOT NULL,
        distributor_display_name TEXT,
        installation_id TEXT,
        customer_name TEXT NOT NULL,
        sync_state TEXT NOT NULL DEFAULT 'local',
        remote_status TEXT,
        notes TEXT,
        reject_reason TEXT,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        last_sync_error TEXT
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS field_returns_outbox_lines (
        id TEXT PRIMARY KEY,
        outbox_id TEXT NOT NULL,
        line_index INTEGER NOT NULL,
        product_id TEXT,
        product_name TEXT NOT NULL,
        barcode TEXT,
        quantity REAL NOT NULL,
        unit_price REAL,
        unit_name TEXT,
        FOREIGN KEY (outbox_id) REFERENCES field_returns_outbox(id) ON DELETE CASCADE
      )
    ''');
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_field_returns_outbox_dist '
      'ON field_returns_outbox(distributor_user_id, created_at DESC)',
    );
  }

  Future<void> _migrateToV41(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS field_expenses_outbox (
        id TEXT PRIMARY KEY,
        server_expense_id TEXT,
        organization_id TEXT NOT NULL,
        branch_id TEXT NOT NULL,
        distributor_user_id TEXT NOT NULL,
        distributor_display_name TEXT,
        installation_id TEXT,
        sync_state TEXT NOT NULL DEFAULT 'local',
        remote_status TEXT,
        title TEXT NOT NULL,
        amount REAL NOT NULL,
        notes TEXT,
        payment_type TEXT NOT NULL DEFAULT 'cash',
        expense_date TEXT NOT NULL,
        reject_reason TEXT,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        last_sync_error TEXT
      )
    ''');
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_field_expenses_outbox_dist '
      'ON field_expenses_outbox(distributor_user_id, created_at DESC)',
    );
  }

  Future<void> _migrateToV40(Database db) async {
    await _ensureFieldTruckTables(db);
  }

  Future<void> _ensureFieldTruckTables(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS field_truck_stock_meta (
        organization_id TEXT NOT NULL,
        distributor_user_id TEXT NOT NULL,
        version TEXT NOT NULL,
        item_count INTEGER NOT NULL DEFAULT 0,
        synced_at TEXT,
        updated_at TEXT,
        PRIMARY KEY (organization_id, distributor_user_id)
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS field_truck_stock_items (
        id TEXT PRIMARY KEY,
        organization_id TEXT NOT NULL,
        distributor_user_id TEXT NOT NULL,
        product_id TEXT NOT NULL,
        product_name TEXT NOT NULL,
        barcode TEXT,
        sale_price REAL,
        unit_name TEXT,
        sort_order INTEGER NOT NULL DEFAULT 0,
        qty REAL NOT NULL DEFAULT 0
      )
    ''');
    await db.execute(
      'CREATE UNIQUE INDEX IF NOT EXISTS uq_field_truck_stock_local '
      'ON field_truck_stock_items(organization_id, distributor_user_id, product_id)',
    );
    await db.execute('''
      CREATE TABLE IF NOT EXISTS field_truck_movements (
        id TEXT PRIMARY KEY,
        organization_id TEXT NOT NULL,
        branch_id TEXT NOT NULL,
        distributor_user_id TEXT NOT NULL,
        distributor_display_name TEXT,
        product_id TEXT NOT NULL,
        product_name TEXT NOT NULL,
        movement_type TEXT NOT NULL,
        quantity REAL NOT NULL,
        reference_id TEXT,
        notes TEXT,
        movement_date TEXT NOT NULL,
        created_by TEXT NOT NULL
      )
    ''');
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_field_truck_mov_org_dist_date '
      'ON field_truck_movements(organization_id, distributor_user_id, movement_date DESC)',
    );
  }

  Future<void> _migrateToV39(Database db) async {
    await _ensureFieldTruckTables(db);
    await _addColumnIfMissing(
      db,
      'field_orders_outbox',
      'inventory_source',
      "TEXT NOT NULL DEFAULT 'main'",
    );
  }

  Future<void> _migrateToV38(Database db) async {
    await _addColumnIfMissing(
      db,
      'field_catalog_products',
      'stock_qty',
      'REAL',
    );
    await _addColumnIfMissing(
      db,
      'field_orders_outbox',
      'payment_type',
      "TEXT NOT NULL DEFAULT 'deferred'",
    );
    await _addColumnIfMissing(
      db,
      'field_orders_outbox',
      'paid_amount',
      'REAL NOT NULL DEFAULT 0',
    );
    await _addColumnIfMissing(
      db,
      'field_orders_outbox',
      'discount_amount',
      'REAL NOT NULL DEFAULT 0',
    );
    await _addColumnIfMissing(
      db,
      'field_orders_outbox',
      'tax_percent',
      'REAL NOT NULL DEFAULT 0',
    );
    await _addColumnIfMissing(
      db,
      'field_orders_outbox',
      'grand_total',
      'REAL',
    );
    await _addColumnIfMissing(
      db,
      'field_orders_outbox',
      'payment_splits_json',
      'TEXT',
    );
  }

  Future<void> _migrateToV37(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS team_users_sync_meta (
        organization_id TEXT PRIMARY KEY,
        version TEXT NOT NULL,
        updated_at TEXT NOT NULL
      )
    ''');
  }

  Future<void> _migrateToV36(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS field_catalog_customers (
        id TEXT PRIMARY KEY,
        organization_id TEXT NOT NULL,
        customer_id TEXT NOT NULL,
        customer_name TEXT NOT NULL,
        phone TEXT,
        address TEXT,
        customer_number TEXT,
        sort_order INTEGER NOT NULL DEFAULT 0
      )
    ''');
    await db.execute(
      'CREATE UNIQUE INDEX IF NOT EXISTS uq_field_catalog_local_org_customer '
      'ON field_catalog_customers(organization_id, customer_id)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_field_catalog_local_org_customer_sort '
      'ON field_catalog_customers(organization_id, sort_order, customer_name)',
    );
    await _addColumnIfMissing(
      db,
      'field_catalog_meta',
      'customer_count',
      'INTEGER NOT NULL DEFAULT 0',
    );
  }

  Future<void> _migrateToV35(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS field_catalog_meta (
        organization_id TEXT PRIMARY KEY,
        version TEXT NOT NULL,
        product_count INTEGER NOT NULL DEFAULT 0,
        synced_at TEXT NOT NULL,
        published_at TEXT
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS field_catalog_products (
        id TEXT PRIMARY KEY,
        organization_id TEXT NOT NULL,
        product_id TEXT NOT NULL,
        product_name TEXT NOT NULL,
        barcode TEXT,
        sale_price REAL,
        unit_name TEXT,
        sort_order INTEGER NOT NULL DEFAULT 0
      )
    ''');
    await db.execute(
      'CREATE UNIQUE INDEX IF NOT EXISTS uq_field_catalog_local_org_product '
      'ON field_catalog_products(organization_id, product_id)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_field_catalog_local_org_sort '
      'ON field_catalog_products(organization_id, sort_order, product_name)',
    );
  }

  Future<void> _migrateToV34(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS field_orders_outbox (
        id TEXT PRIMARY KEY,
        server_order_id TEXT,
        organization_id TEXT NOT NULL,
        branch_id TEXT NOT NULL,
        distributor_user_id TEXT NOT NULL,
        distributor_display_name TEXT,
        installation_id TEXT,
        sync_state TEXT NOT NULL DEFAULT 'local',
        remote_status TEXT,
        customer_id TEXT,
        customer_name TEXT NOT NULL,
        customer_phone TEXT,
        customer_address TEXT,
        notes TEXT,
        reject_reason TEXT,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL,
        last_sync_error TEXT
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS field_orders_outbox_lines (
        id TEXT PRIMARY KEY,
        outbox_id TEXT NOT NULL,
        line_index INTEGER NOT NULL,
        product_id TEXT,
        product_name TEXT NOT NULL,
        barcode TEXT,
        quantity REAL NOT NULL,
        unit_price REAL,
        unit_name TEXT,
        FOREIGN KEY (outbox_id) REFERENCES field_orders_outbox(id) ON DELETE CASCADE
      )
    ''');
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_field_orders_outbox_dist '
      'ON field_orders_outbox(distributor_user_id, created_at DESC)',
    );
  }

  Future<void> _migrateToV33(Database db) async {
    await _addColumnIfMissing(
      db,
      'products',
      'isFavorite',
      'INTEGER NOT NULL DEFAULT 0',
    );
  }

  Future<void> _migrateToV32(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS invoice_payment_splits (
        id TEXT PRIMARY KEY,
        organizationId TEXT NOT NULL,
        branchId TEXT NOT NULL,
        invoiceKind TEXT NOT NULL,
        invoiceId TEXT NOT NULL,
        paymentType TEXT NOT NULL,
        amount REAL NOT NULL,
        lineOrder INTEGER NOT NULL DEFAULT 0,
        FOREIGN KEY (organizationId) REFERENCES organizations(id),
        FOREIGN KEY (branchId) REFERENCES branches(id)
      )
    ''');
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_invoice_payment_splits_invoice '
      'ON invoice_payment_splits(invoiceKind, invoiceId)',
    );
  }

  Future<void> _migrateToV31(Database db) async {
    await _addColumnIfMissing(db, 'salesInvoices', 'invoiceNumber', 'INTEGER');
    await _addColumnIfMissing(db, 'purchaseInvoices', 'invoiceNumber', 'INTEGER');
    await _backfillInvoiceNumbers(db, 'salesInvoices');
    await _backfillInvoiceNumbers(db, 'purchaseInvoices');
  }

  Future<void> _backfillInvoiceNumbers(Database db, String table) async {
    final scopes = await db.rawQuery(
      'SELECT DISTINCT organizationId, branchId FROM $table',
    );
    for (final scope in scopes) {
      final org = scope['organizationId'] as String?;
      final branch = scope['branchId'] as String?;
      if (org == null || branch == null) continue;
      final rows = await db.query(
        table,
        columns: ['id'],
        where: 'organizationId = ? AND branchId = ?',
        whereArgs: [org, branch],
        orderBy: 'invoiceDate ASC, id ASC',
      );
      var seq = 1;
      for (final r in rows) {
        await db.update(
          table,
          {'invoiceNumber': seq},
          where: 'id = ?',
          whereArgs: [r['id']],
        );
        seq++;
      }
    }
  }

  Future<void> _migrateToV30(Database db) async {
    await _addColumnIfMissing(
        db, 'salesInvoices', 'paidAmount', 'REAL NOT NULL DEFAULT 0');
    await _addColumnIfMissing(
        db, 'purchaseInvoices', 'paidAmount', 'REAL NOT NULL DEFAULT 0');
    await db.execute(
      "UPDATE salesInvoices SET paidAmount = total "
      "WHERE paidAmount = 0 AND paymentType != 'deferred'",
    );
    await db.execute(
      "UPDATE purchaseInvoices SET paidAmount = total "
      "WHERE paidAmount = 0 AND paymentType != 'deferred'",
    );
  }

  Future<void> _migrateToV29(Database db) async {
    await _addColumnIfMissing(db, 'products', 'expiryDate', 'TEXT');
    await _addColumnIfMissing(db, 'product_trash', 'expiryDate', 'TEXT');
  }

  Future<void> _migrateToV28(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS product_sale_units (
        id TEXT PRIMARY KEY,
        organizationId TEXT NOT NULL,
        branchId TEXT NOT NULL,
        productId TEXT NOT NULL,
        unitName TEXT NOT NULL,
        toBaseFactor REAL NOT NULL,
        createdAt TEXT NOT NULL
      )
    ''');
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_product_sale_units_scope_product '
      'ON product_sale_units(organizationId, branchId, productId)',
    );
    await db.execute(
      'CREATE UNIQUE INDEX IF NOT EXISTS uq_product_sale_units_scope_product_unit '
      'ON product_sale_units(organizationId, branchId, productId, unitName COLLATE NOCASE)',
    );
  }

  Future<void> _migrateToV27(Database db) async {
    await _addColumnIfMissing(db, 'partnerLedger', 'voucherNumber', 'TEXT');
  }

  Future<void> _migrateToV26(Database db) async {
    await _addColumnIfMissing(db, 'salesInvoices', 'notes', 'TEXT');
    await _addColumnIfMissing(
        db, 'salesInvoices', 'discountAmount', 'REAL NOT NULL DEFAULT 0');
    await _addColumnIfMissing(
        db, 'salesInvoices', 'taxPercent', 'REAL NOT NULL DEFAULT 0');
    await _addColumnIfMissing(
        db, 'salesInvoices', 'lineSubtotal', 'REAL NOT NULL DEFAULT 0');
    await _addColumnIfMissing(
        db, 'salesInvoices', 'totalsFormat', 'INTEGER NOT NULL DEFAULT 0');
    await _addColumnIfMissing(db, 'purchaseInvoices', 'notes', 'TEXT');
    await _addColumnIfMissing(
        db, 'purchaseInvoices', 'discountAmount', 'REAL NOT NULL DEFAULT 0');
    await _addColumnIfMissing(
        db, 'purchaseInvoices', 'taxPercent', 'REAL NOT NULL DEFAULT 0');
    await _addColumnIfMissing(
        db, 'purchaseInvoices', 'lineSubtotal', 'REAL NOT NULL DEFAULT 0');
    await _addColumnIfMissing(
        db, 'purchaseInvoices', 'totalsFormat', 'INTEGER NOT NULL DEFAULT 0');
    // ترحيل: الفواتير القديمة totalsFormat=0 وlineSubtotal=0 حتى التحديث
    await db.execute(
      'UPDATE salesInvoices SET lineSubtotal = total WHERE lineSubtotal = 0',
    );
    await db.execute(
      'UPDATE purchaseInvoices SET lineSubtotal = total WHERE lineSubtotal = 0',
    );
  }

  Future<void> _migrateToV25(Database db) async {
    await _addColumnIfMissing(
      db,
      'products',
      'isFrozen',
      'INTEGER NOT NULL DEFAULT 0',
    );
    await _addColumnIfMissing(
      db,
      'product_trash',
      'isFrozen',
      'INTEGER NOT NULL DEFAULT 0',
    );
  }

  /// تحويل لاحقات الإيميل الداخليّة من «.hsnposs» إلى «.mizapos» في كل
  /// الصفوف التي خُلِّقَت بالاسم القديم (sentinel emails للضيف + إيميلات
  /// المستخدمين القدامى المُولَّدة في V7 + إيميلات الأجهزة المربوطة). هذه
  /// لاحقات داخليّة لا تُعرَض للمستخدم وإنّما تستخدم كمعرّفات صفوف فقط، لذا
  /// التحويل آمن ولا يكسر أيّ منطق تسجيل دخول حقيقيّ.
  Future<void> _migrateToV24(Database db) async {
    await db.execute('''
      UPDATE users
      SET email = REPLACE(email, '@local.hsnposs', '@local.mizapos')
      WHERE email LIKE '%@local.hsnposs'
    ''');
    await db.execute('''
      UPDATE users
      SET email = REPLACE(email, '@legacy.hsnposs', '@legacy.mizapos')
      WHERE email LIKE '%@legacy.hsnposs'
    ''');
    await db.execute('''
      UPDATE users
      SET email = REPLACE(email, '@hsnposs.local', '@mizapos.local')
      WHERE email LIKE '%@hsnposs.local'
    ''');
  }

  Future<void> _migrateToV23(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS activation_redeems (
        signupRequestId TEXT NOT NULL,
        installationId TEXT NOT NULL,
        redeemedAt TEXT NOT NULL,
        PRIMARY KEY (signupRequestId, installationId)
      )
    ''');
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_activation_redeems_installation '
      'ON activation_redeems(installationId)',
    );
  }

  Future<void> _migrateToV22(Database db) async {
    await _addColumnIfMissing(
      db,
      'users',
      'subscriptionAccessSuspended',
      'INTEGER NOT NULL DEFAULT 0',
    );
  }

  Future<void> _migrateToV21(Database db) async {
    await _addColumnIfMissing(
      db,
      'users',
      'webActivationPending',
      'INTEGER NOT NULL DEFAULT 0',
    );
  }

  Future<void> _migrateToV20(Database db) async {
    await _addColumnIfMissing(
      db,
      'salesReturns',
      'returnStatus',
      "TEXT NOT NULL DEFAULT 'posted'",
    );
    await _addColumnIfMissing(
      db,
      'purchaseReturns',
      'returnStatus',
      "TEXT NOT NULL DEFAULT 'posted'",
    );
  }

  Future<void> _migrateToV19(Database db) async {
    await _addColumnIfMissing(
      db,
      'products',
      'sortOrder',
      'INTEGER NOT NULL DEFAULT 0',
    );
    await db.execute('''
      CREATE TABLE IF NOT EXISTS product_trash (
        id TEXT PRIMARY KEY,
        organizationId TEXT NOT NULL,
        branchId TEXT NOT NULL,
        name TEXT NOT NULL,
        salePrice REAL NOT NULL,
        costPrice REAL NOT NULL,
        stockQty REAL NOT NULL DEFAULT 0,
        barcode TEXT,
        categoryId TEXT,
        description TEXT,
        unitName TEXT,
        imagePath TEXT,
        isHidden INTEGER NOT NULL DEFAULT 0,
        isService INTEGER NOT NULL DEFAULT 0,
        createdAt TEXT NOT NULL,
        sortOrder INTEGER NOT NULL DEFAULT 0,
        deletedAt TEXT NOT NULL
      )
    ''');
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_product_trash_scope '
      'ON product_trash(organizationId, branchId)',
    );
  }

  Future<void> _migrateToV18(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS product_units (
        id TEXT PRIMARY KEY,
        organizationId TEXT NOT NULL,
        branchId TEXT NOT NULL,
        name TEXT NOT NULL,
        createdAt TEXT NOT NULL
      )
    ''');
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_product_units_scope '
      'ON product_units(organizationId, branchId)',
    );
    await db.execute(
      'CREATE UNIQUE INDEX IF NOT EXISTS uq_product_units_scope_name_nocase '
      'ON product_units(organizationId, branchId, name COLLATE NOCASE)',
    );
  }

  Future<void> _migrateToV17(Database db) async {
    await _addColumnIfMissing(db, 'products', 'description', 'TEXT');
    await _addColumnIfMissing(db, 'products', 'unitName', 'TEXT');
    await _addColumnIfMissing(db, 'products', 'imagePath', 'TEXT');
  }

  Future<void> _migrateToV16(Database db) async {
    await _addColumnIfMissing(db, 'customers', 'customerNumber', 'TEXT');
    await _addColumnIfMissing(db, 'customers', 'creditLimit', 'REAL NOT NULL DEFAULT 0');
    await _addColumnIfMissing(db, 'customers', 'overdueAlertDays', 'INTEGER');
    await _addColumnIfMissing(db, 'suppliers', 'supplierNumber', 'TEXT');
    await _addColumnIfMissing(db, 'suppliers', 'creditLimit', 'REAL NOT NULL DEFAULT 0');
    await _addColumnIfMissing(db, 'suppliers', 'overdueAlertDays', 'INTEGER');
    await db.execute(
      'CREATE UNIQUE INDEX IF NOT EXISTS uq_customers_scope_number '
      'ON customers(organizationId, branchId, customerNumber) '
      'WHERE customerNumber IS NOT NULL AND TRIM(customerNumber) != \'\'',
    );
    await db.execute(
      'CREATE UNIQUE INDEX IF NOT EXISTS uq_suppliers_scope_number '
      'ON suppliers(organizationId, branchId, supplierNumber) '
      'WHERE supplierNumber IS NOT NULL AND TRIM(supplierNumber) != \'\'',
    );
  }

  Future<void> _migrateToV15(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS product_categories (
        id TEXT PRIMARY KEY,
        organizationId TEXT NOT NULL,
        branchId TEXT NOT NULL,
        name TEXT NOT NULL,
        createdAt TEXT NOT NULL
      )
    ''');
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_product_categories_scope '
      'ON product_categories(organizationId, branchId)',
    );
    await db.execute(
      'CREATE UNIQUE INDEX IF NOT EXISTS uq_product_categories_scope_name_nocase '
      'ON product_categories(organizationId, branchId, name COLLATE NOCASE)',
    );
    await _addColumnIfMissing(db, 'products', 'categoryId', 'TEXT');
  }

  Future<void> _migrateToV14(Database db) async {
    await db.execute('''
      UPDATE products
      SET barcode = NULL
      WHERE barcode IS NOT NULL
        AND TRIM(barcode) != ''
        AND rowid NOT IN (
          SELECT MIN(rowid)
          FROM products
          WHERE barcode IS NOT NULL AND TRIM(barcode) != ''
          GROUP BY organizationId, branchId, LOWER(TRIM(barcode))
        )
    ''');
    await db.execute(
      'CREATE UNIQUE INDEX IF NOT EXISTS uq_products_scope_barcode_nocase '
      'ON products(organizationId, branchId, LOWER(TRIM(barcode))) '
      'WHERE barcode IS NOT NULL AND TRIM(barcode) != \'\'',
    );
  }

  Future<void> _migrateToV13(Database db) async {
    await _addColumnIfMissing(
      db,
      'signup_requests',
      'pendingRemotePush',
      'INTEGER NOT NULL DEFAULT 0',
    );
  }

  Future<void> _migrateToV12(Database db) async {
    await _addColumnIfMissing(db, 'users', 'subscriptionDeviceBinding', 'TEXT');
  }

  /// تفعيل سنوي / قديم مرتبط بالمستخدم، وترحيل من `activation.json` مرّة واحدة.
  Future<void> _migrateToV11(Database db) async {
    await _addColumnIfMissing(db, 'users', 'subscriptionAnnualUntil', 'TEXT');
    await _addColumnIfMissing(
      db,
      'users',
      'subscriptionLegacyActivated',
      'INTEGER NOT NULL DEFAULT 0',
    );
    try {
      final activationCandidates = <String>[
        join(Directory.current.path, 'activation.json'),
        appDataFilePath('activation.json'),
      ];
      String? activationPath;
      for (final candidate in activationCandidates) {
        if (await File(candidate).exists()) {
          activationPath = candidate;
          break;
        }
      }
      if (activationPath == null) return;
      final f = File(activationPath);
      if (await f.exists()) {
        final map =
            jsonDecode(await f.readAsString()) as Map<String, dynamic>;
        final legacy = map['isActivated'] == true;
        final au = (map['annualValidUntil'] as String?)?.trim();
        final annualEnd =
            au != null && au.isNotEmpty ? DateTime.tryParse(au) : null;
        if (annualEnd != null) {
          await db.rawUpdate(
            '''
            UPDATE users
            SET subscriptionAnnualUntil = ?,
                subscriptionLegacyActivated = 0
            WHERE lower(trim(role)) <> 'guest'
            ''',
            [annualEnd.toIso8601String()],
          );
        } else if (legacy) {
          await db.rawUpdate(
            '''
            UPDATE users
            SET subscriptionLegacyActivated = 1,
                subscriptionAnnualUntil = NULL
            WHERE lower(trim(role)) <> 'guest'
            ''',
            [],
          );
        }
      }
    } catch (_) {}
  }

  Future<void> _migrateToV9(Database db) async {
    await _addColumnIfMissing(db, 'signup_requests', 'issuedActivationKey', 'TEXT');
  }

  /// يحدّد المستخدمين المنشأين من طلب تسجيل معتمد — لإخفاء المشتركين عن بعضهم.
  Future<void> _migrateToV10(Database db) async {
    await _addColumnIfMissing(db, 'users', 'fromSignupRequestId', 'TEXT');
    final approved = await db.query(
      'signup_requests',
      columns: ['id', 'organizationId', 'email'],
      where: 'status = ?',
      whereArgs: ['approved'],
    );
    for (final sr in approved) {
      final rid = sr['id'] as String;
      final orgId = sr['organizationId'] as String;
      final em = (sr['email'] as String).trim().toLowerCase();
      await db.update(
        'users',
        {'fromSignupRequestId': rid},
        where:
            'organizationId = ? AND (lower(trim(email)) = ? OR lower(trim(username)) = ?)',
        whereArgs: [orgId, em, em],
      );
    }
  }

  /// مستخدم «زائر» + ملف ترخيص للمستخدمين القدامى (وصول كامل دون قفل).
  Future<void> _migrateToV8(Database db) async {
    await _ensureGuestUserRow(db);
    await LicenseGate.writeGrandfatherOnDbUpgrade();
  }

  Future<void> _ensureGuestUserRow(Database db) async {
    const guestId = LicenseGate.guestUserId;
    final ex = await db.query('users', where: 'id = ?', whereArgs: [guestId]);
    if (ex.isNotEmpty) return;
    final org = await db.query('organizations', limit: 1);
    if (org.isEmpty) return;
    final orgId = org.first['id'] as String;
    final br = await db.query(
      'branches',
      where: 'organizationId = ?',
      whereArgs: [orgId],
      limit: 1,
    );
    if (br.isEmpty) return;
    final branchId = br.first['id'] as String;
    final now = DateTime.now().toIso8601String();
    await db.insert('users', {
      'id': guestId,
      'organizationId': orgId,
      'branchId': branchId,
      'fullName': 'زائر',
      'username': 'guest',
      'email': 'guest@local.mizapos',
      'phone': '',
      'dialCode': '+970',
      'password': PasswordCrypto.hash('__guest_nologin__v1__'),
      'role': 'guest',
      'accountStatus': 'active',
      'createdAt': now,
    });
  }

  Future<void> _dropLegacyTables(Database db) async {
    final legacyTables = <String>[
      'invoices',
      'products',
      'purchases',
      'employees',
      'inventory',
      'reports',
    ];
    for (final table in legacyTables) {
      await db.execute('DROP TABLE IF EXISTS $table');
    }
  }

  Future<void> _createV2Schema(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS organizations (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        createdAt TEXT NOT NULL
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS branches (
        id TEXT PRIMARY KEY,
        organizationId TEXT NOT NULL,
        name TEXT NOT NULL,
        code TEXT NOT NULL,
        createdAt TEXT NOT NULL
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS users (
        id TEXT PRIMARY KEY,
        organizationId TEXT NOT NULL,
        branchId TEXT NOT NULL,
        fullName TEXT NOT NULL,
        username TEXT NOT NULL,
        password TEXT NOT NULL,
        role TEXT NOT NULL,
        createdAt TEXT NOT NULL,
        email TEXT NOT NULL DEFAULT '',
        phone TEXT NOT NULL DEFAULT '',
        dialCode TEXT NOT NULL DEFAULT '+970',
        accountStatus TEXT NOT NULL DEFAULT 'active',
        fromSignupRequestId TEXT,
        subscriptionAnnualUntil TEXT,
        subscriptionLegacyActivated INTEGER NOT NULL DEFAULT 0,
        subscriptionDeviceBinding TEXT,
        webActivationPending INTEGER NOT NULL DEFAULT 0,
        subscriptionAccessSuspended INTEGER NOT NULL DEFAULT 0
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS signup_requests (
        id TEXT PRIMARY KEY,
        organizationId TEXT NOT NULL,
        fullName TEXT NOT NULL,
        email TEXT NOT NULL,
        phone TEXT NOT NULL,
        dialCode TEXT NOT NULL,
        password TEXT NOT NULL,
        requestedAt TEXT NOT NULL,
        status TEXT NOT NULL DEFAULT 'pending',
        reviewedAt TEXT,
        reviewedByUserId TEXT,
        issuedActivationKey TEXT,
        pendingRemotePush INTEGER NOT NULL DEFAULT 0
      )
    ''');
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_signup_org_status '
      'ON signup_requests(organizationId, status)',
    );
    await db.execute('''
      CREATE TABLE IF NOT EXISTS activation_redeems (
        signupRequestId TEXT NOT NULL,
        installationId TEXT NOT NULL,
        redeemedAt TEXT NOT NULL,
        PRIMARY KEY (signupRequestId, installationId)
      )
    ''');
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_activation_redeems_installation '
      'ON activation_redeems(installationId)',
    );
    await db.execute(
      'CREATE UNIQUE INDEX IF NOT EXISTS uq_users_org_email_nocase '
      'ON users(organizationId, email COLLATE NOCASE)',
    );
    await db.execute('''
      CREATE TABLE IF NOT EXISTS customers (
        id TEXT PRIMARY KEY,
        organizationId TEXT NOT NULL,
        branchId TEXT NOT NULL,
        customerNumber TEXT,
        name TEXT NOT NULL,
        phone TEXT,
        address TEXT,
        creditLimit REAL NOT NULL DEFAULT 0,
        overdueAlertDays INTEGER,
        notes TEXT,
        createdAt TEXT NOT NULL
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS suppliers (
        id TEXT PRIMARY KEY,
        organizationId TEXT NOT NULL,
        branchId TEXT NOT NULL,
        supplierNumber TEXT,
        name TEXT NOT NULL,
        phone TEXT,
        address TEXT,
        creditLimit REAL NOT NULL DEFAULT 0,
        overdueAlertDays INTEGER,
        notes TEXT,
        createdAt TEXT NOT NULL
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS product_categories (
        id TEXT PRIMARY KEY,
        organizationId TEXT NOT NULL,
        branchId TEXT NOT NULL,
        name TEXT NOT NULL,
        createdAt TEXT NOT NULL
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS product_units (
        id TEXT PRIMARY KEY,
        organizationId TEXT NOT NULL,
        branchId TEXT NOT NULL,
        name TEXT NOT NULL,
        createdAt TEXT NOT NULL
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS products (
        id TEXT PRIMARY KEY,
        organizationId TEXT NOT NULL,
        branchId TEXT NOT NULL,
        name TEXT NOT NULL,
        salePrice REAL NOT NULL,
        costPrice REAL NOT NULL,
        stockQty REAL NOT NULL DEFAULT 0,
        barcode TEXT,
        categoryId TEXT,
        description TEXT,
        unitName TEXT,
        imagePath TEXT,
        expiryDate TEXT,
        isHidden INTEGER NOT NULL DEFAULT 0,
        isFrozen INTEGER NOT NULL DEFAULT 0,
        isService INTEGER NOT NULL DEFAULT 0,
        isFavorite INTEGER NOT NULL DEFAULT 0,
        sortOrder INTEGER NOT NULL DEFAULT 0,
        createdAt TEXT NOT NULL
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS product_sale_units (
        id TEXT PRIMARY KEY,
        organizationId TEXT NOT NULL,
        branchId TEXT NOT NULL,
        productId TEXT NOT NULL,
        unitName TEXT NOT NULL,
        toBaseFactor REAL NOT NULL,
        createdAt TEXT NOT NULL
      )
    ''');
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_product_sale_units_scope_product '
      'ON product_sale_units(organizationId, branchId, productId)',
    );
    await db.execute(
      'CREATE UNIQUE INDEX IF NOT EXISTS uq_product_sale_units_scope_product_unit '
      'ON product_sale_units(organizationId, branchId, productId, unitName COLLATE NOCASE)',
    );
    await db.execute('''
      CREATE TABLE IF NOT EXISTS product_trash (
        id TEXT PRIMARY KEY,
        organizationId TEXT NOT NULL,
        branchId TEXT NOT NULL,
        name TEXT NOT NULL,
        salePrice REAL NOT NULL,
        costPrice REAL NOT NULL,
        stockQty REAL NOT NULL DEFAULT 0,
        barcode TEXT,
        categoryId TEXT,
        description TEXT,
        unitName TEXT,
        imagePath TEXT,
        expiryDate TEXT,
        isHidden INTEGER NOT NULL DEFAULT 0,
        isFrozen INTEGER NOT NULL DEFAULT 0,
        isService INTEGER NOT NULL DEFAULT 0,
        createdAt TEXT NOT NULL,
        sortOrder INTEGER NOT NULL DEFAULT 0,
        deletedAt TEXT NOT NULL
      )
    ''');
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_product_trash_scope '
      'ON product_trash(organizationId, branchId)',
    );
    await db.execute('''
      CREATE TABLE IF NOT EXISTS salesInvoices (
        id TEXT PRIMARY KEY,
        organizationId TEXT NOT NULL,
        branchId TEXT NOT NULL,
        customerId TEXT,
        invoiceDate TEXT NOT NULL,
        total REAL NOT NULL,
        paymentType TEXT NOT NULL,
        invoiceStatus TEXT NOT NULL DEFAULT 'posted',
        createdBy TEXT NOT NULL,
        notes TEXT,
        discountAmount REAL NOT NULL DEFAULT 0,
        taxPercent REAL NOT NULL DEFAULT 0,
        lineSubtotal REAL NOT NULL DEFAULT 0,
        totalsFormat INTEGER NOT NULL DEFAULT 0,
        paidAmount REAL NOT NULL DEFAULT 0,
        invoiceNumber INTEGER
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS salesInvoiceItems (
        id TEXT PRIMARY KEY,
        invoiceId TEXT NOT NULL,
        productId TEXT NOT NULL,
        quantity REAL NOT NULL,
        unitPrice REAL NOT NULL,
        lineTotal REAL NOT NULL
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS purchaseInvoices (
        id TEXT PRIMARY KEY,
        organizationId TEXT NOT NULL,
        branchId TEXT NOT NULL,
        supplierId TEXT,
        invoiceDate TEXT NOT NULL,
        total REAL NOT NULL,
        paymentType TEXT NOT NULL,
        invoiceStatus TEXT NOT NULL DEFAULT 'posted',
        createdBy TEXT NOT NULL,
        notes TEXT,
        discountAmount REAL NOT NULL DEFAULT 0,
        taxPercent REAL NOT NULL DEFAULT 0,
        lineSubtotal REAL NOT NULL DEFAULT 0,
        totalsFormat INTEGER NOT NULL DEFAULT 0,
        paidAmount REAL NOT NULL DEFAULT 0,
        invoiceNumber INTEGER
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS purchaseInvoiceItems (
        id TEXT PRIMARY KEY,
        invoiceId TEXT NOT NULL,
        productId TEXT NOT NULL,
        quantity REAL NOT NULL,
        unitCost REAL NOT NULL,
        lineTotal REAL NOT NULL
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS stockMovements (
        id TEXT PRIMARY KEY,
        organizationId TEXT NOT NULL,
        branchId TEXT NOT NULL,
        productId TEXT NOT NULL,
        movementType TEXT NOT NULL,
        quantity REAL NOT NULL,
        referenceType TEXT NOT NULL,
        referenceId TEXT NOT NULL,
        movementDate TEXT NOT NULL,
        createdBy TEXT NOT NULL
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS cashTransactions (
        id TEXT PRIMARY KEY,
        organizationId TEXT NOT NULL,
        branchId TEXT NOT NULL,
        transactionType TEXT NOT NULL,
        amount REAL NOT NULL,
        description TEXT NOT NULL,
        referenceType TEXT NOT NULL,
        referenceId TEXT NOT NULL,
        transactionDate TEXT NOT NULL,
        createdBy TEXT NOT NULL
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS expenses (
        id TEXT PRIMARY KEY,
        organizationId TEXT NOT NULL,
        branchId TEXT NOT NULL,
        title TEXT NOT NULL,
        amount REAL NOT NULL,
        expenseDate TEXT NOT NULL,
        notes TEXT,
        createdBy TEXT NOT NULL
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS auditLogs (
        id TEXT PRIMARY KEY,
        organizationId TEXT NOT NULL,
        branchId TEXT NOT NULL,
        userId TEXT NOT NULL,
        action TEXT NOT NULL,
        entityType TEXT NOT NULL,
        entityId TEXT NOT NULL,
        details TEXT NOT NULL,
        createdAt TEXT NOT NULL
      )
    ''');

    await _createAccountingPrecisionTables(db);

    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_branch_lookup ON users(organizationId, branchId)');
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_customers_scope ON customers(organizationId, branchId)');
    await db.execute(
      'CREATE UNIQUE INDEX IF NOT EXISTS uq_customers_scope_number '
      'ON customers(organizationId, branchId, customerNumber) '
      'WHERE customerNumber IS NOT NULL AND TRIM(customerNumber) != \'\'',
    );
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_suppliers_scope ON suppliers(organizationId, branchId)');
    await db.execute(
      'CREATE UNIQUE INDEX IF NOT EXISTS uq_suppliers_scope_number '
      'ON suppliers(organizationId, branchId, supplierNumber) '
      'WHERE supplierNumber IS NOT NULL AND TRIM(supplierNumber) != \'\'',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_product_categories_scope '
      'ON product_categories(organizationId, branchId)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_product_units_scope '
      'ON product_units(organizationId, branchId)',
    );
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_products_scope ON products(organizationId, branchId)');
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_sales_scope ON salesInvoices(organizationId, branchId, invoiceDate)');
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_purchase_scope ON purchaseInvoices(organizationId, branchId, invoiceDate)');
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_cash_scope ON cashTransactions(organizationId, branchId, transactionDate)');
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_stock_scope ON stockMovements(organizationId, branchId, movementDate)');
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_partner_ledger_scope ON partnerLedger(organizationId, branchId, partnerKind, partnerId)');
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_partner_ledger_date ON partnerLedger(organizationId, branchId, entryDate)');
    await _createUniqueIndexes(db);
  }

  Future<void> _createAccountingPrecisionTables(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS partnerLedger (
        id TEXT PRIMARY KEY,
        organizationId TEXT NOT NULL,
        branchId TEXT NOT NULL,
        partnerKind TEXT NOT NULL,
        partnerId TEXT NOT NULL,
        entryType TEXT NOT NULL,
        referenceType TEXT NOT NULL,
        referenceId TEXT NOT NULL,
        amountSigned REAL NOT NULL,
        notes TEXT,
        voucherNumber TEXT,
        entryDate TEXT NOT NULL,
        createdBy TEXT NOT NULL
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS salesReturns (
        id TEXT PRIMARY KEY,
        organizationId TEXT NOT NULL,
        branchId TEXT NOT NULL,
        customerId TEXT,
        originalInvoiceId TEXT,
        returnDate TEXT NOT NULL,
        total REAL NOT NULL,
        refundPaymentType TEXT NOT NULL,
        notes TEXT,
        createdBy TEXT NOT NULL,
        returnStatus TEXT NOT NULL DEFAULT 'posted'
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS salesReturnItems (
        id TEXT PRIMARY KEY,
        returnId TEXT NOT NULL,
        productId TEXT NOT NULL,
        quantity REAL NOT NULL,
        unitPrice REAL NOT NULL,
        lineTotal REAL NOT NULL
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS purchaseReturns (
        id TEXT PRIMARY KEY,
        organizationId TEXT NOT NULL,
        branchId TEXT NOT NULL,
        supplierId TEXT,
        originalInvoiceId TEXT,
        returnDate TEXT NOT NULL,
        total REAL NOT NULL,
        refundPaymentType TEXT NOT NULL,
        notes TEXT,
        createdBy TEXT NOT NULL,
        returnStatus TEXT NOT NULL DEFAULT 'posted'
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS purchaseReturnItems (
        id TEXT PRIMARY KEY,
        returnId TEXT NOT NULL,
        productId TEXT NOT NULL,
        quantity REAL NOT NULL,
        unitCost REAL NOT NULL,
        lineTotal REAL NOT NULL
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS invoice_payment_splits (
        id TEXT PRIMARY KEY,
        organizationId TEXT NOT NULL,
        branchId TEXT NOT NULL,
        invoiceKind TEXT NOT NULL,
        invoiceId TEXT NOT NULL,
        paymentType TEXT NOT NULL,
        amount REAL NOT NULL,
        lineOrder INTEGER NOT NULL DEFAULT 0,
        FOREIGN KEY (organizationId) REFERENCES organizations(id),
        FOREIGN KEY (branchId) REFERENCES branches(id)
      )
    ''');
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_invoice_payment_splits_invoice '
      'ON invoice_payment_splits(invoiceKind, invoiceId)',
    );
  }

  Future<void> _migrateToV4(Database db) async {
    await _addColumnIfMissing(db, 'salesInvoices', 'invoiceStatus', "TEXT DEFAULT 'posted'");
    await _addColumnIfMissing(db, 'purchaseInvoices', 'invoiceStatus', "TEXT DEFAULT 'posted'");
    await _createAccountingPrecisionTables(db);
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_partner_ledger_scope ON partnerLedger(organizationId, branchId, partnerKind, partnerId)');
    await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_partner_ledger_date ON partnerLedger(organizationId, branchId, entryDate)');
    await _backfillPartnerLedgerIfEmpty(db);
  }

  Future<void> _addColumnIfMissing(Database db, String table, String column, String ddlTail) async {
    final rows = await db.rawQuery('PRAGMA table_info($table)');
    final exists = rows.any((r) => r['name'] == column);
    if (!exists) {
      await db.execute('ALTER TABLE $table ADD COLUMN $column $ddlTail');
    }
  }

  Future<void> _backfillPartnerLedgerIfEmpty(Database db) async {
    final cnt = await db.rawQuery('SELECT COUNT(*) AS c FROM partnerLedger');
    final n = (cnt.first['c'] as int?) ?? 0;
    if (n > 0) return;

    final rnd = Random();
    String nid() => '${DateTime.now().microsecondsSinceEpoch}_${rnd.nextInt(16777215)}';

    final deferredSales = await db.rawQuery(
      'SELECT id, organizationId, branchId, customerId, total, invoiceDate, createdBy '
      'FROM salesInvoices WHERE paymentType = ? AND customerId IS NOT NULL',
      ['deferred'],
    );
    for (final r in deferredSales) {
      await db.insert('partnerLedger', {
        'id': nid(),
        'organizationId': r['organizationId'],
        'branchId': r['branchId'],
        'partnerKind': 'customer',
        'partnerId': r['customerId'],
        'entryType': 'sale_ar',
        'referenceType': 'sale',
        'referenceId': r['id'],
        'amountSigned': r['total'],
        'notes': 'ترحيل: ذمة عميل من فاتورة آجلة سابقة',
        'entryDate': r['invoiceDate'],
        'createdBy': r['createdBy'],
      });
    }

    final deferredPurchases = await db.rawQuery(
      'SELECT id, organizationId, branchId, supplierId, total, invoiceDate, createdBy '
      'FROM purchaseInvoices WHERE paymentType = ? AND supplierId IS NOT NULL',
      ['deferred'],
    );
    for (final r in deferredPurchases) {
      await db.insert('partnerLedger', {
        'id': nid(),
        'organizationId': r['organizationId'],
        'branchId': r['branchId'],
        'partnerKind': 'supplier',
        'partnerId': r['supplierId'],
        'entryType': 'purchase_ap',
        'referenceType': 'purchase',
        'referenceId': r['id'],
        'amountSigned': r['total'],
        'notes': 'ترحيل: ذمة مورد من فاتورة آجلة سابقة',
        'entryDate': r['invoiceDate'],
        'createdBy': r['createdBy'],
      });
    }
  }

  Future<void> _migrateToV3(Database db) async {
    await _deduplicateForUniqueConstraints(db);
    await _createUniqueIndexes(db);
  }

  Future<void> _migrateToV6(Database db) async {
    await db.execute(
      "UPDATE users SET role = 'accountant' WHERE role = 'branch_manager'",
    );
  }

  Future<void> _migrateToV7(Database db) async {
    await _addColumnIfMissing(db, 'users', 'email', "TEXT NOT NULL DEFAULT ''");
    await _addColumnIfMissing(db, 'users', 'phone', "TEXT NOT NULL DEFAULT ''");
    await _addColumnIfMissing(
        db, 'users', 'dialCode', "TEXT NOT NULL DEFAULT '+970'");
    await _addColumnIfMissing(db, 'users', 'accountStatus',
        "TEXT NOT NULL DEFAULT 'active'");
    await db.execute('''
      UPDATE users
      SET email = lower(trim(username)) || '@legacy.mizapos'
      WHERE trim(COALESCE(email, '')) = ''
      ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS signup_requests (
        id TEXT PRIMARY KEY,
        organizationId TEXT NOT NULL,
        fullName TEXT NOT NULL,
        email TEXT NOT NULL,
        phone TEXT NOT NULL,
        dialCode TEXT NOT NULL,
        password TEXT NOT NULL,
        requestedAt TEXT NOT NULL,
        status TEXT NOT NULL DEFAULT 'pending',
        reviewedAt TEXT,
        reviewedByUserId TEXT
      )
    ''');
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_signup_org_status '
      'ON signup_requests(organizationId, status)',
    );
    await db.execute(
      'CREATE UNIQUE INDEX IF NOT EXISTS uq_users_org_email_nocase '
      'ON users(organizationId, email COLLATE NOCASE)',
    );
  }

  Future<void> _migrateToV5(Database db) async {
    await _addColumnIfMissing(db, 'products', 'barcode', 'TEXT');
    await _addColumnIfMissing(db, 'products', 'isHidden', 'INTEGER NOT NULL DEFAULT 0');
    await _addColumnIfMissing(db, 'products', 'isService', 'INTEGER NOT NULL DEFAULT 0');
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_products_scope_hidden '
      'ON products(organizationId, branchId, isHidden)',
    );
  }

  Future<void> _createUniqueIndexes(Database db) async {
    await db.execute(
      'CREATE UNIQUE INDEX IF NOT EXISTS uq_branches_org_code_nocase '
      'ON branches(organizationId, code COLLATE NOCASE)',
    );
    await db.execute(
      'CREATE UNIQUE INDEX IF NOT EXISTS uq_users_org_username_nocase '
      'ON users(organizationId, username COLLATE NOCASE)',
    );
    await db.execute(
      'CREATE UNIQUE INDEX IF NOT EXISTS uq_products_scope_name_nocase '
      'ON products(organizationId, branchId, name COLLATE NOCASE)',
    );
    await db.execute(
      'CREATE UNIQUE INDEX IF NOT EXISTS uq_product_categories_scope_name_nocase '
      'ON product_categories(organizationId, branchId, name COLLATE NOCASE)',
    );
    await db.execute(
      'CREATE UNIQUE INDEX IF NOT EXISTS uq_product_units_scope_name_nocase '
      'ON product_units(organizationId, branchId, name COLLATE NOCASE)',
    );
    await db.execute(
      'CREATE UNIQUE INDEX IF NOT EXISTS uq_products_scope_barcode_nocase '
      'ON products(organizationId, branchId, LOWER(TRIM(barcode))) '
      'WHERE barcode IS NOT NULL AND TRIM(barcode) != \'\'',
    );
  }

  Future<void> _deduplicateForUniqueConstraints(Database db) async {
    await db.execute('''
      DELETE FROM branches
      WHERE rowid NOT IN (
        SELECT MIN(rowid)
        FROM branches
        GROUP BY organizationId, lower(trim(code))
      )
    ''');
    await db.execute('''
      DELETE FROM users
      WHERE rowid NOT IN (
        SELECT MIN(rowid)
        FROM users
        GROUP BY organizationId, lower(trim(username))
      )
    ''');
    await db.execute('''
      DELETE FROM products
      WHERE rowid NOT IN (
        SELECT MIN(rowid)
        FROM products
        GROUP BY organizationId, branchId, lower(trim(name))
      )
    ''');
  }
}