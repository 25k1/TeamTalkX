import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:teamtalkx/src/audio/native_engine.dart';
import 'package:teamtalkx/src/platform/media_keys.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(
    const MaterialApp(
      home: Scaffold(body: Center(child: Text('Media keys check'))),
    ),
  );
  final started = DateTime.now();
  void log(String line) => debugPrint(
    'TTX-BENCH ${DateTime.now().difference(started).inMilliseconds} ms: $line',
  );
  final engine = NativeAudioEngine(sampleRate: 48000, playbackChannels: 2);
  engine.startPlayback();
  final silence = Int16List(9600);
  final feeder = Timer.periodic(
    const Duration(milliseconds: 90),
    (_) => engine.writeSpeaker(1, silence),
  );
  final keys = AndroidMediaKeys();
  keys.events.listen((e) => log('${e.key.name} ${e.down ? 'down' : 'up'}'));
  await keys.configure(
    session: true,
    mapped: {MediaKey.playPause, MediaKey.next},
  );
  log('mapped playPause and next, session on');
  await Future<void>.delayed(const Duration(seconds: 20));
  await keys.configure(session: false, mapped: const {});
  log('nothing mapped, session off');
  await Future<void>.delayed(const Duration(seconds: 10));
  feeder.cancel();
  engine.dispose();
  log('done');
  debugPrint('TTX-BENCH done');
}
