import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:teamtalkx/src/audio/dsp/agc.dart';
import 'package:teamtalkx/src/audio/dsp/pcm_level.dart';

Uint8List sineFrame(double amplitude, {int samples = 960}) {
  final out = Uint8List(samples * 2);
  final bd = ByteData.view(out.buffer);
  for (var i = 0; i < samples; i++) {
    final t = i / 48000;
    final s = (amplitude * 32767 * math.sin(2 * math.pi * 440 * t))
        .round()
        .clamp(-32768, 32767)
        .toInt();
    bd.setInt16(i * 2, s, Endian.little);
  }
  return out;
}

double settle(AutoGainControl agc, Uint8List frame, {int frames = 100}) {
  var gain = 1.0;
  for (var i = 0; i < frames; i++) {
    gain = agc.gainFor(frame);
  }
  return gain;
}

void main() {
  group('pcmRms', () {
    test('silence measures zero', () {
      expect(pcmRms(Uint8List(960 * 2)), 0);
    });

    test('an empty buffer measures zero', () {
      expect(pcmRms(Uint8List(0)), 0);
    });

    test('a sine measures amplitude / sqrt(2)', () {
      expect(pcmRms(sineFrame(0.5)), closeTo(0.5 / math.sqrt2, 1e-3));
    });

    test('reads a buffer that is not 2-byte aligned', () {
      final frame = sineFrame(0.5);
      final shifted = Uint8List(frame.lengthInBytes + 1)
        ..setRange(1, frame.lengthInBytes + 1, frame);
      final view = Uint8List.sublistView(shifted, 1);
      expect(view.offsetInBytes.isOdd, isTrue);
      expect(pcmRms(view), closeTo(pcmRms(frame), 1e-9));
    });
  });

  group('AutoGainControl.targetForGainPercent', () {
    test('50 % maps to -15 dBFS RMS (0.17783)', () {
      expect(AutoGainControl.targetForGainPercent(50), closeTo(0.17783, 1e-3));
    });

    test('100 % maps to -9 dBFS RMS (0.35566)', () {
      expect(AutoGainControl.targetForGainPercent(100), closeTo(0.35566, 1e-3));
    });

    test('0 % maps to silence', () {
      expect(AutoGainControl.targetForGainPercent(0), 0);
    });
  });

  group('AutoGainControl.gainFor', () {
    test('boosts a quiet signal toward the target level', () {
      final frame = sineFrame(0.05);
      final gain = settle(AutoGainControl(), frame);
      expect(pcmRms(frame) * gain, closeTo(0.17783, 0.02));
    });

    test('attenuates a loud signal toward the target level', () {
      final frame = sineFrame(0.99);
      final gain = settle(AutoGainControl(), frame, frames: 50);
      expect(pcmRms(frame) * gain, closeTo(0.17783, 0.02));
    });

    test('never asks for more than the signal can survive', () {
      final gain = settle(AutoGainControl(), sineFrame(0.9), frames: 200);
      expect(gain, lessThan(1.0));
    });

    test('does not adapt to silence below the gate', () {
      final agc = AutoGainControl();
      expect(agc.gainFor(Uint8List(960 * 2)), 1.0);
      expect(agc.gain, 1.0);
    });

    test('silence freezes the gain instead of drifting', () {
      final agc = AutoGainControl();
      final frozen = settle(agc, sineFrame(0.5), frames: 20);
      expect(frozen, isNot(1.0));
      final silence = Uint8List(960 * 2);
      for (var i = 0; i < 50; i++) {
        expect(agc.gainFor(silence), frozen);
      }
      expect(agc.gain, frozen);
    });

    test('caps the gain at maxGain for very quiet signals', () {
      final agc = AutoGainControl();
      expect(settle(agc, sineFrame(0.014), frames: 200), closeTo(8.0, 0.01));
    });

    test('does not overshoot on the first voiced frame', () {
      final agc = AutoGainControl();
      final frame = sineFrame(0.05);
      final steady = settle(AutoGainControl(), frame);
      for (var i = 0; i < 100; i++) {
        expect(agc.gainFor(frame), lessThanOrEqualTo(steady + 1e-9));
      }
    });

    test('zero target (slider at 0 %) mutes', () {
      final agc = AutoGainControl()
        ..targetRms = AutoGainControl.targetForGainPercent(0);
      expect(agc.gainFor(sineFrame(0.5)), 0);
    });

    test('reset returns the gain to unity', () {
      final agc = AutoGainControl();
      expect(settle(agc, sineFrame(0.014), frames: 200), greaterThan(2));
      agc.reset();
      expect(agc.gain, 1.0);
      expect(agc.gainFor(sineFrame(0.05)), lessThan(2));
    });
  });
}
