import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:teamtalkx/src/audio/dsp/silero_vad.dart';
import 'package:teamtalkx/src/audio/dsp/silero_voice_detector.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(
    const MaterialApp(
      home: Scaffold(body: Center(child: Text('Silero check'))),
    ),
  );
  final weights = await SileroVoiceDetector.loadModelBytes();
  final dir = '${(await getExternalStorageDirectory())!.path}/silero';
  final lines = await Isolate.run(() => _check(weights, dir));
  for (final line in lines) {
    debugPrint('TTX-BENCH $line');
  }
  debugPrint('TTX-BENCH done');
}

List<String> _check(Uint8List weights, String dir) {
  final out = <String>[];
  final expected =
      jsonDecode(File('$dir/expected.json').readAsStringSync())
          as Map<String, dynamic>;
  final reference = (expected['probs'] as List).cast<num>();
  final wav = File('$dir/input.wav').readAsBytesSync();
  final data = ByteData.sublistView(wav);
  var at = 12;
  while (String.fromCharCodes(wav, at, at + 4) != 'data') {
    at += 8 + data.getUint32(at + 4, Endian.little);
  }
  final pcm = Int16List.fromList([
    for (var i = 0; i < data.getUint32(at + 4, Endian.little) ~/ 2; i++)
      data.getInt16(at + 8 + 2 * i, Endian.little),
  ]);

  final vad = SileroVad(weights);
  final probs = <double>[
    for (var i = 0; i < pcm.length; i += 320)
      ...vad.feed(Int16List.sublistView(pcm, i, math.min(i + 320, pcm.length))),
  ];
  var worst = 0.0;
  for (var i = 0; i < reference.length; i++) {
    worst = math.max(worst, (probs[i] - reference[i]).abs());
  }
  final ok = probs.length == reference.length && worst < 1e-4;
  out.add(
    '${ok ? 'PASS' : 'FAIL'} ${probs.length} of ${reference.length} chunks, '
    'largest difference from ONNX Runtime ${worst.toStringAsExponential(2)}',
  );

  final random = math.Random(1);
  final chunk = Float32List(SileroVad.chunkSize);
  final micros = <int>[];
  for (var round = 0; round < 3000; round++) {
    for (var i = 0; i < chunk.length; i++) {
      chunk[i] =
          (math.sin(2 * math.pi * 300 * (round * chunk.length + i) / 16000) *
                  6000 +
              (random.nextDouble() * 2 - 1) * 3000) /
          32768;
    }
    final watch = Stopwatch()..start();
    vad.process(chunk);
    micros.add(watch.elapsedMicroseconds);
  }
  vad.dispose();
  micros.sort();
  final mean = micros.reduce((a, b) => a + b) / micros.length;
  out.add(
    'Silero v6.2: ${micros.length} x 32 ms, median ${micros[micros.length ~/ 2]} us, '
    'mean ${mean.toStringAsFixed(0)} us, '
    'p99 ${micros[(micros.length * 0.99).floor()]} us, max ${micros.last} us, '
    'load ${(mean / 32000 * 100).toStringAsFixed(2)} %',
  );
  return out;
}
