import 'package:mizapos_desktop/services/cloud/api/cloud_api_client.dart';
import 'package:mizapos_desktop/services/cloud/api/cloud_http_response.dart';
import 'package:mizapos_desktop/services/cloud/api/cloud_multipart_body.dart';
import 'package:mizapos_desktop/services/cloud/models/cloud_api_response.dart';
import 'package:mizapos_desktop/services/cloud/models/cloud_error.dart';

class ProductMediaUploadResult {
  const ProductMediaUploadResult({
    required this.productId,
    required this.imageUrl,
  });

  factory ProductMediaUploadResult.fromJson(Object? json) {
    final map = json is Map ? Map<String, dynamic>.from(json) : <String, dynamic>{};
    return ProductMediaUploadResult(
      productId: (map['product_id'] ?? '').toString(),
      imageUrl: (map['image_url'] ?? '').toString(),
    );
  }

  final String productId;
  final String imageUrl;
}

class ProductMediaApi {
  ProductMediaApi({required CloudApiClient apiClient}) : _apiClient = apiClient;

  final CloudApiClient _apiClient;

  Future<CloudApiResponse<ProductMediaUploadResult>> uploadProductImage({
    required String productId,
    required String filePath,
  }) async {
    final http = await _apiClient.upload(
      '/media/products/$productId',
      body: CloudMultipartBody(
        files: [
          CloudMultipartFile(
            fieldName: 'image',
            path: filePath,
          ),
        ],
      ),
    );
    return _parseResponse(http, ProductMediaUploadResult.fromJson);
  }

  CloudApiResponse<T> _parseResponse<T>(
    CloudHttpResponse http,
    T Function(Object? json) fromJsonT,
  ) {
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
                statusCode: http.statusCode,
              ),
        );
      }
      return parsed;
    }

    return CloudApiResponse<T>(
      ok: http.isSuccess,
      error: http.isSuccess
          ? null
          : CloudError(
              code: 'http_error',
              message: 'Request failed',
              statusCode: http.statusCode,
            ),
    );
  }

  Map<String, dynamic>? _decodeBodyMap(Object? body) {
    if (body is Map<String, dynamic>) return body;
    if (body is Map) return Map<String, dynamic>.from(body);
    return null;
  }
}
