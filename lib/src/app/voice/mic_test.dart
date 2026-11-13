import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../audio/audio_worker.dart';
import '../../domain/audio_output.dart';
import '../announcer.dart';
import '../platform_services.dart';
import '../settings/locale_providers.dart';
import '../settings/settings_providers.dart';
import 'audio_output.dart';
import 'voice_providers.dart';

typedef MicTestWorkerFactory =
    Future<AudioWorker> Function(MicTestHandler onPhase);

final micTestWorkerFactoryProvider = Provider<MicTestWorkerFactory>(
  (ref) =>
      (onPhase) => AudioWorker.spawn(onTx: (_) {}, onMicTest: onPhase),
);

bool headphonesConnected(List<AudioOutputDevice> outputs) => outputs.any(
  (d) =>
      d.kind != AudioOutputKind.speaker && d.kind != AudioOutputKind.earpiece,
);

enum MicTestRefusal { transmitting, noPermission }

final micTestProvider =
    NotifierProvider.autoDispose<MicTestNotifier, MicTestPhase?>(
      MicTestNotifier.new,
    );

class MicTestNotifier extends Notifier<MicTestPhase?> {
  AudioWorker? _worker;

  @override
  MicTestPhase? build() {
    ref.onDispose(() => unawaited(_shutdown()));
    return null;
  }

  Future<MicTestRefusal?> start({required bool live}) async {
    final voice = ref.read(voiceProvider);
    if (voice.txEnabled || voice.voxEnabled) {
      return MicTestRefusal.transmitting;
    }
    if (!await ref.read(permissionsProvider).requestConnect()) {
      return MicTestRefusal.noPermission;
    }
    await _shutdown();
    final playbackSettings = ref.read(playbackSettingsProvider);
    final microphoneSettings = ref.read(microphoneSettingsProvider);
    final worker = _worker = await ref.read(micTestWorkerFactoryProvider)(
      _onPhase,
    );
    final outputs = ref.read(audioOutputsProvider).value ?? const [];
    final device = chosenOutput(
      outputs,
      playbackSettings.outputRoute,
      voiceCall: playbackSettings.voiceCallMode,
    );
    worker.setOutput(
      AudioOutput(
        voiceCall: playbackSettings.voiceCallMode,
        deviceId: playbackSettings.voiceCallMode ? 0 : device?.id ?? 0,
      ),
    );
    await worker.startAudio(
      outputGain: playbackSettings.masterVolumePercent / 100,
    );
    worker
      ..configureCapture(
        captureSettingsFor(microphoneSettings, voiceDetection: false),
      )
      ..startCapture(
        audioSource: microphoneSettings.customAudioSource,
        sampleRate: microphoneSettings.customInputSampleRate,
        channels: microphoneSettings.customInputChannels,
      )
      ..startMicTest(live: live);
    return null;
  }

  Future<void> stop() async {
    _worker?.stopMicTest();
    await _shutdown();
    state = null;
  }

  void _onPhase(MicTestPhase phase) {
    if (!ref.mounted) return;
    state = phase;
    final l10n = ref.read(appLocalizationsProvider);
    ref.read(announcerProvider).announce(switch (phase) {
      MicTestPhase.listening => l10n.micTestListening,
      MicTestPhase.recording => l10n.micTestRecording,
      MicTestPhase.playing => l10n.micTestPlaying,
      MicTestPhase.finished => l10n.micTestFinished,
    });
    if (phase == MicTestPhase.finished) unawaited(_shutdown());
  }

  Future<void> _shutdown() async {
    final worker = _worker;
    _worker = null;
    await worker?.shutdown();
  }
}
