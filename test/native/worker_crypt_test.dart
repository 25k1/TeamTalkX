@Tags(['native'])
library;

import 'dart:io';
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

class _FakeServer {
  _FakeServer(this.socket) {
    socket.listen((event) {
      if (event != RawSocketEvent.read) return;
      final dg = socket.receive();
      if (dg == null || dg.data.isEmpty) return;
      final h = parseHeader(dg.data);
      if (h.kind == packetKindHello) {
        users[h.srcUserId] = (dg.address, dg.port);
        socket.send(helloPacket(0, 0), dg.address, dg.port);
        return;
      }
      if (h.kind == packetKindKeepAlive) return;
      kinds.add(h.kind);
      for (final MapEntry(:key, value: (address, port)) in users.entries) {
        if (key != h.srcUserId) socket.send(dg.data, address, port);
      }
    });
  }

  final RawDatagramSocket socket;
  final users = <int, (InternetAddress, int)>{};
  final kinds = <int>{};
}

Future<AudioWorker> _worker(
  _FakeServer server,
  int userId,
  Uint8List? key, {
  RxDecodedHandler? onRx,
}) async {
  final worker = await AudioWorker.spawn(onTx: (_) {}, onRx: onRx);
  addTearDown(worker.shutdown);
  await worker.startAudio();
  worker.setCryptKey(key);
  final error = await worker.startUdp(
    address: InternetAddress.loopbackIPv4,
    port: server.socket.port,
    userId: userId,
  );
  expect(error, isNull);
  return worker;
}

void _talk(AudioWorker worker, int userId) {
  worker
    ..configureCapture(const CaptureSettings(sampleRate: 48000, channels: 1))
    ..startCapture(audioSource: 7, sampleRate: 48000, channels: 1)
    ..setCaptureState(
      streamId: 1,
      userId: userId,
      channelId: 1,
      transmit: true,
      config: const TxCodecConfig(
        sampleRate: 48000,
        channels: 1,
        bitrate: 32000,
      ),
    );
  for (var i = 0; i < 25; i++) {
    worker.injectCapture(_frame(i));
  }
}

void main() {
  const skip = nativeLibraryOverride == ''
      ? 'Needs a host build of native/: --dart-define=TT_NATIVE_LIB=<path>'
      : null;

  group('encrypted voice (V3)', skip: skip, () {
    late _FakeServer server;
    final key = Uint8List.fromList(List.generate(32, (i) => i * 7));

    setUp(() async {
      server = _FakeServer(
        await RawDatagramSocket.bind(InternetAddress.loopbackIPv4, 0),
      );
      addTearDown(server.socket.close);
    });

    test('goes out encrypted and is decoded with the channel key', () async {
      final heard = <RxDecoded>[];
      await _worker(server, 2, key, onRx: heard.add);
      _talk(await _worker(server, 1, key), 1);
      await Future<void>.delayed(const Duration(seconds: 1));

      expect(server.kinds, {packetKindVoiceCrypt});
      expect(heard, isNotEmpty);
      expect(heard.map((d) => d.key).toSet(), {(1 << 8) | packetKindVoice});
    });

    test('a listener with another key hears nothing', () async {
      final heard = <RxDecoded>[];
      await _worker(server, 2, Uint8List(32), onRx: heard.add);
      _talk(await _worker(server, 1, key), 1);
      await Future<void>.delayed(const Duration(seconds: 1));

      expect(server.kinds, {packetKindVoiceCrypt});
      expect(heard, isEmpty);
    });

    test('without a key voice stays plain', () async {
      final heard = <RxDecoded>[];
      await _worker(server, 2, null, onRx: heard.add);
      _talk(await _worker(server, 1, null), 1);
      await Future<void>.delayed(const Duration(seconds: 1));

      expect(server.kinds, {packetKindVoice});
      expect(heard, isNotEmpty);
    });
  });
}
