@Tags(['native'])
library;

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:teamtalkx/src/audio/dsp/time_stretch.dart';
import 'package:teamtalkx/src/audio/native_library.dart';

const _skip = nativeLibraryOverride == ''
    ? 'Needs a host build of native/: --dart-define=TT_NATIVE_LIB=<path>'
    : null;

Int16List _tone(int ms, {int offset = 0}) {
  final frames = 48 * ms;
  final out = Int16List(frames * 2);
  for (var i = 0; i < frames; i++) {
    final v = (math.sin(2 * math.pi * 440 * (offset + i) / 48000) * 8000)
        .round();
    out[i * 2] = v;
    out[i * 2 + 1] = v;
  }
  return out;
}

List<int> _stretch(TimeStretcher s, double speed) {
  final out = <int>[];
  for (var p = 0; p < 50; p++) {
    out.addAll(s.process(_tone(20, offset: p * 960), speed));
  }
  out.addAll(s.flush());
  return out;
}

double _pitch(List<int> pcm) {
  var crossings = 0;
  for (var i = 2; i < pcm.length; i += 2) {
    if (pcm[i - 2] < 0 && pcm[i] >= 0) crossings++;
  }
  return crossings / (pcm.length / 2 / 48000);
}

void main() {
  group('time-stretching', skip: _skip, () {
    late TimeStretcher stretcher;

    setUp(() {
      stretcher = TimeStretcher();
      addTearDown(stretcher.dispose);
    });

    test('at normal speed the audio passes through unchanged', () {
      final tone = _tone(20);
      expect(stretcher.process(tone, 1), tone);
    });

    for (final speed in [1.12, 0.94]) {
      test('at ${speed}x the duration changes, the pitch does not', () {
        final out = _stretch(stretcher, speed);
        final seconds = out.length / 2 / 48000;

        expect(seconds, closeTo(1 / speed, 0.02));
        expect(_pitch(out), closeTo(440, 10));
      });
    }

    test('switching speeds mid-stream loses no audio', () {
      final out = <int>[];
      for (var p = 0; p < 50; p++) {
        final speed = p < 25 ? 1.12 : 1.0;
        out.addAll(stretcher.process(_tone(20, offset: p * 960), speed));
      }
      out.addAll(stretcher.flush());
      expect(out.length / 2 / 48000, closeTo(0.5 / 1.12 + 0.5, 0.02));
    });
  });
}
