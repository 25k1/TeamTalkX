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
  late ProviderContainer c;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    platform = FakePlatform();
    c = ProviderContainer(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(
          await SharedPreferences.getInstance(),
        ),
        ...platform.overrides,
      ],
    );
    addTearDown(() async {
      c.dispose();
      await platform.dispose();
    });
  });

  test('events vibrate by default', () async {
    c.read(eventDispatcherProvider).fire(AppEvent.voiceTransmitOn);
    await pumpEventQueue();
    expect(platform.haptics.played, hasLength(1));
  });

  test('turning vibration off silences every event, and is kept', () async {
    c.read(eventFeedbackSettingsProvider.notifier).setVibrationEnabled(false);
    c.read(eventDispatcherProvider).fire(AppEvent.voiceTransmitOn);
    await pumpEventQueue();
    expect(platform.haptics.played, isEmpty);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool('vibration_enabled'), isFalse);
  });
}
