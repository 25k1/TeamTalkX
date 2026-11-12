import 'package:flutter/material.dart';
import 'package:teamtalkx/src/audio/audio_worker.dart';
import 'package:teamtalkx/src/domain/capture_settings.dart';
import 'package:teamtalkx/src/protocol/packet.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final notifier = ValueNotifier<List<String>>(['Running… speak now']);
  runApp(
    MaterialApp(
      home: Scaffold(
        appBar: AppBar(title: const Text('Voice loopback')),
        body: ValueListenableBuilder(
          valueListenable: notifier,
          builder: (_, lines, _) => ListView(
            padding: const EdgeInsets.all(16),
            children: [for (final line in lines) Text(line)],
          ),
        ),
      ),
    ),
  );
  final results = await _loopback();
  for (final line in results) {
    debugPrint('TTX-BENCH $line');
  }
  debugPrint('TTX-BENCH done');
  notifier.value = results;
}

const _codecList = String.fromEnvironment('TT_LOOPBACK_CODEC');

final TxCodecConfig _codec = _codecList.isEmpty
    ? const TxCodecConfig(sampleRate: 48000, channels: 1, bitrate: 32000)
    : txCodecConfigFromWire(
        [for (final v in _codecList.split(',')) int.parse(v.trim())],
        fallbackRate: 48000,
        outChannels: 1,
      );

Future<List<String>> _loopback() async {
  final out = <String>[];
  var sent = 0;
  var bytes = 0;
  var voiceResults = 0;
  late AudioWorker worker;
  final held = <VoicePacket>[];
  var holding = false;
  void deliver(VoicePacket voice) => worker.pushRx(
    key: (2 << 8) | voice.kind,
    streamId: voice.streamId,
    packetNo: voice.packetNumber,
    encoded: voice.encodedAudio,
    frameSizes: voice.frameSizes,
    framesPerPacket: _codec.fpp,
  );
  worker = await AudioWorker.spawn(
    onTx: (tx) {
      for (final packet in tx.packets) {
        sent++;
        bytes += packet.length;
        final voice = parseVoicePacket(packet);
        if (voice == null) continue;
        holding ? held.add(voice) : deliver(voice);
      }
    },
    onRx: (_) => out.add('unexpected: decoded audio came back to the root'),
    onVoice: (_) => voiceResults++,
  );

  final playback = await worker.startAudio(outputGain: 0.2);
  out.add('native playback: $playback');
  final codec = _codec;
  out.add(
    'codec: ${codec.codec.name} ${codec.sampleRate} Hz, fpp ${codec.fpp}',
  );
  worker.setRxCodec(codec);
  worker
    ..configureCapture(
      const CaptureSettings(
        sampleRate: 48000,
        channels: 1,
        noiseSuppression: true,
        voiceDetection: true,
        detector: VoiceDetectorKind.rnnoise,
        agc: true,
      ),
    )
    ..startCapture(audioSource: 7, sampleRate: 48000, channels: 1)
    ..setCaptureState(
      streamId: 1,
      userId: 1,
      channelId: 1,
      transmit: true,
      config: codec,
    );

  final start = DateTime.now();
  Future<void> at(int ms) => Future<void>.delayed(
    Duration(milliseconds: ms) - DateTime.now().difference(start),
  );
  Future<void> playout(String when) async {
    for (final s in await worker.playoutStats()) {
      out.add('playout $when: $s');
    }
  }

  await at(1500);
  await playout('steady');
  holding = true;
  await at(1900);
  holding = false;
  final burst = held.length;
  held
    ..forEach(deliver)
    ..clear();
  await at(1950);
  out.add('network stall: $burst packets held 400 ms');
  await playout('after the stall');
  await at(3500);
  await playout('2 s later');
  await at(6000);
  await playout('4 s later');
  final seconds = DateTime.now().difference(start).inMilliseconds / 1000;
  final stats = await worker.engineStats();
  worker.stopCapture();
  await Future<void>.delayed(const Duration(milliseconds: 300));
  await worker.shutdown();

  out
    ..add(
      'packets sent: $sent in ${seconds.toStringAsFixed(1)} s '
      '(~${(seconds * 50 / codec.fpp).round()} expected), ${bytes ~/ (sent == 0 ? 1 : sent)} '
      'bytes each',
    )
    ..add('voice detection results: $voiceResults')
    ..add('engine: $stats');
  return out;
}
