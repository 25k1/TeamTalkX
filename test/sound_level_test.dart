import 'package:flutter_test/flutter_test.dart';
import 'package:teamtalkx/src/domain/sound_level.dart';

void main() {
  group('refVolume', () {
    test('clamps to 0..100', () {
      expect(refVolume(-10.0), refVolume(0.0));
      expect(refVolume(150.0), refVolume(100.0));
    });

    test('0 % maps to ~32 (TeamTalk convention, not silence)', () {
      expect(refVolume(0), inInclusiveRange(30, 35));
    });

    test('100 % maps to the curve maximum (~13268)', () {
      expect(refVolume(100), inInclusiveRange(13260, 13280));
    });

    test('is monotonically increasing', () {
      var prev = refVolume(0.0);
      for (var p = 5; p <= 100; p += 5) {
        final v = refVolume(p.toDouble());
        expect(v, greaterThan(prev), reason: 'p=$p should be > p=${p - 5}');
        prev = v;
      }
    });
  });

  group('refVolumeToPercent', () {
    test('round-trip preserves value at multiples of 5', () {
      for (var p = 0; p <= 100; p += 5) {
        final back = refVolumeToPercent(refVolume(p.toDouble()));
        expect(back, p, reason: 'p=$p');
      }
    });

    test('respects custom step', () {
      expect(refVolumeToPercent(1000, step: 10), 50);
    });

    test('volume 0 returns 0', () {
      expect(refVolumeToPercent(0), 0);
    });

    test('clamps to 100 at the top', () {
      expect(refVolumeToPercent(soundVolumeMax + 1000), 100);
    });
  });

  group('refGain', () {
    test('returns 0 at exactly 0 %', () {
      expect(refGain(0), 0);
    });

    test('agrees with refVolume for positive percent', () {
      expect(refGain(50), refVolume(50));
      expect(refGain(100), refVolume(100));
    });
  });
}
