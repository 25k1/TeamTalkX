import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:teamtalkx/src/app/app_startup.dart';
import 'package:teamtalkx/src/app/connection/connection_providers.dart';
import 'package:teamtalkx/src/app/settings/event_feedback.dart';
import 'package:teamtalkx/src/app/settings/settings_providers.dart';
import 'package:teamtalkx/src/app/voice/media_stream_providers.dart';
import 'package:teamtalkx/src/domain/events.dart';
import 'package:teamtalkx/src/domain/failure.dart';
import 'package:teamtalkx/src/domain/media_stream.dart';
import 'package:teamtalkx/src/domain/server_state.dart';
import 'package:teamtalkx/src/domain/teamtalk_client.dart';

import 'support/fake_platform.dart';

class _FakeClient implements TeamTalkClient {
  final eventController = StreamController<TtEvent>.broadcast();
  final changes = StreamController<MediaStreamState?>.broadcast();
  MediaStreamState? media;
  final calls = <String>[];
  TtFailure? startFailure;
  ({int volume, bool monitor})? started;

  void emit(MediaStreamState? s) {
    media = s;
    changes.add(s);
  }

  @override
  final ServerState state = ServerState();
  @override
  Stream<TtEvent> get events => eventController.stream;
  @override
  MediaStreamState? get mediaStream => media;
  @override
  Stream<MediaStreamState?> get mediaStreamChanges => changes.stream;
  @override
  Future<void> startStreamingMediaFile(
    String path, {
    required String fileName,
    bool loop = false,
    int volumePercent = 100,
    bool monitor = false,
  }) async {
    if (startFailure case final f?) throw f;
    started = (volume: volumePercent, monitor: monitor);
    emit(
      MediaStreamState(
        fileName: fileName,
        duration: const Duration(minutes: 3, seconds: 20),
        volumePercent: volumePercent,
        monitor: monitor,
      ),
    );
  }

  @override
  void setMediaStreamPaused({required bool paused}) {
    calls.add('paused $paused');
    emit(media?.copyWith(paused: paused));
  }

  @override
  void seekMediaStreamBy(Duration offset) => calls.add('seek $offset');
  @override
  void setMediaStreamLoop({required bool loop}) => calls.add('loop $loop');
  @override
  void setMediaStreamVolume(int percent) => calls.add('volume $percent');
  @override
  void setMediaStreamMonitor({required bool monitor}) =>
      calls.add('monitor $monitor');
  @override
  void stopStreamingMediaFile() {
    calls.add('stop');
    emit(null);
  }

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
    SharedPreferences.setMockInitialValues({'speech_output': 'tts', ...prefs});
    final container = ProviderContainer(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(
          await SharedPreferences.getInstance(),
        ),
        teamTalkClientProvider.overrideWithValue(client),
        ...platform.overrides,
      ],
    );
    addTearDown(container.dispose);
    startAppServices(container);
    container
      ..read(eventFeedbackProvider)
      ..listen(mediaStreamProvider, (_, _) {});
    return container;
  }

  setUp(() {
    platform = FakePlatform();
    client = _FakeClient();
    addTearDown(() async {
      await platform.dispose();
      await client.eventController.close();
      await client.changes.close();
    });
  });

  test('starting uses the remembered volume and monitoring', () async {
    final c = await start({
      'media_stream_volume_percent': 60,
      'media_stream_monitor': true,
    });

    final failure = await c
        .read(mediaStreamProvider.notifier)
        .start('/x/song.mp3', 'song.mp3');
    await pumpEventQueue();

    expect(failure, isNull);
    expect(client.started, (volume: 60, monitor: true));
    expect(c.read(mediaStreamProvider)?.fileName, 'song.mp3');
    expect(platform.tts.spoken.last, contains('song.mp3'));
  });

  test('monitoring is off by default', () async {
    final c = await start();
    await c.read(mediaStreamProvider.notifier).start('/a.wav', 'a.wav');
    expect(client.started, (volume: 100, monitor: false));
  });

  test('a file that cannot be played is reported', () async {
    final c = await start();
    client.startFailure = const MediaFileUnplayable();

    final failure = await c
        .read(mediaStreamProvider.notifier)
        .start('/x/notes.txt', 'notes.txt');

    expect(failure, isA<MediaFileUnplayable>());
    expect(c.read(mediaStreamProvider), isNull);
  });

  test('controls are announced and remembered', () async {
    final c = await start();
    final media = c.read(mediaStreamProvider.notifier);
    await media.start('/a.mp3', 'a.mp3');
    await pumpEventQueue();

    media.togglePause();
    await pumpEventQueue();
    expect(platform.tts.spoken.last, 'Paused');
    media.togglePause();
    await pumpEventQueue();
    expect(platform.tts.spoken.last, 'Resumed');

    media.seekBy(const Duration(seconds: 10));
    await pumpEventQueue();
    expect(platform.tts.spoken.last, '0:10 of 3:20');

    media
      ..setLoop(loop: true)
      ..setVolume(150)
      ..setMonitor(monitor: true);
    await pumpEventQueue();
    expect(platform.tts.spoken.last, 'Loop on');
    expect(c.read(playbackSettingsProvider).mediaStreamVolumePercent, 150);
    expect(c.read(playbackSettingsProvider).mediaStreamMonitor, isTrue);

    media.stop();
    await pumpEventQueue();
    expect(platform.tts.spoken.last, 'Streaming stopped');
    expect(c.read(mediaStreamProvider), isNull);
    expect(client.calls, [
      'paused true',
      'paused false',
      'seek 0:00:10.000000',
      'loop true',
      'volume 150',
      'monitor true',
      'stop',
    ]);
  });

  test('the end of the file is announced', () async {
    await start();
    client.eventController
      ..add(const MediaStreamEndedEvent('a.mp3'))
      ..add(const MediaStreamEndedEvent('b.mp3', failed: true));
    await pumpEventQueue();

    expect(platform.tts.spoken, [
      'Finished streaming a.mp3',
      contains('could not be read'),
    ]);
  });

  test('positions read as minutes and seconds, hours when needed', () {
    expect(formatStreamPosition(const Duration(seconds: 65)), '1:05');
    expect(
      formatStreamPosition(const Duration(hours: 1, minutes: 2, seconds: 5)),
      '1:02:05',
    );
  });
}
