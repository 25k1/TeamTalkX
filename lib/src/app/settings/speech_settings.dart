import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'prefs_notifier.dart';
import 'settings_types.dart';

class SpeechSettings {
  const SpeechSettings({
    this.speechOutput = SpeechOutput.screenReader,
    this.ttsUseAccessibilityStream = false,
    this.ttsEngine = '',
    this.ttsLanguage = '',
    this.ttsVoice = '',
    this.ttsVolumePercent = 100,
    this.ttsRatePercent = 100,
    this.ttsPitchPercent = 100,
  });

  final SpeechOutput speechOutput;
  final bool ttsUseAccessibilityStream;
  final String ttsEngine;
  final String ttsLanguage;
  final String ttsVoice;
  final int ttsVolumePercent;
  final int ttsRatePercent;
  final int ttsPitchPercent;

  SpeechSettings copyWith({
    SpeechOutput? speechOutput,
    bool? ttsUseAccessibilityStream,
    String? ttsEngine,
    String? ttsLanguage,
    String? ttsVoice,
    int? ttsVolumePercent,
    int? ttsRatePercent,
    int? ttsPitchPercent,
  }) => SpeechSettings(
    speechOutput: speechOutput ?? this.speechOutput,
    ttsUseAccessibilityStream:
        ttsUseAccessibilityStream ?? this.ttsUseAccessibilityStream,
    ttsEngine: ttsEngine ?? this.ttsEngine,
    ttsLanguage: ttsLanguage ?? this.ttsLanguage,
    ttsVoice: ttsVoice ?? this.ttsVoice,
    ttsVolumePercent: ttsVolumePercent ?? this.ttsVolumePercent,
    ttsRatePercent: ttsRatePercent ?? this.ttsRatePercent,
    ttsPitchPercent: ttsPitchPercent ?? this.ttsPitchPercent,
  );
}

final speechSettingsProvider =
    NotifierProvider<SpeechSettingsNotifier, SpeechSettings>(
      SpeechSettingsNotifier.new,
    );

class SpeechSettingsNotifier extends PrefsNotifier<SpeechSettings> {
  @override
  SpeechSettings build() {
    final stored = prefs.getString('speech_output');
    final legacy = (prefs.getBool('tts_enabled') ?? true)
        ? SpeechOutput.screenReader
        : SpeechOutput.none;
    return SpeechSettings(
      speechOutput: stored == null ? legacy : SpeechOutput.fromName(stored),
      ttsUseAccessibilityStream:
          prefs.getBool('tts_accessibility_stream') ?? false,
      ttsEngine: prefs.getString('tts_engine') ?? '',
      ttsLanguage: prefs.getString('tts_language') ?? '',
      ttsVoice: prefs.getString('tts_voice') ?? '',
      ttsVolumePercent: prefs.getInt('tts_volume_percent') ?? 100,
      ttsRatePercent: prefs.getInt('tts_rate_percent') ?? 100,
      ttsPitchPercent: prefs.getInt('tts_pitch_percent') ?? 100,
    );
  }

  void setSpeechOutput(SpeechOutput output) => saveString(
    'speech_output',
    output.name,
    (s) => s.copyWith(speechOutput: output),
  );

  void setTtsUseAccessibilityStream(bool v) => saveBool(
    'tts_accessibility_stream',
    v,
    (s) => s.copyWith(ttsUseAccessibilityStream: v),
  );

  void setTtsEngine(String engine) {
    unawaited(prefs.setString('tts_engine', engine));
    unawaited(prefs.setString('tts_language', ''));
    unawaited(prefs.setString('tts_voice', ''));
    state = state.copyWith(ttsEngine: engine, ttsLanguage: '', ttsVoice: '');
  }

  void setTtsLanguage(String language) {
    unawaited(prefs.setString('tts_language', language));
    unawaited(prefs.setString('tts_voice', ''));
    state = state.copyWith(ttsLanguage: language, ttsVoice: '');
  }

  void setTtsVoice(String v) =>
      saveString('tts_voice', v, (s) => s.copyWith(ttsVoice: v));

  void setTtsVolumePercent(int v) =>
      saveInt('tts_volume_percent', v, (s) => s.copyWith(ttsVolumePercent: v));

  void setTtsRatePercent(int v) =>
      saveInt('tts_rate_percent', v, (s) => s.copyWith(ttsRatePercent: v));

  void setTtsPitchPercent(int v) =>
      saveInt('tts_pitch_percent', v, (s) => s.copyWith(ttsPitchPercent: v));
}

class EventFeedbackSettings {
  const EventFeedbackSettings({
    this.soundsEnabled = true,
    this.disabledSounds = const {},
    this.eventVolumePercent = 100,
    this.vibrationEnabled = true,
  });

  final bool soundsEnabled;
  final Set<SoundEvent> disabledSounds;
  final int eventVolumePercent;
  final bool vibrationEnabled;

  bool soundEnabled(SoundEvent event) =>
      soundsEnabled && !disabledSounds.contains(event);

  EventFeedbackSettings copyWith({
    bool? soundsEnabled,
    Set<SoundEvent>? disabledSounds,
    int? eventVolumePercent,
    bool? vibrationEnabled,
  }) => EventFeedbackSettings(
    soundsEnabled: soundsEnabled ?? this.soundsEnabled,
    disabledSounds: disabledSounds ?? this.disabledSounds,
    eventVolumePercent: eventVolumePercent ?? this.eventVolumePercent,
    vibrationEnabled: vibrationEnabled ?? this.vibrationEnabled,
  );
}

final eventFeedbackSettingsProvider =
    NotifierProvider<EventFeedbackSettingsNotifier, EventFeedbackSettings>(
      EventFeedbackSettingsNotifier.new,
    );

class EventFeedbackSettingsNotifier
    extends PrefsNotifier<EventFeedbackSettings> {
  @override
  EventFeedbackSettings build() => EventFeedbackSettings(
    soundsEnabled: prefs.getBool('sounds_enabled') ?? true,
    disabledSounds: {
      for (final event in SoundEvent.values)
        if (!(prefs.getBool('sound.${event.name}') ?? true)) event,
    },
    eventVolumePercent: prefs.getInt('event_volume_percent') ?? 100,
    vibrationEnabled: prefs.getBool('vibration_enabled') ?? true,
  );

  void setSoundsEnabled(bool v) =>
      saveBool('sounds_enabled', v, (s) => s.copyWith(soundsEnabled: v));

  void setVibrationEnabled(bool v) =>
      saveBool('vibration_enabled', v, (s) => s.copyWith(vibrationEnabled: v));

  void setEventVolumePercent(int v) => saveInt(
    'event_volume_percent',
    v,
    (s) => s.copyWith(eventVolumePercent: v),
  );
}
