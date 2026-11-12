@Tags(['native'])
library;

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:teamtalkx/src/audio/audio_worker.dart';
import 'package:teamtalkx/src/audio/native_library.dart';
import 'package:teamtalkx/src/audio/opus_encoder.dart';
import 'package:teamtalkx/src/protocol/packet.dart';

Int16List _frame(int index) => Int16List.fromList([
  for (var i = 0; i < 960; i++)
    (math.sin(2 * math.pi * 440 * (index * 960 + i) / 48000) * 8000).round(),
]);

Int16List _voiced(int index) => Int16List.fromList([
  for (var i = 0; i < 960; i++)
    () {
      final t = (index * 960 + i) / 48000;
      var s = 0.0;
      for (var h = 1; h <= 20; h++) {
        final f = 150.0 * h;
        final formants =
            math.exp(-math.pow((f - 700) / 250, 2)) +
            0.6 * math.exp(-math.pow((f - 1200) / 300, 2));
        s += formants * math.sin(2 * math.pi * f * t) / h;
      }
      return (s * (0.6 + 0.4 * math.sin(2 * math.pi * 4 * t)) * 9000)
          .round()
          .clamp(-32768, 32767);
    }(),
]);

List<(Uint8List, List<int>)> _twoFramePackets(
  int packets, {
  required bool vbr,
}) {
  final encoder = OpusFrameEncoder(
    sampleRate: 48000,
    channels: 1,
    bitrate: 32000,
    vbr: vbr,
  );
  try {
    return [
      for (var p = 0; p < packets; p++)
        () {
          final a = encoder.encode(_frame(p * 2));
          final b = encoder.encode(_frame(p * 2 + 1));
          return (Uint8List.fromList([...a, ...b]), [a.length, b.length]);
        }(),
    ];
  } finally {
    encoder.dispose();
  }
}

Future<int> _decodedSamples(
  List<(Uint8List, List<int>)> packets, {
  required bool sendSizes,
}) async {
  final decoded = <RxDecoded>[];
  final worker = await AudioWorker.spawn(onTx: (_) {}, onRx: decoded.add);
  expect(await worker.startAudio(), isFalse);
  for (var i = 0; i < packets.length; i++) {
    worker.pushRx(
      key: (2 << 8) | 3,
      streamId: 1,
      packetNo: i,
      encoded: packets[i].$1,
      frameSizes: sendSizes ? packets[i].$2 : const [],
      framesPerPacket: 2,
    );
  }
  await Future<void>.delayed(const Duration(milliseconds: 300));
  await worker.shutdown();
  return decoded.fold<int>(0, (n, d) => n + d.pcm.length);
}

Future<Int16List> _decodedAudio(List<Uint8List> packets) async {
  final decoded = <RxDecoded>[];
  final worker = await AudioWorker.spawn(onTx: (_) {}, onRx: decoded.add);
  await worker.startAudio();
  for (var i = 0; i < packets.length; i++) {
    worker.pushRx(
      key: (2 << 8) | 3,
      streamId: 1,
      packetNo: i,
      encoded: packets[i],
    );
  }
  await Future<void>.delayed(const Duration(milliseconds: 300));
  await worker.shutdown();
  return Int16List.fromList([for (final d in decoded) ...d.pcm]);
}

double _frameLevel(Int16List stereo, int index) {
  var sum = 0;
  for (var i = 0; i < 960; i++) {
    sum += stereo[(index * 960 + i) * 2].abs();
  }
  return sum / 960;
}

void main() {
  const skip = nativeLibraryOverride == ''
      ? 'Needs a host build of native/: --dart-define=TT_NATIVE_LIB=<path>'
      : null;

  group('receiving multi-frame packets', skip: skip, () {
    const expected = 6 * 960 * 2;

    test('VBR packets are split by their frame sizes', () async {
      final packets = _twoFramePackets(3, vbr: true);
      expect(await _decodedSamples(packets, sendSizes: true), expected);
    });

    test('CBR packets are split by the channel frames per packet', () async {
      final packets = _twoFramePackets(3, vbr: false);
      expect(packets.first.$2[0], packets.first.$2[1], reason: 'equal frames');
      expect(await _decodedSamples(packets, sendSizes: false), expected);
    });
  });

  test(
    'a lost packet is recovered from the next one\'s FEC',
    skip: skip,
    () async {
      final encoder = OpusFrameEncoder(
        sampleRate: 48000,
        channels: 1,
        bitrate: 32000,
        fec: true,
        lossPercent: 10,
      );
      final packets = [
        for (var i = 0; i < 20; i++)
          Uint8List.fromList(encoder.encode(_voiced(i))),
      ];
      encoder.dispose();
      final worker = await AudioWorker.spawn(onTx: (_) {}, onRx: (_) {});
      addTearDown(worker.shutdown);
      await worker.startAudio();
      for (var i = 0; i < packets.length; i++) {
        if (i == 5 || i == 12) continue;
        worker.pushRx(
          key: (2 << 8) | 3,
          streamId: 1,
          packetNo: i,
          encoded: packets[i],
        );
      }
      await Future<void>.delayed(const Duration(milliseconds: 600));
      final stats = (await worker.playoutStats()).single;
      expect(stats.concealed, 2);
      expect(stats.recovered, 2);
    },
  );

  test('every frame keeps its own audio', skip: skip, () async {
    final encoder = OpusFrameEncoder(
      sampleRate: 48000,
      channels: 1,
      bitrate: 32000,
    );
    final packets = [
      for (var i = 0; i < 4; i++)
        Uint8List.fromList(encoder.encode(i == 0 ? Int16List(960) : _frame(i))),
    ];
    encoder.dispose();

    final audio = await _decodedAudio(packets);

    expect(audio.length, 4 * 960 * 2);
    expect(_frameLevel(audio, 0), lessThan(50), reason: 'silence');
    expect(_frameLevel(audio, 1), greaterThan(1000), reason: 'the tone');
  });

  test('the media volume scales media streams only', skip: skip, () async {
    final encoder = OpusFrameEncoder(
      sampleRate: 48000,
      channels: 1,
      bitrate: 32000,
    );
    final packets = [
      for (var i = 0; i < 6; i++) Uint8List.fromList(encoder.encode(_frame(i))),
    ];
    encoder.dispose();

    final decoded = <RxDecoded>[];
    final worker = await AudioWorker.spawn(onTx: (_) {}, onRx: decoded.add);
    await worker.startAudio();
    worker.setMediaGain(0.25);
    for (final kind in [packetKindVoice, packetKindMediaFileAudio]) {
      for (var i = 0; i < packets.length; i++) {
        worker.pushRx(
          key: (2 << 8) | kind,
          streamId: 1,
          packetNo: i,
          encoded: packets[i],
        );
      }
    }
    await Future<void>.delayed(const Duration(milliseconds: 400));
    await worker.shutdown();

    double level(int kind) {
      final pcm = [
        for (final d in decoded)
          if (d.key & 0xFF == kind) ...d.pcm,
      ];
      return pcm.fold<int>(0, (n, s) => n + s.abs()) / pcm.length;
    }

    expect(
      level(packetKindMediaFileAudio) / level(packetKindVoice),
      closeTo(0.25, 0.02),
    );
  });
}
