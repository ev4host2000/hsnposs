import 'package:mizapos_desktop/services/cloud/api/cloud_http_request.dart';
import 'package:mizapos_desktop/services/cloud/api/cloud_http_response.dart';

/// عقد عميل HTTP لـ Miza Cloud — بدون تنفيذ (لا `http`، لا Dio).
abstract class CloudHttpClient {
  const CloudHttpClient();

  Future<CloudHttpResponse> get(CloudHttpRequest request);

  Future<CloudHttpResponse> post(CloudHttpRequest request);

  Future<CloudHttpResponse> put(CloudHttpRequest request);

  Future<CloudHttpResponse> patch(CloudHttpRequest request);

  Future<CloudHttpResponse> delete(CloudHttpRequest request);

  /// رفع ملف أو حمولة multipart — الطلب يحدد `contentType` والـ `body`.
  Future<CloudHttpResponse> upload(CloudHttpRequest request);

  /// تنزيل ملف أو استجابة ثنائية — `body` في الاستجابة قد يكون `List<int>`.
  Future<CloudHttpResponse> download(CloudHttpRequest request);
}
