import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:teamtalkx/src/app/announcer.dart';
import 'package:teamtalkx/src/app/settings/settings_providers.dart';

import 'support/fake_platform.dart';

void main() {
  late FakePlatform platform;
  late ProviderContainer c;

  setUp(() async {
    SharedPreferences.setMockInitialValues({'speech_output': 'tts'});
    final shared = await SharedPreferences.getInstance();
    platform = FakePlatform();
    c = ProviderContainer(
      overrides: [
        ...platform.overrides,
        sharedPreferencesProvider.overrideWithValue(shared),
      ],
    );
    addTearDown(() async {
      c.dispose();
      await platform.dispose();
    });
  });

  testWidgets('a shown message is spoken by TTS without a screen reader', (
    tester,
  ) async {
    c.read(announcerProvider).announceShown('Press back again to disconnect');
    await tester.pump();
    expect(platform.tts.spoken, ['Press back again to disconnect']);
  });

  testWidgets('with a screen reader, only the screen reader reads it', (
    tester,
  ) async {
    tester.platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures(accessibleNavigation: true);
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
    c.read(announcerProvider).announceShown('Press back again to disconnect');
    await tester.pump();
    expect(platform.tts.spoken, isEmpty);
  });

  testWidgets('announcements that are not shown still use TTS', (tester) async {
    tester.platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures(accessibleNavigation: true);
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
    c.read(announcerProvider).announce('Alice joined');
    await tester.pump();
    expect(platform.tts.spoken, ['Alice joined']);
  });
}
