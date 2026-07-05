import 'package:mizapos_mobile/services/cloud/api/cloud_http_client.dart';
import 'package:mizapos_mobile/services/cloud/api/cloud_http_method.dart';
import 'package:mizapos_mobile/services/cloud/api/cloud_http_request.dart';
import 'package:mizapos_mobile/services/cloud/api/cloud_http_response.dart';
import 'package:mizapos_mobile/services/cloud/auth/auth_expired_exception.dart';
import 'package:mizapos_mobile/services/cloud/config/cloud_config.dart';
import 'package:mizapos_mobile/services/cloud/storage/cloud_secure_storage.dart';
import 'package:uuid/uuid.dart';

import 'cloud_api_auth_coordinator.dart';

/// غلاف طلبات Miza Cloud — headers، auth interceptor، request IDs.
class CloudApiClient {
  CloudApiClient({
    required CloudHttpClient httpClient,
    required CloudConfig config,
    required CloudSecureStorage storage,
    CloudApiAuthCoordinator? authCoordinator,
    Uuid? uuid,
  })  : _httpClient = httpClient,
        _config = config,
        _storage = storage,
        _authCoordinator = authCoordinator,
        _uuid = uuid ?? const Uuid();

  final CloudHttpClient _httpClient;
  final CloudConfig _config;
  final CloudSecureStorage _storage;
  final CloudApiAuthCoordinator? _authCoordinator;
  final Uuid _uuid;

  /// آخر `X-Request-ID` أُرسِل (للتتبع في sync_logs).
  String? lastRequestId;

  Future<CloudHttpResponse> get(
    String path, {
    Map<String, String> queryParameters = const {},
    Map<String, String> headers = const {},
    Duration? timeout,
    String? contentType,
  }) {
    return _send(
      method: CloudHttpMethod.get,
      path: path,
      queryParameters: queryParameters,
      headers: headers,
      timeout: timeout,
      contentType: contentType,
    );
  }

  Future<CloudHttpResponse> post(
    String path, {
    Object? body,
    Map<String, String> queryParameters = const {},
    Map<String, String> headers = const {},
    Duration? timeout,
    String? contentType,
  }) {
    return _send(
      method: CloudHttpMethod.post,
      path: path,
      body: body,
      queryParameters: queryParameters,
      headers: headers,
      timeout: timeout,
      contentType: contentType,
    );
  }

  Future<CloudHttpResponse> put(
    String path, {
    Object? body,
    Map<String, String> queryParameters = const {},
    Map<String, String> headers = const {},
    Duration? timeout,
    String? contentType,
  }) {
    return _send(
      method: CloudHttpMethod.put,
      path: path,
      body: body,
      queryParameters: queryParameters,
      headers: headers,
      timeout: timeout,
      contentType: contentType,
    );
  }

  Future<CloudHttpResponse> patch(
    String path, {
    Object? body,
    Map<String, String> queryParameters = const {},
    Map<String, String> headers = const {},
    Duration? timeout,
    String? contentType,
  }) {
    return _send(
      method: CloudHttpMethod.patch,
      path: path,
      body: body,
      queryParameters: queryParameters,
      headers: headers,
      timeout: timeout,
      contentType: contentType,
    );
  }

  Future<CloudHttpResponse> delete(
    String path, {
    Object? body,
    Map<String, String> queryParameters = const {},
    Map<String, String> headers = const {},
    Duration? timeout,
    String? contentType,
  }) {
    return _send(
      method: CloudHttpMethod.delete,
      path: path,
      body: body,
      queryParameters: queryParameters,
      headers: headers,
      timeout: timeout,
      contentType: contentType,
    );
  }

  Future<CloudHttpResponse> upload(
    String path, {
    required Object? body,
    Map<String, String> queryParameters = const {},
    Map<String, String> headers = const {},
    Duration? timeout,
    String? contentType,
  }) {
    return _send(
      method: CloudHttpMethod.upload,
      path: path,
      body: body,
      queryParameters: queryParameters,
      headers: headers,
      timeout: timeout,
      contentType: contentType,
    );
  }

