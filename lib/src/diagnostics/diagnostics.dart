import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import 'file_log_sink.dart';
import 'log.dart';

final logFileSinkProvider = Provider<RotatingFileLogSink?>((ref) => null);

Future<RotatingFileLogSink?> initDiagnostics() async {
  if (kDebugMode) appLog.addSink(const ConsoleLogSink());
  RotatingFileLogSink? fileSink;
  try {
    final support = await getApplicationSupportDirectory();
    fileSink = RotatingFileLogSink(
      Directory('${support.path}${Platform.pathSeparator}logs'),
    );
    appLog.addSink(fileSink);
  } on Exception catch (e) {
    appLog.w('diagnostics', 'No log file', e);
  }
  installErrorHooks();
  return fileSink;
}

void installErrorHooks() {
  final previous = FlutterError.onError;
  FlutterError.onError = (details) {
    appLog.e(
      'flutter',
      details.context?.toDescription() ?? 'Framework error',
      details.exception,
      details.stack,
    );
    previous?.call(details);
  };
  PlatformDispatcher.instance.onError = (error, stack) {
    appLog.e('uncaught', 'Uncaught error', error, stack);
    return true;
  };
}
