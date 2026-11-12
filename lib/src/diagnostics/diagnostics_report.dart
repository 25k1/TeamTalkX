import 'dart:convert';
import 'dart:io';

import 'file_log_sink.dart';
import 'redact.dart';

Future<String> buildDiagnosticsReport({
  required String appVersion,
  required RotatingFileLogSink? logSink,
  DateTime? now,
}) async {
  final out = StringBuffer()
    ..writeln('TeamTalkX diagnostics')
    ..writeln('Created: ${(now ?? DateTime.now()).toIso8601String()}')
    ..writeln('App version: $appVersion')
    ..writeln(
      'OS: ${Platform.operatingSystem} ${Platform.operatingSystemVersion}',
    )
    ..writeln('Dart: ${Platform.version.split(' ').first}')
    ..writeln('Locale: ${Platform.localeName}')
    ..writeln();
  final files = logSink?.files ?? const <File>[];
  if (files.isEmpty) {
    out.writeln('(no log files)');
    return out.toString();
  }
  for (final file in files) {
    out.writeln('===== ${file.uri.pathSegments.last} =====');
    try {
      final bytes = await file.readAsBytes();
      out.writeln(redact(utf8.decode(bytes, allowMalformed: true)));
    } on FileSystemException catch (e) {
      out.writeln('(could not read: ${e.message})');
    }
  }
  return out.toString();
}
