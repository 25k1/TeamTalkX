import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../domain/audio_output.dart';
import '../../domain/sound_level.dart';
import '../../domain/voice_quality.dart';
import 'prefs_notifier.dart';
import 'settings_types.dart';

class PlaybackSettings {
  const PlaybackSettings({
    this.masterVolumePercent = 100,
    this.mediaVolumePercent = 100,
    this.normalizeSpeakers = false,
    this.voiceQuality = const VoiceQuality(),
    this.mediaStreamMonitor = false,
    this.mediaStreamVolumePercent = 100,
    this.voiceCallMode = false,
    this.outputRoute,
  });

  final int masterVolumePercent;
  final int mediaVolumePercent;
  final bool normalizeSpeakers;
  final VoiceQuality voiceQuality;
  final bool mediaStreamMonitor;
  final int mediaStreamVolumePercent;
  final bool voiceCallMode;
  final AudioOutputKind? outputRoute;

  PlaybackSettings copyWith({
    int? masterVolumePercent,
    int? mediaVolumePercent,
    bool? normalizeSpeakers,
    VoiceQuality? voiceQuality,
    bool? mediaStreamMonitor,
    int? mediaStreamVolumePercent,
    bool? voiceCallMode,
    AudioOutputKind? Function()? outputRoute,
  }) => PlaybackSettings(
    masterVolumePercent: masterVolumePercent ?? this.masterVolumePercent,
    mediaVolumePercent: mediaVolumePercent ?? this.mediaVolumePercent,
    normalizeSpeakers: normalizeSpeakers ?? this.normalizeSpeakers,
    voiceQuality: voiceQuality ?? this.voiceQuality,
    mediaStreamMonitor: mediaStreamMonitor ?? this.mediaStreamMonitor,
    mediaStreamVolumePercent:
        mediaStreamVolumePercent ?? this.mediaStreamVolumePercent,
    voiceCallMode: voiceCallMode ?? this.voiceCallMode,
    outputRoute: outputRoute == null ? this.outputRoute : outputRoute(),
  );
}

const _outputVolumeKey = 'output_volume_percent';

int _outputVolumePercent(SharedPreferences prefs) {
  final current = prefs.getInt(_outputVolumeKey);
  if (current != null) return current.clamp(0, volumePercentMax);
  final old = prefs.getInt('master_volume_percent');
  if (old == null) return 100;
  final percent = volumeToPercent(refVolume(old.toDouble()));
  return ((percent / 5).round() * 5).clamp(0, volumePercentMax);
}

final playbackSettingsProvider =
    NotifierProvider<PlaybackSettingsNotifier, PlaybackSettings>(
      PlaybackSettingsNotifier.new,
    );

class PlaybackSettingsNotifier extends PrefsNotifier<PlaybackSettings> {
  @override
  PlaybackSettings build() => PlaybackSettings(
    masterVolumePercent: _outputVolumePercent(prefs),
    mediaVolumePercent: prefs.getInt('media_volume_percent') ?? 100,
    normalizeSpeakers: prefs.getBool('normalize_speakers') ?? false,
    voiceQuality: VoiceQuality(
      enhancement: VoiceEnhancement.fromName(
        prefs.getString('voice_enhancement'),
      ),
      bandwidthExtension: prefs.getBool('bandwidth_extension') ?? false,
      protection: LossProtection.fromName(prefs.getString('loss_protection')),
    ),
    mediaStreamMonitor: prefs.getBool('media_stream_monitor') ?? false,
    mediaStreamVolumePercent:
        prefs.getInt('media_stream_volume_percent') ?? 100,
    voiceCallMode: prefs.getString('audio_mode') == 'voiceCall',
    outputRoute: AudioOutputKind.fromName(prefs.getString('output_route')),
  );

  void setMasterVolumePercent(int v) =>
      saveInt(_outputVolumeKey, v, (s) => s.copyWith(masterVolumePercent: v));

