import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:teamtalkx/src/audio/native_engine.dart';
import 'package:teamtalkx/src/platform/audio_routing.dart';
import 'package:teamtalkx/src/platform/interruptions.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(
    const MaterialApp(
      home: Scaffold(body: Center(child: Text('Interruptions check'))),
    ),
  );
  final started = DateTime.now();
  void log(String line) => debugPrint(
    'TTX-BENCH ${DateTime.now().difference(started).inMilliseconds} ms: $line',
  );

  final interruptions = AndroidInterruptions();
  interruptions.callState.listen((s) => log('call ${s.name}'));
  interruptions.otherAppPlaying.listen((p) => log('other app playing $p'));

  final engine = NativeAudioEngine(sampleRate: 48000, playbackChannels: 2);
  log('own playback started: ${engine.startPlayback()}');
  final silence = Int16List(9600);
  final feeder = Timer.periodic(
    const Duration(milliseconds: 90),
    (_) => engine.writeSpeaker(1, silence),
  );
  await interruptions.start();

  await Future<void>.delayed(const Duration(seconds: 3));
  final routing = AndroidAudioRouting();
  await routing.setCommunication(on: true);
  log('own voice-call mode on');
  await Future<void>.delayed(const Duration(seconds: 3));
  await routing.setCommunication(on: false);
  log('own voice-call mode off');

  final seconds = int.tryParse(
    const String.fromEnvironment('TT_CHECK_SECONDS', defaultValue: '30'),
  );
  await Future<void>.delayed(Duration(seconds: seconds ?? 30));
  feeder.cancel();
  await interruptions.stop();
  engine.dispose();
  log('done');
  debugPrint('TTX-BENCH done');
}
