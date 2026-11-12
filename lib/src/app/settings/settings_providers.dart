import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../domain/audio_output.dart';
import '../../domain/media_keys.dart';
import '../../domain/sound_level.dart';
import '../../domain/voice_quality.dart';

enum FocusLossPolicy {
  ignore,
  duck,
  mute;

  static FocusLossPolicy fromName(String? name) =>
      values.firstWhere((v) => v.name == name, orElse: () => ignore);
}

final sharedPreferencesProvider = Provider<SharedPreferences>(
  (ref) => throw UnimplementedError('Override in main()'),
);

enum SoundEvent {
  userJoin('user_join.ogg'),
  userLeft('user_left.ogg'),
  loggedOn('logged_on.ogg'),
  loggedOff('logged_off.ogg'),
  channelMessage('channel_message.ogg'),
  channelMessageSent('channel_message_sent.ogg'),
  userMessage('user_message.ogg'),
  broadcastMessage('broadcast_message.ogg'),
  serverLost('serverlost.ogg'),
  txOn('tx_on.ogg'),
  txOff('tx_off.ogg'),
  voiceActEnable('voiceact_enable.ogg'),
  voiceActDisable('voiceact_disable.ogg'),
  voiceActOn('voiceact_on.ogg'),
  voiceActOff('voiceact_off.ogg'),
  fileUpdate('fileupdate.ogg'),
  typing('typing.ogg');

  const SoundEvent(this.asset);

  final String asset;

  String get packName => asset.substring(0, asset.lastIndexOf('.'));
}

enum AppLanguage {
  system(null),
  english('en'),
  russian('ru'),
  georgian('ka');

  const AppLanguage(this.code);

  final String? code;

  static AppLanguage fromName(String? name) => values.firstWhere(
    (l) => l.name == name,
    orElse: () => AppLanguage.system,
  );
}

enum VadEngine {
  rnnoise('RNNoise'),
  silero('Silero');

  const VadEngine(this.label);

  final String label;

  static VadEngine fromName(String? name) =>
      VadEngine.values.firstWhere((e) => e.name == name, orElse: () => rnnoise);
}

enum AppTheme {
  system,
  light,
  dark;

  static AppTheme fromName(String? name) =>
      values.firstWhere((t) => t.name == name, orElse: () => system);
}

enum SpeechOutput {
  screenReader,
  tts,
  none;

  static SpeechOutput fromName(String? name) => switch (name) {
    'tts' => SpeechOutput.tts,
    'none' => SpeechOutput.none,
    _ => SpeechOutput.screenReader,
  };
}

enum Gender {
  male(0x00000000),
  female(0x00000100),
  neutral(0x00001000);

  const Gender(this.statusBits);

  final int statusBits;

  static Gender fromName(String? name) =>
      Gender.values.firstWhere((g) => g.name == name, orElse: () => male);
}

enum UserStatus {
  available(0x00000000),
  away(0x00000001),
  question(0x00000002);

  const UserStatus(this.statusBits);

  final int statusBits;

  static UserStatus fromName(String? name) => UserStatus.values.firstWhere(
    (s) => s.name == name,
    orElse: () => available,
  );

  static UserStatus fromMode(int mode) {
    if ((mode & question.statusBits) != 0) return question;
    if ((mode & away.statusBits) != 0) return away;
    return available;
  }
}

enum StereoChannel {
  both,
  left,
  right;

  static StereoChannel fromName(String? name) => StereoChannel.values
      .firstWhere((c) => c.name == name, orElse: () => StereoChannel.both);

  int get outputChannel => switch (this) {
    StereoChannel.both => -1,
    StereoChannel.left => 0,
    StereoChannel.right => 1,
  };
}

