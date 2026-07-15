import 'package:flutter/foundation.dart';
import 'package:mizapos_desktop/services/cloud/config/cloud_environment.dart';

/// إعدادات عامة لعميل Miza Cloud — immutable، بدون I/O أو شبكة.
class CloudConfig {
  const CloudConfig({
    required this.baseUrl,
    required this.apiVersion,
    required this.connectTimeout,
    required this.receiveTimeout,
    required this.maxRetryCount,
    required this.retryDelay,
    required this.userAgent,
    required this.enableLogging,
    required this.enableCompression,
    required this.enableGzip,
    required this.enableHttp2,
    required this.enableCertificatePinning,
    required this.environment,
  });

  /// تطوير محلي — تشخيص كامل، بدون تثبيت شهادات.
  factory CloudConfig.development({
    String? baseUrl,
    String? apiVersion,
    Duration? connectTimeout,
    Duration? receiveTimeout,
    int? maxRetryCount,
    Duration? retryDelay,
    String? userAgent,
    bool? enableLogging,
    bool? enableCompression,
    bool? enableGzip,
    bool? enableHttp2,
    bool? enableCertificatePinning,
  }) {
    return CloudConfig(
      baseUrl: baseUrl ?? _developmentBaseUrl,
      apiVersion: apiVersion ?? _defaultApiVersion,
      connectTimeout: connectTimeout ?? const Duration(seconds: 30),
      receiveTimeout: receiveTimeout ?? const Duration(seconds: 60),
      maxRetryCount: maxRetryCount ?? 2,
      retryDelay: retryDelay ?? const Duration(milliseconds: 500),
      userAgent: userAgent ?? _defaultUserAgent,
      enableLogging: enableLogging ?? true,
      enableCompression: enableCompression ?? true,
      enableGzip: enableGzip ?? true,
      enableHttp2: enableHttp2 ?? false,
      enableCertificatePinning: enableCertificatePinning ?? false,
      environment: CloudEnvironment.development,
    );
  }

  /// ما قبل الإنتاج — سلوك قريب من الإنتاج مع logging اختياري.
  factory CloudConfig.staging({
    String? baseUrl,
    String? apiVersion,
    Duration? connectTimeout,
    Duration? receiveTimeout,
    int? maxRetryCount,
    Duration? retryDelay,
    String? userAgent,
    bool? enableLogging,
    bool? enableCompression,
    bool? enableGzip,
    bool? enableHttp2,
    bool? enableCertificatePinning,
  }) {
    return CloudConfig(
      baseUrl: baseUrl ?? _stagingBaseUrl,
      apiVersion: apiVersion ?? _defaultApiVersion,
      connectTimeout: connectTimeout ?? const Duration(seconds: 20),
      receiveTimeout: receiveTimeout ?? const Duration(seconds: 45),
      maxRetryCount: maxRetryCount ?? 3,
      retryDelay: retryDelay ?? const Duration(seconds: 1),
      userAgent: userAgent ?? _defaultUserAgent,
      enableLogging: enableLogging ?? true,
      enableCompression: enableCompression ?? true,
      enableGzip: enableGzip ?? true,
      enableHttp2: enableHttp2 ?? true,
      enableCertificatePinning: enableCertificatePinning ?? false,
      environment: CloudEnvironment.staging,
    );
  }

  /// إنتاج — القيم الافتراضية الآمنة لـ api.mizapos.com.
  ///
  /// TODO(security): تنفيذ TLS certificate pinning في [CloudHttpClientIo]
  /// قبل تفعيل `enableCertificatePinning: true`.
  factory CloudConfig.production({
    String? baseUrl,
    String? apiVersion,
    Duration? connectTimeout,
    Duration? receiveTimeout,
    int? maxRetryCount,
    Duration? retryDelay,
    String? userAgent,
    bool? enableLogging,
    bool? enableCompression,
    bool? enableGzip,
    bool? enableHttp2,
    bool? enableCertificatePinning,
  }) {
    return CloudConfig(
      baseUrl: baseUrl ?? _productionBaseUrl,
      apiVersion: apiVersion ?? _defaultApiVersion,
      connectTimeout: connectTimeout ?? const Duration(seconds: 15),
      receiveTimeout: receiveTimeout ?? const Duration(seconds: 30),
      maxRetryCount: maxRetryCount ?? 3,
      retryDelay: retryDelay ?? const Duration(seconds: 2),
      userAgent: userAgent ?? _defaultUserAgent,
      enableLogging: enableLogging ?? false,
      enableCompression: enableCompression ?? true,
      enableGzip: enableGzip ?? true,
      enableHttp2: enableHttp2 ?? true,
      enableCertificatePinning: enableCertificatePinning ?? false,
      environment: CloudEnvironment.production,
    );
  }

  static const String _defaultApiVersion = 'v1';
  static const String _defaultUserAgent = 'MizaPos-CloudClient/1.0';
  static const String _productionBaseUrl = 'https://api.mizapos.com';
  static const String _stagingBaseUrl = 'https://api-staging.mizapos.com';
  static const String _developmentBaseUrl = 'http://127.0.0.1:8787';

