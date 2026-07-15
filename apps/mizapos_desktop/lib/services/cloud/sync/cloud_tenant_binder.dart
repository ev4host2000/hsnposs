import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:mizapos_desktop/models/entities.dart';
import 'package:mizapos_desktop/services/accounting_service.dart';
import 'package:mizapos_desktop/services/cloud/storage/cloud_secure_storage.dart';
import 'package:mizapos_desktop/services/cloud/sync/cash_sync_constants.dart';
import 'package:mizapos_desktop/services/cloud/sync/catalog_sync_constants.dart';
import 'package:mizapos_desktop/services/cloud/sync/catalog_sync_outbox_writer.dart';
import 'package:mizapos_desktop/services/cloud/sync/expense_sync_constants.dart';
import 'package:mizapos_desktop/services/cloud/sync/invoice_sync_backfill.dart';
import 'package:mizapos_desktop/services/cloud/sync/opening_stock_sync_constants.dart';
import 'package:mizapos_desktop/services/cloud/sync/partners_sync_constants.dart';
import 'package:mizapos_desktop/services/cloud/sync/product_image_cloud_sync.dart';
import 'package:mizapos_desktop/services/cloud/sync/product_sync_outbox_writer.dart';
import 'package:mizapos_desktop/services/cloud/sync/tenant_sync_cursor_reset.dart';
import 'package:mizapos_desktop/services/cloud/sync/transactions/transaction_sync_constants.dart';
import 'package:mizapos_desktop/services/database_service.dart';
import 'package:mizapos_desktop/services/voucher_session_manager.dart';
import 'package:sqflite/sqflite.dart';

/// يوحّد معرّفات المؤسسة/الفرع المحلية مع حساب Miza Cloud ويرفع الكتالوج لأول مرة.
class CloudTenantBinder {
  CloudTenantBinder._();

  static const String _bindMetaScope = TenantSyncCursorReset.bindingScope;

  static const _skipTables = <String>{
    'organizations',
    'branches',
    'sqlite_sequence',
    'android_metadata',
  };

  /// أخطاء outbox لا يُعاد رفعها تلقائياً — تحتاج تدخلاً يدوياً أو جلسة جديدة.
  static const Set<String> _permanentOutboxErrors = {
    'unauthorized',
    'validation_error',
    'validation_failed',
    'invalid_request',
    'invalid_payload',
    'bad_request',
  };

  /// يصلح صفوف outbox الفاشلة القابلة للإصلاح ويعيدها إلى pending.
  ///
  /// When local org/branch differ from cloud, remap is gated by [allowRemap].
  static Future<CloudRepairResult> repairFailedOperations({
    required DatabaseService databaseService,
    required AccountingService accountingService,
    required CloudSecureStorage storage,
    bool allowRemap = false,
  }) async {
    final companyId = (await storage.readCompanyId())?.trim() ?? '';
    final branchId = (await storage.readBranchId())?.trim() ?? '';
    if (companyId.isEmpty || branchId.isEmpty) {
      return const CloudRepairResult(
        repairedCount: 0,
        remapped: false,
        message: 'missing_cloud_tenant',
      );
    }

    final db = await databaseService.database;
    final session = accountingService.session;
    final localOrg = session?.organizationId.trim() ?? '';
    final localBranch = session?.branchId.trim() ?? '';

    var remapped = false;
    if (localOrg.isNotEmpty &&
        localBranch.isNotEmpty &&
        (localOrg != companyId || localBranch != branchId)) {
      final autoRemap = allowRemap ||
          await _shouldAutoRemapSameTenant(
            db: db,
            accountingService: accountingService,
            storage: storage,
            localOrg: localOrg,
            cloudCompanyId: companyId,
          );
      if (!autoRemap) {
        return CloudRepairResult(
          repairedCount: 0,
          remapped: false,
          message: 'needs_remap',
          localOrganizationId: localOrg,
          localBranchId: localBranch,
          cloudCompanyId: companyId,
          cloudBranchId: branchId,
        );
      }
      remapped = await _remapOperationalScope(
        db: db,
        fromOrg: localOrg,
        fromBranch: localBranch,
        toOrg: companyId,
        toBranch: branchId,
      );
      if (remapped) {
        await accountingService.applyCloudTenantScope(
          organizationId: companyId,
          branchId: branchId,
        );
      }
    } else if (session != null &&
        (session.organizationId != companyId || session.branchId != branchId)) {
      await accountingService.applyCloudTenantScope(
        organizationId: companyId,
        branchId: branchId,
      );
    }

    await _resetCursorsForObservedTenantChange(
      db,
      companyId: companyId,
      alreadyResetByRemap: remapped,
    );
    await _markBound(
      db,
      companyId: companyId,
      branchId: branchId,
    );

    await _enqueueExistingCategories(
      db: db,
      organizationId: companyId,
      branchId: branchId,
      databaseService: databaseService,
      storage: storage,
    );

    var repaired = 0;
    repaired += await _repairFailedProductPush(
      db: db,
      organizationId: companyId,
      branchId: branchId,
      databaseService: databaseService,
      storage: storage,
    );
    repaired += await _repairFailedOpeningStockPush(
      db: db,
      organizationId: companyId,
      branchId: branchId,
    );
    repaired += await _repairProductNotFoundDependencies(
      db: db,
      organizationId: companyId,
      branchId: branchId,
      databaseService: databaseService,
      storage: storage,
    );
    repaired += await _repairPartnerNotFoundDependencies(db: db);
    repaired += await _repairInvoiceNotFoundDependencies(
      db: db,
      organizationId: companyId,
      branchId: branchId,
      databaseService: databaseService,
      storage: storage,
    );
    repaired += await _ackConflictCreateOutbox(db);
    repaired += await _repairFailedInvoicePush(db);
    repaired += await _repairFailedCashPush(db);
    repaired += await _repairFailedOutboxTenantScope(
      db: db,
      organizationId: companyId,
      branchId: branchId,
      excludeEntityTypes: {
        ProductSyncOutboxWriter.entityTypeProduct,
        OpeningStockSyncConstants.entityType,
        CashSyncConstants.entityType,
        ...TransactionSyncConstants.transactionEntityTypes,
      },
    );
    repaired += await ProductImageCloudSync.enqueueUnsyncedImageUpdates(
      databaseService: databaseService,
      organizationId: companyId,
      branchId: branchId,
    );

    if (kDebugMode) {
      debugPrint(
        'CloudTenantBinder.repairFailedOperations: repaired=$repaired remapped=$remapped',
      );
    }

    return CloudRepairResult(
      repairedCount: repaired,
      remapped: remapped,
      message: 'ok',
    );
  }

