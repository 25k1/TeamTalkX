import 'dart:isolate';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:teamtalkx/src/audio/latency_probe.dart';
import 'package:teamtalkx/src/audio/native_engine.dart';

const _pipelineMs = 20 + 60;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final notifier = ValueNotifier<List<String>>(['Measuring…']);
  runApp(
    MaterialApp(
      home: Scaffold(
        appBar: AppBar(title: const Text('Latency probe')),
        body: ValueListenableBuilder(
          valueListenable: notifier,
          builder: (_, lines, _) => ListView(
            padding: const EdgeInsets.all(16),
            children: [for (final line in lines) Text(line)],
          ),
        ),
      ),
    ),
  );
  final results = await Isolate.run(_measure);
  for (final line in results) {
    debugPrint('TTX-BENCH $line');
  }
  debugPrint('TTX-BENCH done');
  notifier.value = results;
}

Future<List<String>> _measure() async {
  final out = <String>[];
  final engine = NativeAudioEngine(sampleRate: 48000, playbackChannels: 2);
  final probe = LatencyProbe();

  void read() => probe.addCapture(engine.readCapture());
  Future<void> run(Duration duration) async {
    final end = DateTime.now().add(duration);
    while (DateTime.now().isBefore(end)) {
      await Future<void>.delayed(const Duration(milliseconds: 5));
      read();
    }
  }

  out
    ..add('playback: ${engine.startPlayback()}')
    ..add(
      'capture: '
      '${engine.startCapture(audioSource: 9, sampleRate: 48000, channels: 1)}',
    );
  await run(const Duration(milliseconds: 600));

  final mono = probe.burst();
  final stereo = Int16List(mono.length * 2);
  for (var i = 0; i < mono.length; i++) {
    stereo[i * 2] = mono[i];
    stereo[i * 2 + 1] = mono[i];
  }

  final trips = <double>[];
  for (var round = 0; round < 5; round++) {
    read();
    final played = probe.capturedSamples;
    engine.writeSpeaker(1, stereo);
    await run(const Duration(milliseconds: 500));
    final onset = probe.onsetAfter(played);
    if (onset == null) {
      out.add('round ${round + 1}: burst not heard');
    } else {
      final ms = probe.millis(played, onset);
      trips.add(ms);
      out.add('round ${round + 1}: ${ms.toStringAsFixed(1)} ms');
    }
  }
  out.add('engine: ${engine.stats()}');
  engine
    ..stopCapture()
    ..stopPlayback()
    ..dispose();

  if (trips.isNotEmpty) {
    trips.sort();
    final median = trips[trips.length ~/ 2];
    out
      ..add('acoustic round trip (median): ${median.toStringAsFixed(1)} ms')
      ..add(
        'mouth-to-ear estimate without network: '
        '${(median + _pipelineMs).toStringAsFixed(0)} ms '
        '(round trip + 20 ms frame + 60 ms jitter prebuffer; target 150 ms)',
      );
  }
  return out;
}