  void setMediaVolumePercent(int v) => saveInt(
    'media_volume_percent',
    v,
    (s) => s.copyWith(mediaVolumePercent: v),
  );

  void setNormalizeSpeakers(bool v) => saveBool(
    'normalize_speakers',
    v,
    (s) => s.copyWith(normalizeSpeakers: v),
  );

  void setMediaStreamMonitor(bool v) => saveBool(
    'media_stream_monitor',
    v,
    (s) => s.copyWith(mediaStreamMonitor: v),
  );

  void setMediaStreamVolumePercent(int v) => saveInt(
    'media_stream_volume_percent',
    v,
    (s) => s.copyWith(mediaStreamVolumePercent: v),
  );

  void setVoiceCallMode(bool v) => saveString(
    'audio_mode',
    v ? 'voiceCall' : 'media',
    (s) => s.copyWith(voiceCallMode: v),
  );

  void setOutputRoute(AudioOutputKind? route) {
    if (route == null) {
      unawaited(prefs.remove('output_route'));
    } else {
      unawaited(prefs.setString('output_route', route.name));
    }
    state = state.copyWith(outputRoute: () => route);
  }

  void setVoiceEnhancement(VoiceEnhancement v) => saveString(
    'voice_enhancement',
    v.name,
    (s) => s.copyWith(
      voiceQuality: VoiceQuality(
        enhancement: v,
        bandwidthExtension: s.voiceQuality.bandwidthExtension,
        protection: s.voiceQuality.protection,
      ),
    ),
  );

  void setBandwidthExtension(bool v) => saveBool(
    'bandwidth_extension',
    v,
    (s) => s.copyWith(
      voiceQuality: VoiceQuality(
        enhancement: s.voiceQuality.enhancement,
        bandwidthExtension: v,
        protection: s.voiceQuality.protection,
      ),
    ),
  );

  void setLossProtection(LossProtection v) => saveString(
    'loss_protection',
    v.name,
    (s) => s.copyWith(
      voiceQuality: VoiceQuality(
        enhancement: s.voiceQuality.enhancement,
        bandwidthExtension: s.voiceQuality.bandwidthExtension,
        protection: v,
      ),
    ),
  );
}

class MicrophoneSettings {
  const MicrophoneSettings({
    this.microphoneGainPercent = 50,
    this.voiceActivationLevel = 5,
    this.vadEngine = VadEngine.rnnoise,
    this.noiseSuppressionEnabled = false,
    this.noiseSuppressionLevel = 70,
    this.agcEnabled = false,
    this.customAudioSource = 7,
    this.customInputSampleRate = 48000,
    this.customInputChannels = 1,
    this.customInputGainPercent = 50,
    this.customStereoChannel = StereoChannel.both,
  });

  final int microphoneGainPercent;
  final int voiceActivationLevel;
  final VadEngine vadEngine;
  final bool noiseSuppressionEnabled;
  final int noiseSuppressionLevel;
  final bool agcEnabled;
  final int customAudioSource;
  final int customInputSampleRate;
  final int customInputChannels;
  final int customInputGainPercent;
  final StereoChannel customStereoChannel;

  double get customInputGain => customInputGainPercent / 50.0;

