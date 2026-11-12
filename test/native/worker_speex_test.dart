@Tags(['native'])
library;

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:teamtalkx/src/audio/audio_worker.dart';
import 'package:teamtalkx/src/audio/native_library.dart';
import 'package:teamtalkx/src/domain/capture_settings.dart';
import 'package:teamtalkx/src/protocol/packet.dart';

Int16List _frame(int index) => Int16List.fromList([
  for (var i = 0; i < 960; i++)
    (math.sin(2 * math.pi * 440 * (index * 960 + i) / 48000) * 8000).round(),
]);

Future<(List<VoicePacket>, Int16List)> _speak(List<int> codec) async {
  final config = txCodecConfigFromWire(
    codec,
    fallbackRate: 48000,
    outChannels: 1,
  );
  final heard = <RxDecoded>[];
  final listener = await AudioWorker.spawn(onTx: (_) {}, onRx: heard.add);
  addTearDown(listener.shutdown);
  await listener.startAudio();
  listener.setRxCodec(config);

  final packets = <VoicePacket>[];
  final sender = await AudioWorker.spawn(
    onTx: (tx) {
      for (final p in tx.packets) {
        final v = parseVoicePacket(p)!;
        packets.add(v);
        listener.pushRx(
          key: (v.srcUserId << 8) | v.kind,
          streamId: v.streamId,
          packetNo: v.packetNumber,
          encoded: v.encodedAudio,
          frameSizes: v.frameSizes,
          framesPerPacket: config.fpp,
        );
      }
    },
  );
  addTearDown(sender.shutdown);
  sender
    ..configureCapture(const CaptureSettings(sampleRate: 48000, channels: 1))
    ..startCapture(audioSource: 7, sampleRate: 48000, channels: 1)
    ..setCaptureState(
      streamId: 1,
      userId: 4,
      channelId: 3,
      transmit: true,
      config: config,
    );
  for (var i = 0; i < 50; i++) {
    sender.injectCapture(_frame(i));
  }
  await Future<void>.delayed(const Duration(milliseconds: 1600));
  return (packets, Int16List.fromList([for (final d in heard) ...d.pcm]));
}

double _pitch(Int16List stereo) {
  var crossings = 0;
  for (var i = 2; i < stereo.length; i += 2) {
    if (stereo[i - 2] < 0 && stereo[i] >= 0) crossings++;
  }
  return crossings / (stereo.length / 2 / 48000);
}

void main() {
  const skip = nativeLibraryOverride == ''
      ? 'Needs a host build of native/: --dart-define=TT_NATIVE_LIB=<path>'
      : null;

  group('Speex voice between workers (D23)', skip: skip, () {
    test('wideband, two frames per packet', () async {
      final (packets, audio) = await _speak([1, 1, 4, 2, 0]);

      expect(packets, hasLength(inInclusiveRange(24, 25)));
      expect(packets.first.frameSizes, isEmpty);
      expect(audio.length, greaterThan(48000 * 2 * 0.8));
      final steady = Int16List.sublistView(audio, audio.length ~/ 2);
      expect(_pitch(steady), closeTo(440, 30));
    });

    test('VBR ultra-wideband sends its frame sizes', () async {
      final (packets, audio) = await _speak([2, 2, 6, 0, 0, 0, 2, 0]);

      expect(packets.first.frameSizes, hasLength(2));
      expect(audio.length, greaterThan(48000 * 2 * 0.8));
      final steady = Int16List.sublistView(audio, audio.length ~/ 2);
      expect(_pitch(steady), closeTo(440, 30));
    });
  });
}
