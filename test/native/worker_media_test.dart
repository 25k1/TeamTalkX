@Tags(['native'])
library;

import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:teamtalkx/src/audio/audio_worker.dart';
import 'package:teamtalkx/src/audio/native_library.dart';
import 'package:teamtalkx/src/protocol/packet.dart';

String _wav(Directory dir, double seconds) {
  final frames = (48000 * seconds).round();
  final b = ByteData(44 + frames * 2)
    ..setUint32(0, 0x46464952, Endian.little)
    ..setUint32(4, 36 + frames * 2, Endian.little)
    ..setUint32(8, 0x45564157, Endian.little)
    ..setUint32(12, 0x20746d66, Endian.little)
    ..setUint32(16, 16, Endian.little)
    ..setUint16(20, 1, Endian.little)
    ..setUint16(22, 1, Endian.little)
    ..setUint32(24, 48000, Endian.little)
    ..setUint32(28, 96000, Endian.little)
    ..setUint16(32, 2, Endian.little)
    ..setUint16(34, 16, Endian.little)
    ..setUint32(36, 0x61746164, Endian.little)
    ..setUint32(40, frames * 2, Endian.little);
  for (var i = 0; i < frames; i++) {
    b.setInt16(
      44 + i * 2,
      (math.sin(2 * math.pi * 440 * i / 48000) * 8000).round(),
      Endian.little,
    );
  }
  final path = '${dir.path}/tone.wav';
  File(path).writeAsBytesSync(b.buffer.asUint8List());
  return path;
}

void main() {
  group(
    'media streaming in the worker (V5)',
    skip: nativeLibraryOverride == ''
        ? 'Needs a host build of native/: --dart-define=TT_NATIVE_LIB=<path>'
        : null,
    () {
      late Directory dir;
      late List<VoicePacket> sent;
      late List<MediaStreamStatus> statuses;
      late AudioWorker worker;

      setUp(() async {
        dir = Directory.systemTemp.createTempSync('ttx-media');
        addTearDown(() => dir.deleteSync(recursive: true));
        sent = [];
        statuses = [];
        worker = await AudioWorker.spawn(
          onTx: (tx) =>
              sent.addAll(tx.packets.map((p) => parseVoicePacket(p)!)),
          onMediaStatus: statuses.add,
        );
        addTearDown(worker.shutdown);
      });

      Future<String?> start(String path) => worker.startMedia(
        path: path,
        codec: const TxCodecConfig(
          sampleRate: 48000,
          channels: 2,
          bitrate: 64000,
        ),
        streamId: 3,
        userId: 5,
        channelId: 1,
      );

      test('streams the file as media packets and reports the end', () async {
        expect(await start(_wav(dir, 0.6)), isNull);
        await Future<void>.delayed(const Duration(milliseconds: 1200));

        expect(sent.map((p) => p.kind).toSet(), {packetKindMediaFileAudio});
        expect(sent.map((p) => p.streamId).toSet(), {3});
        expect(sent, hasLength(30), reason: '600 ms in 20 ms packets');
        expect(statuses.last.ended, isTrue);
        expect(statuses.last.position.inMilliseconds, closeTo(600, 1));
      });

      test('pausing stops the packets', () async {
        expect(await start(_wav(dir, 5)), isNull);
        await Future<void>.delayed(const Duration(milliseconds: 300));
        worker.controlMedia(paused: true);
        await Future<void>.delayed(const Duration(milliseconds: 100));
        final count = sent.length;
        await Future<void>.delayed(const Duration(milliseconds: 500));

        expect(sent, hasLength(count));
        expect(statuses.last.paused, isTrue);
        worker.stopMedia();
        await Future<void>.delayed(const Duration(milliseconds: 100));
        expect(statuses.last.ended, isTrue);
      });

      test('a file it cannot play is refused with a reason', () async {
        final path = '${dir.path}/notes.txt';
        File(path).writeAsStringSync('not audio');
        expect(await start(path), isNotNull);
        expect(await start('${dir.path}/missing.wav'), isNotNull);
      });
    },
  );
}
