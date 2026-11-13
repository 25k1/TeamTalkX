import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../platform_services.dart';
import '../recording/recording_controller.dart';
import '../settings/locale_providers.dart';
import '../settings/settings_providers.dart';
import '../voice/voice_providers.dart';
import 'connection_providers.dart';
import 'notification_text.dart';

final foregroundNotificationProvider = Provider<void>((ref) {
  final connection = ref.watch(connectionProvider);
  ref.watch(serverStateTickProvider);
  final transmitting = ref.watch(voiceProvider.select((v) => v.txEnabled));
  final recording = ref.watch(recordingProvider) is RecordingActive;
  final keepAwake = ref.watch(
    settingsProvider.select((s) => s.keepAwakeWhileConnected),
  );
  final text = notificationText(ref.watch(appLocalizationsProvider));
  if (connection is! LoggedIn) return;

  final client = ref.read(teamTalkClientProvider);
  final entry = ref.read(connectionProvider.notifier).currentEntry;
  final serverName = entry?.displayName ?? client.state.serverInfo.name;
  final joined = client.state.channels[client.state.joinedChannelId];
  final channelName = (joined == null || joined.isRoot) ? '' : joined.name;

  unawaited(
    ref
        .read(foregroundServiceProvider)
        .update(
          serverName: serverName,
          channelName: channelName,
          text: text,
          transmitting: transmitting,
          recording: recording,
          keepAwake: keepAwake,
        ),
  );
});
