import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:teamtalkx/src/audio/dsp/playback_normalizer.dart';

Int16List _chunk(double db) {
  final amplitude = math.pow(10, db / 20) * math.sqrt2 * 32767;
  return Int16List.fromList([
    for (var i = 0; i < 960; i++)
      for (var c = 0; c < 2; c++)
        (math.sin(2 * math.pi * 440 * i / 48000) * amplitude).round(),
  ]);
}

void main() {
  test('a quiet speaker is raised slowly, up to the limit', () {
    final n = PlaybackNormalizer();
    n.update(_chunk(-40));
    expect(n.gainDb, closeTo(0.06, 0.01), reason: '3 dB/s for 20 ms');
    for (var i = 0; i < 50 * 10; i++) {
      n.update(_chunk(-40));
    }
    expect(n.gainDb, 15, reason: 'wanted +20 dB, capped at +15');
  });

  test('a loud speaker is lowered to the target', () {
    final n = PlaybackNormalizer();
    for (var i = 0; i < 50 * 5; i++) {
      n.update(_chunk(-12));
    }
    expect(n.gainDb, closeTo(-8, 0.1));
    expect(n.gain, closeTo(0.398, 0.01));
  });

  test('silence leaves the gain alone', () {
    final n = PlaybackNormalizer();
    for (var i = 0; i < 50; i++) {
      n.update(_chunk(-40));
    }
    final before = n.gainDb;
    for (var i = 0; i < 100; i++) {
      n.update(Int16List(1920));
    }
    expect(n.gainDb, before);
    n.reset();
    expect(n.gain, 1);
  });
}
