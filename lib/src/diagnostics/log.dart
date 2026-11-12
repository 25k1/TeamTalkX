library;

import 'package:flutter/foundation.dart';

import 'crash_reporter.dart';
import 'redact.dart';

enum LogLevel {
  debug('D'),
  info('I'),
  warning('W'),
  error('E');

  const LogLevel(this.letter);

  final String letter;
}

@immutable
class LogRecord {
  const LogRecord({
    required this.time,
    required this.level,
    required this.tag,
    required this.message,
    this.error,
    this.stackTrace,
  });

  final DateTime time;
  final LogLevel level;
  final String tag;
  final String message;

  final String? error;
  final StackTrace? stackTrace;

  String format() {
    final out = StringBuffer()
      ..write(time.toIso8601String())
      ..write(' ')
      ..write(level.letter)
      ..write(' [')
      ..write(tag)
      ..write('] ')
      ..write(message);
    if (error != null) out.write(': $error');
    if (stackTrace != null) {
      out
        ..write('\n')
        ..write(stackTrace.toString().trimRight());
    }
    return out.toString();
  }
}

abstract interface class LogSink {
  void write(LogRecord record);
}

class ConsoleLogSink implements LogSink {
  const ConsoleLogSink();

  @override
  void write(LogRecord record) => debugPrint(record.format());
}

class MemoryLogSink implements LogSink {
  MemoryLogSink({this.capacity = 1000});

  final int capacity;
  final records = <LogRecord>[];

  @override
  void write(LogRecord record) {
    records.add(record);
    if (records.length > capacity) records.removeAt(0);
  }
}

class Logger {
  Logger();

  final _sinks = <LogSink>[];

  LogLevel minLevel = kDebugMode ? LogLevel.debug : LogLevel.info;

  CrashReporter crashReporter = const NoopCrashReporter();

  DateTime Function() now = DateTime.now;

  void addSink(LogSink sink) => _sinks.add(sink);

  void removeSink(LogSink sink) => _sinks.remove(sink);

  void d(String tag, String message) => log(LogLevel.debug, tag, message);

  void i(String tag, String message) => log(LogLevel.info, tag, message);

  void w(String tag, String message, [Object? error, StackTrace? stack]) =>
      log(LogLevel.warning, tag, message, error, stack);

  void e(String tag, String message, [Object? error, StackTrace? stack]) =>
      log(LogLevel.error, tag, message, error, stack);

  void log(
    LogLevel level,
    String tag,
    String message, [
    Object? error,
    StackTrace? stack,
  ]) {
    if (level.index < minLevel.index) return;
    final record = LogRecord(
      time: now(),
      level: level,
      tag: tag,
      message: redact(message),
      error: error == null ? null : redact(error.toString()),
      stackTrace: stack,
    );
    for (final sink in List.of(_sinks)) {
      try {
        sink.write(record);
      } on Object catch (sinkError) {
        debugPrint('Log sink $sink failed: $sinkError');
      }
    }
    if (level == LogLevel.error) {
      crashReporter.captureError(record, error, stack);
    }
  }
}

final appLog = Logger();
