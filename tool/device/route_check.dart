import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:teamtalkx/src/audio/native_engine.dart';
import 'package:teamtalkx/src/platform/audio_routing.dart';

Int16List _tone(int ms) => Int16List.fromList([
  for (var i = 0; i < ms * 48; i++)
    for (var c = 0; c < 2; c++)
      (math.sin(2 * math.pi * 660 * i / 48000) * 3000).round(),
]);

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(
    const MaterialApp(
      home: Scaffold(body: Center(child: Text('Route check'))),
    ),
  );
  final routing = AndroidAudioRouting();
  final outputs = await routing.outputs();
  for (final d in outputs) {
    debugPrint('TTX-BENCH output ${d.id}: ${d.kind.name} "${d.name}"');
  }
  final engine = NativeAudioEngine(sampleRate: 48000, playbackChannels: 2);
  debugPrint('TTX-BENCH start playback: ${engine.startPlayback()}');

  Future<void> play(String label) async {
    final tone = _tone(400);
    for (var off = 0; off < tone.length; off += 9600) {
      engine.writeSpeaker(
        1,
        Int16List.sublistView(tone, off, math.min(off + 9600, tone.length)),
      );
      await Future<void>.delayed(const Duration(milliseconds: 90));
    }
    await Future<void>.delayed(const Duration(milliseconds: 300));
    debugPrint('TTX-BENCH $label: ${engine.stats()}');
  }

  await play('media, automatic');
  await routing.setCommunication(on: true);
  engine.setOutput(voiceCall: true);
  debugPrint(
    'TTX-BENCH capture in call mode: ${engine.startCapture(audioSource: 7, sampleRate: 48000, channels: 1)}',
  );
  await play('voice call, automatic');
  for (final d in outputs.where((d) => d.kind != AudioOutputKind.speaker)) {
    await routing.setCommunication(on: true, deviceId: d.id);
    await play('voice call to ${d.kind.name}');
  }
  engine.stopCapture();
  await routing.setCommunication(on: false);
  for (final d in outputs.where((d) => d.kind != AudioOutputKind.earpiece)) {
    engine.setOutput(voiceCall: false, deviceId: d.id);
    await play('media to ${d.kind.name}');
  }
  engine.setOutput(voiceCall: false);
  engine
    ..stopPlayback()
    ..dispose();
  debugPrint('TTX-BENCH done');
}
