/// أفعال HTTP المدعومة في [CloudHttpClient].
enum CloudHttpMethod {
  get,
  post,
  put,
  patch,
  delete,
  upload,
  download,
}

extension CloudHttpMethodX on CloudHttpMethod {
  String get name => switch (this) {
        CloudHttpMethod.get => 'GET',
        CloudHttpMethod.post => 'POST',
        CloudHttpMethod.put => 'PUT',
        CloudHttpMethod.patch => 'PATCH',
        CloudHttpMethod.delete => 'DELETE',
        CloudHttpMethod.upload => 'UPLOAD',
        CloudHttpMethod.download => 'DOWNLOAD',
      };
}
