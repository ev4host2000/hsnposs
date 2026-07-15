import 'package:mizapos_desktop/services/cloud/models/cloud_error.dart';

class DeviceException implements Exception {
  const DeviceException({
    required this.code,
    required this.message,
    this.statusCode,
    this.details,
  });

  factory DeviceException.fromCloudError(CloudError error) {
    return DeviceException(
      code: error.code,
      message: error.message,
      statusCode: error.statusCode,
      details: error.details,
    );
  }

  final String code;
  final String message;
  final int? statusCode;
  final Map<String, dynamic>? details;

  @override
  String toString() => 'DeviceException($code): $message';
}
