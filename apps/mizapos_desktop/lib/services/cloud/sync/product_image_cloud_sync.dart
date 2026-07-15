import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:mizapos_desktop/services/cloud/sync/product_media_api.dart';
import 'package:mizapos_desktop/services/cloud/sync/product_sync_outbox_writer.dart';
import 'package:mizapos_desktop/services/database_service.dart';
import 'package:mizapos_desktop/services/product_image_storage.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

/// رفع صور المنتجات إلى السحابة وسحبها محلياً بعد sync.
class ProductImageCloudSync {
  ProductImageCloudSync({
    required ProductMediaApi mediaApi,
    DatabaseService? databaseService,
    http.Client? httpClient,
  })  : _mediaApi = mediaApi,
        _db = databaseService ?? DatabaseService(),
        _httpClient = httpClient ?? http.Client();

  final ProductMediaApi _mediaApi;
  final DatabaseService _db;
  final http.Client _httpClient;

  /// يضيف `image_url` إلى payload قبل push إن وُجدت صورة مرفوعة مسبقاً.
  /// الرفع الثقيل يتم عبر [flushPendingImageUploads] بعد المزامنة الأساسية.
  Future<Map<String, dynamic>> enrichProductPayload({
    required String productId,
    required Map<String, dynamic> payload,
    String operation = 'update',
  }) async {
    final enriched = Map<String, dynamic>.from(payload);
    final db = await _db.database;
    final rows = await db.query(
      'products',
      columns: const ['imagePath', 'cloudImageUrl', 'cloudImageLocalPath'],
      where: 'id = ?',
      whereArgs: [productId],
      limit: 1,
    );
    if (rows.isEmpty) return enriched;

    final imagePath = rows.first['imagePath']?.toString().trim() ?? '';
    final existingUrl = rows.first['cloudImageUrl']?.toString().trim() ?? '';
    final syncedPath =
        rows.first['cloudImageLocalPath']?.toString().trim() ?? '';

    if (imagePath.isEmpty || !ProductImageStorage.isManagedPath(imagePath)) {
      if (existingUrl.isNotEmpty) {
        enriched['image_url'] = null;
      }
      return enriched;
    }

    if (existingUrl.isNotEmpty && syncedPath == imagePath) {
      enriched['image_url'] = existingUrl;
    }
    // لا نرفع هنا — حتى لا تبطئ دورة المنتجات/الفواتير.
    return enriched;
  }

  /// عدد المنتجات ذات صورة محلية لم تُرفع بعد.
  Future<int> countUnsyncedImages({
    required String organizationId,
    required String branchId,
  }) async {
    final db = await _db.database;
    final rows = await db.rawQuery(
      'SELECT COUNT(*) AS c FROM products '
      'WHERE organizationId = ? AND branchId = ? AND imagePath IS NOT NULL '
      "AND TRIM(imagePath) != '' AND ("
      'cloudImageUrl IS NULL OR TRIM(cloudImageUrl) = \'\' OR '
      'cloudImageLocalPath IS NULL OR cloudImageLocalPath != imagePath'
      ')',
      [organizationId, branchId],
    );
    return (rows.first['c'] as int?) ?? 0;
  }

  /// رفع صور معلّقة في الخلفية ثم صفّ تحديثات outbox (لا يوقف المزامنة الأساسية).
  Future<int> flushPendingImageUploads({
    required String organizationId,
    required String branchId,
    int limit = 15,
  }) async {
    final db = await _db.database;
    final rows = await db.query(
      'products',
      columns: const ['id', 'imagePath', 'cloudImageUrl', 'cloudImageLocalPath'],
      where: 'organizationId = ? AND branchId = ? AND imagePath IS NOT NULL '
          "AND TRIM(imagePath) != '' AND ("
          'cloudImageUrl IS NULL OR TRIM(cloudImageUrl) = \'\' OR '
          'cloudImageLocalPath IS NULL OR cloudImageLocalPath != imagePath'
          ')',
      whereArgs: [organizationId, branchId],
      limit: limit,
    );
    var uploaded = 0;
    for (final row in rows) {
      final productId = row['id']?.toString() ?? '';
      final imagePath = row['imagePath']?.toString().trim() ?? '';
      if (productId.isEmpty || imagePath.isEmpty) continue;
      if (!ProductImageStorage.isManagedPath(imagePath)) continue;

      final absolutePath = ProductImageStorage.resolveDisplayPath(imagePath);
      final file = File(absolutePath);
      if (!await file.exists()) continue;

      try {
        final upload = await _mediaApi.uploadProductImage(
          productId: productId,
          filePath: absolutePath,
        );
        if (!upload.ok ||
            upload.data == null ||
            upload.data!.imageUrl.isEmpty) {
          continue;
        }
        final imageUrl = upload.data!.imageUrl;
        await db.update(
          'products',
          {
            'cloudImageUrl': imageUrl,
            'cloudImageLocalPath': imagePath,
          },
          where: 'id = ?',
          whereArgs: [productId],
        );
        await ProductSyncOutboxWriter.record(
          operation: 'update',
          productId: productId,
          organizationId: organizationId,
          branchId: branchId,
          databaseService: _db,
        );
        uploaded++;
      } on Object {
        // صورة فاشلة لا توقف بقية الطابور.
      }
    }
    return uploaded;
  }

