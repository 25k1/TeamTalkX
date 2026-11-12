import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/events.dart';
import '../../domain/models.dart';
import '../../domain/server_state.dart';
import '../connection/client_events.dart';
import '../connection/connection_providers.dart';
import '../settings/persisted_notifier.dart';

enum ChannelSort { name, popularity }

final channelSortProvider = NotifierProvider<ChannelSortNotifier, ChannelSort>(
  ChannelSortNotifier.new,
);

class ChannelSortNotifier extends PersistedEnumNotifier<ChannelSort> {
  @override
  String get prefsKey => 'channel_sort';
  @override
  ChannelSort get defaultValue => ChannelSort.name;
  @override
  List<ChannelSort> get values => ChannelSort.values;
}

List<TtChannel> _sortedChildren(
  ServerState state,
  int parentId,
  ChannelSort sort,
) {
  final children = state.channels.values
      .where((c) => c.parentId == parentId)
      .toList();
  int byName(TtChannel a, TtChannel b) =>
      a.name.toLowerCase().compareTo(b.name.toLowerCase());
  switch (sort) {
    case ChannelSort.name:
      children.sort(byName);
    case ChannelSort.popularity:
      children.sort((a, b) {
        final ca = state.usersInChannel(a.id).length;
        final cb = state.usersInChannel(b.id).length;
        return ca == cb ? byName(a, b) : cb - ca;
      });
  }
  return children;
}

List<TtChannel> channelsInTreeOrder(ServerState state, ChannelSort sort) {
  final out = <TtChannel>[];
  void visit(TtChannel channel) {
    out.add(channel);
    _sortedChildren(state, channel.id, sort).forEach(visit);
  }

  final root = state.rootChannel;
  if (root != null) visit(root);
  return out;
}

final expandedChannelProvider = NotifierProvider<ExpandedChannelNotifier, int?>(
  ExpandedChannelNotifier.new,
);

class ExpandedChannelNotifier extends Notifier<int?> {
  @override
  int? build() {
    final client = ref.read(teamTalkClientProvider);
    ref.listenClientEvents((event) {
      switch (event) {
        case UserJoinedEvent(:final user) when user.id == client.state.myUserId:
          state = null;
        case ConLostEvent() || MyselfLoggedOutEvent():
          state = null;
        default:
          break;
      }
    });
    return null;
  }

  void expand(int channelId) => state = channelId;

  void toggle(int channelId, int currentlyExpandedId) {
    if (channelId != currentlyExpandedId) {
      state = channelId;
      return;
    }
    final parentId =
        ref.read(teamTalkClientProvider).state.channels[channelId]?.parentId ??
        0;
    state = parentId == 0 ? -1 : parentId;
  }
}

final effectiveExpandedChannelProvider = Provider<int>((ref) {
  final explicit = ref.watch(expandedChannelProvider);
  ref.watch(serverStateTickProvider);
  if (explicit == null) {
    final state = ref.watch(teamTalkClientProvider).state;
    final joined = state.joinedChannelId;
    return joined != 0 ? joined : (state.rootChannel?.id ?? 0);
  }
  return explicit == -1 ? 0 : explicit;
});

sealed class TreeEntry {
  const TreeEntry();
}

final class ChannelEntry extends TreeEntry {
  const ChannelEntry(
    this.channel,
    this.depth, {
    required this.userCount,
    required this.totalUserCount,
    required this.hasSubchannels,
    required this.isJoined,
    required this.isExpanded,
  });

  final TtChannel channel;
  final int depth;

  final int userCount;

  final int totalUserCount;
  final bool hasSubchannels;
  final bool isJoined;
  final bool isExpanded;
}

final class UserEntry extends TreeEntry {
  const UserEntry(this.user, this.depth, {required this.isMe});

  final TtUser user;
  final int depth;
  final bool isMe;
}

final channelTreeProvider = Provider<List<TreeEntry>>((ref) {
  ref.watch(serverStateTickProvider);
  final state = ref.watch(teamTalkClientProvider).state;
  final expandedId = ref.watch(effectiveExpandedChannelProvider);
  final sort = ref.watch(channelSortProvider);
  final entries = <TreeEntry>[];

  final directCount = <int, int>{};
  for (final u in state.users.values) {
    if (u.channelId != 0) {
      directCount[u.channelId] = (directCount[u.channelId] ?? 0) + 1;
    }
  }
  final childIds = <int, List<int>>{};
  for (final c in state.channels.values) {
    (childIds[c.parentId] ??= []).add(c.id);
  }
  final subtreeTotal = <int, int>{};
  int totalFor(int channelId) {
    final cached = subtreeTotal[channelId];
    if (cached != null) return cached;
    var sum = directCount[channelId] ?? 0;
    for (final child in childIds[channelId] ?? const <int>[]) {
      sum += totalFor(child);
    }
    subtreeTotal[channelId] = sum;
    return sum;
  }

  final ancestors = <int>{};
  var pid = state.channels[expandedId]?.parentId ?? 0;
  while (pid != 0) {
    ancestors.add(pid);
    pid = state.channels[pid]?.parentId ?? 0;
  }

  void addChannel(TtChannel channel, int depth) {
    final users = state.usersInChannel(channel.id);
    entries.add(
      ChannelEntry(
        channel,
        depth,
        userCount: users.length,
        totalUserCount: totalFor(channel.id),
        hasSubchannels: (childIds[channel.id]?.isNotEmpty ?? false),
        isJoined: channel.id == state.joinedChannelId,
        isExpanded: channel.id == expandedId,
      ),
    );
    if (channel.id == expandedId) {
      for (final user in users) {
        entries.add(
          UserEntry(user, depth + 1, isMe: user.id == state.myUserId),
        );
      }
    }
    final showChildren =
        channel.id == expandedId || ancestors.contains(channel.id);
    if (showChildren) {
      for (final child in _sortedChildren(state, channel.id, sort)) {
        addChannel(child, depth + 1);
      }
    }
  }

  final root = state.rootChannel;
  if (root != null) {
    addChannel(root, 0);
  }
  return entries;
});
