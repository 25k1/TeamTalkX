import 'dart:async';

import 'events.dart';
import 'models.dart';

class ServerState {
  final _channels = <int, TtChannel>{};
  final _users = <int, TtUser>{};
  final _files = <int, TtRemoteFile>{};
  final _changes = StreamController<int>.broadcast();
  int _revision = 0;
  bool _notifyScheduled = false;

  int myUserId = 0;

  int myUserRights = 0;
  TtServerInfo serverInfo = const TtServerInfo(name: '', motd: '');

  bool hasRight(int userRight) => (myUserRights & userRight) != 0;

  Stream<int> get changes => _changes.stream;

  Map<int, TtChannel> get channels => Map.unmodifiable(_channels);
  Map<int, TtUser> get users => Map.unmodifiable(_users);

  int get joinedChannelId => _users[myUserId]?.channelId ?? 0;

  List<TtUser> usersInChannel(int channelId) =>
      _users.values.where((u) => u.channelId == channelId).toList()..sort(
        (a, b) =>
            a.displayName.toLowerCase().compareTo(b.displayName.toLowerCase()),
      );

  List<TtRemoteFile> filesInChannel(int channelId) =>
      _files.values.where((f) => f.channelId == channelId).toList()..sort(
        (a, b) => a.fileName.toLowerCase().compareTo(b.fileName.toLowerCase()),
      );

  List<TtChannel> childrenOf(int channelId) =>
      _channels.values.where((c) => c.parentId == channelId).toList()
        ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));

  TtChannel? get rootChannel {
    for (final channel in _channels.values) {
      if (channel.isRoot) return channel;
    }
    return null;
  }

  void apply(TtEvent event) {
    switch (event) {
      case MyselfLoggedInEvent(:final userId, :final userRights):
        myUserId = userId;
        myUserRights = userRights;
      case UserLoggedInEvent(:final user):
      case UserUpdateEvent(:final user):
      case UserJoinedEvent(:final user):
      case UserStateChangeEvent(:final user):
        _users[user.id] = user;
      case UserLeftEvent(:final user):
        _users[user.id] = user;
      case UserLoggedOutEvent(:final user):
        _users.remove(user.id);
      case ChannelNewEvent(:final channel):
        _channels[channel.id] = channel;
      case ChannelUpdateEvent(:final channel):
        final existing = _channels[channel.id];
        _channels[channel.id] = existing == null
            ? channel
            : TtChannel(
                id: channel.id,
                parentId: existing.parentId,
                name: channel.name,
                topic: channel.topic,
                hasPassword: channel.hasPassword,
                maxUsers: channel.maxUsers,
                channelType: channel.channelType,
              );
      case ChannelRemoveEvent(:final channel):
        _channels.remove(channel.id);
      case FileNewEvent(:final file):
        _files[file.fileId] = file;
      case FileRemoveEvent(:final file):
        _files.remove(file.fileId);
      case ServerUpdateEvent(:final info):
        serverInfo = info;
      case ConLostEvent() || MyselfLoggedOutEvent():
        clear();
      default:
        return;
    }
    _notify();
  }

  void clear() {
    _channels.clear();
    _users.clear();
    _files.clear();
    myUserId = 0;
    myUserRights = 0;
    serverInfo = const TtServerInfo(name: '', motd: '');
    _notify();
  }

  void _notify() {
    if (_notifyScheduled || _changes.isClosed) return;
    _notifyScheduled = true;
    scheduleMicrotask(() {
      _notifyScheduled = false;
      if (!_changes.isClosed) _changes.add(++_revision);
    });
  }

  void dispose() {
    unawaited(_changes.close());
  }
}
