import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:teamtalkx/src/app/channels/channel_tree_providers.dart';
import 'package:teamtalkx/src/app/connection/connection_providers.dart';
import 'package:teamtalkx/src/app/settings/settings_providers.dart';
import 'package:teamtalkx/src/domain/events.dart';
import 'package:teamtalkx/src/domain/models.dart';
import 'package:teamtalkx/src/domain/server_state.dart';
import 'package:teamtalkx/src/domain/teamtalk_client.dart';

class _FakeClient implements TeamTalkClient {
  _FakeClient(this._state);
  final ServerState _state;
  @override
  ServerState get state => _state;
  @override
  Stream<TtEvent> get events => const Stream.empty();
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

TtChannel _chan(int id, int parent, String name) => TtChannel(
  id: id,
  parentId: parent,
  name: name,
  topic: '',
  hasPassword: false,
  maxUsers: 100,
  channelType: 0,
);

TtUser _me(int id, int channelId) => TtUser(
  id: id,
  username: 'me',
  nickname: 'me',
  statusMessage: '',
  channelId: channelId,
  userState: 0,
  userType: 2,
  clientName: '',
);

void main() {
  test('subchannel created under joined channel appears in the tree', () async {
    SharedPreferences.setMockInitialValues(const {});
    final prefs = await SharedPreferences.getInstance();

    final state = ServerState();
    state.apply(const MyselfLoggedInEvent(1));
    state.apply(ChannelNewEvent(_chan(1, 0, '')));
    state.apply(ChannelNewEvent(_chan(5, 1, 'X')));
    state.apply(UserJoinedEvent(_me(1, 5)));
    state.apply(ChannelNewEvent(_chan(10, 5, 'Y')));

    final container = ProviderContainer(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(prefs),
        teamTalkClientProvider.overrideWith((ref) => _FakeClient(state)),
      ],
    );
    addTearDown(container.dispose);

    final entries = container.read(channelTreeProvider);
    final ids = entries.whereType<ChannelEntry>().map((e) => e.channel.id);
    expect(ids, contains(10), reason: 'subchannel Y should render; got $ids');
  });

  test('channel update with parentId 0 does not orphan the channel', () {
    final state = ServerState();
    state.apply(ChannelNewEvent(_chan(1, 0, '')));
    state.apply(ChannelNewEvent(_chan(5, 1, 'X')));
    state.apply(ChannelNewEvent(_chan(10, 5, 'Y')));
    state.apply(ChannelUpdateEvent(_chan(10, 0, 'Y')));

    expect(state.channels[10]!.parentId, 5);
    expect(state.childrenOf(5).map((c) => c.id), contains(10));
  });
}
