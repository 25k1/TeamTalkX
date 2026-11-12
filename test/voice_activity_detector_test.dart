import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:teamtalkx/src/audio/dsp/voice_activity_detector.dart';

Uint8List _pcm(int amplitude, {int samples = 160}) {
  final out = Uint8List(samples * 2);
  final view = ByteData.sublistView(out);
  for (var i = 0; i < samples; i++) {
    view.setInt16(i * 2, amplitude, Endian.little);
  }
  return out;
}

bool _settle(
  VoiceActivityDetector vad,
  double probability, {
  required int level,
  required bool currentlyActive,
  int frames = 40,
}) {
  var active = currentlyActive;
  for (var i = 0; i < frames; i++) {
    active = vad.acceptProbability(
      probability,
      level: level,
      currentlyActive: active,
    );
  }
  return active;
}

void main() {
  group('thresholds', () {
    test('probability threshold spans the level slider', () {
      expect(VoiceActivityDetector.probabilityThreshold(0), 0);
      expect(
        VoiceActivityDetector.probabilityThreshold(20),
        closeTo(0.95, 1e-9),
      );
      var previous = -1.0;
      for (var level = 0; level <= 20; level++) {
        final t = VoiceActivityDetector.probabilityThreshold(level);
        expect(t, greaterThan(previous));
        previous = t;
      }
    });

    test('levels are clamped to the slider range', () {
      expect(
        VoiceActivityDetector.probabilityThreshold(-5),
        VoiceActivityDetector.probabilityThreshold(0),
      );
      expect(
        VoiceActivityDetector.probabilityThreshold(999),
        VoiceActivityDetector.probabilityThreshold(20),
      );
      expect(
        VoiceActivityDetector.rmsThreshold(999),
        VoiceActivityDetector.rmsThreshold(20),
      );
    });

    test('rms threshold spans 0..0.15', () {
      expect(VoiceActivityDetector.rmsThreshold(0), 0);
      expect(VoiceActivityDetector.rmsThreshold(20), closeTo(0.15, 1e-9));
    });
  });

  group('rms', () {
    test('silence is 0 and full scale is ~1', () {
      expect(VoiceActivityDetector.rms(_pcm(0)), 0);
      expect(VoiceActivityDetector.rms(_pcm(32767)), closeTo(1.0, 1e-3));
    });

    test('half amplitude is ~0.5 (linear in amplitude)', () {
      expect(VoiceActivityDetector.rms(_pcm(16384)), closeTo(0.5, 1e-3));
    });

    test('empty frame does not divide by zero', () {
      expect(VoiceActivityDetector.rms(Uint8List(0)), 0);
    });

    test('matches the textbook definition', () {
      final vad = _pcm(1000, samples: 8);
      expect(
        VoiceActivityDetector.rms(vad),
        closeTo(math.sqrt(1000 * 1000) / 32768.0, 1e-9),
      );
    });
  });

  group('probability detection', () {
    test('loud speech triggers, silence does not', () {
      expect(
        _settle(
          VoiceActivityDetector(),
          1.0,
          level: 10,
          currentlyActive: false,
        ),
        isTrue,
      );
      expect(
        _settle(
          VoiceActivityDetector(),
          0.0,
          level: 10,
          currentlyActive: false,
        ),
        isFalse,
      );
    });

    test('level 0 triggers on anything, level 20 needs confident speech', () {
      expect(
        _settle(
          VoiceActivityDetector(),
          0.05,
          level: 0,
          currentlyActive: false,
        ),
        isTrue,
      );
      expect(
        _settle(
          VoiceActivityDetector(),
          0.8,
          level: 20,
          currentlyActive: false,
        ),
        isFalse,
      );
    });

    test('hysteresis: an in-band level holds when speaking but cannot trigger '
        'from idle', () {
      const level = 14;
      final upper = VoiceActivityDetector.probabilityThreshold(level);
      final inBand = upper - 0.05;
      expect(inBand, greaterThan(upper - VoiceActivityDetector.hysteresis));

      expect(
        _settle(
          VoiceActivityDetector(),
          inBand,
          level: level,
          currentlyActive: false,
        ),
        isFalse,
      );

      final vad = VoiceActivityDetector();
      var active = _settle(vad, 1.0, level: level, currentlyActive: false);
      expect(active, isTrue, reason: 'loud speech should trigger first');
      for (var i = 0; i < 40; i++) {
        active = vad.acceptProbability(
          inBand,
          level: level,
          currentlyActive: active,
        );
      }
      expect(active, isTrue, reason: 'in-band dip should hold via hysteresis');
    });

    test('a single loud frame does not trigger (EMA rejects bursts)', () {
      final vad = VoiceActivityDetector();
      final triggered = vad.acceptProbability(
        1.0,
        level: 20,
        currentlyActive: false,
      );
      expect(triggered, isFalse);
    });

    test('reset clears smoothing so detection starts from silence', () {
      final vad = VoiceActivityDetector();
      _settle(vad, 1.0, level: 10, currentlyActive: false);
      expect(vad.smoothedProbability, greaterThan(0.9));
      vad.reset();
      expect(vad.smoothedProbability, 0);
      expect(vad.smoothedRms, 0);
    });
  });

  group('rms fallback detection', () {
    test('loud frames trigger, silence does not', () {
      final loud = VoiceActivityDetector();
      var active = false;
      for (var i = 0; i < 40; i++) {
        active = loud.acceptPcm(_pcm(20000), level: 5, currentlyActive: active);
      }
      expect(active, isTrue);

      final quiet = VoiceActivityDetector();
      var quietActive = false;
      for (var i = 0; i < 40; i++) {
        quietActive = quiet.acceptPcm(
          _pcm(0),
          level: 5,
          currentlyActive: quietActive,
        );
      }
      expect(quietActive, isFalse);
    });

    test('probability and rms smoothing are independent', () {
      final vad = VoiceActivityDetector();
      _settle(vad, 1.0, level: 10, currentlyActive: false);
      expect(vad.smoothedProbability, greaterThan(0));
      expect(vad.smoothedRms, 0);
    });
  });
}
