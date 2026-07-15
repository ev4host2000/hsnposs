/// نتيجة محاولة تجديد access token.
enum RefreshTokenOutcome {
  success,
  /// refresh token غير صالح — يجب إعادة تسجيل الدخول.
  invalid,
  /// فشل مؤقت (شبكة، 5xx) — يمكن إعادة المحاولة.
  failed,
}
