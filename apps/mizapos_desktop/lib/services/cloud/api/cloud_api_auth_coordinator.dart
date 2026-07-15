import 'dart:convert';

import 'package:mizapos_desktop/services/cloud/api/cloud_http_client.dart';
import 'package:mizapos_desktop/services/cloud/api/cloud_http_method.dart';
import 'package:mizapos_desktop/services/cloud/api/cloud_http_request.dart';
import 'package:mizapos_desktop/services/cloud/auth/auth_api.dart';
import 'package:mizapos_desktop/services/cloud/auth/cloud_token_lifecycle.dart';
import 'package:mizapos_desktop/services/cloud/auth/refresh_token_outcome.dart';
import 'package:mizapos_desktop/services/cloud/auth/requests/refresh_token_request.dart';
import 'package:mizapos_desktop/services/cloud/auth/responses/refresh_token_response.dart';
import 'package:mizapos_desktop/services/cloud/config/cloud_config.dart';
import 'package:mizapos_desktop/services/cloud/models/cloud_api_response.dart';
import 'package:mizapos_desktop/services/cloud/models/cloud_session.dart';
import 'package:mizapos_desktop/services/cloud/storage/cloud_secure_storage.dart';

/// تجديد token عبر HTTP مباشر — يتجنب دورة CloudApiClient ↔ AuthApi.
class CloudApiAuthCoordinator {
  CloudApiAuthCoordinator({
    required CloudHttpClient httpClient,
    required CloudConfig config,
    required CloudSecureStorage storage,
  })  : _httpClient = httpClient,
        _config = config,
        _storage = storage;

  final CloudHttpClient _httpClient;
  final CloudConfig _config;
  final CloudSecureStorage _storage;

  Future<RefreshTokenOutcome>? _refreshInFlight;

  Future<void> ensureFreshAccessToken() async {
    final expiresAt = CloudTokenLifecycle.parseExpiresAt(
      await _storage.readAccessTokenExpiresAt(),
    );
    if (!CloudTokenLifecycle.shouldRefresh(expiresAt)) return;
    await refreshAccessToken();
  }

  Future<RefreshTokenOutcome> refreshAccessToken() {
    final inFlight = _refreshInFlight;
    if (inFlight != null) return inFlight;
    final future = _refreshAccessToken().whenComplete(() {
      _refreshInFlight = null;
    });
    _refreshInFlight = future;
    return future;
  }

  Future<RefreshTokenOutcome> _refreshAccessToken() async {
    final refreshToken = await _storage.readRefreshToken();
    if (refreshToken == null || refreshToken.isEmpty) {
      return RefreshTokenOutcome.invalid;
    }

    final request = RefreshTokenRequest(
      refreshToken: refreshToken,
      installationId: await _storage.readInstallationId(),
      deviceId: await _storage.readDeviceId(),
    );

    final httpRequest = CloudHttpRequest(
      method: CloudHttpMethod.post,
      path: _config.resolveApiUrl(AuthApi.refreshPath),
      headers: const {
        'Accept': 'application/json',
        'Content-Type': 'application/json; charset=utf-8',
      },
      body: jsonEncode(request.toJson()),
      timeout: _config.receiveTimeout,
    );

    try {
      final httpResponse = await _httpClient.post(httpRequest);
      if (httpResponse.statusCode == 401 || httpResponse.statusCode == 403) {
        return RefreshTokenOutcome.invalid;
      }
      if (httpResponse.statusCode >= 500) {
        return RefreshTokenOutcome.failed;
      }

      final bodyMap = _decodeBodyMap(httpResponse.body);
      if (bodyMap == null) return RefreshTokenOutcome.failed;

      final parsed = CloudApiResponse<RefreshTokenResponse>.fromJson(
        bodyMap,
        RefreshTokenResponse.fromJson,
      );
      if (!parsed.ok || parsed.data == null) {
        final code = parsed.error?.code.toLowerCase() ?? '';
        if (code.contains('invalid') ||
            code.contains('expired') ||
            code.contains('revoked')) {
          return RefreshTokenOutcome.invalid;
        }
        return RefreshTokenOutcome.failed;
      }

      await _persistRefreshResult(parsed.data!);
      return RefreshTokenOutcome.success;
    } on Object {
      return RefreshTokenOutcome.failed;
    }
  }

  Future<void> clearCredentials() => _storage.clearAll();

  Future<void> _persistRefreshResult(RefreshTokenResponse response) async {
    final token = response.token;
    if (token.accessToken.isNotEmpty) {
      await _storage.writeAccessToken(token.accessToken);
    }
    final refresh = token.refreshToken;
    if (refresh != null && refresh.isNotEmpty) {
      await _storage.writeRefreshToken(refresh);
    }

    final expiresAt = CloudTokenLifecycle.resolveExpiresAt(token);
    if (expiresAt != null) {
      await _storage.writeAccessTokenExpiresAt(
        CloudTokenLifecycle.formatExpiresAt(expiresAt),
      );
    } else {
      await _storage.deleteAccessTokenExpiresAt();
    }

    final session = response.session;
    if (session != null) {
      await _persistSessionFields(session);
    }
  }

  Future<void> _persistSessionFields(CloudSession session) async {
    if (session.deviceId.isNotEmpty) {
      await _storage.writeDeviceId(session.deviceId);
    }
    if (session.companyId.isNotEmpty) {
      await _storage.writeCompanyId(session.companyId);
    }
    if (session.branchId.isNotEmpty) {
      await _storage.writeBranchId(session.branchId);
    }
    final userId = session.userId;
    if (userId != null && userId.isNotEmpty) {
      await _storage.writeUserId(userId);
    }
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
