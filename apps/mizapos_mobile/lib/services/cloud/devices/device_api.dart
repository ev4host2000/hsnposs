import 'dart:convert';

import 'package:mizapos_mobile/services/cloud/api/cloud_api_client.dart';
import 'package:mizapos_mobile/services/cloud/api/cloud_http_response.dart';
import 'package:mizapos_mobile/services/cloud/config/cloud_config.dart';
import 'package:mizapos_mobile/services/cloud/devices/requests/heartbeat_request.dart';
import 'package:mizapos_mobile/services/cloud/devices/requests/register_device_request.dart';
import 'package:mizapos_mobile/services/cloud/devices/responses/register_device_response.dart';
import 'package:mizapos_mobile/services/cloud/models/cloud_api_response.dart';
import 'package:mizapos_mobile/services/cloud/models/cloud_device.dart';
import 'package:mizapos_mobile/services/cloud/models/cloud_error.dart';

/// HTTP لمسارات الأجهزة — عبر [CloudApiClient].
class DeviceApi {
  DeviceApi({
    required CloudApiClient apiClient,
    CloudConfig? config,
  })  : _apiClient = apiClient,
        _config = config;

  final CloudApiClient _apiClient;
  final CloudConfig? _config;

  static const String registerPath = '/devices/register';
  static const String heartbeatPath = '/devices/heartbeat';
  static const String mePath = '/devices/me';

  static const String _jsonContentType = 'application/json; charset=utf-8';

  Future<CloudApiResponse<RegisterDeviceResponse>> register(
    RegisterDeviceRequest request,
  ) async {
    final http = await _apiClient.post(
      registerPath,
      body: jsonEncode(request.toJson()),
      contentType: _jsonContentType,
      timeout: _config?.receiveTimeout,
    );
    final reused = http.statusCode == 200;
    return _parseResponse(
      http,
      (json) => RegisterDeviceResponse.fromJson(json, reused: reused),
    );
  }

  Future<CloudApiResponse<Map<String, dynamic>>> heartbeat(
    HeartbeatRequest request,
  ) async {
    final http = await _apiClient.post(
      heartbeatPath,
      body: jsonEncode(request.toJson()),
      contentType: _jsonContentType,
      timeout: _config?.receiveTimeout,
    );
    return _parseResponse(http, (json) {
      if (json is Map<String, dynamic>) return json;
      if (json is Map) return Map<String, dynamic>.from(json);
      return <String, dynamic>{};
    });
  }

  Future<CloudApiResponse<CloudDevice>> me() async {
    final http = await _apiClient.get(
      mePath,
      timeout: _config?.receiveTimeout,
    );
    return _parseResponse(http, (json) {
      if (json is Map<String, dynamic>) {
        return CloudDevice.fromJson(json);
      }
      if (json is Map) {
        return CloudDevice.fromJson(Map<String, dynamic>.from(json));
      }
      return const CloudDevice(id: '', companyId: '', installationId: '');
    });
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
