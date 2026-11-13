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
    final playbackSettings = ref.read(playbackSettingsProvider);
    final microphoneSettings = ref.read(microphoneSettingsProvider);
    final interruption = ref.read(outputInterruptionProvider);
    final master = volumeFromPercent(playbackSettings.masterVolumePercent);
    final mv = interruption == OutputEffect.duck
        ? (master * duckGain).round()
        : master;
    if (!client.setMasterVolume(mv)) {
      debugPrint('[VolumeController] setMasterVolume=$mv rejected by client');
    }
    client
      ..setMediaPlaybackVolume(playbackSettings.mediaVolumePercent)
      ..setPlaybackNormalization(enabled: playbackSettings.normalizeSpeakers)
      ..setVoiceQuality(playbackSettings.voiceQuality);
    if (client.supportsInputGain) {
      final mg = refGain(microphoneSettings.microphoneGainPercent.toDouble());
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

  bool playbackChanged(PlaybackSettings? a, PlaybackSettings b) =>
      a == null ||
      a.masterVolumePercent != b.masterVolumePercent ||
      a.mediaVolumePercent != b.mediaVolumePercent ||
      a.normalizeSpeakers != b.normalizeSpeakers ||
      a.voiceQuality != b.voiceQuality;

  bool microphoneChanged(MicrophoneSettings? a, MicrophoneSettings b) =>
      a == null ||
      a.microphoneGainPercent != b.microphoneGainPercent ||
      a.customInputGainPercent != b.customInputGainPercent;

  suppressed = ref.read(connectionProvider) is! LoggedIn;

  ref.listen<TeamTalkClient>(teamTalkClientProvider, (_, _) => scheduleApply());
  ref
    ..listen<PlaybackSettings>(playbackSettingsProvider, (prev, next) {
      if (playbackChanged(prev, next)) scheduleApply();
    })
    ..listen<MicrophoneSettings>(microphoneSettingsProvider, (prev, next) {
      if (microphoneChanged(prev, next)) scheduleApply();
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