class Settings {
  const Settings({
    required this.nickname,
    required this.status,
    required this.statusMessage,
    required this.soundsEnabled,
    required this.speechOutput,
    this.language = AppLanguage.system,
    required this.disabledSounds,
    required this.pttKeyCode,
    required this.pttKeyLabel,
    this.keyBindings = const KeyBindings(),
    this.focusLossPolicy = FocusLossPolicy.ignore,
    this.duckOthersForVoice = false,
    this.duckOthersForEvents = false,
    this.keepVolumeUnderTalkBack = false,
    required this.awayDuringCalls,
    required this.callStatusMessage,
    required this.masterVolumePercent,
    required this.microphoneGainPercent,
    required this.voiceActivationLevel,
    required this.vadEngine,
    required this.noiseSuppressionEnabled,
    required this.noiseSuppressionLevel,
    required this.agcEnabled,
    required this.customAudioSource,
    required this.customInputSampleRate,
    required this.customInputChannels,
    required this.customInputGainPercent,
    required this.customStereoChannel,
    required this.gender,
    required this.showOfficialServers,
    required this.showUnofficialServers,
    required this.autoJoinRootChannel,
    required this.ttsUseAccessibilityStream,
    required this.ttsEngine,
    required this.ttsLanguage,
    required this.ttsVoice,
    required this.ttsVolumePercent,
    required this.ttsRatePercent,
    required this.ttsPitchPercent,
    this.mediaStreamMonitor = false,
    this.mediaStreamVolumePercent = 100,
    this.mediaVolumePercent = 100,
    this.normalizeSpeakers = false,
    this.voiceQuality = const VoiceQuality(),
    this.keepAwakeWhileConnected = false,
    this.eventVolumePercent = 100,
    this.chatRetentionDays = 90,
    this.theme = AppTheme.system,
    this.highContrast = false,
    this.voiceCallMode = false,
    this.outputRoute,
  });

  final bool voiceCallMode;

  final AudioOutputKind? outputRoute;

  final int eventVolumePercent;

  final int chatRetentionDays;

  final AppTheme theme;

  final bool highContrast;

  final int mediaVolumePercent;

  final bool normalizeSpeakers;

  final VoiceQuality voiceQuality;

  final bool mediaStreamMonitor;

  final int mediaStreamVolumePercent;

  final String nickname;

  final UserStatus status;
  final String statusMessage;

  final bool soundsEnabled;
  final SpeechOutput speechOutput;
  final AppLanguage language;
  final Set<SoundEvent> disabledSounds;

  final bool ttsUseAccessibilityStream;
  final String ttsEngine;
  final String ttsLanguage;
  final String ttsVoice;
  final int ttsVolumePercent;
  final int ttsRatePercent;
  final int ttsPitchPercent;

  final int pttKeyCode;
  final String pttKeyLabel;

  final KeyBindings keyBindings;

  final FocusLossPolicy focusLossPolicy;

  final bool duckOthersForVoice;
  final bool duckOthersForEvents;

  final bool keepVolumeUnderTalkBack;

  final bool awayDuringCalls;
  final String callStatusMessage;

  final int masterVolumePercent;
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

  final Gender gender;

  double get customInputGain => customInputGainPercent / 50.0;

  final bool showOfficialServers;
  final bool showUnofficialServers;

  final bool autoJoinRootChannel;

  final bool keepAwakeWhileConnected;

  bool soundEnabled(SoundEvent event) =>
      soundsEnabled && !disabledSounds.contains(event);

