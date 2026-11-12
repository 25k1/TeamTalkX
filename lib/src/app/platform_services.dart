library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../platform/app_updater.dart';
import '../platform/audio_routing.dart';
import '../platform/connectivity.dart';
import '../platform/deep_links.dart';
import '../platform/foreground_service.dart';
import '../platform/interruptions.dart';
import '../platform/media_keys.dart';
import '../platform/native_app_info.dart';
import '../platform/native_export.dart';
import '../platform/native_haptics.dart';
import '../platform/native_hotkey.dart';
import '../platform/native_pm_notifications.dart';
import '../platform/native_tts.dart';
import '../platform/permissions.dart';
import '../platform/recording_folder.dart';
import '../platform/sound_pack_folder.dart';

final ttsProvider = Provider<Tts>((ref) => AndroidTts());

final audioRoutingProvider = Provider<AudioRouting>(
  (ref) => AndroidAudioRouting(),
);

final pmNotificationsProvider = Provider<PmNotifications>(
  (ref) => AndroidPmNotifications(),
);

final foregroundServiceProvider = Provider<ForegroundService>(
  (ref) => AndroidForegroundService(),
);

final hapticsProvider = Provider<Haptics>((ref) => AndroidHaptics());

final hotkeysProvider = Provider<Hotkeys>((ref) => AndroidHotkeys());

final mediaKeysProvider = Provider<MediaKeys>((ref) => AndroidMediaKeys());

final interruptionsProvider = Provider<Interruptions>(
  (ref) => AndroidInterruptions(),
);

final deepLinksProvider = Provider<DeepLinks>((ref) => AndroidDeepLinks());

final downloadsProvider = Provider<Downloads>((ref) => AndroidDownloads());

final appUpdaterProvider = Provider<AppUpdater>((ref) => AndroidAppUpdater());

final soundPackFolderProvider = Provider<SoundPackFolder>(
  (ref) => AndroidSoundPackFolder(),
);

final recordingFolderProvider = Provider<RecordingFolder>(
  (ref) => AndroidRecordingFolder(),
);

final permissionsProvider = Provider<Permissions>(
  (ref) => AndroidPermissions(),
);

final reportStartupDoneProvider = Provider<Future<void> Function()>(
  (ref) => reportFullyDrawn,
);

final connectivityProvider = Provider<Connectivity>(
  (ref) => AndroidConnectivity(),
);
