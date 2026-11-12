import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:teamtalkx/src/audio/dsp/pcm_resampler.dart';

Uint8List _bytes(List<int> samples) {
  final out = Uint8List(samples.length * 2);
  final view = ByteData.sublistView(out);
  for (var i = 0; i < samples.length; i++) {
    view.setInt16(i * 2, samples[i], Endian.little);
  }
  return out;
}

List<int> _samples(Uint8List pcm) {
  final view = ByteData.sublistView(pcm);
  return [
    for (var i = 0; i < pcm.lengthInBytes ~/ 2; i++)
      view.getInt16(i * 2, Endian.little),
  ];
}

Uint8List _tone(double hz, int sampleRate) => _bytes([
  for (var i = 0; i < sampleRate; i++)
    (math.sin(2 * math.pi * hz * i / sampleRate) * 20000).round(),
]);

void main() {
  test('16 kHz mono passes through untouched', () {
    final input = _bytes([1, -2, 3, -4]);
    final out = resampleForVad(input, sampleRate: 16000, channels: 1);
    expect(_samples(out), [1, -2, 3, -4]);
  });

  test('stereo is downmixed by averaging both channels', () {
    final input = _bytes([100, 200, -100, -200]);
    final out = resampleForVad(input, sampleRate: 16000, channels: 2);
    expect(_samples(out), [150, -150]);
  });

  test('48 kHz decimates 3:1 by averaging (integer factor)', () {
    final input = _bytes([3, 6, 9, 30, 60, 90, -3, -6, -9]);
    final out = resampleForVad(input, sampleRate: 48000, channels: 1);
    expect(_samples(out), [6, 60, -6]);
  });

  test('output length matches the target rate', () {
    for (final rate in [16000, 24000, 48000, 44100]) {
      final out = resampleForVad(
        _tone(440, rate),
        sampleRate: rate,
        channels: 1,
      );
      final produced = out.lengthInBytes ~/ 2;
      expect(produced, closeTo(vadSampleRate, 2), reason: 'from $rate Hz');
    }
  });

  test('44.1 kHz (non-integer ratio) resamples via interpolation', () {
    final out = resampleForVad(
      _tone(440, 44100),
      sampleRate: 44100,
      channels: 1,
    );
    expect(out.lengthInBytes ~/ 2, closeTo(vadSampleRate, 2));
  });

  test('a 440 Hz tone keeps its amplitude through downsampling', () {
    final out = resampleForVad(
      _tone(440, 48000),
      sampleRate: 48000,
      channels: 1,
    );
    final peak = _samples(out).map((s) => s.abs()).reduce(math.max);
    expect(peak, greaterThan(18000));
    expect(peak, lessThanOrEqualTo(20001));
  });

  test('stereo 48 kHz downmixes and decimates together', () {
    final out = resampleForVad(
      _tone(440, 48000 * 2),
      sampleRate: 48000,
      channels: 2,
    );
    expect(out.lengthInBytes ~/ 2, closeTo(vadSampleRate, 2));
  });

  test('empty and sub-frame input do not throw', () {
    expect(
      resampleForVad(Uint8List(0), sampleRate: 48000, channels: 1),
      isEmpty,
    );
    expect(
      resampleForVad(_bytes([1]), sampleRate: 48000, channels: 1),
      isEmpty,
    );
  });

  group('StreamingResampler', () {
    Int16List tone(int rate, int count, {double hz = 440}) =>
        Int16List.fromList([
          for (var i = 0; i < count; i++)
            (math.sin(2 * math.pi * hz * i / rate) * 20000).round(),
        ]);

    test('the same rate passes through', () {
      final input = tone(48000, 480);
      expect(StreamingResampler(48000, 48000).process(input), same(input));
    });

    test('output length follows the rate ratio across chunk sizes', () {
      for (final (from, to) in [
        (16000, 48000),
        (48000, 16000),
        (44100, 48000),
      ]) {
        final resampler = StreamingResampler(from, to);
        var produced = 0;
        var consumed = 0;
        for (final size in [160, 333, 1, 960, 441, 77]) {
          produced += resampler.process(tone(from, size)).length;
          consumed += size;
        }
        expect(
          produced,
          closeTo(consumed * to / from, 2),
          reason: '$from -> $to',
        );
      }
    });

    test('chunked output matches one-shot output', () {
      final input = tone(16000, 1600);
      final whole = StreamingResampler(16000, 48000).process(input);
      final chunked = StreamingResampler(16000, 48000);
      final parts = <int>[];
      for (var i = 0; i < input.length; i += 160) {
        parts.addAll(chunked.process(Int16List.sublistView(input, i, i + 160)));
      }
      expect(parts, whole);
    });

    test('a tone survives a round trip', () {
      final input = tone(16000, 1600, hz: 300);
      final up = StreamingResampler(16000, 48000).process(input);
      final back = StreamingResampler(48000, 16000).process(up);
      var maxError = 0;
      for (var i = 10; i < back.length - 10; i++) {
        maxError = math.max(maxError, (back[i] - input[i - 1]).abs());
      }
      expect(maxError, lessThan(2000));
    });
  });

  group('resamplePcm downsampling', () {
    Int16List tone(double hz) => Int16List.fromList([
      for (var i = 0; i < 4800; i++)
        (math.sin(2 * math.pi * hz * i / 48000) * 10000).round(),
    ]);
    double level(Int16List pcm) =>
        pcm.fold<int>(0, (n, s) => n + s.abs()) / pcm.length;

    test('48 to 8 kHz damps what would alias', () {
      final out = resamplePcm(tone(7000), 48000, 1, 8000, 1);
      expect(out, hasLength(800));
      expect(level(out), lessThan(level(tone(7000)) / 4));
    });

    test('speech frequencies pass', () {
      final out = resamplePcm(tone(440), 48000, 1, 16000, 1);
      expect(out, hasLength(1600));
      expect(level(out), greaterThan(level(tone(440)) * 0.9));
    });
  });
}