  Future<CloudHttpResponse> download(
    String path, {
    Map<String, String> queryParameters = const {},
    Map<String, String> headers = const {},
    Duration? timeout,
    String? contentType,
  }) {
    return _send(
      method: CloudHttpMethod.download,
      path: path,
      queryParameters: queryParameters,
      headers: headers,
      timeout: timeout,
      contentType: contentType,
    );
  }

  Future<CloudHttpResponse> _send({
    required CloudHttpMethod method,
    required String path,
    Object? body,
    Map<String, String> queryParameters = const {},
    Map<String, String> headers = const {},
    Duration? timeout,
    String? contentType,
    bool isAuthRetry = false,
  }) async {
    final skipAuth = _shouldSkipAuthorization(path);
    final coordinator = _authCoordinator;

    if (!skipAuth && coordinator != null && !isAuthRetry) {
      await coordinator.ensureFreshAccessToken();
    }

    final requestId = _uuid.v4();
    lastRequestId = requestId;

    final resolvedHeaders = await _buildHeaders(
      callerHeaders: headers,
      requestId: requestId,
      includeAuthorization: !skipAuth,
    );

    final request = CloudHttpRequest(
      method: method,
      path: _config.resolveApiUrl(path),
      headers: resolvedHeaders,
      queryParameters: queryParameters,
      body: body,
      timeout: timeout ?? _config.receiveTimeout,
      contentType: contentType,
    );

    final response = await _dispatch(method, request);

    if (response.statusCode == 401 &&
        !skipAuth &&
        !isAuthRetry &&
        coordinator != null) {
      final refreshed = await coordinator.refreshAccessToken();
      if (refreshed) {
        return _send(
          method: method,
          path: path,
          body: body,
          queryParameters: queryParameters,
          headers: headers,
          timeout: timeout,
          contentType: contentType,
          isAuthRetry: true,
        );
      }
      await coordinator.clearCredentials();
      throw const AuthExpiredException();
    }

    return response;
  }

  static bool _shouldSkipAuthorization(String path) {
    final normalized = path.split('?').first.toLowerCase();
    if (normalized.contains('/health')) return true;
    if (normalized.endsWith('/auth/login')) return true;
    if (normalized.endsWith('/auth/token/refresh')) return true;
    if (normalized.endsWith('/auth/logout')) return true;
    return false;
  }

  /// Exposed for unit tests.
  static bool shouldSkipAuthorizationForPath(String path) =>
      _shouldSkipAuthorization(path);

  Future<Map<String, String>> _buildHeaders({
    required Map<String, String> callerHeaders,
    required String requestId,
    required bool includeAuthorization,
  }) async {
    final headers = Map<String, String>.from(callerHeaders);

    if (includeAuthorization) {
      final accessToken = await _storage.readAccessToken();
      if (accessToken != null && accessToken.isNotEmpty) {
        headers['Authorization'] = 'Bearer $accessToken';
      }
    }

    final userAgent = _config.userAgent.trim();
    if (userAgent.isNotEmpty) {
      headers['User-Agent'] = userAgent;
    }

    if (_config.enableGzip) {
      headers['Accept-Encoding'] = 'gzip';
    }

    final deviceId = await _storage.readDeviceId();
    if (deviceId != null && deviceId.isNotEmpty) {
      headers['X-Device-ID'] = deviceId;
    }

    final companyId = await _storage.readCompanyId();
    if (companyId != null && companyId.isNotEmpty) {
      headers['X-Company-ID'] = companyId;
    }

    final branchId = await _storage.readBranchId();
    if (branchId != null && branchId.isNotEmpty) {
      headers['X-Branch-ID'] = branchId;
    }

    headers['X-Request-ID'] = requestId;

    return headers;
  }

  Future<CloudHttpResponse> _dispatch(
    CloudHttpMethod method,
    CloudHttpRequest request,
  ) {
    switch (method) {
      case CloudHttpMethod.get:
        return _httpClient.get(request);
      case CloudHttpMethod.post:
        return _httpClient.post(request);
      case CloudHttpMethod.put:
        return _httpClient.put(request);
      case CloudHttpMethod.patch:
        return _httpClient.patch(request);
      case CloudHttpMethod.delete:
        return _httpClient.delete(request);
      case CloudHttpMethod.upload:
        return _httpClient.upload(request);
      case CloudHttpMethod.download:
        return _httpClient.download(request);
    }
  }
}
