import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:teamtalkx/src/audio/audio_worker.dart';
import 'package:teamtalkx/src/audio/recording_writers.dart';
import 'package:teamtalkx/src/domain/recording.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(
    const MaterialApp(
      home: Scaffold(body: Center(child: Text('Recording check'))),
    ),
  );
  void log(String line) => debugPrint('TTX-BENCH $line');
  final cache = await getApplicationCacheDirectory();
  final dir = Directory('${cache.path}/recording-check');
  if (dir.existsSync()) dir.deleteSync(recursive: true);
  dir.createSync(recursive: true);
  final worker = await AudioWorker.spawn(onTx: (_) {});
  try {
    for (final format in RecordingFormat.values) {
      final sub = Directory('${dir.path}/${format.name}')..createSync();
      final error = await worker.startRecording(
        directory: sub.path,
        mode: RecordingMode.mixed,
        format: format,
      );
      if (error != null) {
        log('FAIL ${format.name}: $error');
        continue;
      }
      await Future<void>.delayed(const Duration(seconds: 2));
      final watch = Stopwatch()..start();
      await worker.stopRecording();
      final file = File('${sub.path}/${recordingFileName(0, format)}');
      final bytes = file.readAsBytesSync();
      log(
        '${format.name}: ${bytes.length} bytes, closed in '
        '${watch.elapsedMilliseconds} ms',
      );
      if (format == RecordingFormat.wav) {
        final data = ByteData.sublistView(bytes).getUint32(40, Endian.little);
        log(
          'wav data $data bytes, '
          '${data / 192000} s, header ok: ${data == bytes.length - 44}',
        );
      } else {
        var at = 0;
        var pages = 0;
        var crcOk = true;
        var granule = 0;
        var flags = 0;
        while (at < bytes.length) {
          final b = ByteData.sublistView(bytes, at);
          final segments = b.getUint8(26);
          var length = 27 + segments;
          for (var i = 0; i < segments; i++) {
            length += bytes[at + 27 + i];
          }
          final page = Uint8List.fromList(bytes.sublist(at, at + length));
          final crc = ByteData.sublistView(page).getUint32(22, Endian.little);
          page.setRange(22, 26, const [0, 0, 0, 0]);
          crcOk &= oggCrc(page) == crc;
          granule = b.getInt64(6, Endian.little);
          flags = b.getUint8(5);
          pages++;
          at += length;
        }
        log(
          'ogg $pages pages, checksums ok: $crcOk, end '
          '${(granule - 312) / 48000} s, last page flags $flags',
        );
      }
    }
  } on Object catch (e, st) {
    log('FAIL: $e\n$st');
  } finally {
    await worker.shutdown();
    dir.deleteSync(recursive: true);
  }
  debugPrint('TTX-BENCH done');
}
