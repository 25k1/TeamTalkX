import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:teamtalkx/src/diagnostics/crash_reporter.dart';
import 'package:teamtalkx/src/diagnostics/diagnostics_report.dart';
import 'package:teamtalkx/src/diagnostics/file_log_sink.dart';
import 'package:teamtalkx/src/diagnostics/log.dart';
import 'package:teamtalkx/src/diagnostics/redact.dart';

class _RecordingReporter implements CrashReporter {
  final reported = <LogRecord>[];

  @override
  void captureError(LogRecord record, Object? error, StackTrace? stack) =>
      reported.add(record);
}

LogRecord _record(String message) => LogRecord(
  time: DateTime.utc(2026, 11, 9, 12),
  level: LogLevel.info,
  tag: 't',
  message: message,
);

void main() {
  group('redact', () {
    test('removes secrets from TeamTalk commands', () {
      final out = redact(
        'login nickname="Beka" username="beqa" password="hunter2" '
        'clientname="TeamTalkX" id=3',
      );

      expect(out, contains('nickname="Beka"'));
      expect(out, contains('username="beqa"'));
      expect(out, contains('password=<redacted>'));
      expect(out, isNot(contains('hunter2')));
    });

    test('removes op passwords, transfer and crypt keys', () {
      final out = redact(
        'updatechannel chanid=2 oppassword="op" '
        'regsendfile filetxkey=0123abcd cryptkey=deadbeef',
      );

      expect(out, isNot(contains('"op"')));
      expect(out, isNot(contains('0123abcd')));
      expect(out, isNot(contains('deadbeef')));
      expect(out, contains('chanid=2'));
    });

    test('removes message text but keeps the metadata', () {
      final out = redact(
        'textmessage type=2 srcuserid=5 destuserid=7 content="my secret note"',
      );

      expect(out, contains('srcuserid=5'));
      expect(out, contains('content=<redacted>'));
      expect(out, isNot(contains('secret note')));
    });

    test('removes credentials from tt:// links and JSON', () {
      expect(
        redact('tt://example.org?tcpport=10333&username=a&password=pw&x=1'),
        'tt://example.org?tcpport=10333&username=a&password=<redacted>&x=1',
      );
      expect(
        redact('{"username": "a", "password": "pw"}'),
        '{"username": "a", "password": "<redacted>"}',
      );
    });

    test('handles escaped quotes inside a secret', () {
      final out = redact(r'password="a\"b c" next=1');

      expect(out, 'password=<redacted> next=1');
    });
  });

  group('Logger', () {
    late Logger log;
    late MemoryLogSink sink;

    setUp(() {
      log = Logger()
        ..minLevel = LogLevel.info
        ..now = () => DateTime.utc(2026, 11, 9, 12);
      sink = MemoryLogSink();
      log.addSink(sink);
    });

    test('drops records below the minimum level', () {
      log
        ..d('t', 'debug')
        ..i('t', 'info');

      expect(sink.records.map((r) => r.message), ['info']);
    });

    test('redacts the message and the error text', () {
      log.w('t', 'joining with password=abc', StateError('key=1 token=xyz'));

      final r = sink.records.single;
      expect(r.message, 'joining with password=<redacted>');
      expect(r.error, contains('token=<redacted>'));
    });

    test('hands error records to the crash reporter', () {
      final reporter = _RecordingReporter();
      log.crashReporter = reporter;

      log
        ..w('t', 'warning')
        ..e('t', 'failure', StateError('x'));

      expect(reporter.reported.map((r) => r.message), ['failure']);
    });

    test('a failing sink does not stop the others', () {
      log
        ..addSink(_ThrowingSink())
        ..addSink(sink)
        ..i('t', 'still logged');

      expect(
        sink.records.where((r) => r.message == 'still logged'),
        isNotEmpty,
      );
    });

    test('formats records as one line plus the stack', () {
      final record = LogRecord(
        time: DateTime.utc(2026, 11, 9, 12),
        level: LogLevel.error,
        tag: 'voice',
        message: 'start failed',
        error: 'TimeoutException',
        stackTrace: StackTrace.fromString('#0 main'),
      );

      expect(
        record.format(),
        '2026-11-09T12:00:00.000Z E [voice] start failed: TimeoutException\n'
        '#0 main',
      );
    });
  });

  group('RotatingFileLogSink', () {
    late Directory dir;

    setUp(() async {
      dir = await Directory.systemTemp.createTemp('tt_log_test');
    });

    tearDown(() => dir.delete(recursive: true));

    test('rotates and keeps at most maxFiles files', () {
      final sink = RotatingFileLogSink(dir, maxBytes: 200, maxFiles: 3);
      addTearDown(sink.close);

      for (var i = 0; i < 40; i++) {
        sink.write(_record('line $i ${'x' * 20}'));
      }

      final names = sink.files.map((f) => f.uri.pathSegments.last).toList();
      expect(names, ['teamtalkx.2.log', 'teamtalkx.1.log', 'teamtalkx.log']);
      for (final f in sink.files) {
        expect(f.lengthSync(), lessThanOrEqualTo(200));
      }
      expect(sink.files.last.readAsStringSync(), contains('line 39'));
      expect(
        sink.files.map((f) => f.readAsStringSync()).join(),
        isNot(contains('line 0 ')),
        reason: 'the oldest records were rotated out',
      );
    });

    test('appends to an existing log after a restart', () {
      RotatingFileLogSink(dir)
        ..write(_record('before restart'))
        ..close();
      final sink = RotatingFileLogSink(dir)..write(_record('after restart'));
      addTearDown(sink.close);

      final text = sink.files.single.readAsStringSync();
      expect(text, contains('before restart'));
      expect(text, contains('after restart'));
    });

    test('the report lists device info and the logs oldest first', () async {
      final sink = RotatingFileLogSink(dir, maxBytes: 120, maxFiles: 2);
      addTearDown(sink.close);
      for (var i = 0; i < 6; i++) {
        sink.write(_record('entry $i ${'y' * 30}'));
      }
      File(
        '${dir.path}/teamtalkx.log',
      ).writeAsStringSync('legacy password=leaked\n', mode: FileMode.append);

      final report = await buildDiagnosticsReport(
        appVersion: '9.8.7',
        logSink: sink,
      );

      expect(report, contains('App version: 9.8.7'));
      expect(
        report.indexOf('teamtalkx.1.log'),
        lessThan(report.indexOf('teamtalkx.log =====')),
      );
      expect(report, contains('entry 5'));
      expect(report, isNot(contains('leaked')));
    });

    test('the report works without log files', () async {
      final report = await buildDiagnosticsReport(
        appVersion: '1.0.0',
        logSink: null,
      );

      expect(report, contains('(no log files)'));
    });
  });
}

class _ThrowingSink implements LogSink {
  @override
  void write(LogRecord record) => throw StateError('disk full');
}
