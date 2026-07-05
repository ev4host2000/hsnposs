import 'package:mizapos_mobile/services/cloud/models/cloud_device.dart';
import 'package:mizapos_mobile/services/cloud/models/cloud_session.dart';
import 'package:mizapos_mobile/services/cloud/models/cloud_token.dart';

/// استجابة تسجيل جهاز — يطابق POST /devices/register.
class RegisterDeviceResponse {
  const RegisterDeviceResponse({
    required this.device,
    required this.session,
    required this.token,
    required this.reused,
  });

  factory RegisterDeviceResponse.fromJson(Object? json, {bool reused = false}) {
    if (json is! Map) {
      return RegisterDeviceResponse(
        device: const CloudDevice(
          id: '',
          companyId: '',
          installationId: '',
        ),
        session: const CloudSession(
          sessionId: '',
          deviceId: '',
          companyId: '',
          branchId: '',
        ),
        token: const CloudToken(accessToken: ''),
        reused: reused,
      );
    }
    final map = Map<String, dynamic>.from(json);
    final token = CloudToken.fromJson(map);
    final device = CloudDevice.fromJson(map);
    final session = CloudSession.fromJson(map);

    return RegisterDeviceResponse(
      device: device,
      session: session.copyWith(token: token, device: device),
      token: token,
      reused: reused,
    );
  }

  final CloudDevice device;
  final CloudSession session;
  final CloudToken token;
  final bool reused;

  Map<String, dynamic> toJson() => {
        ...device.toJson(),
        ...session.toJson(),
        ...token.toJson(),
        'reused': reused,
      };
}
