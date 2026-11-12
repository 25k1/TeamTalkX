import 'dart:async';
import 'dart:isolate';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:teamtalkx/src/audio/native_engine.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final notifier = ValueNotifier<List<String>>(['Running…']);
  runApp(
    MaterialApp(
      home: Scaffold(
        appBar: AppBar(title: const Text('Audio engine check')),
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
  final results = await Isolate.run(_check);
  for (final line in results) {
    debugPrint('TTX-BENCH $line');
  }
  debugPrint('TTX-BENCH done');
  notifier.value = results;
}

Future<void> _every20ms(int times, void Function(int tick) body) async {
  final done = Completer<void>();
  var tick = 0;
  Timer.periodic(const Duration(milliseconds: 20), (timer) {
    body(tick++);
    if (tick >= times) {
      timer.cancel();
      done.complete();
    }
  });
  return done.future;
}

Future<List<String>> _check() async {
  final out = <String>[];
  final engine = NativeAudioEngine(sampleRate: 48000, playbackChannels: 2);

  out.add('startPlayback: ${engine.startPlayback()}');
  var phase = 0;
  final rejected = <int>[];
  await _every20ms(50, (_) {
    final frame = Int16List(960 * 2);
    for (var i = 0; i < 960; i++) {
      final v = (math.sin(2 * math.pi * 440 * phase++ / 48000) * 3277).round();
      frame[i * 2] = v;
      frame[i * 2 + 1] = v;
    }
    if (engine.writeSpeaker(1, frame) < frame.length) rejected.add(1);
  });
  await Future<void>.delayed(const Duration(milliseconds: 200));
  out
    ..add('playback: ${engine.stats()}')
    ..add('playback writes rejected: ${rejected.length}');
  engine.stopPlayback();

  out.add(
    'startCapture: '
    '${engine.startCapture(audioSource: 7, sampleRate: 48000, channels: 1)}',
  );
  var samples = 0;
  var sumSquares = 0.0;
  var reads = 0;
  await _every20ms(50, (_) {
    final pcm = engine.readCapture();
    reads++;
    samples += pcm.length;
    for (final s in pcm) {
      sumSquares += s * s;
    }
  });
  out
    ..add('capture: ${engine.stats()}')
    ..add(
      'captured $samples samples in $reads reads '
      '(~48000 expected), rms '
      '${samples == 0 ? 0 : math.sqrt(sumSquares / samples).toStringAsFixed(0)}',
    );
  engine
    ..stopCapture()
    ..dispose();
  return out;
}