  /// إن كانت الجلسة السحابية جاهزة: اربط البيانات المحلية ثم املأ outbox للمنتجات.
  ///
  /// When local org/branch differ from cloud, remap is gated by [allowRemap].
  /// Callers should confirm with the user then retry with `allowRemap: true`.
  static Future<CloudTenantBindResult> bindIfNeeded({
    required DatabaseService databaseService,
    required AccountingService accountingService,
    required CloudSecureStorage storage,
    bool allowRemap = false,
  }) async {
    final companyId = (await storage.readCompanyId())?.trim() ?? '';
    final branchId = (await storage.readBranchId())?.trim() ?? '';
    if (companyId.isEmpty || branchId.isEmpty) {
      return const CloudTenantBindResult(
        remapped: false,
        productsEnqueued: 0,
        message: 'missing_cloud_tenant',
      );
    }

    final db = await databaseService.database;
    final session = accountingService.session;
    final localOrg = session?.organizationId.trim() ?? '';
    final localBranch = session?.branchId.trim() ?? '';

    var remapped = false;
    if (localOrg.isNotEmpty &&
        localBranch.isNotEmpty &&
        (localOrg != companyId || localBranch != branchId)) {
      final autoRemap = allowRemap ||
          await _shouldAutoRemapSameTenant(
            db: db,
            accountingService: accountingService,
            storage: storage,
            localOrg: localOrg,
            cloudCompanyId: companyId,
          );
      if (!autoRemap) {
        return CloudTenantBindResult(
          remapped: false,
          productsEnqueued: 0,
          message: 'needs_remap',
          localOrganizationId: localOrg,
          localBranchId: localBranch,
          cloudCompanyId: companyId,
          cloudBranchId: branchId,
        );
      }
      remapped = await _remapOperationalScope(
        db: db,
        fromOrg: localOrg,
        fromBranch: localBranch,
        toOrg: companyId,
        toBranch: branchId,
      );
      if (remapped) {
        await accountingService.applyCloudTenantScope(
          organizationId: companyId,
          branchId: branchId,
        );
      }
    } else if (session != null &&
        (session.organizationId != companyId ||
            session.branchId != branchId)) {
      await accountingService.applyCloudTenantScope(
        organizationId: companyId,
        branchId: branchId,
      );
    }

    final cursorTenantChanged = await _resetCursorsForObservedTenantChange(
      db,
      companyId: companyId,
      alreadyResetByRemap: remapped,
    );
    final alreadyBound = await _isAlreadyBound(
      db,
      companyId: companyId,
      branchId: branchId,
    );
    var enqueued = 0;
    if (!alreadyBound || remapped || cursorTenantChanged) {
      final cats = await _enqueueExistingCategories(
        db: db,
        organizationId: companyId,
        branchId: branchId,
        databaseService: databaseService,
        storage: storage,
      );
      final taxes = await _enqueueExistingTaxes(
        db: db,
        organizationId: companyId,
        branchId: branchId,
        databaseService: databaseService,
        storage: storage,
      );
      final priceLists = await _enqueueExistingPriceLists(
        db: db,
        organizationId: companyId,
        branchId: branchId,
        databaseService: databaseService,
        storage: storage,
      );
      enqueued = await _enqueueExistingProducts(
        db: db,
        organizationId: companyId,
        branchId: branchId,
        databaseService: databaseService,
        storage: storage,
      );
      enqueued += taxes + priceLists;
      await _markBound(
        db,
        companyId: companyId,
        branchId: branchId,
      );
      if (kDebugMode) {
        debugPrint(
          'CloudTenantBinder: categoriesEnqueued=$cats taxesEnqueued=$taxes '
          'priceListsEnqueued=$priceLists',
        );
      }

      // العملاء/الموردون قبل الفواتير (يشمل عميل نقدي / مورد نقدي).
      // فقط عند الربط الأول أو إعادة التعيين — المسح الكامل يبطئ كل مزامنة يدوية.
      final partnersEnqueued = await _enqueueExistingPartners(
        db: db,
        organizationId: companyId,
        branchId: branchId,
        databaseService: databaseService,
        storage: storage,
      );
      enqueued += partnersEnqueued;

      final cashEnqueued = await _enqueueExistingCashTransactions(
        db: db,
        organizationId: companyId,
        branchId: branchId,
        databaseService: databaseService,
        storage: storage,
      );
      enqueued += cashEnqueued;

      final expensesEnqueued = await _enqueueExistingExpenses(
        db: db,
        organizationId: companyId,
        branchId: branchId,
        databaseService: databaseService,
        storage: storage,
      );
      enqueued += expensesEnqueued;

      // فواتير مرحّلة قديمة لم تدخل outbox مطلقاً (قبل ربط المبيعات بالسحابة).
      final invoicesBackfilled =
          await InvoiceSyncBackfill.enqueueMissingPostedInvoices(
        databaseService: databaseService,
        storage: storage,
        organizationId: companyId,
        branchId: branchId,
      );
      enqueued += invoicesBackfilled;
      if (kDebugMode) {
        debugPrint(
          'CloudTenantBinder: partners=$partnersEnqueued cash=$cashEnqueued '
          'expenses=$expensesEnqueued invoicesBackfilled=$invoicesBackfilled',
        );
      }
    }

    // إصلاح منتجات فشلت بسبب category_id غير الموجود على السحابة.
    final repaired = await _repairFailedProductPush(
      db: db,
      organizationId: companyId,
      branchId: branchId,
      databaseService: databaseService,
      storage: storage,
    );
    enqueued += repaired;

    final openingStockRepaired = await _repairFailedOpeningStockPush(
      db: db,
      organizationId: companyId,
      branchId: branchId,
    );
    enqueued += openingStockRepaired;

    // صور محلية لم تُرفع بعد (منتجات رُفعت سابقاً بدون image_url).
    final imagesQueued = await ProductImageCloudSync.enqueueUnsyncedImageUpdates(
      databaseService: databaseService,
      organizationId: companyId,
      branchId: branchId,
    );
    enqueued += imagesQueued;

    // فواتير فشلت لأن المنتج غير موجود على السحابة بعد.
    enqueued += await _repairProductNotFoundDependencies(
      db: db,
      organizationId: companyId,
      branchId: branchId,
      databaseService: databaseService,
      storage: storage,
    );
    enqueued += await _repairPartnerNotFoundDependencies(db: db);
    enqueued += await _repairInvoiceNotFoundDependencies(
      db: db,
      organizationId: companyId,
      branchId: branchId,
      databaseService: databaseService,
      storage: storage,
    );

    final invoicesAcked = await _ackConflictCreateOutbox(db);
    final invoicesRepaired = await _repairFailedInvoicePush(db);
    final cashRepaired = await _repairFailedCashPush(db);
    if (kDebugMode) {
      debugPrint(
        'CloudTenantBinder: remapped=$remapped enqueued=$enqueued '
        'repaired=$repaired openingStockRepaired=$openingStockRepaired '
        'invoicesAcked=$invoicesAcked invoicesRepaired=$invoicesRepaired '
        'cashRepaired=$cashRepaired '
        'cloud=$companyId/$branchId localWas=$localOrg/$localBranch',
      );
    }

    return CloudTenantBindResult(
      remapped: remapped,
      productsEnqueued: enqueued,
      message: 'ok',
    );
  }

