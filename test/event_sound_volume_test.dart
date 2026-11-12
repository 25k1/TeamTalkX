import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:teamtalkx/src/app/settings/event_config.dart';
import 'package:teamtalkx/src/app/settings/event_dispatcher.dart';
import 'package:teamtalkx/src/app/settings/settings_providers.dart';

import 'support/fake_platform.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late FakePlatform platform;

  Future<ProviderContainer> start([
    Map<String, Object> prefs = const {},
  ]) async {
    SharedPreferences.setMockInitialValues(prefs);
    final container = ProviderContainer(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(
          await SharedPreferences.getInstance(),
        ),
        ...platform.overrides,
      ],
    );
    addTearDown(container.dispose);
    return container;
  }

  setUp(() {
    platform = FakePlatform();
    addTearDown(platform.dispose);
  });

  test('an event plays its sound at its own volume', () async {
    final c = await start();
    c.read(eventDispatcherProvider).fire(AppEvent.userJoined);
    c
        .read(eventConfigProvider.notifier)
        .setSoundVolume(AppEvent.userJoined, 40);
    c.read(eventDispatcherProvider).fire(AppEvent.userJoined);

    expect(platform.sounds.played, ['userJoin', 'userJoin']);
    expect(platform.sounds.volumes, [100, 40]);
  });

  test('which events interrupt other speech', () async {
    final c = await start({'speech_output': 'tts'});
    final configs = c.read(eventConfigProvider);
    expect(
      [
        for (final e in AppEvent.values)
          if (configs[e]!.interrupts) e,
      ],
      [
        AppEvent.privateMessage,
        AppEvent.connectionLost,
        AppEvent.kickedFromServer,
        AppEvent.kickedFromChannel,
      ],
    );
    c
        .read(eventConfigProvider.notifier)
        .setInterrupts(AppEvent.userJoined, true);
    c
        .read(eventDispatcherProvider)
        .fire(AppEvent.userJoined, vars: {'nickname': 'Ann'});
    expect(platform.tts.interrupted, hasLength(1));

    final again = await start({
      'speech_output': 'tts',
      'event.privateMessage.interrupt': false,
    });
    expect(
      again.read(eventConfigProvider)[AppEvent.privateMessage]!.interrupts,
      isFalse,
    );
  });

  test('the per-event volume is remembered', () async {
    final c = await start({'event.userJoined.sound_volume': 150});
    expect(
      c.read(eventConfigProvider)[AppEvent.userJoined]!.soundVolumePercent,
      150,
    );
  });

  test('the event-sound volume defaults to 100 % and is kept', () async {
    final c = await start();
    expect(c.read(settingsProvider).eventVolumePercent, 100);
    c.read(settingsProvider.notifier).setEventVolumePercent(60);
    final again = await start({'event_volume_percent': 60});
    expect(again.read(settingsProvider).eventVolumePercent, 60);
  });
}
