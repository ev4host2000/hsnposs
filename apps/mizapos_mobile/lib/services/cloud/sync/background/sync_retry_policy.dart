import 'dart:io';

import 'package:mizapos_mobile/services/cloud/sync/products_pull_worker.dart';
import 'package:mizapos_mobile/services/cloud/sync/products_push_worker.dart';

/// سياسة إعادة المحاولة للمزامنة الخلفية — exponential backoff.
class SyncRetryPolicy {
  SyncRetryPolicy._();

  static const int maxAttempts = 5;

  static Duration delayForAttempt(int attemptIndex) {
    // attemptIndex 1 → 2s, 2 → 4s, 3 → 8s, 4 → 16s, 5+ → 32s (cap 60s)
    final seconds = 1 << attemptIndex.clamp(1, 6);
    return Duration(seconds: seconds > 60 ? 60 : seconds);
  }

  static bool isPermanentError(
    Object error, {
    int? statusCode,
    String? code,
  }) {
    final httpStatus = statusCode ??
        _statusFromError(error) ??
        _statusFromCode(code ?? _codeFromError(error));

    if (httpStatus == 401 || httpStatus == 403) return true;

    final normalized = (code ?? _codeFromError(error)).toLowerCase();
    if (normalized.isEmpty) return false;

    const permanentCodes = {
      'unauthorized',
      'forbidden',
      'validation_error',
      'validation_failed',
      'invalid_request',
      'invalid_payload',
      'bad_request',
    };
    if (permanentCodes.contains(normalized)) return true;
    if (normalized.contains('validation') || normalized.contains('invalid')) {
      return true;
    }
    return false;
  }

  static bool isTransientError(Object error, {int? statusCode, String? code}) {
    if (isPermanentError(error, statusCode: statusCode, code: code)) {
      return false;
    }
    if (error is SocketException || error is HttpException) return true;
    if (error is ProductsSyncException || error is ProductsPullException) {
      return !isPermanentError(error, code: _codeFromError(error));
    }
    if (statusCode != null && statusCode >= 500) return true;
    return true;
  }

  static int? _statusFromError(Object error) {
    if (error is ProductsSyncException) {
      return _statusFromCode(error.code);
    }
    if (error is ProductsPullException) {
      return _statusFromCode(error.code);
    }
    return null;
  }

  static int? _statusFromCode(String code) {
    final match = RegExp(r'\b(401|403|4\d{2}|5\d{2})\b').firstMatch(code);
    if (match == null) return null;
    return int.tryParse(match.group(1)!);
  }

  static String _codeFromError(Object error) {
    if (error is ProductsSyncException) return error.code;
    if (error is ProductsPullException) return error.code;
    return error.toString();
  }
}
