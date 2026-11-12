import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:teamtalkx/src/platform/interruptions.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final early = AndroidInterruptions();
  await early.duckOthers(voiceCall: false);
  runApp(
    const MaterialApp(
      home: Scaffold(body: Center(child: Text('Focus check'))),
    ),
  );
  final started = DateTime.now();
  void log(String line) => debugPrint(
    'TTX-BENCH ${DateTime.now().difference(started).inMilliseconds} ms: $line',
  );
  final interruptions = early;
  interruptions.focusChanges.listen((c) => log('focus ${c.name}'));
  log('ducking others');
  await Future<void>.delayed(const Duration(seconds: 1));
  final view = WidgetsBinding.instance.platformDispatcher.implicitView!;
  await SemanticsService.sendAnnouncement(
    view,
    'TeamTalkX focus check',
    TextDirection.ltr,
  );
  log('announced');
  await Future<void>.delayed(const Duration(seconds: 5));
  await interruptions.stopDuckingOthers();
  log('stopped ducking others');
  log('done');
  debugPrint('TTX-BENCH done');
}