  /// ربط تلقائي آمن في الحالات الشائعة؛ الحوار فقط عند تبديل حساب سحابي مختلف.
  static Future<bool> _shouldAutoRemapSameTenant({
    required Database db,
    required AccountingService accountingService,
    required CloudSecureStorage storage,
    required String localOrg,
    required String cloudCompanyId,
  }) async {
    final cloud = cloudCompanyId.trim();
    if (localOrg.trim() == cloud) {
      return true;
    }

    // سبق ربط هذا الجهاز بهذا الحساب السحابي — أعد المحاذاة بصمت.
    if (await _hasCloudTenantBindForCompany(db, cloud)) {
      return true;
    }

    // لم يُربط الجهاز من قبل بحساب سحابي آخر → أول ربط (المعرّف المحلي ≠ السحابي).
    // هذه الحالة هي الأكثر شيوعاً بعد إنشاء المتجر محلياً ثم تسجيل دخول Miza Cloud.
    final otherCloudBind = await db.query(
      'sync_meta',
      columns: const ['organization_id'],
      where: 'scope_key = ? AND organization_id != ?',
      whereArgs: [_bindMetaScope, cloud],
      limit: 1,
    );
    if (otherCloudBind.isEmpty) {
      return true;
    }

    final cloudUser =
        (await storage.readCloudUsername())?.trim().toLowerCase() ?? '';
    if (cloudUser.isEmpty || !cloudUser.contains('@')) return false;

    final voucherEmail = VoucherSessionManager
            .instance.sessionNotifier.value?.email
            .trim()
            .toLowerCase() ??
        '';
    if (voucherEmail.isNotEmpty && voucherEmail == cloudUser) return true;

    try {
      final sub = await accountingService.activeSubscriptionEmailForSync(
        localOrganizationId: localOrg,
      );
      final localEmail = (sub ?? '').trim().toLowerCase();
      if (localEmail.isNotEmpty && localEmail == cloudUser) return true;
    } catch (_) {}
    return false;
  }

  static Future<bool> _hasCloudTenantBindForCompany(
    Database db,
    String companyId,
  ) async {
    final rows = await db.query(
      'sync_meta',
      columns: const ['organization_id'],
      where: 'scope_key = ? AND organization_id = ?',
      whereArgs: [_bindMetaScope, companyId.trim()],
      limit: 1,
    );
    return rows.isNotEmpty;
  }

  static Future<bool> _resetCursorsForObservedTenantChange(
    Database db, {
    required String companyId,
    required bool alreadyResetByRemap,
  }) async {
    if (alreadyResetByRemap) return true;

    final rows = await db.query(
      'sync_meta',
      columns: const ['organization_id'],
      where: 'scope_key = ?',
      whereArgs: const [_bindMetaScope],
      orderBy: 'updated_at DESC',
      limit: 1,
    );
    if (rows.isEmpty) return false;

    final previousCompanyId =
        (rows.first['organization_id'] ?? '').toString().trim();
    final currentCompanyId = companyId.trim();
    if (previousCompanyId.isEmpty ||
        currentCompanyId.isEmpty ||
        previousCompanyId == currentCompanyId) {
      return false;
    }

    await db.transaction((txn) {
      return TenantSyncCursorReset.forOrganizationChange(
        txn,
        fromOrganizationId: previousCompanyId,
        toOrganizationId: currentCompanyId,
      );
    });
    return true;
  }

  static Future<bool> _isAlreadyBound(
    Database db, {
    required String companyId,
    required String branchId,
  }) async {
    final rows = await db.query(
      'sync_meta',
      columns: const ['updated_at'],
      where: 'organization_id = ? AND branch_id = ? AND scope_key = ?',
      whereArgs: [companyId, branchId, _bindMetaScope],
      limit: 1,
    );
    return rows.isNotEmpty;
  }

