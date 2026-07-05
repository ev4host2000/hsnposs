import 'dart:convert';

import 'package:mizapos_mobile/services/cloud/api/cloud_api_client.dart';
import 'package:mizapos_mobile/services/cloud/api/cloud_http_response.dart';
import 'package:mizapos_mobile/services/cloud/auth/requests/login_request.dart';
import 'package:mizapos_mobile/services/cloud/auth/requests/logout_request.dart';
import 'package:mizapos_mobile/services/cloud/auth/requests/refresh_token_request.dart';
import 'package:mizapos_mobile/services/cloud/auth/responses/login_response.dart';
import 'package:mizapos_mobile/services/cloud/auth/responses/refresh_token_response.dart';
import 'package:mizapos_mobile/services/cloud/config/cloud_config.dart';
import 'package:mizapos_mobile/services/cloud/models/cloud_api_response.dart';
import 'package:mizapos_mobile/services/cloud/models/cloud_error.dart';

/// عميل HTTP لمسارات المصادقة فقط — عبر [CloudApiClient].
class AuthApi {
  AuthApi({
    required CloudApiClient apiClient,
    CloudConfig? config,
  })  : _apiClient = apiClient,
        _config = config;

  final CloudApiClient _apiClient;
  final CloudConfig? _config;

  static const String loginPath = '/auth/login';
  static const String refreshPath = '/auth/token/refresh';
  static const String logoutPath = '/auth/logout';

  static const String _jsonContentType = 'application/json; charset=utf-8';

  Future<CloudApiResponse<LoginResponse>> login(LoginRequest request) async {
    final http = await _apiClient.post(
      loginPath,
      body: jsonEncode(request.toJson()),
      contentType: _jsonContentType,
      timeout: _config?.receiveTimeout,
    );
    return _parseResponse(http, LoginResponse.fromJson);
  }

  Future<CloudApiResponse<RefreshTokenResponse>> refreshToken(
    RefreshTokenRequest request,
  ) async {
    final http = await _apiClient.post(
      refreshPath,
      body: jsonEncode(request.toJson()),
      contentType: _jsonContentType,
      timeout: _config?.receiveTimeout,
    );
    return _parseResponse(http, RefreshTokenResponse.fromJson);
  }

  Future<CloudApiResponse<void>> logout(LogoutRequest request) async {
    final http = await _apiClient.post(
      logoutPath,
      body: jsonEncode(request.toJson()),
      contentType: _jsonContentType,
      timeout: _config?.receiveTimeout,
    );
    return _parseResponse(http, (_) {});
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
