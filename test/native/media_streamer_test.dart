@Tags(['native'])
library;

import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:teamtalkx/src/audio/codec_config.dart';
import 'package:teamtalkx/src/audio/media_source.dart';
import 'package:teamtalkx/src/audio/media_streamer.dart';
import 'package:teamtalkx/src/audio/native_library.dart';
import 'package:teamtalkx/src/audio/voice_decoder.dart';
import 'package:teamtalkx/src/domain/tt_types.dart';
import 'package:teamtalkx/src/protocol/packet.dart';

String _wav(
  Directory dir, {
  int rate = 44100,
  int channels = 2,
  double seconds = 1,
}) {
  final frames = (rate * seconds).round();
  final data = ByteData(frames * channels * 2);
  for (var f = 0; f < frames; f++) {
    final v = (math.sin(2 * math.pi * 440 * f / rate) * 10000).round();
    for (var c = 0; c < channels; c++) {
      data.setInt16((f * channels + c) * 2, v, Endian.little);
    }
  }
  final header = ByteData(44)
    ..setUint32(0, 0x46464952, Endian.little)
    ..setUint32(4, 36 + data.lengthInBytes, Endian.little)
    ..setUint32(8, 0x45564157, Endian.little)
    ..setUint32(12, 0x20746d66, Endian.little)
    ..setUint32(16, 16, Endian.little)
    ..setUint16(20, 1, Endian.little)
    ..setUint16(22, channels, Endian.little)
    ..setUint32(24, rate, Endian.little)
    ..setUint32(28, rate * channels * 2, Endian.little)
    ..setUint16(32, channels * 2, Endian.little)
    ..setUint16(34, 16, Endian.little)
    ..setUint32(36, 0x61746164, Endian.little)
    ..setUint32(40, data.lengthInBytes, Endian.little);
  final path = '${dir.path}/tone-$rate-$channels.wav';
  File(path).writeAsBytesSync([
    ...header.buffer.asUint8List(),
    ...data.buffer.asUint8List(),
  ]);
  return path;
}

const _opusStereo = TxCodecConfig(
  sampleRate: 48000,
  channels: 2,
  bitrate: 64000,
);

int _ms(int ms) => ms * 1000;

List<Uint8List> _run(MediaStreamer streamer, int fromMs, int toMs) => [
  for (var t = fromMs; t <= toMs; t += 10) ...streamer.tick(_ms(t)).packets,
];

double _pitch(List<int> stereo) {
  var crossings = 0;
  for (var i = 2; i < stereo.length; i += 2) {
    if (stereo[i - 2] < 0 && stereo[i] >= 0) crossings++;
  }
  return crossings / (stereo.length / 2 / 48000);
}

double _level(List<int> pcm) =>
    pcm.fold<int>(0, (n, s) => n + s.abs()) / math.max(1, pcm.length);

List<int> _decode(List<Uint8List> packets, VoiceFrameDecoder decoder) => [
  for (final p in packets) ...decoder.decode(parseVoicePacket(p)!.encodedAudio),
];

