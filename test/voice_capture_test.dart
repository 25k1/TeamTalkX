import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:teamtalkx/src/app/connection/connection_providers.dart';
import 'package:teamtalkx/src/app/settings/settings_providers.dart';
import 'package:teamtalkx/src/app/voice/voice_providers.dart';
import 'package:teamtalkx/src/domain/capture_settings.dart';
import 'package:teamtalkx/src/domain/events.dart';
import 'package:teamtalkx/src/domain/server_state.dart';
import 'package:teamtalkx/src/domain/teamtalk_client.dart';

import 'support/fake_platform.dart';

class _FakeClient implements TeamTalkClient {
  final eventController = StreamController<TtEvent>.broadcast();
  final voiceController = StreamController<bool>.broadcast(sync: true);
  final starts = <(int, int, int)>[];
  final transmits = <({bool transmit, bool flush})>[];
  final settings = <CaptureSettings>[];
  int resets = 0;

  @override
  final ServerState state = ServerState();
  @override
  Stream<TtEvent> get events => eventController.stream;
  @override
  bool get isVoiceTransmitting => false;
  @override
  int beginAudioInput() => 1;
  @override
  void endAudioInput() {}
  @override
  void configureCapture(CaptureSettings s) => settings.add(s);
  @override
  void startCapture({
    required int audioSource,
    required int sampleRate,
    required int channels,
  }) => starts.add((audioSource, sampleRate, channels));
  @override
  void stopCapture() {}
  @override
  void setCaptureTransmit(
    int streamId, {
    required bool transmit,
    bool flushPreRoll = false,
    bool voiceActive = false,
  }) => transmits.add((transmit: transmit, flush: flushPreRoll));
  @override
  Stream<bool> get captureVoice => voiceController.stream;
  @override
  void resetCapture() => resets++;
  @override
  bool setVoiceActivation({required bool enabled}) => true;
  @override
  bool setVoiceActivationLevel(int level) => true;
  @override
  bool setVoiceTransmission({required bool enabled}) => true;
  @override
  void applyLocalEvent(TtEvent event) => eventController.add(event);
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);

  Future<void> close() async {
    await eventController.close();
    await voiceController.close();
  }
}

void main() {
  late FakePlatform platform;
  late _FakeClient client;
  late ProviderContainer c;

  VoiceNotifier voice() => c.read(voiceProvider.notifier);

  setUp(() async {
    SharedPreferences.setMockInitialValues({'vad_engine': 'silero'});
    final prefs = await SharedPreferences.getInstance();
    platform = FakePlatform();
    client = _FakeClient();
    c = ProviderContainer(
      overrides: [
        ...platform.overrides,
        sharedPreferencesProvider.overrideWithValue(prefs),
        teamTalkClientProvider.overrideWithValue(client),
      ],
    );
    c.listen(voiceProvider, (_, _) {});
    addTearDown(() async {
      c.dispose();
      await platform.dispose();
      await client.close();
    });
  });

  test('VOX opens the mic with voice detection in the worker', () async {
    voice().setVoiceActivation(enabled: true);
    await pumpEventQueue();

    expect(client.starts, hasLength(1));
    expect(client.settings.last.voiceDetection, isTrue);
    expect(client.settings.last.detector, VoiceDetectorKind.silero);
    expect(client.transmits.last, (transmit: false, flush: false));
  });

  test('a detected voice starts TX and sends the pre-roll once', () async {
    voice().setVoiceActivation(enabled: true);
    await pumpEventQueue();

    client.voiceController.add(true);
    expect(c.read(voiceProvider).txEnabled, isTrue);
    expect(c.read(voiceProvider).voxActive, isTrue);
    expect(client.transmits.last, (transmit: true, flush: true));

    client.voiceController.add(true);
    expect(
      client.transmits.where((t) => t.flush),
      hasLength(1),
      reason: 'the pre-roll is sent once',
    );

    client.voiceController.add(false);
    await Future<void>.delayed(const Duration(milliseconds: 300));
    expect(c.read(voiceProvider).txEnabled, isFalse);
    expect(client.transmits.last, (transmit: false, flush: false));
  });

  test('push-to-talk ignores voice detection', () async {
    voice()
      ..setVoiceActivation(enabled: true)
      ..startTransmission();
    await pumpEventQueue();

    client.voiceController.add(false);
    await Future<void>.delayed(const Duration(milliseconds: 300));

    expect(c.read(voiceProvider).txEnabled, isTrue);
    expect(client.transmits.last, (transmit: true, flush: false));
  });

  test('settings changes reach the worker while capturing', () async {
    voice().setVoiceActivation(enabled: true);
    await pumpEventQueue();

    c.read(microphoneSettingsProvider.notifier).setVadEngine(VadEngine.rnnoise);
    await pumpEventQueue();

    expect(client.settings.last.detector, VoiceDetectorKind.rnnoise);
  });
}