  static Future<void> _markBound(
    Database db, {
    required String companyId,
    required String branchId,
  }) async {
    final now = DateTime.now().toIso8601String();
    await db.insert(
      'sync_meta',
      {
        'organization_id': companyId,
        'branch_id': branchId,
        'scope_key': _bindMetaScope,
        'last_pulled_sequence': 0,
        'last_pushed_sequence': 0,
        'last_pulled_at': null,
        'last_pushed_at': now,
        'cloud_version_catalog': 0,
        'cloud_version_invoices': 0,
        'cloud_version_users': 0,
        'updated_at': now,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  static Future<bool> _remapOperationalScope({
    required Database db,
    required String fromOrg,
    required String fromBranch,
    required String toOrg,
    required String toBranch,
  }) async {
    if (fromOrg == toOrg && fromBranch == toBranch) return false;

    await _ensureOrganizationAndBranch(
      db,
      toOrg: toOrg,
      toBranch: toBranch,
      fromOrg: fromOrg,
      fromBranch: fromBranch,
    );

    await db.transaction((txn) async {
      await TenantSyncCursorReset.forOrganizationChange(
        txn,
        fromOrganizationId: fromOrg,
        toOrganizationId: toOrg,
      );

      final tables = await txn.rawQuery(
        "SELECT name FROM sqlite_master WHERE type = 'table' AND name NOT LIKE 'sqlite_%'",
      );
      for (final row in tables) {
        final table = (row['name'] ?? '').toString();
        if (table.isEmpty || _skipTables.contains(table)) continue;

        final cols = await txn.rawQuery('PRAGMA table_info($table)');
        final names = cols
            .map((c) => (c['name'] ?? '').toString())
            .where((n) => n.isNotEmpty)
            .toSet();

        // نقل الصفوف التشغيلية فقط — لا تغيّر جداول المفاتيح الأساسية هنا.
        if (names.contains('organizationId') && names.contains('branchId')) {
          await txn.rawUpdate(
            'UPDATE $table SET organizationId = ?, branchId = ? '
            'WHERE organizationId = ? AND branchId = ?',
            [toOrg, toBranch, fromOrg, fromBranch],
          );
          // صفوف قديمة على نفس المؤسسة لكن بفرع آخر (نادرة).
          if (fromOrg != toOrg) {
            await txn.rawUpdate(
              'UPDATE $table SET organizationId = ? '
              'WHERE organizationId = ? AND (branchId IS NULL OR branchId = ? OR branchId = ?)',
              [toOrg, fromOrg, fromBranch, ''],
            );
          }
        } else if (names.contains('organizationId') && fromOrg != toOrg) {
          await txn.rawUpdate(
            'UPDATE $table SET organizationId = ? WHERE organizationId = ?',
            [toOrg, fromOrg],
          );
        }

        if (names.contains('organization_id') && names.contains('branch_id')) {
          await txn.rawUpdate(
            'UPDATE $table SET organization_id = ?, branch_id = ? '
            'WHERE organization_id = ? AND branch_id = ?',
            [toOrg, toBranch, fromOrg, fromBranch],
          );
        } else if (names.contains('organization_id') && fromOrg != toOrg) {
          await txn.rawUpdate(
            'UPDATE $table SET organization_id = ? WHERE organization_id = ?',
            [toOrg, fromOrg],
          );
        }
      }

      // المستخدمون: انقل الجميع على مستأجر السحابة.
      await txn.rawUpdate(
        'UPDATE users SET organizationId = ?, branchId = ? WHERE organizationId = ?',
        [toOrg, toBranch, fromOrg],
      );

      // احذف الفرع المحلي القديم إن اختلف عن فرع السحابة.
      if (fromBranch != toBranch) {
        await txn.delete('branches', where: 'id = ?', whereArgs: [fromBranch]);
      } else if (fromOrg != toOrg) {
        // نفس id الفرع لكن تحت مؤسسة أخرى — نحدّث الـ org فقط بعد ضمان الفرع الهدف.
        await txn.rawUpdate(
          'UPDATE branches SET organizationId = ? WHERE id = ?',
          [toOrg, fromBranch],
        );
      }

      if (fromOrg != toOrg) {
        final remainingBranches = await txn.query(
          'branches',
          where: 'organizationId = ?',
          whereArgs: [fromOrg],
        );
        if (remainingBranches.isEmpty) {
          await txn.delete(
            'organizations',
            where: 'id = ?',
            whereArgs: [fromOrg],
          );
        }
      }
    });

    return true;
  }

  static Future<void> _ensureOrganizationAndBranch(
    Database db, {
    required String toOrg,
    required String toBranch,
    required String fromOrg,
    required String fromBranch,
  }) async {
    final orgRows = await db.query(
      'organizations',
      where: 'id = ?',
      whereArgs: [toOrg],
      limit: 1,
    );
    if (orgRows.isEmpty) {
      final src = await db.query(
        'organizations',
        where: 'id = ?',
        whereArgs: [fromOrg],
        limit: 1,
      );
      final name = src.isNotEmpty
          ? (src.first['name'] ?? 'Store').toString()
          : 'Store';
      await db.insert(
        'organizations',
        {
          'id': toOrg,
          'name': name,
          'createdAt': DateTime.now().toIso8601String(),
        },
        conflictAlgorithm: ConflictAlgorithm.ignore,
      );
    }

    final branchRows = await db.query(
      'branches',
      where: 'id = ?',
      whereArgs: [toBranch],
      limit: 1,
    );
    if (branchRows.isEmpty) {
      final src = await db.query(
        'branches',
        where: 'id = ?',
        whereArgs: [fromBranch],
        limit: 1,
      );
      final name = src.isNotEmpty
          ? (src.first['name'] ?? 'Main').toString()
          : 'Main';
      // استخدم كوداً فريداً لتجنّب UNIQUE(organizationId, code) مع الفرع المحلي.
      final code = 'C${toBranch.replaceAll('-', '').substring(0, 8).toUpperCase()}';
      await db.insert(
        'branches',
        {
          'id': toBranch,
          'organizationId': toOrg,
          'name': name,
          'code': code,
          'createdAt': DateTime.now().toIso8601String(),
        },
        conflictAlgorithm: ConflictAlgorithm.ignore,
      );
    } else {
      // تأكد أن فرع السحابة يتبع الشركة السحابية.
      await db.rawUpdate(
        'UPDATE branches SET organizationId = ? WHERE id = ? AND organizationId != ?',
        [toOrg, toBranch, toOrg],
      );
    }
  }

  static Future<int> _enqueueExistingCategories({
    required Database db,
    required String organizationId,
    required String branchId,
    required DatabaseService databaseService,
    required CloudSecureStorage storage,
  }) async {
    final rows = await db.query(
      'product_categories',
      where: 'organizationId = ? AND branchId = ?',
      whereArgs: [organizationId, branchId],
    );
    var count = 0;
    for (final row in rows) {
      final id = (row['id'] ?? '').toString();
      if (id.isEmpty) continue;
      final already = await db.query(
        'sync_outbox',
        columns: const ['id'],
        where: 'entity_type = ? AND entity_id = ? AND operation = ?',
        whereArgs: [
          CatalogSyncConstants.entityTypeProductCategory,
          id,
          'create',
        ],
        limit: 1,
      );
      if (already.isNotEmpty) continue;

      await CatalogSyncOutboxWriter.record(
        entityType: CatalogSyncConstants.entityTypeProductCategory,
        operation: 'create',
        entityId: id,
        organizationId: organizationId,
        branchId: branchId,
        payload: {
          'id': id,
          'company_id': organizationId,
          'branch_id': branchId,
          'name': (row['name'] ?? '').toString(),
          'sort_order': ((row['sortOrder'] as num?) ?? 0).toInt(),
        },
        databaseService: databaseService,
        storage: storage,
      );
      count++;
    }
    return count;
  }

  static Future<int> _enqueueExistingTaxes({
    required Database db,
    required String organizationId,
    required String branchId,
    required DatabaseService databaseService,
    required CloudSecureStorage storage,
  }) async {
    final rows = await db.query(
      'taxes',
      where: 'organizationId = ? AND branchId = ?',
      whereArgs: [organizationId, branchId],
    );
    var count = 0;
    for (final row in rows) {
      final id = (row['id'] ?? '').toString();
      if (id.isEmpty) continue;
      final already = await db.query(
        'sync_outbox',
        columns: const ['id'],
        where: 'entity_type = ? AND entity_id = ? AND operation = ?',
        whereArgs: [CatalogSyncConstants.entityTypeTax, id, 'create'],
        limit: 1,
      );
      if (already.isNotEmpty) continue;

      await CatalogSyncOutboxWriter.record(
        entityType: CatalogSyncConstants.entityTypeTax,
        operation: 'create',
        entityId: id,
        organizationId: organizationId,
        branchId: branchId,
        payload: taxEntityCloudPayload(
          id: id,
          organizationId: organizationId,
          branchId: branchId,
          name: (row['name'] ?? '').toString(),
          percent: ((row['percent'] as num?) ?? 0).toDouble(),
          isDefault: ((row['isDefault'] as num?) ?? 0) != 0,
          sortOrder: ((row['sortOrder'] as num?) ?? 0).toInt(),
        ),
        databaseService: databaseService,
        storage: storage,
      );
      count++;
    }
    return count;
  }

  static Future<int> _enqueueExistingPriceLists({
    required Database db,
    required String organizationId,
    required String branchId,
    required DatabaseService databaseService,
    required CloudSecureStorage storage,
  }) async {
    final rows = await db.query(
      'price_lists',
      where: 'organizationId = ? AND branchId = ?',
      whereArgs: [organizationId, branchId],
    );
    var count = 0;
    for (final row in rows) {
      final id = (row['id'] ?? '').toString();
      if (id.isEmpty) continue;
      final already = await db.query(
        'sync_outbox',
        columns: const ['id'],
        where: 'entity_type = ? AND entity_id = ? AND operation = ?',
        whereArgs: [CatalogSyncConstants.entityTypePriceList, id, 'create'],
        limit: 1,
      );
      if (already.isNotEmpty) continue;

      final itemRows = await db.query(
        'price_list_items',
        where: 'priceListId = ?',
        whereArgs: [id],
      );
      final items = itemRows
          .map(
            (item) => {
              'id': (item['id'] ?? '').toString(),
              'product_id': (item['productId'] ?? '').toString(),
              'sale_price': ((item['salePrice'] as num?) ?? 0).toDouble(),
            },
          )
          .where((item) => (item['product_id'] as String).isNotEmpty)
          .toList();

      await CatalogSyncOutboxWriter.record(
        entityType: CatalogSyncConstants.entityTypePriceList,
        operation: 'create',
        entityId: id,
        organizationId: organizationId,
        branchId: branchId,
        payload: priceListEntityCloudPayload(
          id: id,
          organizationId: organizationId,
          branchId: branchId,
          name: (row['name'] ?? '').toString(),
          isDefault: ((row['isDefault'] as num?) ?? 0) != 0,
          sortOrder: ((row['sortOrder'] as num?) ?? 0).toInt(),
          items: items,
        ),
        databaseService: databaseService,
        storage: storage,
      );
      count++;
    }
    return count;
  }

  static Future<int> _enqueueExistingProducts({
    required Database db,
    required String organizationId,
    required String branchId,
    required DatabaseService databaseService,
    required CloudSecureStorage storage,
  }) async {
    final rows = await db.query(
      'products',
      where: 'organizationId = ? AND branchId = ?',
      whereArgs: [organizationId, branchId],
    );
    var count = 0;
    for (final row in rows) {
      final productId = (row['id'] ?? '').toString();
      if (productId.isEmpty) continue;

      final already = await db.query(
        'sync_outbox',
        columns: const ['id'],
        where: 'entity_type = ? AND entity_id = ? AND operation = ?',
        whereArgs: [
          ProductSyncOutboxWriter.entityTypeProduct,
          productId,
          'create',
        ],
        limit: 1,
      );
      if (already.isNotEmpty) continue;

      final product = _productFromRow(row);
      await ProductSyncOutboxWriter.record(
        operation: 'create',
        productId: productId,
        organizationId: organizationId,
        branchId: branchId,
        product: product,
        databaseService: databaseService,
        storage: storage,
      );
      count++;
    }
    return count;
  }

  /// يرفع العملاء والموردين الحاليين (بما فيهم نقدي) قبل فواتير الـ outbox.
  static Future<int> _enqueueExistingPartners({
    required Database db,
    required String organizationId,
    required String branchId,
    required DatabaseService databaseService,
    required CloudSecureStorage storage,
  }) async {
    var count = 0;
    count += await _enqueuePartnerTable(
      db: db,
      table: 'customers',
      entityType: PartnersSyncConstants.entityTypeCustomer,
      numberColumn: 'customerNumber',
      organizationId: organizationId,
      branchId: branchId,
      databaseService: databaseService,
      storage: storage,
    );
    count += await _enqueuePartnerTable(
      db: db,
      table: 'suppliers',
      entityType: PartnersSyncConstants.entityTypeSupplier,
      numberColumn: 'supplierNumber',
      organizationId: organizationId,
      branchId: branchId,
      databaseService: databaseService,
      storage: storage,
    );
    return count;
  }

  static Future<int> _enqueuePartnerTable({
    required Database db,
    required String table,
    required String entityType,
    required String numberColumn,
    required String organizationId,
    required String branchId,
    required DatabaseService databaseService,
    required CloudSecureStorage storage,
  }) async {
    final rows = await db.query(
      table,
      where: 'organizationId = ? AND branchId = ?',
      whereArgs: [organizationId, branchId],
    );
    var count = 0;
    for (final row in rows) {
      final id = (row['id'] ?? '').toString();
      if (id.isEmpty) continue;
      final already = await db.query(
        'sync_outbox',
        columns: const ['id', 'sync_state'],
        where: 'entity_type = ? AND entity_id = ?',
        whereArgs: [entityType, id],
        limit: 1,
      );
      final name = (row['name'] ?? '').toString();
      if (name.isEmpty) continue;
      final payload = partnerEntityCloudPayload(
        id: id,
        organizationId: organizationId,
        branchId: branchId,
        name: name,
        partnerNumber: row[numberColumn]?.toString(),
        phone: row['phone']?.toString(),
        address: row['address']?.toString(),
        notes: row['notes']?.toString(),
        creditLimit: (row['creditLimit'] as num?)?.toDouble() ?? 0,
        overdueAlertDays: (row['overdueAlertDays'] as num?)?.toInt(),
      );

      if (already.isNotEmpty) {
        final state = (already.first['sync_state'] ?? '').toString();
        if (state == 'synced' || state == 'pending') continue;
        final outboxId = (already.first['id'] ?? '').toString();
        if (outboxId.isEmpty) continue;
        await db.update(
          'sync_outbox',
          {
            'sync_state': 'pending',
            'last_sync_error': null,
            'payload_json': jsonEncode(payload),
            'organization_id': organizationId,
            'branch_id': branchId,
            'operation': 'create',
            'updated_at': DateTime.now().toIso8601String(),
          },
          where: 'id = ?',
          whereArgs: [outboxId],
        );
        count++;
        continue;
      }

      await CatalogSyncOutboxWriter.record(
        entityType: entityType,
        operation: 'create',
        entityId: id,
        organizationId: organizationId,
        branchId: branchId,
        payload: payload,
        databaseService: databaseService,
        storage: storage,
      );
      count++;
    }
    return count;
  }

  /// يرفع حركات الصندوق المحلية (ما عدا دفعات العملاء/الموردين المضمّنة في post).
  static Future<int> _enqueueExistingCashTransactions({
    required Database db,
    required String organizationId,
    required String branchId,
    required DatabaseService databaseService,
    required CloudSecureStorage storage,
  }) async {
    final rows = await db.query(
      'cashTransactions',
      where: 'organizationId = ? AND branchId = ?',
      whereArgs: [organizationId, branchId],
    );
    var count = 0;
    for (final row in rows) {
      final id = (row['id'] ?? '').toString();
      if (id.isEmpty) continue;
      final refType = (row['referenceType'] ?? '').toString().trim().toLowerCase();
      if (CashSyncConstants.paymentSyncedReferenceTypes.contains(refType)) {
        continue;
      }

      final already = await db.query(
        'sync_outbox',
        columns: const ['id', 'sync_state'],
        where: 'entity_type = ? AND entity_id = ?',
        whereArgs: [CashSyncConstants.entityType, id],
        limit: 1,
      );
      final type = (row['transactionType'] ?? '').toString().toLowerCase();
      if (type != 'in' && type != 'out') continue;
      final amount = (row['amount'] as num?)?.toDouble() ?? 0;
      if (amount <= 0) continue;
      final createdBy = (row['createdBy'] ?? '').toString();
      if (createdBy.isEmpty) continue;

      final payload = cashEntityCloudPayload(
        id: id,
        organizationId: organizationId,
        branchId: branchId,
        transactionType: type,
        amount: amount,
        description: (row['description'] ?? '').toString(),
        referenceType: (row['referenceType'] ?? 'manual').toString(),
        referenceId: (row['referenceId'] ?? id).toString(),
        transactionDate: (row['transactionDate'] ?? DateTime.now().toIso8601String())
            .toString(),
        createdByUserId: createdBy,
      );

      if (already.isNotEmpty) {
        final state = (already.first['sync_state'] ?? '').toString();
        if (state == 'synced' || state == 'pending') continue;
        final outboxId = (already.first['id'] ?? '').toString();
        if (outboxId.isEmpty) continue;
        await db.update(
          'sync_outbox',
          {
            'sync_state': 'pending',
            'last_sync_error': null,
            'payload_json': jsonEncode(payload),
            'organization_id': organizationId,
            'branch_id': branchId,
            'operation': 'create',
            'updated_at': DateTime.now().toIso8601String(),
          },
          where: 'id = ?',
          whereArgs: [outboxId],
        );
        count++;
        continue;
      }

      await CatalogSyncOutboxWriter.record(
        entityType: CashSyncConstants.entityType,
        operation: 'create',
        entityId: id,
        organizationId: organizationId,
        branchId: branchId,
        payload: payload,
        databaseService: databaseService,
        storage: storage,
      );
      count++;
    }
    return count;
  }

  /// يرفع المصاريف المحلية قبل/مع صندوق المصروف.
  static Future<int> _enqueueExistingExpenses({
    required Database db,
    required String organizationId,
    required String branchId,
    required DatabaseService databaseService,
    required CloudSecureStorage storage,
  }) async {
    final rows = await db.query(
      'expenses',
      where: 'organizationId = ? AND branchId = ?',
      whereArgs: [organizationId, branchId],
    );
    var count = 0;
    for (final row in rows) {
      final id = (row['id'] ?? '').toString();
      if (id.isEmpty) continue;
      final already = await db.query(
        'sync_outbox',
        columns: const ['id', 'sync_state'],
        where: 'entity_type = ? AND entity_id = ?',
        whereArgs: [ExpenseSyncConstants.entityType, id],
        limit: 1,
      );
      final title = (row['title'] ?? '').toString();
      if (title.isEmpty) continue;
      final amount = (row['amount'] as num?)?.toDouble() ?? 0;
      if (amount <= 0) continue;
      final createdBy = (row['createdBy'] ?? '').toString();
      if (createdBy.isEmpty) continue;
      final payload = expenseEntityCloudPayload(
        id: id,
        organizationId: organizationId,
        branchId: branchId,
        title: title,
        amount: amount,
        expenseDate: (row['expenseDate'] ?? DateTime.now().toIso8601String())
            .toString(),
        createdByUserId: createdBy,
        notes: row['notes']?.toString(),
      );
      if (already.isNotEmpty) {
        final state = (already.first['sync_state'] ?? '').toString();
        if (state == 'synced' || state == 'pending') continue;
        final outboxId = (already.first['id'] ?? '').toString();
        if (outboxId.isEmpty) continue;
        await db.update(
          'sync_outbox',
          {
            'sync_state': 'pending',
            'last_sync_error': null,
            'payload_json': jsonEncode(payload),
            'organization_id': organizationId,
            'branch_id': branchId,
            'operation': 'create',
            'updated_at': DateTime.now().toIso8601String(),
          },
          where: 'id = ?',
          whereArgs: [outboxId],
        );
        count++;
        continue;
      }
      await CatalogSyncOutboxWriter.record(
        entityType: ExpenseSyncConstants.entityType,
        operation: 'create',
        entityId: id,
        organizationId: organizationId,
        branchId: branchId,
        payload: payload,
        databaseService: databaseService,
        storage: storage,
      );
      count++;
    }
    return count;
  }

  /// Create conflict = invoice already on server → mark create synced so post can proceed.
  static Future<int> _ackConflictCreateOutbox(Database db) async {
    final now = DateTime.now().toIso8601String();
    final entityPlaceholders = List.filled(
      TransactionSyncConstants.transactionEntityTypes.length,
      '?',
    ).join(',');
    var updated = await db.rawUpdate(
      'UPDATE sync_outbox SET sync_state = ?, last_sync_error = NULL, '
      'synced_at = ?, updated_at = ? '
      'WHERE sync_state = ? AND operation = ? AND last_sync_error = ? '
      'AND entity_type IN ($entityPlaceholders)',
      [
        'synced',
        now,
        now,
        'failed',
        'create',
        'conflict',
        ...TransactionSyncConstants.transactionEntityTypes,
      ],
    );
    // تعارض الترحيل: غالباً الفاتورة مرحّلة على جهاز آخر — أعد المحاولة بعد السحب.
    updated += await db.rawUpdate(
      'UPDATE sync_outbox SET sync_state = ?, last_sync_error = NULL, '
      'updated_at = ? WHERE sync_state = ? AND last_sync_error IN (?, ?) '
      'AND entity_type IN ($entityPlaceholders)',
      [
        'pending',
        now,
        'failed',
        'posting_conflict',
        'create_version_conflict',
        ...TransactionSyncConstants.transactionEntityTypes,
      ],
    );
    return updated;
  }

  /// يعيد معاملات فشلت (تعارض، خطأ مؤقت، إلخ) إلى pending.
  static Future<int> _repairFailedInvoicePush(Database db) async {
    final now = DateTime.now().toIso8601String();
    final entityPlaceholders = List.filled(
      TransactionSyncConstants.transactionEntityTypes.length,
      '?',
    ).join(',');
    final errorPlaceholders =
        List.filled(_permanentOutboxErrors.length, '?').join(',');
    final updated = await db.rawUpdate(
      'UPDATE sync_outbox SET sync_state = ?, last_sync_error = NULL, '
      'updated_at = ? WHERE sync_state = ? AND entity_type IN ($entityPlaceholders) '
      'AND (last_sync_error IS NULL OR last_sync_error NOT IN ($errorPlaceholders))',
      [
        'pending',
        now,
        'failed',
        ...TransactionSyncConstants.transactionEntityTypes,
        ..._permanentOutboxErrors,
      ],
    );
    return updated;
  }

  /// يجمع معرّفات المنتجات من payload فاتورة/معاملة فاشلة.
  static Set<String> _productIdsFromPayload(Map<String, dynamic> payload) {
    final ids = <String>{};
    void walk(Object? node) {
      if (node is Map) {
        final map = Map<Object?, Object?>.from(node);
        final raw = map['product_id'] ?? map['productId'];
        final id = raw?.toString().trim() ?? '';
        if (id.isNotEmpty) ids.add(id);
        for (final value in map.values) {
          walk(value);
        }
      } else if (node is List) {
        for (final value in node) {
          walk(value);
        }
      }
    }

    walk(payload);
    return ids;
  }

  /// يضمن رفع المنتجات المشار إليها في فواتير فشلت بـ product_not_found ثم يعيد الفواتير.
  static Future<int> _repairProductNotFoundDependencies({
    required Database db,
    required String organizationId,
    required String branchId,
    required DatabaseService databaseService,
    required CloudSecureStorage storage,
  }) async {
    final failed = await db.query(
      'sync_outbox',
      where: 'sync_state = ? AND last_sync_error = ?',
      whereArgs: ['failed', 'product_not_found'],
    );
    if (failed.isEmpty) return 0;

    final productIds = <String>{};
    final invoiceOutboxIds = <String>[];
    for (final row in failed) {
      final outboxId = (row['id'] ?? '').toString();
      if (outboxId.isNotEmpty) invoiceOutboxIds.add(outboxId);
      Map<String, dynamic> payload;
      try {
        final decoded = jsonDecode((row['payload_json'] ?? '{}').toString());
        payload = decoded is Map
            ? Map<String, dynamic>.from(decoded)
            : <String, dynamic>{};
      } on Object {
        payload = <String, dynamic>{};
      }
      productIds.addAll(_productIdsFromPayload(payload));
    }

    var repaired = 0;
    final now = DateTime.now().toIso8601String();
    for (final productId in productIds) {
      final local = await db.query(
        'products',
        columns: const ['id'],
        where: 'id = ?',
        whereArgs: [productId],
        limit: 1,
      );
      if (local.isEmpty) continue;

      repaired += await db.rawUpdate(
        'UPDATE sync_outbox SET sync_state = ?, last_sync_error = NULL, '
        'updated_at = ? WHERE entity_type = ? AND entity_id = ? AND sync_state = ?',
        [
          'pending',
          now,
          ProductSyncOutboxWriter.entityTypeProduct,
          productId,
          'failed',
        ],
      );

      final pending = await db.query(
        'sync_outbox',
        columns: const ['id'],
        where: 'entity_type = ? AND entity_id = ? AND sync_state = ?',
        whereArgs: [
          ProductSyncOutboxWriter.entityTypeProduct,
          productId,
          'pending',
        ],
        limit: 1,
      );
      if (pending.isNotEmpty) continue;

      await ProductSyncOutboxWriter.record(
        operation: 'update',
        productId: productId,
        organizationId: organizationId,
        branchId: branchId,
        databaseService: databaseService,
        storage: storage,
      );
      repaired++;
    }

    if (invoiceOutboxIds.isNotEmpty) {
      final placeholders = List.filled(invoiceOutboxIds.length, '?').join(',');
      repaired += await db.rawUpdate(
        'UPDATE sync_outbox SET sync_state = ?, last_sync_error = NULL, '
        'updated_at = ? WHERE id IN ($placeholders)',
        ['pending', now, ...invoiceOutboxIds],
      );
    }
    return repaired;
  }

  /// يعيد العملاء/الموردين المعلقين ومعاملات فشلت بـ partner_not_found.
  static Future<int> _repairPartnerNotFoundDependencies({
    required Database db,
  }) async {
    final now = DateTime.now().toIso8601String();
    var repaired = await db.rawUpdate(
      'UPDATE sync_outbox SET sync_state = ?, last_sync_error = NULL, '
      'updated_at = ? WHERE sync_state = ? AND entity_type IN (?, ?)',
      [
        'pending',
        now,
        'failed',
        PartnersSyncConstants.entityTypeCustomer,
        PartnersSyncConstants.entityTypeSupplier,
      ],
    );
    repaired += await db.rawUpdate(
      'UPDATE sync_outbox SET sync_state = ?, last_sync_error = NULL, '
      'updated_at = ? WHERE sync_state = ? AND last_sync_error = ?',
      ['pending', now, 'failed', 'partner_not_found'],
    );
    return repaired;
  }

  /// يعيد فواتير فشلت بـ not_found/apply_failed (ترحيل قبل المسودة) إلى pending.
  static Future<int> _repairInvoiceNotFoundDependencies({
    required Database db,
    required String organizationId,
    required String branchId,
    required DatabaseService databaseService,
    required CloudSecureStorage storage,
  }) async {
    final now = DateTime.now().toIso8601String();
    final entityPlaceholders = List.filled(
      TransactionSyncConstants.transactionEntityTypes.length,
      '?',
    ).join(',');
    const recoverable = <String>[
      'not_found',
      'invoice_not_found',
      'partner_not_found',
      'apply_failed',
      'draft_not_found',
    ];
    final errorPlaceholders = List.filled(recoverable.length, '?').join(',');

    final failed = await db.rawQuery(
      'SELECT id, entity_id, entity_type FROM sync_outbox '
      'WHERE sync_state = ? AND entity_type IN ($entityPlaceholders) '
      'AND last_sync_error IN ($errorPlaceholders)',
      [
        'failed',
        ...TransactionSyncConstants.transactionEntityTypes,
        ...recoverable,
      ],
    );
    if (failed.isEmpty) return 0;

    final entityIds = <String>{};
    final outboxIds = <String>[];
    for (final row in failed) {
      final id = (row['id'] ?? '').toString();
      final entityId = (row['entity_id'] ?? '').toString();
      if (id.isNotEmpty) outboxIds.add(id);
      if (entityId.isNotEmpty) entityIds.add(entityId);
    }

    var repaired = 0;
    if (entityIds.isNotEmpty) {
      final idPlaceholders = List.filled(entityIds.length, '?').join(',');
      repaired += await db.rawUpdate(
        'UPDATE sync_outbox SET sync_state = ?, last_sync_error = NULL, '
        'updated_at = ? WHERE sync_state = ? AND operation = ? '
        'AND entity_type IN ($entityPlaceholders) '
        'AND entity_id IN ($idPlaceholders)',
        [
          'pending',
          now,
          'failed',
          'create',
          ...TransactionSyncConstants.transactionEntityTypes,
          ...entityIds,
        ],
      );
    }

    if (outboxIds.isNotEmpty) {
      final outboxPlaceholders = List.filled(outboxIds.length, '?').join(',');
      repaired += await db.rawUpdate(
        'UPDATE sync_outbox SET sync_state = ?, last_sync_error = NULL, '
        'updated_at = ? WHERE id IN ($outboxPlaceholders)',
        ['pending', now, ...outboxIds],
      );
    }
    return repaired;
  }

  /// يعيد حركات صندوق فشلت (مثل created_by المحلي غير الموجود على السحابة) إلى pending.
  static Future<int> _repairFailedCashPush(Database db) async {
    final now = DateTime.now().toIso8601String();
    final errorPlaceholders =
        List.filled(_permanentOutboxErrors.length, '?').join(',');
    return db.rawUpdate(
      'UPDATE sync_outbox SET sync_state = ?, last_sync_error = NULL, '
      'updated_at = ? WHERE sync_state = ? AND entity_type = ? '
      'AND (last_sync_error IS NULL OR last_sync_error NOT IN ($errorPlaceholders))',
      [
        'pending',
        now,
        'failed',
        CashSyncConstants.entityType,
        ..._permanentOutboxErrors,
      ],
    );
  }

  /// يصلح outbox عاماً بتحديث company/branch في payload ثم إعادة pending.
  static Future<int> _repairFailedOutboxTenantScope({
    required Database db,
    required String organizationId,
    required String branchId,
    required Set<String> excludeEntityTypes,
  }) async {
    final errorPlaceholders =
        List.filled(_permanentOutboxErrors.length, '?').join(',');
    final failed = await db.query(
      'sync_outbox',
      where: 'sync_state = ? AND (last_sync_error IS NULL OR '
          'last_sync_error NOT IN ($errorPlaceholders))',
      whereArgs: ['failed', ..._permanentOutboxErrors],
    );
    if (failed.isEmpty) return 0;

    final now = DateTime.now().toIso8601String();
    var repaired = 0;
    for (final row in failed) {
      final entityType = (row['entity_type'] ?? '').toString();
      if (excludeEntityTypes.contains(entityType)) continue;

      final id = (row['id'] ?? '').toString();
      if (id.isEmpty) continue;

      Map<String, dynamic> payload;
      try {
        final decoded = jsonDecode((row['payload_json'] ?? '{}').toString());
        payload = decoded is Map<String, dynamic>
            ? Map<String, dynamic>.from(decoded)
            : <String, dynamic>{};
      } on Object {
        payload = <String, dynamic>{};
      }
      _patchPayloadTenant(payload, organizationId, branchId);

      await db.update(
        'sync_outbox',
        {
          'sync_state': 'pending',
          'last_sync_error': null,
          'payload_json': jsonEncode(payload),
          'organization_id': organizationId,
          'branch_id': branchId,
          'updated_at': now,
        },
        where: 'id = ?',
        whereArgs: [id],
      );
      repaired++;
    }
    return repaired;
  }

  static void _patchPayloadTenant(
    Map<String, dynamic> payload,
    String organizationId,
    String branchId,
  ) {
    payload['company_id'] = organizationId;
    payload['branch_id'] = branchId;

    final aggregateRaw = payload['aggregate'];
    if (aggregateRaw is! Map) return;

    final aggregate = Map<String, dynamic>.from(aggregateRaw);
    final headerRaw = aggregate['header'];
    if (headerRaw is Map) {
      final header = Map<String, dynamic>.from(headerRaw);
      header['company_id'] = organizationId;
      header['branch_id'] = branchId;
      aggregate['header'] = header;
    }
    payload['aggregate'] = aggregate;
  }

  /// يعيد صفوف المنتجات الفاشلة إلى pending بعد تجهيز التصنيفات.
  static Future<int> _repairFailedProductPush({
    required Database db,
    required String organizationId,
    required String branchId,
    required DatabaseService databaseService,
    required CloudSecureStorage storage,
  }) async {
    final errorPlaceholders =
        List.filled(_permanentOutboxErrors.length, '?').join(',');
    final failed = await db.query(
      'sync_outbox',
      where: 'sync_state = ? AND entity_type = ? AND '
          '(last_sync_error IS NULL OR last_sync_error NOT IN ($errorPlaceholders))',
      whereArgs: [
        'failed',
        ProductSyncOutboxWriter.entityTypeProduct,
        ..._permanentOutboxErrors,
      ],
    );
    if (failed.isEmpty) return 0;

    await _enqueueExistingCategories(
      db: db,
      organizationId: organizationId,
      branchId: branchId,
      databaseService: databaseService,
      storage: storage,
    );

    final now = DateTime.now().toIso8601String();
    var repaired = 0;
    for (final row in failed) {
      final id = (row['id'] ?? '').toString();
      if (id.isEmpty) continue;
      final error = (row['last_sync_error'] ?? '').toString();
      Map<String, dynamic> payload;
      try {
        final decoded = jsonDecode((row['payload_json'] ?? '{}').toString());
        payload = decoded is Map<String, dynamic>
            ? Map<String, dynamic>.from(decoded)
            : <String, dynamic>{};
      } on Object {
        payload = <String, dynamic>{};
      }
      // أزل تصنيفاً غير متزامن بعد كفشل سابق — يُعاد ربطه لاحقاً إن لزم.
      if (error == 'internal_error' || error == 'forbidden') {
        payload.remove('category_id');
      }
      _patchPayloadTenant(payload, organizationId, branchId);

      await db.update(
        'sync_outbox',
        {
          'sync_state': 'pending',
          'last_sync_error': null,
          'payload_json': jsonEncode(payload),
          'organization_id': organizationId,
          'branch_id': branchId,
          'updated_at': now,
        },
        where: 'id = ?',
        whereArgs: [id],
      );
      repaired++;
    }
    return repaired;
  }

  /// يصلح opening_stock الفاشل بسبب company_id/branch_id قديمة في payload.
  static Future<int> _repairFailedOpeningStockPush({
    required Database db,
    required String organizationId,
    required String branchId,
  }) async {
    final errorPlaceholders =
        List.filled(_permanentOutboxErrors.length, '?').join(',');
    final failed = await db.query(
      'sync_outbox',
      where: 'sync_state = ? AND entity_type = ? AND '
          '(last_sync_error IS NULL OR last_sync_error NOT IN ($errorPlaceholders))',
      whereArgs: [
        'failed',
        OpeningStockSyncConstants.entityType,
        ..._permanentOutboxErrors,
      ],
    );
    if (failed.isEmpty) return 0;

    final now = DateTime.now().toIso8601String();
    var repaired = 0;
    for (final row in failed) {
      final id = (row['id'] ?? '').toString();
      if (id.isEmpty) continue;

      Map<String, dynamic> payload;
      try {
        final decoded = jsonDecode((row['payload_json'] ?? '{}').toString());
        payload = decoded is Map<String, dynamic>
            ? Map<String, dynamic>.from(decoded)
            : <String, dynamic>{};
      } on Object {
        payload = <String, dynamic>{};
      }
      _patchPayloadTenant(payload, organizationId, branchId);

      await db.update(
        'sync_outbox',
        {
          'sync_state': 'pending',
          'last_sync_error': null,
          'payload_json': jsonEncode(payload),
          'organization_id': organizationId,
          'branch_id': branchId,
          'updated_at': now,
        },
        where: 'id = ?',
        whereArgs: [id],
      );
      repaired++;
    }
    return repaired;
  }

  static ProductEntity _productFromRow(Map<String, Object?> row) {
    final expiryRaw = row['expiryDate']?.toString();
    DateTime? expiry;
    if (expiryRaw != null && expiryRaw.isNotEmpty) {
      expiry = DateTime.tryParse(expiryRaw);
    }
    return ProductEntity(
      id: (row['id'] ?? '').toString(),
      organizationId: (row['organizationId'] ?? '').toString(),
      branchId: (row['branchId'] ?? '').toString(),
      name: (row['name'] ?? '').toString(),
      salePrice: ((row['salePrice'] as num?) ?? 0).toDouble(),
      costPrice: ((row['costPrice'] as num?) ?? 0).toDouble(),
      stockQty: ((row['stockQty'] as num?) ?? 0).toDouble(),
      barcode: row['barcode']?.toString(),
      categoryId: row['categoryId']?.toString(),
      description: row['description']?.toString(),
      unitName: row['unitName']?.toString(),
      imagePath: row['imagePath']?.toString(),
      expiryDate: expiry,
      isHidden: ((row['isHidden'] as num?) ?? 0) != 0,
      isFrozen: ((row['isFrozen'] as num?) ?? 0) != 0,
      isService: ((row['isService'] as num?) ?? 0) != 0,
    );
  }
}

class CloudTenantBindResult {
  const CloudTenantBindResult({
    required this.remapped,
    required this.productsEnqueued,
    required this.message,
    this.localOrganizationId,
    this.localBranchId,
    this.cloudCompanyId,
    this.cloudBranchId,
  });

  final bool remapped;
  final int productsEnqueued;
  final String message;
  final String? localOrganizationId;
  final String? localBranchId;
  final String? cloudCompanyId;
  final String? cloudBranchId;

  bool get needsRemap => message == 'needs_remap';
}

/// نتيجة إصلاح صفوف outbox الفاشلة.
class CloudRepairResult {
  const CloudRepairResult({
    required this.repairedCount,
    required this.remapped,
    required this.message,
    this.localOrganizationId,
    this.localBranchId,
    this.cloudCompanyId,
    this.cloudBranchId,
  });

  final int repairedCount;
  final bool remapped;
  final String message;
  final String? localOrganizationId;
  final String? localBranchId;
  final String? cloudCompanyId;
  final String? cloudBranchId;

  bool get needsRemap => message == 'needs_remap';
}
