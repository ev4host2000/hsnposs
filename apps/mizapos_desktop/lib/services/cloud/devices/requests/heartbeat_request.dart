/// طلب heartbeat — POST /devices/heartbeat.
class HeartbeatRequest {
  const HeartbeatRequest({this.appVersion});

  final String? appVersion;

  Map<String, dynamic> toJson() => {
        if (appVersion != null && appVersion!.isNotEmpty)
          'app_version': appVersion,
      };
}
