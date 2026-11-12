@Tags(['native'])
library;

import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:teamtalkx/src/audio/media_source.dart';
import 'package:teamtalkx/src/audio/native_engine.dart';
import 'package:teamtalkx/src/audio/native_library.dart';
import 'package:teamtalkx/src/audio/sound_effects.dart';

class _EngineSink implements SpeakerSink {
  _EngineSink(this.engine);
  final NativeAudioEngine engine;
  @override
  int writeSpeaker(int key, Int16List pcm, {double gain = 1}) =>
      engine.writeSpeaker(key, pcm, gain: gain);
  @override
  int speakerQueued(int key) => engine.speakerQueued(key);
  @override
  void removeSpeaker(int key) => engine.removeSpeaker(key);
}

Int16List _clip(int ms, int value) =>
    Int16List(ms * 96)..fillRange(0, ms * 96, value);

void main() {
  group(
    'event sounds (D56)',
    skip: nativeLibraryOverride == ''
        ? 'Needs a host build of native/: --dart-define=TT_NATIVE_LIB=<path>'
        : null,
    () {
      late NativeAudioEngine engine;
      late SoundEffectsMixer mixer;

      setUp(() {
        engine = NativeAudioEngine(sampleRate: 48000, playbackChannels: 2);
        addTearDown(engine.dispose);
        mixer = SoundEffectsMixer(_EngineSink(engine), maxVoices: 2);
      });

      List<int> run(int ms) => [
        for (var t = 0; t < ms; t += 10)
          ...(() {
            mixer.tick();
            return engine.render(480);
          })(),
      ];

      test(
        'a sound longer than the mixer queue plays in full, at its gain',
        () {
          mixer.play(_clip(1500, 10000), gain: 0.5);
          final out = run(1600);

          final loud = out.where((s) => s == 5000).length;
          expect(loud, 1500 * 96);
          expect(mixer.idle, isTrue);
        },
      );

      test('sounds overlap, and the oldest is cut past the limit', () {
        mixer
          ..play(_clip(300, 1000))
          ..play(_clip(300, 2000));
        expect(run(10).first, 3000, reason: 'both at once');

        mixer.play(_clip(300, 4000));
        expect(run(10).first, 6000, reason: 'the first one was cut');
      });

      test('decodes a file to 48 kHz stereo', () {
        final dir = Directory.systemTemp.createTempSync('ttx-sfx');
        addTearDown(() => dir.deleteSync(recursive: true));
        final frames = 1600;
        final b = ByteData(44 + frames * 2)
          ..setUint32(0, 0x46464952, Endian.little)
          ..setUint32(4, 36 + frames * 2, Endian.little)
          ..setUint32(8, 0x45564157, Endian.little)
          ..setUint32(12, 0x20746d66, Endian.little)
          ..setUint32(16, 16, Endian.little)
          ..setUint16(20, 1, Endian.little)
          ..setUint16(22, 1, Endian.little)
          ..setUint32(24, 16000, Endian.little)
          ..setUint32(28, 32000, Endian.little)
          ..setUint16(32, 2, Endian.little)
          ..setUint16(34, 16, Endian.little)
          ..setUint32(36, 0x61746164, Endian.little)
          ..setUint32(40, frames * 2, Endian.little);
        for (var i = 0; i < frames; i++) {
          b.setInt16(
            44 + i * 2,
            (math.sin(2 * math.pi * 440 * i / 16000) * 8000).round(),
            Endian.little,
          );
        }
        final path = '${dir.path}/beep.wav';
        File(path).writeAsBytesSync(b.buffer.asUint8List());

        final source = WavMediaSource(path);
        final pcm = decodeForMixer(source);
        source.close();

        expect(pcm.length, closeTo(4800 * 2, 6));
        for (var i = 0; i < pcm.length; i += 2) {
          expect(pcm[i], pcm[i + 1], reason: 'mono on both channels');
        }
      });
    },
  );
}
