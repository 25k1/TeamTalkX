@Tags(['native'])
library;

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:teamtalkx/src/audio/native_library.dart';
import 'package:teamtalkx/src/audio/speex_codec.dart';
import 'package:teamtalkx/src/audio/voice_decoder.dart';

const _skip = nativeLibraryOverride == ''
    ? 'Needs a host build of native/: --dart-define=TT_NATIVE_LIB=<path>'
    : null;

Int16List _tone(int rate, int index) {
  final n = rate ~/ 50;
  return Int16List.fromList([
    for (var i = 0; i < n; i++)
      (math.sin(2 * math.pi * 440 * (index * n + i) / rate) * 8000).round(),
  ]);
}

double _pitch(List<int> pcm, int rate, {int step = 1}) {
  var crossings = 0;
  for (var i = step; i < pcm.length; i += step) {
    if (pcm[i - step] < 0 && pcm[i] >= 0) crossings++;
  }
  return crossings / (pcm.length / step / rate);
}

double _level(List<int> pcm) =>
    pcm.fold<int>(0, (n, s) => n + s.abs()) / math.max(1, pcm.length);

void main() {
  group('Speex (D23)', skip: _skip, () {
    for (final band in [0, 1, 2]) {
      final rate = speexSampleRate(band);
      test('band $band ($rate Hz) encodes and decodes a tone', () {
        final encoder = SpeexFrameEncoder(bandMode: band, quality: 8);
        final decoder = SpeexFrameDecoder(bandMode: band);
        addTearDown(encoder.dispose);
        addTearDown(decoder.dispose);
        expect(encoder.frameSamples, rate ~/ 50);

        final sizes = <int>{};
        final out = <int>[];
        for (var i = 0; i < 25; i++) {
          final encoded = encoder.encode(_tone(rate, i));
          sizes.add(encoded.length);
          out.addAll(decoder.decode(encoded));
        }

        expect(sizes, hasLength(1), reason: 'constant bitrate');
        expect(out, hasLength(25 * rate ~/ 50));
        final steady = out.sublist(out.length ~/ 2);
        expect(_level(steady), greaterThan(2000));
        expect(_pitch(steady, rate), closeTo(440, 30));
      });
    }

    test('VBR frames vary in size, silence is cheap', () {
      final encoder = SpeexFrameEncoder.vbr(
        bandMode: 1,
        vbrQuality: 6,
        dtx: true,
      );
      addTearDown(encoder.dispose);
      final tone = [
        for (var i = 0; i < 10; i++) encoder.encode(_tone(16000, i)),
      ];
      final silence = [
        for (var i = 0; i < 10; i++) encoder.encode(Int16List(320)),
      ];
      expect(silence.last.length, lessThan(tone.last.length));
    });

    test('a lost frame is concealed with a full frame', () {
      final decoder = SpeexFrameDecoder(bandMode: 1);
      addTearDown(decoder.dispose);
      expect(decoder.decode(null), hasLength(320));
    });

    test('the voice decoder plays it at 48 kHz on both channels', () {
      final encoder = SpeexFrameEncoder(bandMode: 1, quality: 8);
      final decoder = SpeexVoiceDecoder(1);
      addTearDown(encoder.dispose);
      addTearDown(decoder.dispose);

      final out = <int>[];
      for (var i = 0; i < 25; i++) {
        out.addAll(decoder.decode(encoder.encode(_tone(16000, i))));
      }
      final concealed = decoder.conceal(1920);

      expect(out, hasLength(25 * 960 * 2));
      expect(concealed, hasLength(2 * 960 * 2), reason: 'two 20 ms frames');
      final steady = out.sublist(out.length ~/ 2);
      for (var i = 0; i < steady.length; i += 2) {
        expect(steady[i], steady[i + 1]);
      }
      expect(_pitch(steady, 48000, step: 2), closeTo(440, 30));
    });
  });
}
