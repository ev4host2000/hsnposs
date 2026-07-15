import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:mizapos_desktop/services/cloud/api/cloud_http_client.dart';
import 'package:mizapos_desktop/services/cloud/api/cloud_http_method.dart';
import 'package:mizapos_desktop/services/cloud/api/cloud_http_request.dart';
import 'package:mizapos_desktop/services/cloud/api/cloud_http_response.dart';
import 'package:mizapos_desktop/services/cloud/api/cloud_multipart_body.dart';

/// تنفيذ [CloudHttpClient] عبر package:http — للتطوير والاختبار.
///
/// TODO(security): عند `CloudConfig.enableCertificatePinning == true`،
/// استخدم SecurityContext مع pinned certificates قبل الإنتاج.
class CloudHttpClientIo implements CloudHttpClient {
  const CloudHttpClientIo({http.Client? client}) : _client = client;

  final http.Client? _client;

  @override
  Future<CloudHttpResponse> get(CloudHttpRequest request) =>
      _send(CloudHttpMethod.get, request);

  @override
  Future<CloudHttpResponse> post(CloudHttpRequest request) =>
      _send(CloudHttpMethod.post, request);

  @override
  Future<CloudHttpResponse> put(CloudHttpRequest request) =>
      _send(CloudHttpMethod.put, request);

  @override
  Future<CloudHttpResponse> patch(CloudHttpRequest request) =>
      _send(CloudHttpMethod.patch, request);

  @override
  Future<CloudHttpResponse> delete(CloudHttpRequest request) =>
      _send(CloudHttpMethod.delete, request);

  @override
  Future<CloudHttpResponse> upload(CloudHttpRequest request) =>
      _send(CloudHttpMethod.upload, request);

  @override
  Future<CloudHttpResponse> download(CloudHttpRequest request) =>
      _send(CloudHttpMethod.download, request);

  Future<CloudHttpResponse> _send(
    CloudHttpMethod method,
    CloudHttpRequest request,
  ) async {
    final client = _client ?? http.Client();
    final uri = _buildUri(request);
    final headers = Map<String, String>.from(request.headers);
    if (request.contentType != null && request.contentType!.isNotEmpty) {
      headers.putIfAbsent('Content-Type', () => request.contentType!);
    }
    headers.putIfAbsent('Accept', () => 'application/json');

    final body = _encodeBody(request.body);
    final httpResponse = await _dispatch(
      client,
      method,
      uri,
      headers,
      body,
      request.body,
    ).timeout(request.timeout ?? const Duration(seconds: 60));

    if (_client == null) {
      client.close();
    }

    Object? parsedBody = httpResponse.body;
    if (httpResponse.body.isNotEmpty && method != CloudHttpMethod.download) {
      try {
        parsedBody = jsonDecode(httpResponse.body);
      } on FormatException {
        parsedBody = httpResponse.body;
      }
    }

    return CloudHttpResponse(
      statusCode: httpResponse.statusCode,
      body: parsedBody,
      headers: httpResponse.headers,
      isSuccess: httpResponse.statusCode >= 200 && httpResponse.statusCode < 300,
      requestId: httpResponse.headers['x-request-id'],
    );
  }

  Uri _buildUri(CloudHttpRequest request) {
    if (request.queryParameters.isEmpty) {
      return Uri.parse(request.path);
    }
    return Uri.parse(request.path).replace(
      queryParameters: request.queryParameters,
    );
  }

  String? _encodeBody(Object? body) {
    if (body == null) return null;
    if (body is String) return body;
    if (body is CloudMultipartBody) return null;
    if (body is Map || body is List) return jsonEncode(body);
    return body.toString();
  }

  Future<http.Response> _dispatch(
    http.Client client,
    CloudHttpMethod method,
    Uri uri,
    Map<String, String> headers,
    String? body,
    Object? rawBody,
  ) {
    switch (method) {
      case CloudHttpMethod.get:
        return client.get(uri, headers: headers);
      case CloudHttpMethod.post:
        return client.post(uri, headers: headers, body: body);
      case CloudHttpMethod.put:
        return client.put(uri, headers: headers, body: body);
      case CloudHttpMethod.patch:
        return client.patch(uri, headers: headers, body: body);
      case CloudHttpMethod.delete:
        return client.delete(uri, headers: headers, body: body);
      case CloudHttpMethod.upload:
        if (rawBody is CloudMultipartBody) {
          return _sendMultipart(client, uri, headers, rawBody);
        }
        return client.post(uri, headers: headers, body: body);
      case CloudHttpMethod.download:
        return client.get(uri, headers: headers);
    }
  }

  Future<http.Response> _sendMultipart(
    http.Client client,
    Uri uri,
    Map<String, String> headers,
    CloudMultipartBody multipart,
  ) async {
    final request = http.MultipartRequest('POST', uri);
    final uploadHeaders = Map<String, String>.from(headers);
    uploadHeaders.remove('Content-Type');
    request.headers.addAll(uploadHeaders);
    request.fields.addAll(multipart.fields);
    for (final file in multipart.files) {
      request.files.add(
        await http.MultipartFile.fromPath(
          file.fieldName,
          file.path,
          filename: file.filename,
        ),
      );
    }
    final streamed = await client.send(request);
    return http.Response.fromStream(streamed);
  }
}
