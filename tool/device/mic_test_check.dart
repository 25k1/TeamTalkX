import 'package:flutter/material.dart';
import 'package:teamtalkx/src/audio/audio_worker.dart';
import 'package:teamtalkx/src/domain/capture_settings.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(
    const MaterialApp(
      home: Scaffold(body: Center(child: Text('Mic test check: speak'))),
    ),
  );
  final start = DateTime.now();
  final finished = <MicTestPhase>[];
  late AudioWorker worker;
  var sent = 0;
  worker = await AudioWorker.spawn(
    onTx: (tx) => sent += tx.packets.length,
    onMicTest: (phase) {
      finished.add(phase);
      debugPrint(
        'TTX-BENCH ${phase.name} at '
        '${DateTime.now().difference(start).inMilliseconds} ms',
      );
    },
  );
  debugPrint('TTX-BENCH playback: ${await worker.startAudio(outputGain: 0.3)}');
  worker
    ..configureCapture(
      const CaptureSettings(
        sampleRate: 48000,
        channels: 1,
        noiseSuppression: true,
      ),
    )
    ..startCapture(audioSource: 7, sampleRate: 48000, channels: 1)
    ..startMicTest(live: false, record: const Duration(seconds: 3));
  for (var i = 0; i < 100 && !finished.contains(MicTestPhase.finished); i++) {
    await Future<void>.delayed(const Duration(milliseconds: 100));
  }
  debugPrint('TTX-BENCH engine: ${await worker.engineStats()}');
  debugPrint('TTX-BENCH packets sent: $sent');
  await worker.shutdown();
  debugPrint('TTX-BENCH done');
}