  /// عند تمرير `--dart-define=CLOUD_API_BASE_URL=https://api.mizapos.com`
  /// يتصل Debug بالسحابة الحية مع الإبقاء على Hot Reload (`r` / `R`).
  static const String cloudApiBaseUrlFromEnvironment =
      String.fromEnvironment('CLOUD_API_BASE_URL');

  /// إعداد Debug الافتراضي، أو الإنتاج إذا وُجد `CLOUD_API_BASE_URL`.
  factory CloudConfig.forAppRuntime() {
    final override = cloudApiBaseUrlFromEnvironment.trim();
    if (override.isNotEmpty) {
      return CloudConfig.development(baseUrl: override);
    }
    return kDebugMode ? CloudConfig.development() : CloudConfig.production();
  }

  /// معرّفات المستأجر التجريبي — dev_seed.sql فقط.
  static const String developmentCompanyId =
      '550e8400-e29b-41d4-a716-446655440000';
  static const String developmentBranchId =
      '660e8400-e29b-41d4-a716-446655440001';

  /// جذر API بدون شرطة نهائية، مثل `https://api.mizapos.com`.
  final String baseUrl;

  /// بادئة مسار API، مثل `v1` → `/v1/sync/push`.
  final String apiVersion;

  /// أقصى انتظار لإتمام الاتصال TCP/TLS.
  final Duration connectTimeout;

  /// أقصى انتظار لاستلام الاستجابة كاملة بعد الاتصال.
  final Duration receiveTimeout;

  /// عدد إعادة المحاولة بعد فشل مؤقت (شبكة/5xx).
  final int maxRetryCount;

  /// التأخير الأساسي بين المحاولات (قابل للتوسيع exponential لاحقاً).
  final Duration retryDelay;

  /// يُرسَل في ترويسة User-Agent لتتبع الإصدارات والدعم.
  final String userAgent;

  /// تفعيل سجلات تشخيص الطبقة السحابية (لا يُفعَّل في الإنتاج افتراضياً).
  final bool enableLogging;

  /// ضغط الحمولة على مستوى التطبيق (قبل الإرسال).
  final bool enableCompression;

  /// طلب/قبول ترميز gzip في HTTP (Accept-Encoding / Content-Encoding).
  final bool enableGzip;

  /// استخدام HTTP/2 عند دعم العميل والخادم.
  final bool enableHttp2;

  /// تثبيت شهادات TLS لـ api.mizapos.com (إنتاج فقط افتراضياً).
  final bool enableCertificatePinning;

  /// البيئة الحالية — تفسير defaults وليس مصدر I/O.
  final CloudEnvironment environment;

  /// عنوان API كامل لمسار نسبي، مثل `/sync/push`.
  String resolveApiUrl(String path) {
    final normalizedPath = path.startsWith('/') ? path : '/$path';
    final versionPrefix = apiVersion.isEmpty ? '' : '/$apiVersion';
    final trimmedBase = _trimTrailingSlashes(baseUrl);
    return '$trimmedBase$versionPrefix$normalizedPath';
  }

  CloudConfig copyWith({
    String? baseUrl,
    String? apiVersion,
    Duration? connectTimeout,
    Duration? receiveTimeout,
    int? maxRetryCount,
    Duration? retryDelay,
    String? userAgent,
    bool? enableLogging,
    bool? enableCompression,
    bool? enableGzip,
    bool? enableHttp2,
    bool? enableCertificatePinning,
    CloudEnvironment? environment,
  }) {
    return CloudConfig(
      baseUrl: baseUrl ?? this.baseUrl,
      apiVersion: apiVersion ?? this.apiVersion,
      connectTimeout: connectTimeout ?? this.connectTimeout,
      receiveTimeout: receiveTimeout ?? this.receiveTimeout,
      maxRetryCount: maxRetryCount ?? this.maxRetryCount,
      retryDelay: retryDelay ?? this.retryDelay,
      userAgent: userAgent ?? this.userAgent,
      enableLogging: enableLogging ?? this.enableLogging,
      enableCompression: enableCompression ?? this.enableCompression,
      enableGzip: enableGzip ?? this.enableGzip,
      enableHttp2: enableHttp2 ?? this.enableHttp2,
      enableCertificatePinning:
          enableCertificatePinning ?? this.enableCertificatePinning,
      environment: environment ?? this.environment,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CloudConfig &&
          runtimeType == other.runtimeType &&
          baseUrl == other.baseUrl &&
          apiVersion == other.apiVersion &&
          connectTimeout == other.connectTimeout &&
          receiveTimeout == other.receiveTimeout &&
          maxRetryCount == other.maxRetryCount &&
          retryDelay == other.retryDelay &&
          userAgent == other.userAgent &&
          enableLogging == other.enableLogging &&
          enableCompression == other.enableCompression &&
          enableGzip == other.enableGzip &&
          enableHttp2 == other.enableHttp2 &&
          enableCertificatePinning == other.enableCertificatePinning &&
          environment == other.environment;

  @override
  int get hashCode => Object.hash(
        baseUrl,
        apiVersion,
        connectTimeout,
        receiveTimeout,
        maxRetryCount,
        retryDelay,
        userAgent,
        enableLogging,
        enableCompression,
        enableGzip,
        enableHttp2,
        enableCertificatePinning,
        environment,
      );
}

String _trimTrailingSlashes(String value) =>
    value.replaceAll(RegExp(r'/+$'), '');
