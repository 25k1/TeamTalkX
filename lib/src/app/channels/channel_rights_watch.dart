import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/events.dart';
import '../../domain/models.dart';
import '../../l10n/l10n.dart';
import '../announcer.dart';
import '../connection/client_events.dart';
import '../connection/connection_providers.dart';
import '../settings/locale_providers.dart';

final channelRightsWatchProvider = Provider<void>((ref) {
  final operators = <int, Set<int>>{};
  bool? mayTalk;
  bool? mayStream;

  void announce(String Function(AppLocalizations l10n) text) => ref
      .read(announcerProvider)
      .announce(text(ref.read(appLocalizationsProvider)));

  void checkTransmit(TtChannel channel, {required bool joined}) {
    final client = ref.read(teamTalkClientProvider);
    final me = client.state.myUserId;
    if (client.state.joinedChannelId != channel.id) return;
    final talk = channel.mayTransmit(me, channel.voiceUsers);
    final stream = channel.mayTransmit(me, channel.mediaFileUsers);
    if (joined) {
      if (!talk) announce((l) => l.transmitYouMayNotTalk);
    } else {
      if (mayTalk != null && talk != mayTalk) {
        announce(
          (l) => (talk ? l.transmitYouMayTalk : l.transmitYouMayNotTalk),
        );
      }
      if (mayStream != null && stream != mayStream) {
        announce(
          (l) => (stream ? l.transmitYouMayStream : l.transmitYouMayNotStream),
        );
      }
    }
    mayTalk = talk;
    mayStream = stream;
  }

  void checkOperators(TtChannel channel) {
    final before = operators[channel.id];
    operators[channel.id] = channel.operators;
    if (before == null) return;
    final client = ref.read(teamTalkClientProvider);
    final state = client.state;
    final me = state.myUserId;
    final name = channel.isRoot ? '/' : channel.name;
    for (final id in {...before, ...channel.operators}) {
      final gained = channel.operators.contains(id);
      if (gained == before.contains(id)) continue;
      if (id == me) {
        announce(
          (l) => (gained ? l.operatorYouGained(name) : l.operatorYouLost(name)),
        );
      } else if (channel.id == state.joinedChannelId) {
        final user = state.users[id]?.displayName;
        if (user == null) continue;
        announce(
          (l) =>
              (gained ? l.operatorUserGained(user) : l.operatorUserLost(user)),
        );
      }
    }
  }

  ref.listenClientEvents((event) {
    switch (event) {
      case ChannelNewEvent(:final channel):
        operators[channel.id] = channel.operators;
      case ChannelUpdateEvent(:final channel):
        checkOperators(channel);
        checkTransmit(channel, joined: false);
      case ChannelRemoveEvent(:final channel):
        operators.remove(channel.id);
      case UserJoinedEvent(:final user):
        final state = ref.read(teamTalkClientProvider).state;
        if (user.id != state.myUserId) break;
        mayTalk = null;
        mayStream = null;
        final channel = state.channels[user.channelId];
        if (channel != null) checkTransmit(channel, joined: true);
      case ConLostEvent() || MyselfLoggedOutEvent():
        operators.clear();
        mayTalk = null;
        mayStream = null;
      default:
        break;
    }
  });
});