  Settings copyWith({
    String? nickname,
    UserStatus? status,
    String? statusMessage,
    bool? soundsEnabled,
    SpeechOutput? speechOutput,
    AppLanguage? language,
    Set<SoundEvent>? disabledSounds,
    int? pttKeyCode,
    String? pttKeyLabel,
    KeyBindings? keyBindings,
    FocusLossPolicy? focusLossPolicy,
    bool? duckOthersForVoice,
    bool? duckOthersForEvents,
    bool? keepVolumeUnderTalkBack,
    bool? awayDuringCalls,
    String? callStatusMessage,
    int? masterVolumePercent,
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
    Gender? gender,
    bool? showOfficialServers,
    bool? showUnofficialServers,
    bool? autoJoinRootChannel,
    bool? keepAwakeWhileConnected,
    bool? ttsUseAccessibilityStream,
    String? ttsEngine,
    String? ttsLanguage,
    String? ttsVoice,
    int? ttsVolumePercent,
    int? ttsRatePercent,
    int? ttsPitchPercent,
    bool? mediaStreamMonitor,
    int? mediaStreamVolumePercent,
    int? mediaVolumePercent,
    bool? normalizeSpeakers,
    VoiceQuality? voiceQuality,
    int? eventVolumePercent,
    int? chatRetentionDays,
    AppTheme? theme,
    bool? highContrast,
    bool? voiceCallMode,
    AudioOutputKind? Function()? outputRoute,
  }) => Settings(
    nickname: nickname ?? this.nickname,
    status: status ?? this.status,
    statusMessage: statusMessage ?? this.statusMessage,
    soundsEnabled: soundsEnabled ?? this.soundsEnabled,
    speechOutput: speechOutput ?? this.speechOutput,
    language: language ?? this.language,
    disabledSounds: disabledSounds ?? this.disabledSounds,
    pttKeyCode: pttKeyCode ?? this.pttKeyCode,
    pttKeyLabel: pttKeyLabel ?? this.pttKeyLabel,
    keyBindings: keyBindings ?? this.keyBindings,
    focusLossPolicy: focusLossPolicy ?? this.focusLossPolicy,
    duckOthersForVoice: duckOthersForVoice ?? this.duckOthersForVoice,
    duckOthersForEvents: duckOthersForEvents ?? this.duckOthersForEvents,
    keepVolumeUnderTalkBack:
        keepVolumeUnderTalkBack ?? this.keepVolumeUnderTalkBack,
    awayDuringCalls: awayDuringCalls ?? this.awayDuringCalls,
    callStatusMessage: callStatusMessage ?? this.callStatusMessage,
    masterVolumePercent: masterVolumePercent ?? this.masterVolumePercent,
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
    gender: gender ?? this.gender,
    showOfficialServers: showOfficialServers ?? this.showOfficialServers,
    showUnofficialServers: showUnofficialServers ?? this.showUnofficialServers,
    autoJoinRootChannel: autoJoinRootChannel ?? this.autoJoinRootChannel,
    keepAwakeWhileConnected:
        keepAwakeWhileConnected ?? this.keepAwakeWhileConnected,
    ttsUseAccessibilityStream:
        ttsUseAccessibilityStream ?? this.ttsUseAccessibilityStream,
    ttsEngine: ttsEngine ?? this.ttsEngine,
    ttsLanguage: ttsLanguage ?? this.ttsLanguage,
    ttsVoice: ttsVoice ?? this.ttsVoice,
    ttsVolumePercent: ttsVolumePercent ?? this.ttsVolumePercent,
    ttsRatePercent: ttsRatePercent ?? this.ttsRatePercent,
    ttsPitchPercent: ttsPitchPercent ?? this.ttsPitchPercent,
    mediaStreamMonitor: mediaStreamMonitor ?? this.mediaStreamMonitor,
    mediaStreamVolumePercent:
        mediaStreamVolumePercent ?? this.mediaStreamVolumePercent,
    mediaVolumePercent: mediaVolumePercent ?? this.mediaVolumePercent,
    normalizeSpeakers: normalizeSpeakers ?? this.normalizeSpeakers,
    voiceQuality: voiceQuality ?? this.voiceQuality,
    eventVolumePercent: eventVolumePercent ?? this.eventVolumePercent,
    chatRetentionDays: chatRetentionDays ?? this.chatRetentionDays,
    theme: theme ?? this.theme,
    highContrast: highContrast ?? this.highContrast,
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

final settingsProvider = NotifierProvider<SettingsNotifier, Settings>(
  SettingsNotifier.new,
);

class SettingsNotifier extends Notifier<Settings> {
  SharedPreferences get _prefs => ref.read(sharedPreferencesProvider);

  @override
  Settings build() {
    final prefs = _prefs;
    final defaultOutput = (prefs.getBool('tts_enabled') ?? true)
        ? SpeechOutput.screenReader
        : SpeechOutput.none;
    return Settings(
      nickname: prefs.getString('nickname') ?? '',
      status: UserStatus.fromName(prefs.getString('status_mode')),
      statusMessage: prefs.getString('status_message') ?? '',
      soundsEnabled: prefs.getBool('sounds_enabled') ?? true,
      speechOutput: prefs.getString('speech_output') == null
          ? defaultOutput
          : SpeechOutput.fromName(prefs.getString('speech_output')),
      language: AppLanguage.fromName(prefs.getString('app_language')),
      disabledSounds: {
        for (final event in SoundEvent.values)
          if (!(prefs.getBool('sound.${event.name}') ?? true)) event,
      },
      pttKeyCode: prefs.getInt('ptt_key_code') ?? 0,
      pttKeyLabel: prefs.getString('ptt_key_label') ?? '',
      keyBindings: KeyBindings.decode(prefs.getString('media_key_bindings')),
      focusLossPolicy: FocusLossPolicy.fromName(
        prefs.getString('focus_loss_policy'),
      ),
      duckOthersForVoice: prefs.getBool('duck_others_voice') ?? false,
      duckOthersForEvents: prefs.getBool('duck_others_events') ?? false,
      keepVolumeUnderTalkBack:
          prefs.getBool('keep_volume_under_talkback') ?? false,
      awayDuringCalls: prefs.getBool('pause_during_calls') ?? true,
      callStatusMessage: prefs.getString('call_status_message') ?? '',
      masterVolumePercent: _outputVolumePercent(prefs),
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
      gender: Gender.fromName(prefs.getString('gender')),
      showOfficialServers: prefs.getBool('show_official_servers') ?? true,
      showUnofficialServers: prefs.getBool('show_unofficial_servers') ?? false,
      autoJoinRootChannel: prefs.getBool('auto_join_root_channel') ?? true,
      ttsUseAccessibilityStream:
          prefs.getBool('tts_accessibility_stream') ?? false,
      ttsEngine: prefs.getString('tts_engine') ?? '',
      ttsLanguage: prefs.getString('tts_language') ?? '',
      ttsVoice: prefs.getString('tts_voice') ?? '',
      ttsVolumePercent: prefs.getInt('tts_volume_percent') ?? 100,
      ttsRatePercent: prefs.getInt('tts_rate_percent') ?? 100,
      ttsPitchPercent: prefs.getInt('tts_pitch_percent') ?? 100,
      mediaStreamMonitor: prefs.getBool('media_stream_monitor') ?? false,
      mediaStreamVolumePercent:
          prefs.getInt('media_stream_volume_percent') ?? 100,
      mediaVolumePercent: prefs.getInt('media_volume_percent') ?? 100,
      normalizeSpeakers: prefs.getBool('normalize_speakers') ?? false,
      voiceQuality: VoiceQuality(
        enhancement: VoiceEnhancement.fromName(
          prefs.getString('voice_enhancement'),
        ),
        bandwidthExtension: prefs.getBool('bandwidth_extension') ?? false,
        protection: LossProtection.fromName(prefs.getString('loss_protection')),
      ),
      keepAwakeWhileConnected:
          prefs.getBool('keep_awake_while_connected') ?? false,
      eventVolumePercent: prefs.getInt('event_volume_percent') ?? 100,
      chatRetentionDays: prefs.getInt('chat_retention_days') ?? 90,
      theme: AppTheme.fromName(prefs.getString('theme')),
      highContrast: prefs.getBool('high_contrast') ?? false,
      voiceCallMode: prefs.getString('audio_mode') == 'voiceCall',
      outputRoute: AudioOutputKind.fromName(prefs.getString('output_route')),
    );
  }

  void _setBool(String key, bool value, Settings Function(Settings) update) {
    unawaited(_prefs.setBool(key, value));
    state = update(state);
  }

  void _setInt(String key, int value, Settings Function(Settings) update) {
    unawaited(_prefs.setInt(key, value));
    state = update(state);
  }

  void _setString(
    String key,
    String value,
    Settings Function(Settings) update,
  ) {
    unawaited(_prefs.setString(key, value));
    state = update(state);
  }

  void setLanguage(AppLanguage language) => _setString(
    'app_language',
    language.name,
    (s) => s.copyWith(language: language),
  );

  void setSpeechOutput(SpeechOutput output) => _setString(
    'speech_output',
    output.name,
    (s) => s.copyWith(speechOutput: output),
  );

  void setShowOfficialServers(bool v) => _setBool(
    'show_official_servers',
    v,
    (s) => s.copyWith(showOfficialServers: v),
  );

  void setShowUnofficialServers(bool v) => _setBool(
    'show_unofficial_servers',
    v,
    (s) => s.copyWith(showUnofficialServers: v),
  );

  void setAutoJoinRootChannel(bool v) => _setBool(
    'auto_join_root_channel',
    v,
    (s) => s.copyWith(autoJoinRootChannel: v),
  );

  void setKeepAwakeWhileConnected(bool v) => _setBool(
    'keep_awake_while_connected',
    v,
    (s) => s.copyWith(keepAwakeWhileConnected: v),
  );

  void setMediaStreamMonitor(bool v) => _setBool(
    'media_stream_monitor',
    v,
    (s) => s.copyWith(mediaStreamMonitor: v),
  );

  void setMediaStreamVolumePercent(int v) => _setInt(
    'media_stream_volume_percent',
    v,
    (s) => s.copyWith(mediaStreamVolumePercent: v),
  );

  void setTtsUseAccessibilityStream(bool v) => _setBool(
    'tts_accessibility_stream',
    v,
    (s) => s.copyWith(ttsUseAccessibilityStream: v),
  );

  void setTtsEngine(String engine) {
    unawaited(_prefs.setString('tts_engine', engine));
    unawaited(_prefs.setString('tts_language', ''));
    unawaited(_prefs.setString('tts_voice', ''));
    state = state.copyWith(ttsEngine: engine, ttsLanguage: '', ttsVoice: '');
  }

  void setTtsLanguage(String language) {
    unawaited(_prefs.setString('tts_language', language));
    unawaited(_prefs.setString('tts_voice', ''));
    state = state.copyWith(ttsLanguage: language, ttsVoice: '');
  }

  void setTtsVoice(String v) =>
      _setString('tts_voice', v, (s) => s.copyWith(ttsVoice: v));

  void setTtsVolumePercent(int v) =>
      _setInt('tts_volume_percent', v, (s) => s.copyWith(ttsVolumePercent: v));

  void setTtsRatePercent(int v) =>
      _setInt('tts_rate_percent', v, (s) => s.copyWith(ttsRatePercent: v));

  void setTtsPitchPercent(int v) =>
      _setInt('tts_pitch_percent', v, (s) => s.copyWith(ttsPitchPercent: v));

  void setMasterVolumePercent(int v) =>
      _setInt(_outputVolumeKey, v, (s) => s.copyWith(masterVolumePercent: v));

  void setMediaVolumePercent(int v) => _setInt(
    'media_volume_percent',
    v,
    (s) => s.copyWith(mediaVolumePercent: v),
  );

  void setVoiceCallMode(bool v) => _setString(
    'audio_mode',
    v ? 'voiceCall' : 'media',
    (s) => s.copyWith(voiceCallMode: v),
  );

  void setOutputRoute(AudioOutputKind? route) {
    if (route == null) {
      unawaited(_prefs.remove('output_route'));
    } else {
      unawaited(_prefs.setString('output_route', route.name));
    }
    state = state.copyWith(outputRoute: () => route);
  }

  void setTheme(AppTheme v) =>
      _setString('theme', v.name, (s) => s.copyWith(theme: v));

  void setHighContrast(bool v) =>
      _setBool('high_contrast', v, (s) => s.copyWith(highContrast: v));

  void setChatRetentionDays(int v) => _setInt(
    'chat_retention_days',
    v,
    (s) => s.copyWith(chatRetentionDays: v),
  );

  void setEventVolumePercent(int v) => _setInt(
    'event_volume_percent',
    v,
    (s) => s.copyWith(eventVolumePercent: v),
  );

  void setNormalizeSpeakers(bool v) => _setBool(
    'normalize_speakers',
    v,
    (s) => s.copyWith(normalizeSpeakers: v),
  );

  void setVoiceEnhancement(VoiceEnhancement v) => _setString(
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

  void setBandwidthExtension(bool v) => _setBool(
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

  void setLossProtection(LossProtection v) => _setString(
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

  void setMicrophoneGainPercent(int v) => _setInt(
    'microphone_gain_percent',
    v,
    (s) => s.copyWith(microphoneGainPercent: v),
  );

  void setVoiceActivationLevel(int v) => _setInt(
    'voice_activation_level',
    v,
    (s) => s.copyWith(voiceActivationLevel: v),
  );

  void setVadEngine(VadEngine v) =>
      _setString('vad_engine', v.name, (s) => s.copyWith(vadEngine: v));

  void setNoiseSuppressionEnabled(bool v) => _setBool(
    'noise_suppression_enabled',
    v,
    (s) => s.copyWith(noiseSuppressionEnabled: v),
  );

  void setNoiseSuppressionLevel(int v) => _setInt(
    'noise_suppression_level',
    v,
    (s) => s.copyWith(noiseSuppressionLevel: v),
  );

  void setAgcEnabled(bool v) =>
      _setBool('agc_enabled', v, (s) => s.copyWith(agcEnabled: v));

  void setCustomAudioSource(int v) => _setInt(
    'custom_audio_source',
    v,
    (s) => s.copyWith(customAudioSource: v),
  );

  void setCustomInputSampleRate(int v) => _setInt(
    'custom_input_sample_rate',
    v,
    (s) => s.copyWith(customInputSampleRate: v),
  );

  void setCustomInputChannels(int v) => _setInt(
    'custom_input_channels',
    v,
    (s) => s.copyWith(customInputChannels: v),
  );

  void setCustomInputGainPercent(int v) => _setInt(
    'custom_input_gain_percent',
    v,
    (s) => s.copyWith(customInputGainPercent: v),
  );

  void setCustomStereoChannel(StereoChannel c) => _setString(
    'custom_stereo_channel',
    c.name,
    (s) => s.copyWith(customStereoChannel: c),
  );

  void setGender(Gender gender) =>
      _setString('gender', gender.name, (s) => s.copyWith(gender: gender));

  void setPttKey(int keyCode, String label) {
    unawaited(_prefs.setInt('ptt_key_code', keyCode));
    unawaited(_prefs.setString('ptt_key_label', label));
    state = state.copyWith(pttKeyCode: keyCode, pttKeyLabel: label);
  }

  void setFocusLossPolicy(FocusLossPolicy v) => _setString(
    'focus_loss_policy',
    v.name,
    (s) => s.copyWith(focusLossPolicy: v),
  );

  void setDuckOthersForVoice(bool v) => _setBool(
    'duck_others_voice',
    v,
    (s) => s.copyWith(duckOthersForVoice: v),
  );

  void setDuckOthersForEvents(bool v) => _setBool(
    'duck_others_events',
    v,
    (s) => s.copyWith(duckOthersForEvents: v),
  );

  void setKeepVolumeUnderTalkBack(bool v) => _setBool(
    'keep_volume_under_talkback',
    v,
    (s) => s.copyWith(keepVolumeUnderTalkBack: v),
  );

  void setKeyAction(MediaKey key, KeyPress press, KeyAction? action) {
    final bindings = state.keyBindings.withAction(key, press, action);
    _setString(
      'media_key_bindings',
      bindings.encode(),
      (s) => s.copyWith(keyBindings: bindings),
    );
  }

  void setAwayDuringCalls(bool v) =>
      _setBool('pause_during_calls', v, (s) => s.copyWith(awayDuringCalls: v));

  void setCallStatusMessage(String v) => _setString(
    'call_status_message',
    v.trim(),
    (s) => s.copyWith(callStatusMessage: v.trim()),
  );

  void setSoundsEnabled(bool v) =>
      _setBool('sounds_enabled', v, (s) => s.copyWith(soundsEnabled: v));

  void setNickname(String v) =>
      _setString('nickname', v, (s) => s.copyWith(nickname: v));

  void setStatus(UserStatus status) =>
      _setString('status_mode', status.name, (s) => s.copyWith(status: status));

  void setStatusMessage(String v) =>
      _setString('status_message', v, (s) => s.copyWith(statusMessage: v));
}
