import 'package:mizapos_mobile/services/cloud/models/cloud_token.dart';

/// دورة حياة JWT — expiry و proactive refresh.
class CloudTokenLifecycle {
  CloudTokenLifecycle._();

  static const Duration refreshLeadTime = Duration(minutes: 1);

  static DateTime? parseExpiresAt(String? raw) {
    if (raw == null || raw.trim().isEmpty) return null;
    return DateTime.tryParse(raw.trim())?.toUtc();
  }

  static DateTime? resolveExpiresAt(CloudToken token, {DateTime? issuedAt}) {
    final explicit = parseExpiresAt(token.expiresAt);
    if (explicit != null) return explicit;

    final base = issuedAt ??
        parseExpiresAt(token.issuedAt) ??
        DateTime.now().toUtc();

    if (token.expiresIn > 0) {
      return base.add(Duration(seconds: token.expiresIn));
    }
    return null;
  }

  static String formatExpiresAt(DateTime value) =>
      value.toUtc().toIso8601String();

  static bool isTokenExpired(DateTime? expiresAt, {DateTime? now}) {
    if (expiresAt == null) return false;
    return (now ?? DateTime.now().toUtc()).isAfter(expiresAt.toUtc());
  }

  /// `true` خلال الدقيقة الأخيرة قبل انتهاء التوكن.
  static bool shouldRefresh(DateTime? expiresAt, {DateTime? now}) {
    if (expiresAt == null) return false;
    final clock = (now ?? DateTime.now()).toUtc();
    return !clock.isBefore(expiresAt.toUtc().subtract(refreshLeadTime));
  }
}
