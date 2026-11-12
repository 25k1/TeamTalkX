import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'channels/channel_rights_watch.dart';
import 'chat/chat_providers.dart';
import 'chat/pm_notification_routing.dart';
import 'chat/pm_providers.dart';
import 'recording/recording_controller.dart';
import 'servers/bearware_login.dart';
import 'servers/server_list_providers.dart';
import 'users/user_config.dart';
import 'voice/audio_focus.dart';
import 'voice/audio_output.dart';
import 'voice/call_handler.dart';
import 'voice/foreground_actions.dart';
import 'voice/headset_watch.dart';
import 'voice/voice_providers.dart';
import 'voice/volume_controller.dart';

void startAppServices(ProviderContainer container) {
  container
    ..read(serverListProvider)
    ..read(bearwareAccountProvider)
    ..read(pmProvider)
    ..read(channelRightsWatchProvider)
    ..read(userConfigApplyProvider)
    ..read(volumeControllerProvider)
    ..read(audioOutputControllerProvider)
    ..read(callHandlerProvider)
    ..read(audioFocusControllerProvider)
    ..read(headsetWatchProvider)
    ..read(noiseSuppressionApplyProvider)
    ..read(chatProvider)
    ..read(pmNotificationRepliesProvider)
    ..read(foregroundActionsProvider)
    ..read(recordingProvider);
}
