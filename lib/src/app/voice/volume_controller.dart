import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/sound_level.dart';
import '../../domain/teamtalk_client.dart';
import '../connection/connection_providers.dart';
import '../settings/settings_providers.dart';
import 'output_interruption.dart';
import 'voice_providers.dart';

final volumeControllerProvider = Provider<void>((ref) {
  Timer? debounce;
  var suppressed = true;

  void applyNow() {
    if (suppressed) return;
    final client = ref.read(teamTalkClientProvider);
    if (!client.isConnected) return;
    final s = ref.read(settingsProvider);
    final interruption = ref.read(outputInterruptionProvider);
    final master = volumeFromPercent(s.masterVolumePercent);
    final mv = interruption == OutputEffect.duck
        ? (master * duckGain).round()
        : master;
    if (!client.setMasterVolume(mv)) {
      debugPrint('[VolumeController] setMasterVolume=$mv rejected by client');
    }
    client
      ..setMediaPlaybackVolume(s.mediaVolumePercent)
      ..setPlaybackNormalization(enabled: s.normalizeSpeakers)
      ..setVoiceQuality(s.voiceQuality);
    if (client.supportsInputGain) {
      final mg = refGain(s.microphoneGainPercent.toDouble());
      if (!client.setMicrophoneGain(mg)) {
        debugPrint(
          '[VolumeController] setMicrophoneGain=$mg rejected by client',
        );
      }
    }
    client.setSoundOutputMute(
      muted:
          ref.read(speakerMutedProvider) || interruption == OutputEffect.mute,
    );
  }

  void scheduleApply() {
    debounce?.cancel();
    debounce = Timer(Duration.zero, applyNow);
  }

  bool volumeRelevantChanged(Settings? a, Settings b) {
    if (a == null) return true;
    return a.masterVolumePercent != b.masterVolumePercent ||
        a.mediaVolumePercent != b.mediaVolumePercent ||
        a.normalizeSpeakers != b.normalizeSpeakers ||
        a.voiceQuality != b.voiceQuality ||
        a.microphoneGainPercent != b.microphoneGainPercent ||
        a.customInputGainPercent != b.customInputGainPercent;
  }

  suppressed = ref.read(connectionProvider) is! LoggedIn;

  ref.listen<TeamTalkClient>(teamTalkClientProvider, (_, _) => scheduleApply());
  ref.listen<Settings>(settingsProvider, (prev, next) {
    if (volumeRelevantChanged(prev, next)) scheduleApply();
  });
  ref.listen<bool>(speakerMutedProvider, (_, _) => scheduleApply());
  ref.listen<OutputEffect?>(outputInterruptionProvider, (_, _) {
    scheduleApply();
  });
  ref.listen<ConnectionState>(connectionProvider, (_, next) {
    if (next is LoggedIn) {
      suppressed = false;
      scheduleApply();
    } else if (next is Disconnected || next is Reconnecting) {
      suppressed = true;
      debounce?.cancel();
    }
  });

  if (!suppressed) scheduleApply();

  ref.onDispose(() => debounce?.cancel());
});
