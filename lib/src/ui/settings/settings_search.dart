import 'package:flutter/material.dart';

import '../../app/settings/event_config.dart';
import '../../l10n/l10n.dart';
import '../chat/chat_templates_screen.dart';
import '../common/labels.dart';
import '../common/ui.dart';
import '../security/trusted_certificates_screen.dart';
import '../voice/mic_test_screen.dart';
import 'chat_history_screen.dart';
import 'events_screen.dart';
import 'feedback_settings.dart';
import 'media_keys_screen.dart';
import 'settings_screen.dart';

class SettingsSearchEntry {
  const SettingsSearchEntry({
    required this.title,
    required this.path,
    required this.open,
  });

  final String title;

  final String path;

  final void Function(BuildContext context) open;

  bool matches(String query) =>
      title.toLowerCase().contains(query) || path.toLowerCase().contains(query);
}

const _general = 0;
const _audio = 1;
const _voiceActivation = 2;
const _keys = 3;
const _calls = 4;
const _events = 5;
const _chat = 6;
const _recording = 7;
const _serverList = 8;
const _privacy = 9;
const _updates = 10;
const _about = 11;

List<SettingsSearchEntry> settingsIndex(AppLocalizations l10n) {
  final sections = settingsSections();
  List<SettingsSearchEntry> inSection(int index, List<String> titles) {
    final section = sections[index];
    return [
      for (final title in titles)
        SettingsSearchEntry(
          title: title,
          path: section.title(l10n),
          open: section.open,
        ),
    ];
  }

  List<SettingsSearchEntry> inScreen(
    int index,
    String screenTitle,
    Widget screen,
    List<String> titles,
  ) {
    final section = sections[index];
    void open(BuildContext context) {
      section.open(context);
      pushScreen(context, screen);
    }

    return [
      SettingsSearchEntry(
        title: screenTitle,
        path: section.title(l10n),
        open: open,
      ),
      for (final title in titles)
        SettingsSearchEntry(
          title: title,
          path: '${section.title(l10n)} › $screenTitle',
          open: open,
        ),
    ];
  }

  return [
    ...inSection(_general, [
      l10n.languageSetting,
      l10n.settingsTheme,
      l10n.settingsHighContrast,
      l10n.commonNickname,
      l10n.bearwareTitle,
      l10n.settingsRememberedUsers,
      l10n.settingsGender,
      l10n.settingsAutoJoinRoot,
      l10n.settingsBackTwice,
      l10n.settingsKeepAwake,
      l10n.settingsFileExport,
      l10n.settingsFileImport,
      l10n.setupRunAgain,
      l10n.permissionBattery,
    ]),
    ...inSection(_audio, [
      l10n.audioVoiceCallMode,
      l10n.audioSource,
      l10n.audioSampleRate,
      l10n.audioChannels,
      l10n.audioNoiseSuppression,
      l10n.audioAgc,
      l10n.audioMasterVolume,
      l10n.audioMediaVolume,
      l10n.audioNormalize,
      l10n.audioEnhancement,
      l10n.audioBandwidthExtension,
      l10n.audioLossProtection,
      l10n.audioMicGain,
    ]),
    ...inScreen(_audio, l10n.micTestEntry, const MicTestScreen(), const []),
    ...inSection(_voiceActivation, [
      l10n.audioVoiceDetection,
      l10n.audioVoxLevel,
    ]),
    ...inSection(_keys, [l10n.settingsPttKey]),
    ...inScreen(
      _keys,
      l10n.settingsMediaKeys,
      const MediaKeysScreen(),
      const [],
    ),
    ...inSection(_calls, [
      l10n.callsAway,
      l10n.callsStatusMessage,
      l10n.focusPolicyTitle,
      l10n.duckOthersVoice,
      l10n.duckOthersEvents,
      l10n.keepVolumeTalkBack,
    ]),
    ...inSection(_events, [l10n.eventsVibration]),
    ...inScreen(_events, l10n.eventsSpeech, const SpeechSettingsScreen(), [
      l10n.speechSpeakEventsThrough,
      l10n.ttsRate,
      l10n.ttsPitch,
      l10n.ttsVolume,
      l10n.ttsAccessibilityStream,
    ]),
    ...inScreen(_events, l10n.settingsSound, const SoundSettingsScreen(), [
      l10n.soundPlayEvents,
      l10n.soundEventVolume,
      l10n.soundPack,
      l10n.soundPackFolder,
    ]),
    for (final event in AppEvent.values)
      ...inScreen(
        _events,
        event.label(l10n),
        EventEditScreen(event: event),
        const [],
      ),
    ...inScreen(_chat, l10n.settingsChatHistory, const ChatHistoryScreen(), [
      l10n.chatHistoryKeep,
      l10n.chatHistoryClearAll,
    ]),
    ...inScreen(
      _chat,
      l10n.eventsEditChatTemplates,
      const ChatTemplatesScreen(),
      const [],
    ),
    ...inScreen(
      _chat,
      l10n.eventsEditTimestamp,
      const TimestampScreen(),
      const [],
    ),
    ...inSection(_recording, [
      l10n.recordingMode,
      l10n.recordingFormat,
      l10n.recordingFolder,
    ]),
    ...inSection(_serverList, [
      l10n.settingsShowOfficial,
      l10n.settingsShowUnofficial,
    ]),
    ...inScreen(
      _serverList,
      l10n.certificatesTitle,
      const TrustedCertificatesScreen(),
      const [],
    ),
    ...inSection(_privacy, [l10n.diagnosticsExport]),
    ...inSection(_updates, [l10n.updateCheckNow, l10n.updateBetas]),
    ...inSection(_about, [l10n.aboutLicenses]),
  ];
}
