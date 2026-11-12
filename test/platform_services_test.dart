import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:teamtalkx/src/app/announcer.dart';
import 'package:teamtalkx/src/app/app_startup.dart';
import 'package:teamtalkx/src/app/chat/pm_notification_routing.dart';
import 'package:teamtalkx/src/app/connection/connection_providers.dart';
import 'package:teamtalkx/src/app/settings/event_feedback.dart';
import 'package:teamtalkx/src/app/settings/settings_providers.dart';
import 'package:teamtalkx/src/app/voice/voice_providers.dart';
import 'package:teamtalkx/src/domain/capture_settings.dart';
import 'package:teamtalkx/src/domain/events.dart';
import 'package:teamtalkx/src/domain/models.dart';
import 'package:teamtalkx/src/domain/server_state.dart';
import 'package:teamtalkx/src/domain/teamtalk_client.dart';
import 'package:teamtalkx/src/platform/foreground_service.dart';

import 'support/fake_platform.dart';

class _FakeClient implements TeamTalkClient {
  final eventController = StreamController<TtEvent>.broadcast();
  final sentPms = <(int, String)>[];
  int audioStreams = 0;

  @override
  final ServerState state = ServerState();
  @override
  Stream<TtEvent> get events => eventController.stream;
  @override
  bool get isConnected => true;
  @override
  bool get isVoiceTransmitting => false;
  @override
  Future<void> sendUserMessage(int userId, String text) async =>
      sentPms.add((userId, text));
  @override
  int beginAudioInput() => ++audioStreams;
  final captureStarts = <(int, int, int)>[];
  int captureStops = 0;
  final transmits = <bool>[];
  final captureSettings = <CaptureSettings>[];
  int captureResets = 0;

  @override
  void configureCapture(CaptureSettings settings) =>
      captureSettings.add(settings);
  @override
  void startCapture({
    required int audioSource,
    required int sampleRate,
    required int channels,
  }) => captureStarts.add((audioSource, sampleRate, channels));
  @override
  void stopCapture() => captureStops++;
  @override
  void setCaptureTransmit(
    int streamId, {
    required bool transmit,
    bool flushPreRoll = false,
    bool voiceActive = false,
  }) => transmits.add(transmit);
  @override
  Stream<bool> get captureVoice => const Stream.empty();
  @override
  void resetCapture() => captureResets++;
  @override
  void endAudioInput() {}
  @override
  bool setVoiceTransmission({required bool enabled}) => true;
  @override
  void applyLocalEvent(TtEvent event) => eventController.add(event);
  @override
  void setAudioOutput({required bool voiceCall, int deviceId = 0}) {}
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  late FakePlatform platform;
  late _FakeClient client;

  Future<ProviderContainer> start([
    Map<String, Object> prefs = const {},
  ]) async {
    SharedPreferences.setMockInitialValues(prefs);
    final sharedPrefs = await SharedPreferences.getInstance();
    final container = ProviderContainer(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(sharedPrefs),
        teamTalkClientProvider.overrideWithValue(client),
        ...platform.overrides,
      ],
    );
    addTearDown(container.dispose);
    startAppServices(container);
    return container;
  }

  setUp(() {
    platform = FakePlatform();
    client = _FakeClient();
    addTearDown(() async {
      await platform.dispose();
      await client.eventController.close();
    });
  });

  test('a reply typed into a PM notification is sent', () async {
    await start();

    platform.pmNotifications.reply.add((7, ' see you '));
    await pumpEventQueue();

    expect(client.sentPms, [(7, 'see you')]);
  });

  test('a received PM shows a notification', () async {
    await start();
    client.state.myUserId = 1;

    client.eventController.add(
      const UserTextMessageEvent(
        TtTextMessage(
          type: TtMsgType.user,
          fromUserId: 9,
          fromUsername: 'ana',
          toUserId: 1,
          channelId: 0,
          text: 'hello',
          more: false,
        ),
      ),
    );
    await pumpEventQueue();

    expect(platform.pmNotifications.shown, [(9, 'ana', 'hello')]);
  });

  test('PM open requests start with the launching notification', () async {
    platform.pmNotifications.launchedFor = 5;
    final container = await start();
    final opened = <int>[];
    final sub = container.read(pmOpenRequestsProvider).listen(opened.add);
    addTearDown(sub.cancel);
    await pumpEventQueue();

    platform.pmNotifications.open
      ..add(7)
      ..add(7);
    await pumpEventQueue();

    expect(opened, [5, 7, 7], reason: 'the same conversation can reopen');
  });

  test('the notification action toggles transmission with the mic', () async {
    final container = await start({
      'custom_input_sample_rate': 48000,
      'custom_input_channels': 1,
    });

    platform.foregroundService.action.add(ForegroundAction.toggleTransmission);
    await pumpEventQueue();

    expect(container.read(voiceProvider).txEnabled, isTrue);
    expect(client.captureStarts.single.$2, 48000);

    platform.foregroundService.action.add(ForegroundAction.toggleTransmission);
    await pumpEventQueue();

    expect(container.read(voiceProvider).txEnabled, isFalse);
    expect(client.captureStops, 1);
  });

  test(
    'announcements use the injected TTS when speech output is TTS',
    () async {
      final container = await start({'speech_output': 'tts'});

      container.read(announcerProvider).announce('Connected');
      await pumpEventQueue();

      expect(platform.tts.spoken, ['Connected']);
    },
  );

  test('voice problems are announced', () async {
    final container = await start({'speech_output': 'tts'});
    container.read(eventFeedbackProvider);

    client.eventController
      ..add(const VoiceProblemEvent(VoiceProblem.serverUnreachable))
      ..add(const VoiceProblemEvent(VoiceProblem.microphoneFailed));
    await pumpEventQueue();

    expect(platform.tts.spoken, [
      contains('not reaching the server'),
      contains('microphone could not be started'),
    ]);
  });
}
