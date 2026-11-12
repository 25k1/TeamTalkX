import 'package:flutter_test/flutter_test.dart';
import 'package:teamtalkx/src/domain/events.dart';
import 'package:teamtalkx/src/domain/models.dart';
import 'package:teamtalkx/src/domain/server_state.dart';

TtChannel channel(int id, int parentId, String name) => TtChannel(
  id: id,
  parentId: parentId,
  name: name,
  topic: '',
  hasPassword: false,
  maxUsers: 100,
  channelType: 0,
);

TtUser user(int id, String nickname, int channelId) => TtUser(
  id: id,
  username: '',
  nickname: nickname,
  statusMessage: '',
  channelId: channelId,
  userState: 0,
  userType: 1,
  clientName: '',
);

void main() {
  test('builds channel hierarchy and tracks joined channel', () {
    final state = ServerState();
    state.apply(const MyselfLoggedInEvent(10));
    state.apply(ChannelNewEvent(channel(1, 0, '')));
    state.apply(ChannelNewEvent(channel(2, 1, 'B room')));
    state.apply(ChannelNewEvent(channel(3, 1, 'a room')));
    state.apply(UserJoinedEvent(user(10, 'me', 2)));
    state.apply(UserJoinedEvent(user(11, 'other', 2)));

    expect(state.rootChannel?.id, 1);
    expect(state.childrenOf(1).map((c) => c.name), ['a room', 'B room']);
    expect(state.joinedChannelId, 2);
    expect(state.usersInChannel(2).map((u) => u.nickname), ['me', 'other']);
    state.dispose();
  });

  test('user leaving and logging out updates maps', () {
    final state = ServerState();
    state.apply(const MyselfLoggedInEvent(10));
    state.apply(ChannelNewEvent(channel(1, 0, '')));
    state.apply(UserJoinedEvent(user(11, 'other', 1)));
    expect(state.usersInChannel(1), hasLength(1));

    state.apply(UserLeftEvent(1, user(11, 'other', 0)));
    expect(state.usersInChannel(1), isEmpty);
    expect(state.users, contains(11));

    state.apply(UserLoggedOutEvent(user(11, 'other', 0)));
    expect(state.users, isNot(contains(11)));
    state.dispose();
  });

  test('changes coalesces a burst of mutations into one revision', () async {
    final state = ServerState();
    final revisions = <int>[];
    final sub = state.changes.listen(revisions.add);

    state.apply(const MyselfLoggedInEvent(10));
    state.apply(ChannelNewEvent(channel(1, 0, '')));
    state.apply(UserJoinedEvent(user(10, 'me', 1)));
    state.apply(UserLeftEvent(1, user(10, 'me', 0)));
    state.apply(UserJoinedEvent(user(10, 'me', 2)));
    await Future<void>.delayed(Duration.zero);

    expect(revisions, hasLength(1));
    expect(state.joinedChannelId, 2);

    state.apply(UserJoinedEvent(user(10, 'me', 1)));
    await Future<void>.delayed(Duration.zero);
    expect(revisions, hasLength(2));
    expect(
      revisions.toSet(),
      hasLength(2),
      reason: 'each burst is a new revision',
    );

    await sub.cancel();
    state.dispose();
  });

  test('connection lost clears everything', () {
    final state = ServerState();
    state.apply(const MyselfLoggedInEvent(10));
    state.apply(ChannelNewEvent(channel(1, 0, '')));
    state.apply(UserJoinedEvent(user(10, 'me', 1)));
    state.apply(const ConLostEvent());
    expect(state.channels, isEmpty);
    expect(state.users, isEmpty);
    expect(state.myUserId, 0);
    state.dispose();
  });
}
