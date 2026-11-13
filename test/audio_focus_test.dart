import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:teamtalkx/src/app/connection/connection_providers.dart';
import 'package:teamtalkx/src/app/settings/settings_providers.dart';
import 'package:teamtalkx/src/app/voice/audio_focus.dart';
import 'package:teamtalkx/src/app/voice/call_handler.dart';
import 'package:teamtalkx/src/app/voice/output_interruption.dart';
import 'package:teamtalkx/src/domain/events.dart';
import 'package:teamtalkx/src/domain/models.dart';
import 'package:teamtalkx/src/domain/tt_types.dart';
import 'package:teamtalkx/src/platform/interruptions.dart';

import 'support/fake_platform.dart';
import 'support/fake_voice_client.dart';

class _FakeConnection extends SessionController {
  @override
  ConnectionState build() => const LoggedIn(0);
}

TtUser _other({int state = 0}) => TtUser(
  id: 8,
  username: '',
  nickname: 'Ann',
  statusMessage: '',
  channelId: 1,
  userState: state,
  userType: 1,
  clientName: '',
);

void main() {
  late FakePlatform platform;
  late FakeVoiceClient client;
  late ProviderContainer c;

  Future<void> setUpWith(Map<String, Object> prefs) async {
    SharedPreferences.setMockInitialValues({'speech_output': 'tts', ...prefs});
    final shared = await SharedPreferences.getInstance();
    platform = FakePlatform();
    client = FakeVoiceClient()..addMe();
    client.state.apply(UserLoggedInEvent(_other()));
    c = ProviderContainer(
      overrides: [
        ...platform.overrides,
        sharedPreferencesProvider.overrideWithValue(shared),
        teamTalkClientProvider.overrideWithValue(client),
        connectionProvider.overrideWith(_FakeConnection.new),
      ],
    );
    c
      ..listen(audioFocusControllerProvider, (_, _) {})
      ..listen(callHandlerProvider, (_, _) {});
    await pumpEventQueue();
    addTearDown(() async {
      c.dispose();
      await platform.dispose();
      await client.close();
    });
  }

  OutputEffect? effect() => c.read(outputInterruptionProvider);
  List<String> focusCalls() =>
      platform.interruptions.calls.where((x) => x.contains('uck')).toList();

  Future<void> otherApp({required bool playing}) async {
    platform.interruptions.otherPlaying.add(playing);
    await pumpEventQueue();
  }

  Future<void> annTalks({required bool talking}) async {
    final ann = _other(state: talking ? UserStates.voice : 0);
    client.state.apply(UserStateChangeEvent(ann));
    client.eventController.add(UserStateChangeEvent(ann));
    await pumpEventQueue();
  }

  test('by default another app changes nothing', () async {
    await setUpWith(const {});
    await otherApp(playing: true);
    expect(effect(), isNull);
  });

  test('"duck" lowers TeamTalkX while another app plays', () async {
    await setUpWith(const {'focus_loss_policy': 'duck'});
    await otherApp(playing: true);
    expect(effect(), OutputEffect.duck);

    await otherApp(playing: false);
    expect(effect(), OutputEffect.duck, reason: 'waits out short gaps');
    await Future<void>.delayed(
      otherAppHang + const Duration(milliseconds: 100),
    );
    expect(effect(), isNull);
  });

  test('"mute" mutes TeamTalkX while another app plays', () async {
    await setUpWith(const {'focus_loss_policy': 'mute'});
    await otherApp(playing: true);
    expect(effect(), OutputEffect.mute);
  });

  test('ducking others for voice only while someone talks', () async {
    await setUpWith(const {'duck_others_voice': true});
    expect(focusCalls(), isEmpty);

    await annTalks(talking: true);
    expect(focusCalls(), ['duckOthers']);

    await annTalks(talking: false);
    expect(focusCalls(), ['duckOthers'], reason: 'holds between words');
    await Future<void>.delayed(duckHang + const Duration(milliseconds: 100));
    expect(focusCalls(), ['duckOthers', 'stopDuckingOthers']);
  });

  test('ducking others for event sounds', () async {
    await setUpWith(const {'duck_others_events': true});
    await annTalks(talking: true);
    expect(focusCalls(), isEmpty, reason: 'voice ducking is off');

    platform.sounds.playingController.add(true);
    await pumpEventQueue();
    expect(focusCalls(), ['duckOthers']);
  });

  test('while ducking others the policy steps aside', () async {
    await setUpWith(const {
      'focus_loss_policy': 'mute',
      'duck_others_voice': true,
    });
    await otherApp(playing: true);
    expect(effect(), OutputEffect.mute);

    await annTalks(talking: true);
    expect(effect(), isNull);

    platform.interruptions.focus.add(FocusChange.lost);
    await pumpEventQueue();
    expect(effect(), OutputEffect.mute, reason: 'the other app took over');
    expect(focusCalls(), ['duckOthers'], reason: "doesn't take it back");

    await annTalks(talking: false);
    await annTalks(talking: true);
    expect(focusCalls(), ['duckOthers', 'duckOthers']);
  });

  test('TalkBack lowers TeamTalkX while it ducks others (D85a)', () async {
    await setUpWith(const {'duck_others_voice': true});
    await annTalks(talking: true);
    platform.interruptions.focus.add(FocusChange.ducked);
    await pumpEventQueue();
    expect(effect(), OutputEffect.duck);

    platform.interruptions.focus.add(FocusChange.regained);
    await pumpEventQueue();
    expect(effect(), isNull);
  });

  test('"keep full volume" ignores TalkBack (D85a)', () async {
    await setUpWith(const {
      'duck_others_voice': true,
      'keep_volume_under_talkback': true,
    });
    await annTalks(talking: true);
    platform.interruptions.focus.add(FocusChange.ducked);
    await pumpEventQueue();
    expect(effect(), isNull);
  });

  test('no ducking of others during a call', () async {
    await setUpWith(const {'duck_others_voice': true});
    platform.interruptions.call.add(CallState.active);
    await pumpEventQueue();
    await annTalks(talking: true);
    expect(focusCalls(), isEmpty);
  });
}
