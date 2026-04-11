import 'package:flutter/foundation.dart';

/// Logger simples para o MVP.
/// Em produção: substituir debugPrint por Sentry/Crashlytics.
class Logger {
  static void error(String context, dynamic error, [StackTrace? stack]) {
    debugPrint('❌ [$context] $error');
    if (stack != null) debugPrint(stack.toString());
    // TODO: enviar para Sentry em produção
    // Sentry.captureException(error, stackTrace: stack);
  }

  static void warn(String context, String message) {
    debugPrint('⚠️  [$context] $message');
  }

  static void info(String context, String message) {
    debugPrint('ℹ️  [$context] $message');
  }
}
