import 'dart:io';

import 'package:flutter/material.dart';
import 'package:teamtalkx/src/audio/audio_worker.dart';
import 'package:teamtalkx/src/audio/media_source.dart';
import 'package:teamtalkx/src/protocol/packet.dart';

const _dir = '/data/user/0/org.gozaltech.teamtalkx.dev/files/media-test';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final notifier = ValueNotifier<List<String>>(['Running…']);
  runApp(
    MaterialApp(
      home: Scaffold(
        appBar: AppBar(title: const Text('Media check')),
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
  final out = <String>[];
  void line(String s) {
    out.add(s);
    debugPrint('TTX-BENCH $s');
  }

  final files = [
    for (final f in Directory(
      _dir,
    ).listSync()..sort((a, b) => a.path.compareTo(b.path)))
      f.path,
    '/system/media/audio/ringtones/SoundTheme/Calm/ACH_Bach_Siciliano.ogg',
  ];
  for (final path in files) {
    line(_decode(path));
  }
  await _stream('$_dir/tone.mp3', line);
  debugPrint('TTX-BENCH done');
  notifier.value = out;
}

String _decode(String path) {
  final name = path.split('/').last;
  final watch = Stopwatch()..start();
  try {
    final source = openMediaSource(path);
    try {
      var samples = 0;
      var crossings = 0;
      var previous = 0;
      int? rate;
      int? channels;
      while (true) {
        final chunk = source.read(9600);
        if (chunk == null) break;
        rate ??= source.sampleRate;
        channels ??= source.channels;
        final ch = source.channels;
        for (var i = 0; i < chunk.length; i += ch) {
          if (previous < 0 && chunk[i] >= 0) crossings++;
          previous = chunk[i];
        }
        samples += chunk.length ~/ ch;
      }
      final seconds = samples / (rate ?? 1);
      final decodeMs = watch.elapsedMilliseconds;
      final duration = source.duration;
      var restSeconds = 0.0;
      if (duration != null) {
        source.seek(duration ~/ 2);
        var rest = 0;
        while (true) {
          final chunk = source.read(9600);
          if (chunk == null) break;
          rest += chunk.length ~/ source.channels;
        }
        restSeconds = rest / source.sampleRate;
      }
      return '$name: $rate Hz x$channels, duration '
          '${duration?.inMilliseconds} ms, decoded '
          '${seconds.toStringAsFixed(2)} s in $decodeMs ms, pitch '
          '${(crossings / seconds).round()} Hz, after seeking to the middle '
          '${restSeconds.toStringAsFixed(2)} s';
    } finally {
      source.close();
    }
  } on Exception catch (e) {
    return '$name: FAILED $e';
  }
}

Future<void> _stream(String path, void Function(String) line) async {
  var packets = 0;
  final kinds = <int>{};
  final statuses = <MediaStreamStatus>[];
  final worker = await AudioWorker.spawn(
    onTx: (tx) {
      packets += tx.packets.length;
      for (final p in tx.packets) {
        kinds.add(parseHeader(p).kind);
      }
    },
    onMediaStatus: statuses.add,
  );
  line('native playback: ${await worker.startAudio(outputGain: 0.2)}');
  final error = await worker.startMedia(
    path: path,
    codec: const TxCodecConfig(sampleRate: 48000, channels: 2, bitrate: 96000),
    streamId: 1,
    userId: 1,
    channelId: 1,
    monitor: true,
  );
  line('stream start: ${error ?? 'ok'}');
  await Future<void>.delayed(const Duration(milliseconds: 1500));
  final beforePause = packets;
  worker.controlMedia(paused: true);
  await Future<void>.delayed(const Duration(milliseconds: 500));
  final duringPause = packets - beforePause;
  worker
    ..controlMedia(seekBy: const Duration(seconds: 2))
    ..controlMedia(paused: false);
  await Future<void>.delayed(const Duration(milliseconds: 2500));
  final stats = await worker.engineStats();
  await worker.shutdown();
  final last = statuses.isEmpty ? null : statuses.last;
  line(
    'streamed: $packets packets (kinds $kinds), $duringPause while paused; '
    'last status ${last?.position.inMilliseconds} ms, ended ${last?.ended}',
  );
  line('engine: $stats');
}
