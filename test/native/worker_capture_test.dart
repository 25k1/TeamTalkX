@Tags(['native'])
library;

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:teamtalkx/src/audio/audio_worker.dart';
import 'package:teamtalkx/src/audio/native_library.dart';
import 'package:teamtalkx/src/domain/capture_settings.dart';

const _codec = TxCodecConfig(sampleRate: 48000, channels: 1, bitrate: 32000);

Int16List _frame(int index) {
  final random = math.Random(index);
  return Int16List.fromList([
    for (var i = 0; i < 960; i++)
      (math.sin(2 * math.pi * 300 * (index * 960 + i) / 48000) * 8000 +
              (random.nextDouble() * 2 - 1) * 2000)
          .round(),
  ]);
}

void main() {
  test(
    'the worker reads native capture, detects voice and encodes',
    skip: nativeLibraryOverride == ''
        ? 'Needs a host build of native/: --dart-define=TT_NATIVE_LIB=<path>'
        : null,
    () async {
      final packets = <TxPackets>[];
      final voices = <bool>[];
      final worker = await AudioWorker.spawn(
        onTx: packets.add,
        onRx: (_) {},
        onVoice: voices.add,
      );
      addTearDown(worker.shutdown);
      worker.configureCapture(
        const CaptureSettings(
          sampleRate: 48000,
          channels: 1,
          noiseSuppression: true,
          voiceDetection: true,
          detector: VoiceDetectorKind.rnnoise,
        ),
      );

      expect(await worker.startAudio(), isFalse);

      void state({required bool transmit, bool flush = false}) =>
          worker.setCaptureState(
            streamId: 1,
            userId: 2,
            channelId: 3,
            transmit: transmit,
            flushPreRoll: flush,
            config: _codec,
          );

      worker.startCapture(audioSource: 7, sampleRate: 48000, channels: 1);
      state(transmit: false);
      for (var i = 0; i < 10; i++) {
        worker.injectCapture(_frame(i));
      }
      await Future<void>.delayed(const Duration(milliseconds: 300));
      expect(voices, hasLength(10), reason: 'one result per 20 ms frame');
      expect(packets, isEmpty, reason: 'nothing is sent before TX');

      state(transmit: true, flush: true);
      worker.injectCapture(_frame(10));
      await Future<void>.delayed(const Duration(milliseconds: 300));
      final sent = packets.expand((p) => p.packets).toList();
      expect(sent, hasLength(11));
      expect(sent, everyElement(isNotEmpty));
    },
  );
}
