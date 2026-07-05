import 'dart:convert';

import 'package:mizapos_mobile/services/cloud/api/cloud_api_client.dart';
import 'package:mizapos_mobile/services/cloud/api/cloud_http_response.dart';
import 'package:mizapos_mobile/services/cloud/config/cloud_config.dart';
import 'package:mizapos_mobile/services/cloud/models/cloud_api_response.dart';
import 'package:mizapos_mobile/services/cloud/models/cloud_error.dart';
import 'package:mizapos_mobile/services/cloud/sync/requests/products_pull_request.dart';
import 'package:mizapos_mobile/services/cloud/sync/requests/products_push_request.dart';
import 'package:mizapos_mobile/services/cloud/sync/responses/products_pull_response.dart';
import 'package:mizapos_mobile/services/cloud/sync/responses/products_push_response.dart';

/// HTTP لمزامنة **products** فقط — عبر [CloudApiClient].
class ProductsSyncApi {
  ProductsSyncApi({
    required CloudApiClient apiClient,
    CloudConfig? config,
  })  : _apiClient = apiClient,
        _config = config;

  final CloudApiClient _apiClient;
  final CloudConfig? _config;

  static const String pushPath = '/sync/push/products';
  static const String pullPath = '/sync/pull/products';
  static const String _jsonContentType = 'application/json; charset=utf-8';

  Future<CloudApiResponse<ProductsPushResponse>> push(
    ProductsPushRequest request, {
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
    return _parseResponse(http, ProductsPushResponse.fromJson);
  }

  Future<CloudApiResponse<ProductsPullResponse>> pull(
    ProductsPullRequest request,
  ) async {
    final http = await _apiClient.get(
      pullPath,
      queryParameters: request.toQueryParameters(),
      timeout: _config?.receiveTimeout,
    );
    return _parseResponse(http, ProductsPullResponse.fromJson);
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
