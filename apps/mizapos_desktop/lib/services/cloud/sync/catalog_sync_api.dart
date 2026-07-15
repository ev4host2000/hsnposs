import 'dart:convert';

import 'package:mizapos_desktop/services/cloud/api/cloud_api_client.dart';
import 'package:mizapos_desktop/services/cloud/api/cloud_http_response.dart';
import 'package:mizapos_desktop/services/cloud/config/cloud_config.dart';
import 'package:mizapos_desktop/services/cloud/models/cloud_api_response.dart';
import 'package:mizapos_desktop/services/cloud/models/cloud_error.dart';
import 'package:mizapos_desktop/services/cloud/sync/requests/catalog_pull_request.dart';
import 'package:mizapos_desktop/services/cloud/sync/requests/catalog_push_request.dart';
import 'package:mizapos_desktop/services/cloud/sync/requests/catalog_snapshot_request.dart';
import 'package:mizapos_desktop/services/cloud/sync/requests/catalog_versions_request.dart';
import 'package:mizapos_desktop/services/cloud/sync/responses/catalog_pull_response.dart';
import 'package:mizapos_desktop/services/cloud/sync/responses/catalog_push_batch_status_response.dart';
import 'package:mizapos_desktop/services/cloud/sync/responses/catalog_push_response.dart';
import 'package:mizapos_desktop/services/cloud/sync/responses/catalog_snapshot_response.dart';
import 'package:mizapos_desktop/services/cloud/sync/responses/catalog_versions_response.dart';

/// HTTP لمزامنة **catalog** — products, customers, suppliers.
///
/// يثبّت `entity_scope=catalog` ولا يغطّي invoices/users.
/// عبر [CloudApiClient] — بدون orchestration (انظر `sync/` workers لاحقاً).
class CatalogSyncApi {
  CatalogSyncApi({
    required CloudApiClient apiClient,
    CloudConfig? config,
  })  : _apiClient = apiClient,
        _config = config;

  final CloudApiClient _apiClient;
  final CloudConfig? _config;

  static const String entityScope = 'catalog';

  static const String pullPath = '/sync/pull';
  static const String snapshotPath = '/sync/pull/snapshot';
  static const String pushPath = '/sync/push';
  static const String versionsPath = '/sync/versions';

  static const String _jsonContentType = 'application/json; charset=utf-8';

  /// GET `/sync/versions` — مقارنة إصدار catalog.
  Future<CloudApiResponse<CatalogVersionsResponse>> versions(
    CatalogVersionsRequest request,
  ) async {
    final http = await _apiClient.get(
      versionsPath,
      queryParameters: request.toQueryParameters(),
      timeout: _config?.receiveTimeout,
    );
    return _parseResponse(http, CatalogVersionsResponse.fromJson);
  }

  /// GET `/sync/pull?entity_scope=catalog`.
  Future<CloudApiResponse<CatalogPullResponse>> pull(
    CatalogPullRequest request,
  ) async {
    final http = await _apiClient.get(
      pullPath,
      queryParameters: request.toQueryParameters(),
      timeout: _config?.receiveTimeout,
    );
    return _parseResponse(http, CatalogPullResponse.fromJson);
  }

  /// GET `/sync/pull/snapshot?entity_scope=catalog`.
  Future<CloudApiResponse<CatalogSnapshotResponse>> pullSnapshot(
    CatalogSnapshotRequest request,
  ) async {
    final http = await _apiClient.get(
      snapshotPath,
      queryParameters: request.toQueryParameters(),
      timeout: _config?.receiveTimeout,
    );
    return _parseResponse(http, CatalogSnapshotResponse.fromJson);
  }

  /// POST `/sync/push` — batch أحداث catalog.
  Future<CloudApiResponse<CatalogPushResponse>> push(
    CatalogPushRequest request, {
    String? idempotencyKey,
  }) async {
    final headers = <String, String>{};
    final key = idempotencyKey?.trim();
    if (key != null && key.isNotEmpty) {
      headers['Idempotency-Key'] = key;
    }

    final http = await _apiClient.post(
      pushPath,
      body: jsonEncode(request.toJson()),
      headers: headers,
      contentType: _jsonContentType,
      timeout: _config?.receiveTimeout,
    );
    return _parseResponse(http, CatalogPushResponse.fromJson);
  }

  /// GET `/sync/push/{batch_id}` — حالة معالجة batch.
  Future<CloudApiResponse<CatalogPushBatchStatusResponse>> pushBatchStatus(
    String batchId,
  ) async {
    final id = batchId.trim();
    final http = await _apiClient.get(
      '$pushPath/$id',
      timeout: _config?.receiveTimeout,
    );
    return _parseResponse(http, CatalogPushBatchStatusResponse.fromJson);
  }

  CloudApiResponse<T> _parseResponse<T>(
    CloudHttpResponse http,
    T Function(Object? json) fromJsonT,
  ) {
    final statusCode = http.statusCode;
    final requestId = http.requestId;
    final bodyMap = _decodeBodyMap(http.body);

    if (bodyMap != null) {
      final parsed = CloudApiResponse<T>.fromJson(bodyMap, fromJsonT);
      if (!parsed.ok || !http.isSuccess) {
        return CloudApiResponse<T>(
          ok: false,
          data: parsed.data,
          error: parsed.error ??
              CloudError(
                code: 'http_error',
                message: 'Request failed',
                statusCode: statusCode,
                details: {
                  if (requestId != null) 'request_id': requestId,
                },
              ),
          meta: parsed.meta,
        );
      }
      return parsed;
    }

    if (http.isSuccess) {
      return CloudApiResponse<T>(ok: true, data: fromJsonT(null));
    }

    return CloudApiResponse<T>(
      ok: false,
      error: CloudError(
        code: 'http_error',
        message: 'Invalid or empty response body',
        statusCode: statusCode,
        details: {
          if (requestId != null) 'request_id': requestId,
        },
      ),
    );
  }

  Map<String, dynamic>? _decodeBodyMap(Object? body) {
    if (body == null) return null;
    if (body is Map<String, dynamic>) return body;
    if (body is Map) return Map<String, dynamic>.from(body);
    if (body is String && body.trim().isNotEmpty) {
      try {
        final decoded = jsonDecode(body);
        if (decoded is Map<String, dynamic>) return decoded;
        if (decoded is Map) return Map<String, dynamic>.from(decoded);
      } on FormatException {
        return null;
      }
    }
    return null;
  }
}
