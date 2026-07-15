/// بيئة تشغيل Miza Cloud — تحدد defaults للإعدادات وسلوك التشخيص.
enum CloudEnvironment {
  /// تطوير محلي — logging مفعّل، pinning معطّل، timeouts أطول.
  development,

  /// ما قبل الإنتاج — قريب من production مع مرونة تشخيص.
  staging,

  /// إنتاج — أمان أقصى، logging معطّل، pinning مفعّل.
  production,
}

extension CloudEnvironmentX on CloudEnvironment {
  /// اسم قصير للـ logs وملفات الإعداد.
  String get name => switch (this) {
        CloudEnvironment.development => 'development',
        CloudEnvironment.staging => 'staging',
        CloudEnvironment.production => 'production',
      };

  bool get isDevelopment => this == CloudEnvironment.development;

  bool get isStaging => this == CloudEnvironment.staging;

  bool get isProduction => this == CloudEnvironment.production;
}
