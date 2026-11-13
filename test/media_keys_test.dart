import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:teamtalkx/src/app/connection/connection_providers.dart';
import 'package:teamtalkx/src/app/keys/press_detector.dart';
import 'package:teamtalkx/src/app/settings/settings_providers.dart';
import 'package:teamtalkx/src/app/voice/hardware_controls.dart';
import 'package:teamtalkx/src/app/voice/voice_providers.dart';
import 'package:teamtalkx/src/domain/events.dart';
import 'package:teamtalkx/src/domain/media_keys.dart';
import 'package:teamtalkx/src/domain/models.dart';

import 'support/fake_platform.dart';
import 'support/fake_voice_client.dart';

class _FakeConnection extends SessionController {
  _FakeConnection(this._initial);
  final ConnectionState _initial;
  @override
  ConnectionState build() => _initial;
  void set(ConnectionState next) => state = next;
}

TtChannel _channel(int id, int parentId, String name) => TtChannel(
  id: id,
  parentId: parentId,
  name: name,
  topic: '',
  hasPassword: false,
  maxUsers: 10,
  channelType: 0,
);

void main() {
  group('KeyBindings', () {
    test('round-trips and skips what it does not know', () {
      final bindings = const KeyBindings()
          .withAction(
            MediaKey.playPause,
            KeyPress.single,
            KeyAction.speakChannel,
          )
          .withAction(MediaKey.next, KeyPress.long, KeyAction.holdToTalk);
      final decoded = KeyBindings.decode('${bindings.encode()};bogus=x;a.b=c');
      expect(decoded, bindings);
      expect(decoded.mappedKeys, {MediaKey.playPause, MediaKey.next});
    });

    test('hold-to-talk is for holds only', () {
      final bindings = const KeyBindings().withAction(
        MediaKey.playPause,
        KeyPress.single,
        KeyAction.holdToTalk,
      );
      expect(bindings.isEmpty, isTrue);
      expect(KeyBindings.decode('playPause.single=holdToTalk').isEmpty, isTrue);
    });

    test('removing an action removes the key', () {
      final bindings = const KeyBindings()
          .withAction(MediaKey.stop, KeyPress.single, KeyAction.speakTalking)
          .withAction(MediaKey.stop, KeyPress.single, null);
      expect(bindings.isEmpty, isTrue);
    });
  });

  group('PressDetector', () {
    late List<String> log;
    PressDetector detector({required bool long}) => PressDetector(
      hasLongPress: (_) => long,
      onPress: (k) => log.add('press'),
      onHoldStart: (k) => log.add('hold'),
      onHoldEnd: (k) => log.add('release'),
      longPress: const Duration(milliseconds: 40),
    );

    setUp(() => log = []);

    test('without a hold action a press acts on key down', () {
      detector(long: false).down(MediaKey.next);
      expect(log, ['press']);
    });

    test('with a hold action a quick release is a press', () async {
      final d = detector(long: true)..down(MediaKey.next);
      expect(log, isEmpty);
      d.up(MediaKey.next);
      expect(log, ['press']);
      await Future<void>.delayed(const Duration(milliseconds: 60));
      expect(log, ['press']);
    });

    test('holding past the threshold is a hold until released', () async {
      final d = detector(long: true)..down(MediaKey.next);
      await Future<void>.delayed(const Duration(milliseconds: 60));
      expect(log, ['hold']);
      d.up(MediaKey.next);
      expect(log, ['hold', 'release']);
    });

    test('a repeated down while held is ignored', () {
      detector(long: false)
        ..down(MediaKey.next)
        ..down(MediaKey.next);
      expect(log, ['press']);
    });
  });

  group('hardware controls', () {
    late FakePlatform platform;
    late FakeVoiceClient client;
    late ProviderContainer c;

    Future<void> setUpWith(String bindings) async {
      SharedPreferences.setMockInitialValues({
        'speech_output': 'tts',
        'vad_engine': 'silero',
        'media_key_bindings': bindings,
      });
      final prefs = await SharedPreferences.getInstance();
      platform = FakePlatform();
      client = FakeVoiceClient()..addMe();
      client.state
        ..apply(ChannelNewEvent(_channel(1, 0, '')))
        ..apply(ChannelNewEvent(_channel(2, 1, 'Lobby')))
        ..apply(ChannelNewEvent(_channel(3, 1, 'Music')));
      c = ProviderContainer(
        overrides: [
          ...platform.overrides,
          sharedPreferencesProvider.overrideWithValue(prefs),
          teamTalkClientProvider.overrideWithValue(client),
          connectionProvider.overrideWith(
            () => _FakeConnection(const LoggedIn(0)),
          ),
        ],
      );
      c
        ..listen(voiceProvider, (_, _) {})
        ..listen(hardwareControlsProvider, (_, _) {});
      await pumpEventQueue();
      addTearDown(() async {
        c.dispose();
        await platform.dispose();
        await client.close();
      });
    }

    test('no mappings: no media session, keys pass through', () async {
      await setUpWith('');
      expect(platform.mediaKeys.configured.last.session, false);
      expect(platform.mediaKeys.configured.last.mapped, <MediaKey>{});
    });

    test('a mapping holds the session and takes that key', () async {
      await setUpWith('playPause.single=toggleTransmission');
      expect(platform.mediaKeys.configured.last.session, true);
      expect(platform.mediaKeys.configured.last.mapped, {MediaKey.playPause});

      platform.mediaKeys.press(MediaKey.playPause);
      expect(c.read(voiceProvider).txEnabled, isTrue);
      platform.mediaKeys.press(MediaKey.next);
      expect(c.read(voiceProvider).txEnabled, isTrue, reason: 'unmapped');
    });

    test('the session goes when disconnected', () async {
      await setUpWith('playPause.single=toggleTransmission');
      (c.read(connectionProvider.notifier) as _FakeConnection).set(
        const Disconnected(),
      );
      await pumpEventQueue();
      expect(platform.mediaKeys.configured.last.session, isFalse);
    });

    test('hold to talk transmits while the key is held', () async {
      await setUpWith('playPause.long=holdToTalk');
      platform.mediaKeys.key.add((key: MediaKey.playPause, down: true));
      await Future<void>.delayed(const Duration(milliseconds: 600));
      expect(c.read(voiceProvider).txEnabled, isTrue);
      platform.mediaKeys.key.add((key: MediaKey.playPause, down: false));
      expect(c.read(voiceProvider).txEnabled, isFalse);
    });

    test('channel keys move through the tree and join', () async {
      await setUpWith(
        'next.single=nextChannel;previous.single=previousChannel;'
        'stop.single=joinSelectedChannel',
      );
      platform.mediaKeys.press(MediaKey.next);
      expect(platform.tts.spoken.last, 'Lobby, no users');
      platform.mediaKeys.press(MediaKey.next);
      expect(platform.tts.spoken.last, 'Music, no users');
      platform.mediaKeys.press(MediaKey.next);
      expect(platform.tts.spoken.last, 'Root channel, 1 user');
      platform.mediaKeys.press(MediaKey.previous);
      expect(platform.tts.spoken.last, 'Music, no users');
    });

    test('speaks the channel and who is talking', () async {
      await setUpWith('next.single=speakChannel;previous.single=speakTalking');
      platform.mediaKeys.press(MediaKey.next);
      expect(platform.tts.spoken.last, 'In Root channel, 1 user');
      platform.mediaKeys.press(MediaKey.previous);
      expect(platform.tts.spoken.last, 'Nobody is talking');
    });

    test('the microphone mute stops sending without stopping TX', () async {
      await setUpWith(
        'next.single=toggleMicrophone;playPause.single=toggleTransmission',
      );
      platform.mediaKeys
        ..press(MediaKey.playPause)
        ..press(MediaKey.next);
      expect(c.read(voiceProvider).txEnabled, isTrue);
      expect(c.read(voiceProvider).micMuted, isTrue);
      expect(platform.tts.spoken.last, 'Microphone muted');
      expect(client.transmits.last, isFalse);
    });
  });
}
