import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:teamtalkx/src/app/connection/connection_providers.dart';
import 'package:teamtalkx/src/app/settings/settings_providers.dart';
import 'package:teamtalkx/src/app/voice/call_handler.dart';
import 'package:teamtalkx/src/app/voice/output_interruption.dart';
import 'package:teamtalkx/src/app/voice/voice_providers.dart';
import 'package:teamtalkx/src/domain/call_state.dart';
import 'package:teamtalkx/src/domain/models.dart';

import 'support/fake_platform.dart';
import 'support/fake_voice_client.dart';

class _FakeConnection extends SessionController {
  @override
  ConnectionState build() => const LoggedIn(0);

  void set(ConnectionState next) => state = next;
}

void main() {
  late FakePlatform platform;
  late FakeVoiceClient client;
  late ProviderContainer c;

  Future<void> setUpWith(Map<String, Object> prefs) async {
    SharedPreferences.setMockInitialValues({
      'speech_output': 'tts',
      'vad_engine': 'silero',
      ...prefs,
    });
    final shared = await SharedPreferences.getInstance();
    platform = FakePlatform();
    client = FakeVoiceClient()..addMe();
    c = ProviderContainer(
      overrides: [
        ...platform.overrides,
        sharedPreferencesProvider.overrideWithValue(shared),
        teamTalkClientProvider.overrideWithValue(client),
        connectionProvider.overrideWith(_FakeConnection.new),
      ],
    );
    c
      ..listen(voiceProvider, (_, _) {})
      ..listen(callHandlerProvider, (_, _) {});
    addTearDown(() async {
      c.dispose();
      await platform.dispose();
      await client.close();
    });
  }

  Future<void> call(CallState state) async {
    platform.interruptions.call.add(state);
    await pumpEventQueue();
  }

  VoiceNotifier voice() => c.read(voiceProvider.notifier);
  int myMode() => client.state.users[7]!.statusMode;
  String myMessage() => client.state.users[7]!.statusMessage;

  test('monitors calls only while connected', () async {
    await setUpWith(const {});
    expect(platform.interruptions.calls, ['start']);

    (c.read(connectionProvider.notifier) as _FakeConnection).set(
      const Disconnected(),
    );
    await pumpEventQueue();
    expect(platform.interruptions.calls, ['start', 'stop']);
  });

  test('ringing stops transmission, ducks and announces', () async {
    await setUpWith(const {});
    voice().startTransmission();
    expect(c.read(voiceProvider).txEnabled, isTrue);

    await call(CallState.ringing);

    expect(c.read(voiceProvider).txEnabled, isFalse);
    expect(c.read(outputInterruptionProvider), OutputEffect.duck);
    expect(platform.tts.spoken, contains('Incoming call'));
    expect(client.statuses, isEmpty, reason: 'away only once in the call');
  });

  test(
    'a call mutes, releases the mic, sets away and blocks the mic',
    () async {
      await setUpWith(const {});
      voice().setVoiceActivation(enabled: true);
      expect(client.captureStarts, 1);

      await call(CallState.ringing);
      await call(CallState.active);

      expect(c.read(voiceProvider).voxEnabled, isFalse);
      expect(client.captureStops, greaterThanOrEqualTo(1));
      expect(c.read(outputInterruptionProvider), OutputEffect.mute);
      expect(platform.sounds.suppressed, isTrue);
      expect(myMode() & TtStatusMode.away, TtStatusMode.away);
      expect(myMessage(), 'hello', reason: 'no call message: it stays');

      voice().startTransmission();
      expect(c.read(voiceProvider).txEnabled, isFalse);
      expect(
        platform.tts.spoken,
        contains('The microphone is unavailable during a call'),
      );
    },
  );

  test('after the call: output, VOX and status return, TX does not', () async {
    await setUpWith(const {});
    voice().startTransmission();
    await call(CallState.active);
    await call(CallState.idle);

    expect(c.read(outputInterruptionProvider), isNull);
    expect(platform.sounds.suppressed, isFalse);
    expect(c.read(voiceProvider).txEnabled, isFalse);
    expect(myMode() & TtStatusMode.away, 0);
    expect(platform.tts.spoken.last, 'Call ended, transmission off');
  });

  test('voice activation comes back after the call', () async {
    await setUpWith(const {});
    voice().setVoiceActivation(enabled: true);
    await call(CallState.active);
    await call(CallState.idle);

    expect(c.read(voiceProvider).voxEnabled, isTrue);
    expect(platform.tts.spoken.last, 'Call ended');
  });

  test('the call status message is configurable (D138)', () async {
    await setUpWith(const {'call_status_message': 'On the phone'});
    await call(CallState.active);
    expect(myMessage(), 'On the phone');

    await call(CallState.idle);
    expect(myMessage(), 'hello');
  });

  test('a status the user changed during the call stays', () async {
    await setUpWith(const {});
    await call(CallState.active);
    await client.changeStatus(TtStatusMode.question, 'brb');
    await call(CallState.idle);

    expect(myMode(), TtStatusMode.question);
    expect(myMessage(), 'brb');
  });

  test('away can be turned off; the rest still happens', () async {
    await setUpWith(const {'pause_during_calls': false});
    await call(CallState.active);

    expect(client.statuses, isEmpty);
    expect(c.read(outputInterruptionProvider), OutputEffect.mute);
  });

  test('disconnecting mid-call clears the interruption', () async {
    await setUpWith(const {});
    await call(CallState.active);
    (c.read(connectionProvider.notifier) as _FakeConnection).set(
      const Disconnected(),
    );
    await pumpEventQueue();

    expect(c.read(callHandlerProvider), CallState.idle);
    expect(c.read(outputInterruptionProvider), isNull);
    expect(platform.sounds.suppressed, isFalse);
  });

  test('duck and mute from several sources combine', () async {
    await setUpWith(const {});
    c.read(outputInterruptionProvider.notifier)
      ..set(InterruptionSource.otherApp, OutputEffect.duck)
      ..set(InterruptionSource.call, OutputEffect.mute);
    expect(c.read(outputInterruptionProvider), OutputEffect.mute);
    c
        .read(outputInterruptionProvider.notifier)
        .set(InterruptionSource.call, null);
    expect(c.read(outputInterruptionProvider), OutputEffect.duck);
  });
}