  /// يسجّل update في outbox للمنتجات ذات صورة محلية لم تُرفع بعد.
  Future<int> enqueueUpdatesForUnsyncedImages({
    required String organizationId,
    required String branchId,
    Iterable<String>? productIds,
  }) {
    return enqueueUnsyncedImageUpdates(
      databaseService: _db,
      organizationId: organizationId,
      branchId: branchId,
      productIds: productIds,
    );
  }

  /// بدون الحاجة لعميل الرفع — مناسب لـ binder/repair.
  static Future<int> enqueueUnsyncedImageUpdates({
    required DatabaseService databaseService,
    required String organizationId,
    required String branchId,
    Iterable<String>? productIds,
  }) async {
    final db = await databaseService.database;
    final args = <Object?>[organizationId, branchId];
    var where =
        'organizationId = ? AND branchId = ? AND imagePath IS NOT NULL '
        "AND TRIM(imagePath) != '' AND ("
        'cloudImageUrl IS NULL OR TRIM(cloudImageUrl) = \'\' OR '
        'cloudImageLocalPath IS NULL OR cloudImageLocalPath != imagePath'
        ')';
    if (productIds != null) {
      final ids = productIds.where((id) => id.trim().isNotEmpty).toList();
      if (ids.isEmpty) return 0;
      where += ' AND id IN (${List.filled(ids.length, '?').join(',')})';
      args.addAll(ids);
    }

    final rows = await db.query(
      'products',
      columns: const ['id'],
      where: where,
      whereArgs: args,
    );
    var count = 0;
    for (final row in rows) {
      final productId = row['id']?.toString() ?? '';
      if (productId.isEmpty) continue;
      await ProductSyncOutboxWriter.record(
        operation: 'update',
        productId: productId,
        organizationId: organizationId,
        branchId: branchId,
        databaseService: databaseService,
      );
      count++;
    }
    return count;
  }

  /// يحمّل صورة المنتج من السحابة بعد pull.
  Future<void> applyRemoteImage({
    required String productId,
    required String? imageUrl,
    DatabaseExecutor? txn,
  }) async {
    final normalizedUrl = imageUrl?.trim() ?? '';

    Future<void> updateProduct(Map<String, Object?> data) async {
      if (txn != null) {
        await txn.update(
          'products',
          data,
          where: 'id = ?',
          whereArgs: [productId],
        );
      } else {
        final db = await _db.database;
        await db.update(
          'products',
          data,
          where: 'id = ?',
          whereArgs: [productId],
        );
      }
    }

    final queryExecutor = txn ?? await _db.database;
    final rows = await queryExecutor.query(
      'products',
      columns: const ['cloudImageUrl', 'imagePath', 'cloudImageLocalPath'],
      where: 'id = ?',
      whereArgs: [productId],
      limit: 1,
    );

    if (normalizedUrl.isEmpty) {
      // احفظ الصورة المحلية فقط إن لم تُرفع بعد؛ إن كانت مزامَنة مسبقاً
      // والسيرفر أرسل null فالحذف مقصود من جهاز آخر.
      if (rows.isNotEmpty) {
        final localPath = rows.first['imagePath']?.toString().trim() ?? '';
        final cloudUrl =
            rows.first['cloudImageUrl']?.toString().trim() ?? '';
        final syncedPath =
            rows.first['cloudImageLocalPath']?.toString().trim() ?? '';
        final hasManagedLocal = localPath.isNotEmpty &&
            ProductImageStorage.isManagedPath(localPath);
        final unsyncedLocal = hasManagedLocal &&
            (cloudUrl.isEmpty || syncedPath != localPath);
        if (unsyncedLocal) {
          return;
        }
      }
      await updateProduct({
        'imagePath': null,
        'cloudImageUrl': null,
        'cloudImageLocalPath': null,
      });
      return;
    }

    if (rows.isNotEmpty) {
      final currentUrl = rows.first['cloudImageUrl']?.toString().trim() ?? '';
      if (currentUrl == normalizedUrl) return;
    }

    final response = await _httpClient.get(Uri.parse(normalizedUrl));
    if (response.statusCode != 200 || response.bodyBytes.isEmpty) {
      return;
    }

    await ProductImageStorage.ensureDirectory();
    final ext = p.extension(Uri.parse(normalizedUrl).path);
    final safeExt = ext.isEmpty || ext.length > 8 ? '.jpg' : ext;
    final fileName = '$productId$safeExt';
    final destAbs = p.join(ProductImageStorage.imagesDirectoryPath, fileName);
    await File(destAbs).writeAsBytes(response.bodyBytes, flush: true);
    final relative = ProductImageStorage.relativeStoragePath(fileName);

    await updateProduct({
      'imagePath': relative,
      'cloudImageUrl': normalizedUrl,
      'cloudImageLocalPath': relative,
    });
  }
}
