@Tags(['native'])
library;

import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:teamtalkx/src/audio/audio_worker.dart';
import 'package:teamtalkx/src/audio/native_library.dart';
import 'package:teamtalkx/src/domain/capture_settings.dart';

void main() {
  test(
    'the microphone test records, plays back and finishes, sending nothing',
    skip: nativeLibraryOverride == ''
        ? 'Needs a host build of native/: --dart-define=TT_NATIVE_LIB=<path>'
        : null,
    () async {
      final phases = <MicTestPhase>[];
      var sent = 0;
      final worker = await AudioWorker.spawn(
        onTx: (tx) => sent += tx.packets.length,
        onMicTest: phases.add,
      );
      addTearDown(worker.shutdown);
      await worker.startAudio();
      worker
        ..configureCapture(
          const CaptureSettings(sampleRate: 48000, channels: 1),
        )
        ..startCapture(audioSource: 7, sampleRate: 48000, channels: 1)
        ..startMicTest(live: false, record: const Duration(milliseconds: 200));
      for (var i = 0; i < 15; i++) {
        worker.injectCapture(Int16List(960)..fillRange(0, 960, 500));
      }
      await Future<void>.delayed(const Duration(milliseconds: 500));

      expect(phases, [
        MicTestPhase.recording,
        MicTestPhase.playing,
        MicTestPhase.finished,
      ]);
      expect(sent, 0);
    },
  );
}
