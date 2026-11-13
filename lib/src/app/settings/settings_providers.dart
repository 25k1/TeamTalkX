import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'audio_settings.dart';
import 'behavior_settings.dart';
import 'profile_settings.dart';
import 'speech_settings.dart';

export 'audio_settings.dart';
export 'behavior_settings.dart';
export 'prefs_notifier.dart';
export 'profile_settings.dart';
export 'settings_types.dart';
export 'speech_settings.dart';

void invalidateAllSettings(Ref ref) => ref
  ..invalidate(profileSettingsProvider)
  ..invalidate(appearanceSettingsProvider)
  ..invalidate(speechSettingsProvider)
  ..invalidate(eventSoundSettingsProvider)
  ..invalidate(playbackSettingsProvider)
  ..invalidate(microphoneSettingsProvider)
  ..invalidate(keySettingsProvider)
  ..invalidate(interruptionSettingsProvider)
  ..invalidate(connectionSettingsProvider)
  ..invalidate(serverListSettingsProvider)
  ..invalidate(chatSettingsProvider);
