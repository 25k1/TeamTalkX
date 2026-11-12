import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:teamtalkx/src/audio/audio_worker.dart';
import 'package:teamtalkx/src/domain/tt_types.dart';

void main() {
  group('AudioWorker', () {
    test('spawn and shutdown start and stop the isolate', () async {
      final worker = await AudioWorker.spawn(onTx: (_) {});
      expect(worker, isNotNull);
      await worker.shutdown();
    });

    test('capture with nothing captured sends nothing', () async {
      final txPackets = <TxPackets>[];
      final worker = await AudioWorker.spawn(onTx: txPackets.add);
      worker
        ..startCapture(audioSource: 7, sampleRate: 48000, channels: 1)
        ..setCaptureState(
          streamId: 1,
          userId: 2,
          channelId: 3,
          transmit: true,
          config: const TxCodecConfig(
            sampleRate: 48000,
            channels: 1,
            bitrate: 32000,
          ),
        )
        ..injectCapture(Int16List(0));
      await Future<void>.delayed(const Duration(milliseconds: 200));
      expect(txPackets, isEmpty);
      await worker.shutdown();
    });

    test('pushRx with garbage keeps the isolate alive', () async {
      final decoded = <RxDecoded>[];
      final worker = await AudioWorker.spawn(onTx: (_) {}, onRx: decoded.add);
      worker.pushRx(
        key: (7 << 8) | 3,
        streamId: 1,
        packetNo: 0,
        encoded: Uint8List.fromList([1, 2, 3, 4, 5]),
      );
      await Future<void>.delayed(const Duration(milliseconds: 200));
      await worker.shutdown();
    });

    test('resetTx/resetRx are safe after shutdown', () async {
      final worker = await AudioWorker.spawn(onTx: (_) {});
      await worker.shutdown();
      worker.resetTx();
      worker.resetRx(1);
      worker.resetRxAll();
    });
  });

  group('TxCodecConfig', () {
    test('equality by fields', () {
      const a = TxCodecConfig(sampleRate: 48000, channels: 1, bitrate: 32000);
      const b = TxCodecConfig(sampleRate: 48000, channels: 1, bitrate: 32000);
      const c = TxCodecConfig(sampleRate: 48000, channels: 1, bitrate: 64000);
      expect(a, b);
      expect(a.hashCode, b.hashCode);
      expect(a == c, isFalse);
    });

    test('equality includes DTX/FEC/fpp', () {
      const a = TxCodecConfig(
        sampleRate: 48000,
        channels: 1,
        bitrate: 32000,
        dtx: true,
      );
      const b = TxCodecConfig(
        sampleRate: 48000,
        channels: 1,
        bitrate: 32000,
        dtx: false,
      );
      expect(a == b, isFalse);
    });
  });

  group('txCodecConfigFromWire', () {
    test('full channel Opus config list', () {
      final cfg = txCodecConfigFromWire(
        [3, 48000, 1, 2048, 5, 1, 1, 64000, 0, 1, 1920, 2],
        fallbackRate: 8000,
        outChannels: 1,
      );
      expect(cfg.sampleRate, 48000);
      expect(cfg.complexity, 5);
      expect(cfg.fec, isTrue);
      expect(cfg.dtx, isTrue);
      expect(cfg.bitrate, 64000);
      expect(cfg.vbr, isFalse);
      expect(cfg.vbrConstraint, isTrue);
      expect(cfg.frameMs, 40);
      expect(cfg.fpp, 2);
    });

    test('Speex: wideband, quality 4, two frames per packet, mono', () {
      final cfg = txCodecConfigFromWire(
        [1, 1, 4, 2, 0],
        fallbackRate: 48000,
        outChannels: 2,
      );
      expect(cfg.codec, AudioCodecType.speex);
      expect(cfg.isSpeex, isTrue);
      expect(cfg.speexBandMode, 1);
      expect(cfg.sampleRate, 16000);
      expect(cfg.channels, 1, reason: 'Speex is always mono');
      expect(cfg.speexQuality, 4);
      expect(cfg.vbr, isFalse);
      expect(cfg.fpp, 2);
    });

    test('Speex VBR: ultra-wideband with bitrate cap and DTX', () {
      final cfg = txCodecConfigFromWire(
        [2, 2, 6, 0, 24000, 1, 3, 0],
        fallbackRate: 48000,
        outChannels: 1,
      );
      expect(cfg.codec, AudioCodecType.speexVbr);
      expect(cfg.sampleRate, 32000);
      expect(cfg.speexQuality, 6);
      expect(cfg.bitrate, 0, reason: '0: the quality decides');
      expect(cfg.maxBitrate, 24000);
      expect(cfg.dtx, isTrue);
      expect(cfg.vbr, isTrue);
      expect(cfg.fpp, 3);
    });

    test('a narrowband Speex channel runs at 8 kHz', () {
      final cfg = txCodecConfigFromWire(
        [1, 0, 8, 1, 0],
        fallbackRate: 48000,
        outChannels: 1,
      );
      expect(cfg.sampleRate, 8000);
      expect(cfg.speexQuality, 8);
    });

    test('missing list falls back to defaults', () {
      final cfg = txCodecConfigFromWire(
        null,
        fallbackRate: 16000,
        outChannels: 2,
      );
      expect(cfg.sampleRate, 16000);
      expect(cfg.channels, 2);
      expect(cfg.bitrate, 32000);
      expect(cfg.dtx, isFalse);
      expect(cfg.vbr, isTrue);
      expect(cfg.frameMs, 20);
      expect(cfg.fpp, 1);
    });

    test('invalid channel sample rate becomes 48000', () {
      final cfg = txCodecConfigFromWire(
        [3, 44100, 1, 2048, 10, 0, 0, 32000, 1, 0, 882, 1],
        fallbackRate: 8000,
        outChannels: 1,
      );
      expect(cfg.sampleRate, 48000);
    });

    test('zero bitrate is replaced by the default', () {
      final cfg = txCodecConfigFromWire(
        [3, 8000, 1, 2048, 10, 0, 0, 0, 1, 0, 160, 1],
        fallbackRate: 8000,
        outChannels: 1,
      );
      expect(cfg.bitrate, 32000);
    });

    test('fpp is clamped to 1..12', () {
      final cfg = txCodecConfigFromWire(
        [3, 48000, 1, 2048, 10, 0, 0, 32000, 1, 0, 960, 99],
        fallbackRate: 48000,
        outChannels: 1,
      );
      expect(cfg.fpp, 12);
    });

    test('DTX flag is read from index 6', () {
      final on = txCodecConfigFromWire(
        [3, 48000, 1, 2048, 10, 1, 1, 32000, 1, 0, 960, 1],
        fallbackRate: 48000,
        outChannels: 1,
      );
      final off = txCodecConfigFromWire(
        [3, 48000, 1, 2048, 10, 1, 0, 32000, 1, 0, 960, 1],
        fallbackRate: 48000,
        outChannels: 1,
      );
      expect(on.dtx, isTrue);
      expect(off.dtx, isFalse);
    });
  });
}
