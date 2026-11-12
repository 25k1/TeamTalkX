import 'dart:isolate';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:teamtalkx/src/audio/opus_decoder.dart';
import 'package:teamtalkx/src/audio/opus_encoder.dart';

const _frame = 960;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(
    const MaterialApp(
      home: Scaffold(body: Center(child: Text('Opus check'))),
    ),
  );
  for (final line in await Isolate.run(_measure)) {
    debugPrint('TTX-BENCH $line');
  }
  debugPrint('TTX-BENCH done');
}

Int16List _speechLike(int frames) {
  final random = math.Random(1);
  final out = Int16List(frames * _frame);
  var phase = 0.0;
  for (var i = 0; i < out.length; i++) {
    final t = i / 48000;
    final syllable = 0.5 - 0.5 * math.cos(2 * math.pi * 4 * t);
    final voiced = math.sin(2 * math.pi * 0.7 * t) > -0.6;
    final pitch = 120 + 60 * math.sin(2 * math.pi * 0.3 * t);
    phase += 2 * math.pi * pitch / 48000;
    var s = 0.0;
    if (voiced) {
      for (var h = 1; h <= 30; h++) {
        final f = h * pitch;
        final formants =
            math.exp(-math.pow((f - 700) / 250, 2)) +
            0.6 * math.exp(-math.pow((f - 1200) / 300, 2)) +
            0.3 * math.exp(-math.pow((f - 2600) / 400, 2));
        s += formants * math.sin(h * phase) / h;
      }
    } else {
      s = (random.nextDouble() * 2 - 1) * 0.15;
    }
    out[i] = (s * syllable * 9000).round().clamp(-32768, 32767);
  }
  return out;
}

List<Uint8List> _encode(Int16List pcm, int bitrate, {int dredMs = 0}) {
  final encoder = OpusFrameEncoder(
    sampleRate: 48000,
    channels: 1,
    bitrate: bitrate,
    fec: true,
    lossPercent: dredMs > 0 ? 20 : 10,
    dredMs: dredMs,
  );
  final watch = Stopwatch()..start();
  final packets = [
    for (var i = 0; i < pcm.length ~/ _frame; i++)
      Uint8List.fromList(
        encoder.encode(
          Int16List.sublistView(pcm, i * _frame, (i + 1) * _frame),
        ),
      ),
  ];
  _lastEncodeUs = watch.elapsedMicroseconds / packets.length;
  encoder.dispose();
  return packets;
}

double _lastEncodeUs = 0;

String _median(List<int> us) {
  us.sort();
  return '${us[us.length ~/ 2]} us median, ${us[(us.length * 0.99).floor()]} p99';
}

List<String> _measure() {
  final out = <String>[];
  final pcm = _speechLike(1000);
  for (final bitrate in [16000, 32000]) {
    final packets = _encode(pcm, bitrate);
    out.add('$bitrate bit/s: encode ${_lastEncodeUs.toStringAsFixed(0)} us');
    for (final (c, bwe) in [
      (0, false),
      (5, false),
      (6, false),
      (7, false),
      (7, true),
    ]) {
      final d = OpusFrameDecoder(sampleRate: 48000, channels: 1)
        ..setQuality(complexity: c, bandwidthExtension: bwe);
      final us = <int>[];
      for (final p in packets) {
        final w = Stopwatch()..start();
        d.decode(p);
        us.add(w.elapsedMicroseconds);
      }
      d.dispose();
      out.add(
        '$bitrate bit/s decode, complexity $c${bwe ? ' +bwe' : ''}: '
        '${_median(us)}',
      );
    }
  }
  final dred = _encode(pcm, 32000, dredMs: 100);
  out.add(
    '32000 bit/s with DRED 100 ms: encode ${_lastEncodeUs.toStringAsFixed(0)} us',
  );
  for (final (name, useNext, offset) in [
    ('deep PLC', false, _frame),
    ('FEC', true, _frame),
    ('DRED 3 back', true, 3 * _frame),
  ]) {
    final d = OpusFrameDecoder(sampleRate: 48000, channels: 1)
      ..setQuality(complexity: 5);
    final us = <int>[];
    final methods = <OpusRecovery, int>{};
    for (var i = 10; i < dred.length - 5; i++) {
      if (i % 10 == 0) {
        final w = Stopwatch()..start();
        d.recover(
          useNext ? dred[i + offset ~/ _frame] : null,
          offset: offset,
          samplesPerChannel: _frame,
        );
        us.add(w.elapsedMicroseconds);
        methods.update(d.lastRecovery, (n) => n + 1, ifAbsent: () => 1);
      } else {
        d.decode(dred[i]);
      }
    }
    d.dispose();
    out.add(
      'recover by $name: ${_median(us)} ${methods.map((k, v) => MapEntry(k.name, v))}',
    );
  }
  return out;
}
