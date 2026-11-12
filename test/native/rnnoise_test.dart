@Tags(['native'])
library;

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:teamtalkx/src/audio/dsp/noise_suppression.dart';
import 'package:teamtalkx/src/audio/dsp/rnnoise.dart';
import 'package:teamtalkx/src/audio/native_library.dart';

const _skip = nativeLibraryOverride == ''
    ? 'Needs a host build of native/: --dart-define=TT_NATIVE_LIB=<path>'
    : null;

const _frame = RnnoiseDenoiser.frameSize;

Int16List _signal(int samples, {bool tone = true, int seed = 1}) {
  final random = math.Random(seed);
  return Int16List.fromList([
    for (var i = 0; i < samples; i++)
      ((tone ? math.sin(2 * math.pi * 300 * i / 48000) * 8000 : 0) +
              (random.nextDouble() * 2 - 1) * 4000)
          .round(),
  ]);
}

double _rms(List<int> samples) {
  if (samples.isEmpty) return 0;
  var sum = 0.0;
  for (final s in samples) {
    sum += s * s;
  }
  return math.sqrt(sum / samples.length);
}

Uint8List _bytes(Int16List samples) =>
    samples.buffer.asUint8List(samples.offsetInBytes, samples.lengthInBytes);

Int16List _samples(Uint8List pcm) =>
    Int16List.view(pcm.buffer, pcm.offsetInBytes, pcm.lengthInBytes ~/ 2);

void main() {
  group('RNNoise (native)', skip: _skip, () {
    test('removes most of steady noise', () {
      final denoiser = RnnoiseDenoiser();
      addTearDown(denoiser.dispose);
      final noise = _signal(48000 * 2, tone: false);
      final out = <int>[];
      for (var i = 0; i + _frame <= noise.length; i += _frame) {
        final frame = Int16List.fromList(noise.sublist(i, i + _frame));
        final p = denoiser.process(frame);
        expect(p, inInclusiveRange(0, 1));
        out.addAll(frame);
      }
      expect(_rms(out.sublist(48000)), lessThan(_rms(noise) * 0.3));
    });

    test('a dry mix is the input one frame later (no comb filtering)', () {
      final denoiser = RnnoiseDenoiser();
      addTearDown(denoiser.dispose);
      final input = _signal(_frame * 4);
      final out = <int>[];
      for (var i = 0; i < input.length; i += _frame) {
        final frame = Int16List.fromList(input.sublist(i, i + _frame));
        denoiser.process(frame, wet: 0);
        out.addAll(frame);
      }
      expect(out.sublist(0, _frame), everyElement(0));
      expect(out.sublist(_frame), input.sublist(0, input.length - _frame));
    });

    test('reset starts the stream over', () {
      final denoiser = RnnoiseDenoiser();
      addTearDown(denoiser.dispose);
      final frame = _signal(_frame);
      denoiser.process(Int16List.fromList(frame));
      denoiser.reset();
      final again = Int16List.fromList(frame);
      denoiser.process(again, wet: 0);
      expect(again, everyElement(0));
    });
  });

  group('NoiseSuppressor (native)', skip: _skip, () {
    test('48 kHz mono keeps pace with 20 ms capture chunks', () {
      final suppressor = NoiseSuppressor()
        ..configure(sampleRate: 48000, channels: 1, wet: 0.7);
      addTearDown(suppressor.dispose);
      final input = _signal(48000);
      var total = 0;
      for (var i = 0; i < input.length; i += 960) {
        final result = suppressor.process(
          _bytes(Int16List.sublistView(input, i, i + 960)),
        );
        expect(result.pcm.lengthInBytes, 960 * 2);
        expect(result.voiceProbability, inInclusiveRange(0, 1));
        total += result.pcm.lengthInBytes ~/ 2;
      }
      expect(total, input.length);
    });

    test('other rates and stereo come back at the same rate', () {
      final suppressor = NoiseSuppressor()
        ..configure(sampleRate: 16000, channels: 2, wet: 1);
      addTearDown(suppressor.dispose);
      final mono = _signal(16000);
      final stereo = Int16List(mono.length * 2);
      for (var i = 0; i < mono.length; i++) {
        stereo[i * 2] = mono[i];
        stereo[i * 2 + 1] = -mono[i];
      }
      var frames = 0;
      for (var i = 0; i < stereo.length; i += 640) {
        final out = _samples(
          suppressor
              .process(_bytes(Int16List.sublistView(stereo, i, i + 640)))
              .pcm,
        );
        expect(out.length.isEven, isTrue);
        frames += out.length ~/ 2;
      }
      expect(frames, inInclusiveRange(16000 - 400, 16000));
    });

    test('without the native library, audio passes through', () {
      final suppressor = NoiseSuppressor(
        createDenoiser: () => throw ArgumentError('no library'),
      )..configure(sampleRate: 48000, channels: 1, wet: 1);
      final pcm = _bytes(_signal(960));
      final result = suppressor.process(pcm);
      expect(result.pcm, same(pcm));
      expect(result.voiceProbability, isNull);
    });
  });
}
