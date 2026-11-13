import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:teamtalkx/src/app/channels/channel_rights_watch.dart';
import 'package:teamtalkx/src/app/connection/connection_providers.dart';
import 'package:teamtalkx/src/app/settings/settings_providers.dart';
import 'package:teamtalkx/src/app/users/user_config.dart';
import 'package:teamtalkx/src/domain/events.dart';
import 'package:teamtalkx/src/domain/models.dart';
import 'package:teamtalkx/src/domain/tt_types.dart';
import 'package:teamtalkx/src/protocol/command.dart';
import 'package:teamtalkx/src/protocol/wire_models.dart';

import 'support/fake_platform.dart';
import 'support/fake_voice_client.dart';

TtChannel _channel({
  int type = 0,
  Set<int> ops = const {},
  Set<int> voice = const {},
  Set<int> media = const {},
}) => TtChannel(
  id: 1,
  parentId: 0,
  name: '',
  topic: '',
  hasPassword: false,
  maxUsers: 10,
  channelType: type,
  operators: ops,
  voiceUsers: voice,
  mediaFileUsers: media,
);

TtUser _user(int id, String nickname) => TtUser(
  id: id,
  username: '',
  nickname: nickname,
  statusMessage: '',
  channelId: 1,
  userState: 0,
  userType: 1,
  clientName: '',
);

void main() {
  test('channel commands carry operators and transmit lists', () {
    final c = channelFromCommand(
      TtCommand.parse(
        'updatechannel chanid=1 parentid=0 name="" operators=[7,9] '
        'voiceusers=[4095] mediafileusers=[3] type=4',
      ),
    );
    expect(c.operators, {7, 9});
    expect(c.voiceUsers, {TtChannel.freeForAll});
    expect(c.mediaFileUsers, {3});
    expect(c.isClassroom, isTrue);
    final empty = channelFromCommand(
      TtCommand.parse('addchannel chanid=2 parentid=1 name="x"'),
    );
    expect(empty.operators, isEmpty, reason: 'left out means none');
  });

  test('a classroom lists who may talk; other channels who may not', () {
    final classroom = _channel(type: 4, voice: {5});
    expect(classroom.mayTransmit(5, classroom.voiceUsers), isTrue);
    expect(classroom.mayTransmit(6, classroom.voiceUsers), isFalse);
    final open = _channel(type: 4, voice: {TtChannel.freeForAll});
    expect(open.mayTransmit(6, open.voiceUsers), isTrue);
    final ordinary = _channel(voice: {5});
    expect(ordinary.mayTransmit(5, ordinary.voiceUsers), isFalse);
    expect(ordinary.mayTransmit(6, ordinary.voiceUsers), isTrue);
  });

  test('remembered subscriptions from older versions keep broadcasts', () {
    final old = StoredUserConfig.fromJson({
      'username': 'ann',
      'subscriptions': Subscriptions.voice,
    });
    expect(
      old.subscriptions,
      Subscriptions.voice |
          Subscriptions.broadcastMsg |
          Subscriptions.customMsg,
    );
    final saved = StoredUserConfig.fromJson(old.toJson());
    expect(saved.subscriptions, old.subscriptions, reason: 'round-trips');
    final off = StoredUserConfig.fromJson({
      'username': 'ann',
      'subscriptions': Subscriptions.voice,
      'subscriptionsVersion': 2,
    });
    expect(off.subscriptions, Subscriptions.voice);
  });

  group('announcements', () {
    late FakePlatform platform;
    late FakeVoiceClient client;
    late ProviderContainer c;

    setUp(() async {
      SharedPreferences.setMockInitialValues({
        'speech_output': 'tts',
        'app_language': 'english',
      });
      final prefs = await SharedPreferences.getInstance();
      platform = FakePlatform();
      client = FakeVoiceClient()..addMe();
      client.state.apply(UserLoggedInEvent(_user(8, 'Ann')));
      c = ProviderContainer(
        overrides: [
          ...platform.overrides,
          sharedPreferencesProvider.overrideWithValue(prefs),
          teamTalkClientProvider.overrideWithValue(client),
        ],
      );
      c.listen(channelRightsWatchProvider, (_, _) {});
      addTearDown(() async {
        c.dispose();
        await platform.dispose();
        await client.close();
      });
    });

    Future<void> emit(TtEvent event) async {
      client.state.apply(event);
      client.eventController.add(event);
      await pumpEventQueue();
    }

    List<String> spoken() => platform.tts.spoken;

    test('operator changes, mine and in my channel', () async {
      await emit(ChannelNewEvent(_channel()));
      await emit(UserJoinedEvent(_user(7, 'me')));
      expect(spoken(), isEmpty);

      await emit(ChannelUpdateEvent(_channel(ops: {7})));
      expect(spoken().last, 'You are now operator of /');
      await emit(ChannelUpdateEvent(_channel(ops: {7, 8})));
      expect(spoken().last, 'Ann is now operator');
      await emit(ChannelUpdateEvent(_channel(ops: {8})));
      expect(spoken().last, 'You are no longer operator of /');
    });

    test('being let to talk in a classroom', () async {
      await emit(ChannelNewEvent(_channel(type: 4)));
      await emit(UserJoinedEvent(_user(7, 'me')));
      expect(spoken().last, 'You may not talk in this channel');

      await emit(ChannelUpdateEvent(_channel(type: 4, voice: {7})));
      expect(spoken().last, 'You may talk now');
      await emit(ChannelUpdateEvent(_channel(type: 4, voice: {7}, media: {7})));
      expect(spoken().last, 'You may stream media files now');
      await emit(ChannelUpdateEvent(_channel(type: 4, media: {7})));
      expect(spoken().last, 'You may not talk in this channel');
    });

    test('nothing to say on joining an ordinary channel', () async {
      await emit(ChannelNewEvent(_channel()));
      await emit(UserJoinedEvent(_user(7, 'me')));
      expect(spoken(), isEmpty);
    });
  });
}
