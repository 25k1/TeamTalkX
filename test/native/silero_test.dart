@Tags(['native'])
library;

import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:teamtalkx/src/audio/dsp/silero_vad.dart';
import 'package:teamtalkx/src/audio/dsp/silero_voice_detector.dart';
import 'package:teamtalkx/src/audio/native_library.dart';

const _skip = nativeLibraryOverride == ''
    ? 'Needs a host build of native/: --dart-define=TT_NATIVE_LIB=<path>'
    : null;

final _weights = File('assets/vad/silero_vad_v6_2.bin').readAsBytesSync();
final _expected =
    jsonDecode(File('test/fixtures/silero/expected.json').readAsStringSync())
        as Map<String, dynamic>;
final _probs = (_expected['probs'] as List).cast<num>();

Int16List _input() {
  final bytes = File('test/fixtures/silero/input.wav').readAsBytesSync();
  final data = ByteData.sublistView(bytes);
  var at = 12;
  while (String.fromCharCodes(bytes, at, at + 4) != 'data') {
    at += 8 + data.getUint32(at + 4, Endian.little);
  }
  final length = data.getUint32(at + 4, Endian.little) ~/ 2;
  return Int16List.fromList([
    for (var i = 0; i < length; i++)
      data.getInt16(at + 8 + 2 * i, Endian.little),
  ]);
}

List<double> _run(SileroVad vad, Int16List pcm, int step) => [
  for (var i = 0; i < pcm.length; i += step)
    ...vad.feed(Int16List.sublistView(pcm, i, math.min(i + step, pcm.length))),
];

double _largestDifference(List<double> a, List<num> b) {
  expect(a, hasLength(b.length));
  var worst = 0.0;
  for (var i = 0; i < a.length; i++) {
    worst = math.max(worst, (a[i] - b[i]).abs());
  }
  return worst;
}

void main() {
  test('every chunk matches ONNX Runtime', skip: _skip, () {
    final vad = SileroVad(_weights);
    addTearDown(vad.dispose);

    final probs = _run(vad, _input(), SileroVad.chunkSize);

    expect(_largestDifference(probs, _probs), lessThan(1e-4));
    expect(probs.where((p) => p < 0.01), isNotEmpty);
    expect(probs.where((p) => p > 0.95), isNotEmpty);

    final state = vad.state;
    final h = (_expected['final_h'] as List).cast<num>();
    final c = (_expected['final_c'] as List).cast<num>();
    for (var i = 0; i < SileroVad.stateSize; i++) {
      expect(state.h[i], closeTo(h[i], 1e-4));
      expect(state.c[i], closeTo(c[i], 1e-4 * math.max(1, c[i].abs())));
    }
  });

  test('pieces of any size give the same chunks', skip: _skip, () {
    final vad = SileroVad(_weights);
    addTearDown(vad.dispose);

    for (final step in [320, 77]) {
      vad.reset();
      expect(
        _largestDifference(_run(vad, _input(), step), _probs),
        lessThan(1e-4),
      );
    }
  });

  test('reset starts the stream over', skip: _skip, () {
    final vad = SileroVad(_weights);
    addTearDown(vad.dispose);
    final pcm = _input();

    final first = _run(vad, pcm, 320);
    vad.reset();
    final again = _run(vad, pcm, 320);

    expect(again, first);
  });

  test('weights in another format are refused', skip: _skip, () {
    expect(() => SileroVad(Uint8List(0)), throwsArgumentError);
    expect(
      () => SileroVad(Uint8List.sublistView(_weights, 0, _weights.length - 4)),
      throwsArgumentError,
    );
    final wrongMagic = Uint8List.fromList(_weights)..[0] = 0x58;
    expect(() => SileroVad(wrongMagic), throwsArgumentError);
    final wrongShape = Uint8List.fromList(_weights)..[16] = 7;
    expect(() => SileroVad(wrongShape), throwsArgumentError);
  });

  test('the detector turns on for speech and off after it', skip: _skip, () {
    final detector = SileroVoiceDetector(modelBytes: _weights);
    addTearDown(detector.dispose);
    final pcm = _input();

    final states = <bool>[];
    for (var i = 0; i + 320 <= pcm.length; i += 320) {
      final frame = Int16List(320 * 3 * 2);
      for (var j = 0; j < 320; j++) {
        for (var k = 0; k < 6; k++) {
          frame[j * 6 + k] = pcm[i + j];
        }
      }
      states.add(
        detector.accept(
          frame.buffer.asUint8List(),
          probability: null,
          sampleRate: 48000,
          channels: 2,
          level: 10,
          currentlyActive: false,
        ),
      );
    }

    expect(detector.isListening, isTrue);
    expect(states.take(45), everyElement(isFalse));
    expect(states, contains(isTrue));
    expect(states.last, isFalse);
  });

  test('without weights voice activation stays off', skip: _skip, () {
    final detector = SileroVoiceDetector();
    addTearDown(detector.dispose);

    final on = detector.accept(
      Uint8List(1920),
      probability: null,
      sampleRate: 48000,
      channels: 1,
      level: 10,
      currentlyActive: false,
    );

    expect(on, isFalse);
    expect(detector.isListening, isFalse);
  });
}
