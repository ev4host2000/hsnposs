/// حمولة multipart لـ [CloudHttpClient.upload].
class CloudMultipartBody {
  const CloudMultipartBody({
    this.fields = const {},
    this.files = const [],
  });

  final Map<String, String> fields;
  final List<CloudMultipartFile> files;
}

class CloudMultipartFile {
  const CloudMultipartFile({
    required this.fieldName,
    required this.path,
    this.filename,
  });

  final String fieldName;
  final String path;
  final String? filename;
}
