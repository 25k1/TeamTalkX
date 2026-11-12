import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/events.dart';
import '../../domain/models.dart';
import '../../domain/server_state.dart';
import '../announcer.dart';
import '../connection/connection_providers.dart';
import 'event_config.dart';
import 'event_dispatcher.dart';
import 'locale_providers.dart';

final eventFeedbackProvider = Provider<void>((ref) {
  final client = ref.watch(teamTalkClientProvider);
  final announcer = ref.watch(announcerProvider);
  final dispatcher = ref.watch(eventDispatcherProvider);

  final sub = client.events.listen((event) {
    final state = client.state;
    final quiet = ref.read(connectionProvider.notifier).suppressAnnouncements;

    void fire(AppEvent e, {Map<String, String> vars = const {}}) {
      if (quiet) return;
      dispatcher.fire(e, vars: vars);
    }

    switch (event) {
      case UserLoggedInEvent(:final user):
        fire(
          AppEvent.userLoggedIn,
          vars: {..._userVars(user), 'servername': state.serverInfo.name},
        );
      case UserLoggedOutEvent(:final user):
        fire(
          AppEvent.userLoggedOut,
          vars: {..._userVars(user), 'servername': state.serverInfo.name},
        );
      case UserJoinedEvent(:final user):
        if (user.id != state.myUserId) {
          final channel = state.channels[user.channelId];
          if (user.channelId == state.joinedChannelId) {
            fire(AppEvent.userJoined, vars: _userVars(user));
          } else {
            fire(
              AppEvent.userJoinedOther,
              vars: {..._userVars(user), 'channel': _channelName(channel)},
            );
          }
        }
      case UserLeftEvent(:final channelId, :final user):
        if (user.id != state.myUserId) {
          final channel = state.channels[channelId];
          if (channelId == state.joinedChannelId) {
            fire(AppEvent.userLeft, vars: _userVars(user));
          } else {
            fire(
              AppEvent.userLeftOther,
              vars: {..._userVars(user), 'channel': _channelName(channel)},
            );
          }
        }
      case UserTextMessageEvent(:final message):
        _messageFeedback(message, state, dispatcher, quiet);
      case MediaStreamEndedEvent(:final fileName, :final failed):
        final l10n = ref.read(appLocalizationsProvider);
        announcer.announce(
          failed
              ? l10n.mediaStreamReadFailed(fileName)
              : l10n.mediaStreamFinished(fileName),
        );
      case VoiceProblemEvent(:final problem):
        final l10n = ref.read(appLocalizationsProvider);
        announcer.announce(switch (problem) {
          VoiceProblem.serverUnreachable => l10n.voiceProblemServerUnreachable,
          VoiceProblem.playbackFailed => l10n.voiceProblemPlaybackFailed,
          VoiceProblem.microphoneFailed => l10n.voiceProblemMicrophoneFailed,
          VoiceProblem.startFailed => l10n.voiceProblemStartFailed,
        });
      case VoiceActivationEvent(:final active):
        fire(
          active
              ? AppEvent.voiceActivationTriggered
              : AppEvent.voiceActivationReleased,
        );
      case FileNewEvent() || FileRemoveEvent():
        fire(AppEvent.filesUpdated);
      case FileTransferEvent(:final transfer):
        switch (transfer.status) {
          case TtFileTransferStatus.finished:
            final l10n = ref.read(appLocalizationsProvider);
            announcer.announce(
              transfer.inbound
                  ? l10n.eventDownloadCompleted(transfer.remoteFileName)
                  : l10n.eventUploadCompleted(transfer.remoteFileName),
            );
          case TtFileTransferStatus.error:
            announcer.announce(
              ref
                  .read(appLocalizationsProvider)
                  .eventTransferFailed(transfer.remoteFileName),
            );
          default:
            break;
        }
      default:
        break;
    }
  });
  ref.onDispose(sub.cancel);
});

Map<String, String> _userVars(TtUser user) => {
  'nickname': user.displayName,
  'username': user.username,
};

String _channelName(TtChannel? channel) {
  final name = channel?.name ?? 'channel';
  return (name == '/' || name.isEmpty) ? 'root' : name;
}

void _messageFeedback(
  TtTextMessage message,
  ServerState state,
  EventDispatcher dispatcher,
  bool quiet,
) {
  if (quiet) return;
  final fromMe = message.fromUserId == state.myUserId;
  final sender =
      state.users[message.fromUserId]?.displayName ?? message.fromUsername;
  final vars = {'nickname': sender, 'message': message.text};
  switch (message.type) {
    case TtMsgType.channel:
      if (fromMe) {
        dispatcher.fire(AppEvent.channelMessageSent);
      } else {
        dispatcher.fire(AppEvent.channelMessage, vars: vars);
      }
    case TtMsgType.user:
      if (!fromMe) {
        dispatcher.fire(AppEvent.privateMessage, vars: vars);
      }
    case TtMsgType.broadcast:
      dispatcher.fire(AppEvent.broadcastMessage, vars: vars);
    case TtMsgType.custom:
      break;
  }
}