void main() {
  late Directory dir;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('ttx-media');
    addTearDown(() => dir.deleteSync(recursive: true));
  });

  group('WAV media source', () {
    test('reads its format, audio and duration, and seeks', () {
      final source = WavMediaSource(_wav(dir, seconds: 0.5));
      addTearDown(source.close);
      expect(source.sampleRate, 44100);
      expect(source.channels, 2);
      expect(source.duration.inMilliseconds, 500);

      expect(source.read(1000), hasLength(1000));
      source.seek(const Duration(milliseconds: 499));
      final rest = source.read(100000)!;
      expect(rest.length, closeTo(44 * 2, 4));
      expect(source.read(1000), isNull, reason: 'the end');
    });

    test('refuses what is not 16-bit PCM WAV', () {
      final path = '${dir.path}/x.mp3';
      File(path).writeAsBytesSync(List.filled(100, 7));
      expect(() => WavMediaSource(path), throwsFormatException);
    });
  });

  group(
    'media streaming (V5)',
    skip: nativeLibraryOverride == ''
        ? 'Needs a host build of native/: --dart-define=TT_NATIVE_LIB=<path>'
        : null,
    () {
      MediaStreamer streamer(
        String path, {
        TxCodecConfig codec = _opusStereo,
        bool loop = false,
        double gain = 1,
        bool monitor = false,
      }) {
        final s = MediaStreamer(
          source: WavMediaSource(path),
          codec: codec,
          streamId: 9,
          userId: 4,
          channelId: 2,
          nowUs: 0,
          loop: loop,
          gain: gain,
          monitor: monitor,
        );
        addTearDown(s.dispose);
        return s;
      }

      test('sends the file in real time as media packets, then ends', () {
        final s = streamer(_wav(dir));

        final first = s.tick(0).packets;
        expect(first.length, inInclusiveRange(5, 6));
        final all = [...first, ..._run(s, 10, 500)];
        expect(all.length, inInclusiveRange(29, 31), reason: '600 ms by then');
        expect(s.ended, isFalse);

        all.addAll(_run(s, 510, 1500));
        expect(s.ended, isTrue);
        expect(s.status.position.inMilliseconds, closeTo(1000, 1));

        final parsed = [for (final p in all) parseVoicePacket(p)!];
        expect(parsed.map((p) => p.kind).toSet(), {packetKindMediaFileAudio});
        expect(parsed.map((p) => p.streamId).toSet(), {9});
        expect([
          for (final p in parsed) p.packetNumber,
        ], List.generate(parsed.length, (i) => i));
        expect(parsed.length, 50);

        final decoder = OpusVoiceDecoder();
        addTearDown(decoder.dispose);
        final audio = _decode(all, decoder);
        expect(_pitch(audio.sublist(audio.length ~/ 4)), closeTo(440, 15));
      });

      test('pausing stops sending; resuming goes on from there', () {
        final s = streamer(_wav(dir));
        _run(s, 0, 200);
        s.pause();
        expect(_run(s, 210, 1000), isEmpty);
        expect(s.status.paused, isTrue);
        final at = s.status.position;

        s.resume(_ms(1010));
        expect(s.tick(_ms(1010)).packets, isNotEmpty);
        expect(s.status.position, greaterThan(at));
      });

      test('seeking moves the position and keeps the packet numbers going', () {
        final s = streamer(_wav(dir));
        final before = _run(s, 0, 100);
        s.seek(const Duration(milliseconds: 800), _ms(110));
        final after = _run(s, 110, 600);

        expect(s.ended, isTrue, reason: '200 ms were left');
        final numbers = [
          for (final p in [...before, ...after])
            parseVoicePacket(p)!.packetNumber,
        ];
        expect(numbers, List.generate(numbers.length, (i) => i));
      });

      test('looping starts again at the end', () {
        final s = streamer(_wav(dir, seconds: 0.3), loop: true);
        _run(s, 0, 1000);
        expect(s.ended, isFalse);
        expect(s.status.position.inMilliseconds, lessThan(300));
      });

      test('the stream volume scales the audio', () {
        final loud = streamer(_wav(dir));
        final quiet = streamer(_wav(dir), gain: 0.25);
        final d1 = OpusVoiceDecoder();
        final d2 = OpusVoiceDecoder();
        addTearDown(d1.dispose);
        addTearDown(d2.dispose);

        final a = _decode(_run(loud, 0, 500), d1);
        final b = _decode(_run(quiet, 0, 500), d2);

        expect(_level(b) / _level(a), closeTo(0.25, 0.08));
      });

      test('monitoring gives the same audio at 48 kHz stereo', () {
        final s = streamer(_wav(dir), monitor: true);
        final tick = s.tick(0);
        expect(tick.monitor!.length, closeTo(4800 * 2, 2 * 50));
        expect(_pitch(tick.monitor!.sublist(1000)), closeTo(440, 30));
      });

      test('a mono Speex channel gets the file mixed down', () {
        const speex = TxCodecConfig(
          codec: AudioCodecType.speex,
          speexBandMode: 1,
          speexQuality: 6,
          sampleRate: 16000,
          channels: 1,
          bitrate: 0,
          fpp: 2,
        );
        final s = streamer(_wav(dir), codec: speex);
        final packets = _run(s, 0, 1500);
        final decoder = SpeexVoiceDecoder(1);
        addTearDown(decoder.dispose);
        final audio = <int>[];
        for (final p in packets) {
          final v = parseVoicePacket(p)!;
          expect(v.kind, packetKindMediaFileAudio);
          for (final f in splitAudioFrames(
            v.encodedAudio,
            v.frameSizes,
            framesPerPacket: 2,
          )!) {
            audio.addAll(decoder.decode(f));
          }
        }
        expect(packets, hasLength(25));
        expect(_pitch(audio.sublist(audio.length ~/ 4)), closeTo(440, 20));
      });
    },
  );
}
