import 'dart:isolate';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:teamtalkx/src/audio/capture_pipeline.dart';
import 'package:teamtalkx/src/audio/dsp/noise_suppression.dart';
import 'package:teamtalkx/src/audio/dsp/silero_vad.dart';
import 'package:teamtalkx/src/audio/dsp/silero_voice_detector.dart';
import 'package:teamtalkx/src/domain/capture_settings.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final lines = <String>['Running…'];
  final notifier = ValueNotifier(lines);
  runApp(
    MaterialApp(
      home: Scaffold(
        appBar: AppBar(title: const Text('DSP benchmark')),
        body: ValueListenableBuilder(
          valueListenable: notifier,
          builder: (_, value, _) => ListView(
            padding: const EdgeInsets.all(16),
            children: [for (final line in value) Text(line)],
          ),
        ),
      ),
    ),
  );

  final model = await SileroVoiceDetector.loadModelBytes();
  final results = await Isolate.run(() => _benchmark(model));
  for (final line in results) {
    debugPrint('TTX-BENCH $line');
  }
  debugPrint('TTX-BENCH done');
  notifier.value = results;
}

Uint8List _signal(int rate, int samples, {int seed = 1}) {
  final random = math.Random(seed);
  return Int16List.fromList([
    for (var i = 0; i < samples; i++)
      (math.sin(2 * math.pi * 300 * i / rate) * 6000 +
              (random.nextDouble() * 2 - 1) * 3000)
          .round(),
  ]).buffer.asUint8List();
}

String _stats(String name, List<int> micros, Duration frame) {
  final sorted = [...micros]..sort();
  final mean = micros.reduce((a, b) => a + b) / micros.length;
  final p99 =
      sorted[(sorted.length * 0.99).floor().clamp(0, sorted.length - 1)];
  final load = mean / frame.inMicroseconds * 100;
  return '$name: ${micros.length} x ${frame.inMilliseconds} ms, '
      'mean ${mean.toStringAsFixed(0)} us, p99 $p99 us, max ${sorted.last} us, '
      'load ${load.toStringAsFixed(1)} %';
}

void _mark(String stage) => debugPrint('TTX-BENCH stage $stage');

Future<List<String>> _benchmark(Uint8List model) async {
  final out = <String>[];
  _mark('rnnoise');
  const seconds = 10;

  final suppressor = NoiseSuppressor()
    ..configure(sampleRate: 48000, channels: 1, wet: 0.7);
  final audio48 = _signal(48000, 48000 * seconds);
  final rnnoise = <int>[];
  for (var i = 0; i + 1920 <= audio48.length; i += 1920) {
    final watch = Stopwatch()..start();
    suppressor.process(Uint8List.sublistView(audio48, i, i + 1920));
    rnnoise.add(watch.elapsedMicroseconds);
  }
  suppressor.dispose();
  out.add(_stats('RNNoise', rnnoise, const Duration(milliseconds: 20)));
  debugPrint('TTX-BENCH ${out.last}');
  _mark('silero');

  final vad = SileroVad(model);
  final audio16 = Int16List.sublistView(_signal(16000, 16000 * seconds));
  final silero = <int>[];
  for (
    var i = 0;
    i + SileroVad.chunkSize <= audio16.length;
    i += SileroVad.chunkSize
  ) {
    final watch = Stopwatch()..start();
    vad.feed(Int16List.sublistView(audio16, i, i + SileroVad.chunkSize));
    silero.add(watch.elapsedMicroseconds);
  }
  _mark('silero release');
  vad.dispose();
  out.add(_stats('Silero v6.2', silero, const Duration(milliseconds: 32)));
  debugPrint('TTX-BENCH ${out.last}');

  for (final detector in VoiceDetectorKind.values) {
    final pipeline =
        CapturePipeline(
          createDetector: detector == VoiceDetectorKind.silero
              ? (kind, _) => SileroVoiceDetector(modelBytes: model)
              : null,
        )..configure(
          CaptureSettings(
            sampleRate: 48000,
            channels: 1,
            noiseSuppression: true,
            voiceDetection: true,
            detector: detector,
            agc: true,
          ),
        );
    _mark('pipeline ${detector.name}');
    final micros = <int>[];
    for (var i = 0; i + 1920 <= audio48.length; i += 1920) {
      final watch = Stopwatch()..start();
      pipeline.process(
        Uint8List.sublistView(audio48, i, i + 1920),
        transmit: true,
      );
      micros.add(watch.elapsedMicroseconds);
      await Future<void>.delayed(Duration.zero);
    }
    _mark('pipeline ${detector.name} dispose');
    await pipeline.dispose();
    out.add(
      _stats(
        'Pipeline (${detector.name})',
        micros,
        const Duration(milliseconds: 20),
      ),
    );
  }
  return out;
}
