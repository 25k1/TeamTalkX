@Tags(['e2e', 'native'])
library;

import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:teamtalkx/src/app/pure_teamtalk_client.dart';
import 'package:teamtalkx/src/audio/audio_worker.dart';
import 'package:teamtalkx/src/audio/native_library.dart';
import 'package:teamtalkx/src/domain/capture_settings.dart';
import 'package:teamtalkx/src/domain/events.dart';
import 'package:teamtalkx/src/protocol/packet.dart';
import 'package:teamtalkx/src/protocol/protocol_client.dart';

import 'support/e2e_server.dart';

Uint8List _toneWav(double seconds) {
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
  return b.buffer.asUint8List();
}

Int16List _frame(int index) => Int16List.fromList([
  for (var i = 0; i < 960; i++)
    (math.sin(2 * math.pi * 440 * (index * 960 + i) / 48000) * 8000).round(),
]);

Future<AudioWorker> _worker(
  ProtocolClient client, {
  RxDecodedHandler? onRx,
  StreamActivityHandler? onActivity,
}) async {
  final worker = await AudioWorker.spawn(
    onTx: (_) {},
    onRx: onRx,
    onActivity: onActivity,
  );
  addTearDown(worker.shutdown);
  await worker.startAudio();
  final error = await worker.startUdp(
    address: client.serverAddress!,
    port: e2ePort,
    userId: client.state.myUserId,
  );
  expect(error, isNull, reason: 'UDP hello');
  return worker;
}

void main() {
  test(
    'voice goes from one client to another through the server',
    skip:
        e2eSkip ??
        (nativeLibraryOverride == ''
            ? 'Needs a host build of native/: --dart-define=TT_NATIVE_LIB=<path>'
            : null),
    () async {
      final alice = await loginAs(E2eAccount.alice);
      final bob = await loginAs(E2eAccount.bob);
      await alice.joinChannel(E2eChannel.root);
      await bob.joinChannel(E2eChannel.root);
      final aliceId = alice.state.myUserId;

      final heard = <RxDecoded>[];
      final talking = <bool>[];
      await _worker(
        bob,
        onRx: heard.add,
        onActivity: (userId, kind, {required active}) {
          if (userId == aliceId && kind == packetKindVoice) talking.add(active);
        },
      );
      final sender = await _worker(alice);

      sender
        ..configureCapture(
          const CaptureSettings(sampleRate: 48000, channels: 1),
        )
        ..startCapture(audioSource: 7, sampleRate: 48000, channels: 1)
        ..setCaptureState(
          streamId: 1,
          userId: aliceId,
          channelId: E2eChannel.root,
          transmit: true,
          config: const TxCodecConfig(
            sampleRate: 48000,
            channels: 1,
            bitrate: 32000,
            frameMs: 40,
          ),
        );
      for (var i = 0; i < 50; i++) {
        sender.injectCapture(_frame(i));
      }
      await Future<void>.delayed(const Duration(seconds: 2));

      expect(heard, isNotEmpty, reason: 'Bob decoded nothing');
      expect(heard.map((d) => d.key).toSet(), {
        (aliceId << 8) | packetKindVoice,
      });
      final samples = heard.fold<int>(0, (n, d) => n + d.pcm.length);
      expect(samples, greaterThan(48000 * 2 ~/ 2));
      expect(talking, [true, false], reason: 'started and stopped talking');
    },
  );

  for (final (channel, name) in [
    (E2eChannel.speex, 'Speex wideband'),
    (E2eChannel.speexVbr, 'Speex VBR ultra-wideband'),
  ]) {
    test(
      '$name voice goes from one client to another',
      skip:
          e2eSkip ??
          (nativeLibraryOverride == ''
              ? 'Needs a host build of native/: '
                    '--dart-define=TT_NATIVE_LIB=<path>'
              : null),
      () async {
        final alice = await loginAs(E2eAccount.alice);
        final bob = await loginAs(E2eAccount.bob);
        await alice.joinChannel(channel);
        await bob.joinChannel(channel);
        final codec = txCodecConfigFromWire(
          alice.channelCodecs[channel],
          fallbackRate: 48000,
          outChannels: 1,
        );
        expect(codec.isSpeex, isTrue, reason: 'the fixture channel');

        final heard = <RxDecoded>[];
        final listener = await _worker(bob, onRx: heard.add);
        listener.setRxCodec(codec);
        final sender = await _worker(alice);
        sender
          ..configureCapture(
            const CaptureSettings(sampleRate: 48000, channels: 1),
          )
          ..startCapture(audioSource: 7, sampleRate: 48000, channels: 1)
          ..setCaptureState(
            streamId: 1,
            userId: alice.state.myUserId,
            channelId: channel,
            transmit: true,
            config: codec,
          );
        for (var i = 0; i < 50; i++) {
          sender.injectCapture(_frame(i));
        }
        await Future<void>.delayed(const Duration(seconds: 2));

        final samples = heard.fold<int>(0, (n, d) => n + d.pcm.length);
        expect(samples, greaterThan(48000 * 2 ~/ 2));
      },
    );
  }

  test(
    'a streamed media file reaches the channel as media audio',
    skip:
        e2eSkip ??
        (nativeLibraryOverride == ''
            ? 'Needs a host build of native/: '
                  '--dart-define=TT_NATIVE_LIB=<path>'
            : null),
    () async {
      final dir = Directory.systemTemp.createTempSync('ttx-e2e-media');
      addTearDown(() => dir.deleteSync(recursive: true));
      final wav = '${dir.path}/tone.wav';
      File(wav).writeAsBytesSync(_toneWav(0.6));

      final bob = await loginAs(E2eAccount.bob);
      await bob.joinChannel(E2eChannel.root);
      final heard = <RxDecoded>[];
      await _worker(bob, onRx: heard.add);

      final alice = PureTeamTalkClient();
      addTearDown(alice.disconnect);
      final ended = alice.events.firstWhere((e) => e is MediaStreamEndedEvent);
      await alice.connect(e2eHost, tcpPort: e2ePort, udpPort: e2ePort);
      await alice.login(
        nickname: 'alice-e2e',
        username: E2eAccount.alice.username,
        password: E2eAccount.alice.password,
      );
      await alice.joinChannel(E2eChannel.root);
      await Future<void>.delayed(const Duration(milliseconds: 300));

      await alice.startStreamingMediaFile(wav, fileName: 'tone.wav');
      expect(alice.mediaStream?.fileName, 'tone.wav');
      await ended.timeout(const Duration(seconds: 5));
      await Future<void>.delayed(const Duration(milliseconds: 500));

      expect(alice.mediaStream, isNull);
      final keys = heard.map((d) => d.key & 0xFF).toSet();
      expect(keys, {packetKindMediaFileAudio});
      final samples = heard.fold<int>(0, (n, d) => n + d.pcm.length);
      expect(samples, greaterThan(48000 * 2 * 0.4));
    },
  );

  test(
    'logging in reports what voice can and cannot do',
    skip: e2eSkip,
    () async {
      final client = PureTeamTalkClient();
      addTearDown(client.disconnect);
      final problems = <VoiceProblem>[];
      client.events.listen((e) {
        if (e is VoiceProblemEvent) problems.add(e.problem);
      });

      await client.connect(e2eHost, tcpPort: e2ePort, udpPort: e2ePort);
      await client.login(
        nickname: 'alice-e2e',
        username: E2eAccount.alice.username,
        password: E2eAccount.alice.password,
      );
      await pumpEventQueue();

      expect(problems, [VoiceProblem.playbackFailed]);
    },
  );
}
