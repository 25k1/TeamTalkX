library;

import 'log.dart';

abstract interface class CrashReporter {
  void captureError(LogRecord record, Object? error, StackTrace? stack);
}

class NoopCrashReporter implements CrashReporter {
  const NoopCrashReporter();

  @override
  void captureError(LogRecord record, Object? error, StackTrace? stack) {}
}
