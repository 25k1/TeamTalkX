import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:teamtalkx/src/app/connection/connection_providers.dart';
import 'package:teamtalkx/src/app/settings/settings_providers.dart';
import 'package:teamtalkx/src/app/voice/audio_output.dart';
import 'package:teamtalkx/src/domain/audio_output.dart';
import 'package:teamtalkx/src/domain/server_state.dart';
import 'package:teamtalkx/src/domain/teamtalk_client.dart';

import 'support/fake_platform.dart';

class _FakeClient implements TeamTalkClient {
  ({bool voiceCall, int deviceId})? output;

  @override
  final ServerState state = ServerState();
  @override
  void setAudioOutput({required bool voiceCall, int deviceId = 0}) =>
      output = (voiceCall: voiceCall, deviceId: deviceId);
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeConnection extends SessionController {
  _FakeConnection(this._initial);
  final ConnectionState _initial;
  @override
  ConnectionState build() => _initial;
  void set(ConnectionState next) => state = next;
}

const _speaker = AudioOutputDevice(
  id: 2,
  kind: AudioOutputKind.speaker,
  name: 'SM-S931B',
);
const _earpiece = AudioOutputDevice(
  id: 1,
  kind: AudioOutputKind.earpiece,
  name: 'SM-S931B',
);
const _headset = AudioOutputDevice(
  id: 7,
  kind: AudioOutputKind.bluetooth,
  name: 'Buds',
);

void main() {
  late FakePlatform platform;
  late _FakeClient client;

  Future<ProviderContainer> start(
    Map<String, Object> prefs, {
    ConnectionState connection = const LoggedIn(1),
  }) async {
    SharedPreferences.setMockInitialValues(prefs);
    final c = ProviderContainer(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(
          await SharedPreferences.getInstance(),
        ),
        teamTalkClientProvider.overrideWithValue(client),
        connectionProvider.overrideWith(() => _FakeConnection(connection)),
        ...platform.overrides,
      ],
    );
    addTearDown(c.dispose);
    c.listen(audioOutputControllerProvider, (_, _) {});
    await pumpEventQueue();
    return c;
  }

  setUp(() {
    platform = FakePlatform();
    platform.routing.devices = [_earpiece, _speaker, _headset];
    client = _FakeClient();
    addTearDown(platform.dispose);
  });

  test('media mode plays to the picked device directly', () async {
    await start({'output_route': 'bluetooth'});

    expect(client.output, (voiceCall: false, deviceId: 7));
    expect(platform.sounds.output, (voiceCall: false, deviceId: 7));
    expect(platform.routing.communication.last.on, isFalse);
  });

  test('voice-call mode routes the call through the system', () async {
    await start({'audio_mode': 'voiceCall', 'output_route': 'earpiece'});

    expect(client.output, (voiceCall: true, deviceId: 0));
    expect(platform.routing.communication.last, (on: true, deviceId: 1));
  });

  test('the earpiece only takes calls; media goes automatic', () async {
    await start({'output_route': 'earpiece'});
    expect(client.output, (voiceCall: false, deviceId: 0));
  });

  test('a route whose device is gone falls back to automatic', () async {
    platform.routing.devices = [_earpiece, _speaker];
    final c = await start({'output_route': 'bluetooth'});
    expect(client.output?.deviceId, 0);

    platform.routing.devices = [_earpiece, _speaker, _headset];
    platform.routing.changed.add(null);
    await pumpEventQueue();
    c.read(audioOutputControllerProvider);
    expect(client.output?.deviceId, 7);
  });

  test('call mode is only on while connected', () async {
    final c = await start({
      'audio_mode': 'voiceCall',
    }, connection: const Disconnected());
    expect(platform.routing.communication.last.on, isFalse);

    (c.read(connectionProvider.notifier) as _FakeConnection).set(
      const LoggedIn(1),
    );
    await pumpEventQueue();
    expect(platform.routing.communication.last.on, isTrue);
  });

  test('the mode and route are remembered', () async {
    final c = await start({});
    c.read(settingsProvider.notifier)
      ..setVoiceCallMode(true)
      ..setOutputRoute(AudioOutputKind.wired);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('audio_mode'), 'voiceCall');
    expect(prefs.getString('output_route'), 'wired');
    c.read(settingsProvider.notifier).setOutputRoute(null);
    expect(prefs.getString('output_route'), isNull);
  });
}
