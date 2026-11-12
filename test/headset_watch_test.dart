import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:teamtalkx/src/app/connection/connection_providers.dart';
import 'package:teamtalkx/src/app/settings/settings_providers.dart';
import 'package:teamtalkx/src/app/voice/headset_watch.dart';
import 'package:teamtalkx/src/app/voice/voice_providers.dart';
import 'package:teamtalkx/src/domain/audio_output.dart';

import 'support/fake_platform.dart';
import 'support/fake_voice_client.dart';

class _FakeConnection extends SessionController {
  _FakeConnection(this._initial);
  final ConnectionState _initial;
  @override
  ConnectionState build() => _initial;
}

const _speaker = AudioOutputDevice(
  id: 2,
  kind: AudioOutputKind.speaker,
  name: 'SM-S931B',
);
const _buds = AudioOutputDevice(
  id: 9,
  kind: AudioOutputKind.bluetooth,
  name: 'Buds',
);

void main() {
  late FakePlatform platform;
  late FakeVoiceClient client;
  late ProviderContainer c;

  Future<void> setUpWith({
    ConnectionState connection = const LoggedIn(0),
    List<AudioOutputDevice> devices = const [_speaker, _buds],
  }) async {
    SharedPreferences.setMockInitialValues({
      'speech_output': 'tts',
      'vad_engine': 'silero',
    });
    final prefs = await SharedPreferences.getInstance();
    platform = FakePlatform();
    platform.routing.devices = devices;
    client = FakeVoiceClient()..addMe();
    c = ProviderContainer(
      overrides: [
        ...platform.overrides,
        sharedPreferencesProvider.overrideWithValue(prefs),
        teamTalkClientProvider.overrideWithValue(client),
        connectionProvider.overrideWith(() => _FakeConnection(connection)),
      ],
    );
    c
      ..listen(voiceProvider, (_, _) {})
      ..listen(headsetWatchProvider, (_, _) {});
    await pumpEventQueue();
    addTearDown(() async {
      c.dispose();
      await platform.dispose();
      await client.close();
    });
  }

  Future<void> devicesNow(List<AudioOutputDevice> devices) async {
    platform.routing.devices = devices;
    platform.routing.changed.add(null);
    await pumpEventQueue();
  }

  VoiceNotifier voice() => c.read(voiceProvider.notifier);

  test('unplugging stops transmission and says so', () async {
    await setUpWith();
    voice().startTransmission();
    await devicesNow(const [_speaker]);

    expect(c.read(voiceProvider).txEnabled, isFalse);
    expect(platform.tts.spoken.last, 'Headset disconnected, transmission off');
  });

  test('unplugging turns voice activation off', () async {
    await setUpWith();
    voice().setVoiceActivation(enabled: true);
    await devicesNow(const [_speaker]);

    expect(c.read(voiceProvider).voxEnabled, isFalse);
    expect(platform.tts.spoken.last, 'Headset disconnected, transmission off');
  });

  test('unplugging while silent is only announced', () async {
    await setUpWith();
    await devicesNow(const [_speaker]);
    expect(platform.tts.spoken.last, 'Headset disconnected');
  });

  test('connecting a headset changes nothing', () async {
    await setUpWith(devices: const [_speaker]);
    voice().startTransmission();
    await devicesNow(const [_speaker, _buds]);

    expect(c.read(voiceProvider).txEnabled, isTrue);
    expect(platform.tts.spoken, isNot(contains('Headset disconnected')));
  });

  test('nothing happens while disconnected', () async {
    await setUpWith(connection: const Disconnected());
    await devicesNow(const [_speaker]);
    expect(platform.tts.spoken, isEmpty);
  });
}