  MicrophoneSettings copyWith({
    int? microphoneGainPercent,
    int? voiceActivationLevel,
    VadEngine? vadEngine,
    bool? noiseSuppressionEnabled,
    int? noiseSuppressionLevel,
    bool? agcEnabled,
    int? customAudioSource,
    int? customInputSampleRate,
    int? customInputChannels,
    int? customInputGainPercent,
    StereoChannel? customStereoChannel,
  }) => MicrophoneSettings(
    microphoneGainPercent: microphoneGainPercent ?? this.microphoneGainPercent,
    voiceActivationLevel: voiceActivationLevel ?? this.voiceActivationLevel,
    vadEngine: vadEngine ?? this.vadEngine,
    noiseSuppressionEnabled:
        noiseSuppressionEnabled ?? this.noiseSuppressionEnabled,
    noiseSuppressionLevel: noiseSuppressionLevel ?? this.noiseSuppressionLevel,
    agcEnabled: agcEnabled ?? this.agcEnabled,
    customAudioSource: customAudioSource ?? this.customAudioSource,
    customInputSampleRate: customInputSampleRate ?? this.customInputSampleRate,
    customInputChannels: customInputChannels ?? this.customInputChannels,
    customInputGainPercent:
        customInputGainPercent ?? this.customInputGainPercent,
    customStereoChannel: customStereoChannel ?? this.customStereoChannel,
  );
}

final microphoneSettingsProvider =
    NotifierProvider<MicrophoneSettingsNotifier, MicrophoneSettings>(
      MicrophoneSettingsNotifier.new,
    );

class MicrophoneSettingsNotifier extends PrefsNotifier<MicrophoneSettings> {
  @override
  MicrophoneSettings build() => MicrophoneSettings(
    microphoneGainPercent: prefs.getInt('microphone_gain_percent') ?? 50,
    voiceActivationLevel: prefs.getInt('voice_activation_level') ?? 5,
    vadEngine: VadEngine.fromName(prefs.getString('vad_engine')),
    noiseSuppressionEnabled:
        prefs.getBool('noise_suppression_enabled') ?? false,
    noiseSuppressionLevel: prefs.getInt('noise_suppression_level') ?? 70,
    agcEnabled: prefs.getBool('agc_enabled') ?? false,
    customAudioSource: prefs.getInt('custom_audio_source') ?? 7,
    customInputSampleRate: prefs.getInt('custom_input_sample_rate') ?? 48000,
    customInputChannels: prefs.getInt('custom_input_channels') ?? 1,
    customInputGainPercent: prefs.getInt('custom_input_gain_percent') ?? 50,
    customStereoChannel: StereoChannel.fromName(
      prefs.getString('custom_stereo_channel'),
    ),
  );

  void setMicrophoneGainPercent(int v) => saveInt(
    'microphone_gain_percent',
    v,
    (s) => s.copyWith(microphoneGainPercent: v),
  );

  void setVoiceActivationLevel(int v) => saveInt(
    'voice_activation_level',
    v,
    (s) => s.copyWith(voiceActivationLevel: v),
  );

  void setVadEngine(VadEngine v) =>
      saveString('vad_engine', v.name, (s) => s.copyWith(vadEngine: v));

  void setNoiseSuppressionEnabled(bool v) => saveBool(
    'noise_suppression_enabled',
    v,
    (s) => s.copyWith(noiseSuppressionEnabled: v),
  );

  void setNoiseSuppressionLevel(int v) => saveInt(
    'noise_suppression_level',
    v,
    (s) => s.copyWith(noiseSuppressionLevel: v),
  );

  void setAgcEnabled(bool v) =>
      saveBool('agc_enabled', v, (s) => s.copyWith(agcEnabled: v));

  void setCustomAudioSource(int v) => saveInt(
    'custom_audio_source',
    v,
    (s) => s.copyWith(customAudioSource: v),
  );

  void setCustomInputSampleRate(int v) => saveInt(
    'custom_input_sample_rate',
    v,
    (s) => s.copyWith(customInputSampleRate: v),
  );

  void setCustomInputChannels(int v) => saveInt(
    'custom_input_channels',
    v,
    (s) => s.copyWith(customInputChannels: v),
  );

  void setCustomInputGainPercent(int v) => saveInt(
    'custom_input_gain_percent',
    v,
    (s) => s.copyWith(customInputGainPercent: v),
  );

  void setCustomStereoChannel(StereoChannel c) => saveString(
    'custom_stereo_channel',
    c.name,
    (s) => s.copyWith(customStereoChannel: c),
  );
}
