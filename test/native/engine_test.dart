@Tags(['native'])
library;

import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:teamtalkx/src/audio/native_engine.dart';
import 'package:teamtalkx/src/audio/native_library.dart';

const _skip = nativeLibraryOverride == ''
    ? 'Needs a host build of native/: --dart-define=TT_NATIVE_LIB=<path>'
    : null;

Int16List _constant(int samples, int value) =>
    Int16List(samples)..fillRange(0, samples, value);

void main() {
  group('native audio engine (core)', skip: _skip, () {
    late NativeAudioEngine engine;

    setUp(() {
      engine = NativeAudioEngine(sampleRate: 48000, playbackChannels: 2);
      addTearDown(engine.dispose);
    });

    test('there is no device on the host', () {
      expect(engine.startPlayback(), engineNoDevice);
      expect(
        engine.startCapture(audioSource: 7, sampleRate: 48000, channels: 1),
        engineNoDevice,
      );
    });

    test('mixes speakers with their gains and the master gain', () {
      engine
        ..writeSpeaker(1, _constant(960, 1000), gain: 0.5)
        ..writeSpeaker(2, _constant(960, 2000))
        ..masterGain = 2;

      final out = engine.render(480);

      expect(out, hasLength(960));
      expect(out, everyElement((1000 * 0.5 + 2000) * 2));
      expect(engine.stats().activeSpeakers, 2);
      expect(engine.render(480), everyElement(0));
    });

    test('bends loud audio towards full scale instead of clipping', () {
      for (var key = 1; key <= 3; key++) {
        engine.writeSpeaker(key, _constant(4, -30000));
      }
      final loud = engine.render(2);
      expect(loud, everyElement(inInclusiveRange(-32767, -32000)));

      engine.writeSpeaker(1, _constant(4, 24000));
      expect(engine.render(2), everyElement(24000));

      engine.writeSpeaker(1, _constant(2, 28000));
      final a = engine.render(1).first;
      engine.writeSpeaker(1, _constant(2, 32000));
      final b = engine.render(1).first;
      expect(a, inExclusiveRange(24576, 28000));
      expect(b, inExclusiveRange(a, 32767));
    });

    test('reports what each speaker still has queued', () {
      engine
        ..writeSpeaker(1, _constant(960, 1))
        ..writeSpeaker(2, _constant(1920, 1));
      expect(engine.speakerQueued(1), 960);
      expect(engine.speakerQueued(2), 1920);
      expect(engine.speakerQueued(3), 0, reason: 'no such speaker');

      engine.render(240);

      expect(engine.speakerQueued(1), 480);
      expect(engine.speakerQueued(2), 1440);
    });

    test('a removed speaker is silent and its slot is reused', () {
      for (var key = 0; key < 32; key++) {
        expect(engine.writeSpeaker(key, _constant(2, 100)), 2);
      }
      expect(engine.writeSpeaker(99, _constant(2, 100)), -1, reason: 'full');

      engine.removeSpeaker(5);
      engine.render(1);
      expect(engine.stats().activeSpeakers, 31);
      expect(engine.writeSpeaker(99, _constant(2, 7)), 2);
    });

    test('a speaker more than 500 ms ahead loses the oldest audio', () {
      final pcm = _constant(60000, 1)
        ..[59998] = 9
        ..[59999] = 9;
      expect(engine.writeSpeaker(1, pcm), 60000);

      final out = engine.render(24000);

      expect(engine.stats().speakerDropped, 12000, reason: '125 ms dropped');
      expect(out.last, 9, reason: 'the newest 500 ms are kept');
    });

    test('a write beyond the queue drops what does not fit', () {
      final accepted = engine.writeSpeaker(1, _constant(96000, 1));

      expect(accepted, lessThan(96000));
      expect(engine.stats().speakerDropped, 96000 - accepted);
    });

    test('captured audio is read back in order and overflow is counted', () {
      engine
        ..pushCapture(Int16List.fromList([1, 2, 3]))
        ..pushCapture(Int16List.fromList([4, 5]));
      expect(engine.readCapture(), [1, 2, 3, 4, 5]);
      expect(engine.readCapture(), isEmpty);

      engine.pushCapture(_constant(96000, 1));
      engine.pushCapture(_constant(96000, 1));
      expect(engine.stats().captureOverflow, greaterThan(0));
    });
  });
}
