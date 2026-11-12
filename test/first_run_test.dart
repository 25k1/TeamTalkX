import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:teamtalkx/src/app/settings/first_run.dart';
import 'package:teamtalkx/src/app/settings/settings_providers.dart';
import 'package:teamtalkx/src/domain/app_permission.dart';
import 'package:teamtalkx/src/ui/first_run/first_run_screen.dart';

import 'support/fake_platform.dart';
import 'support/localized_app.dart';

void main() {
  Future<ProviderContainer> container(Map<String, Object> prefs) async {
    SharedPreferences.setMockInitialValues(prefs);
    final c = ProviderContainer(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(
          await SharedPreferences.getInstance(),
        ),
      ],
    );
    addTearDown(c.dispose);
    return c;
  }

  test('only a new install gets the setup', () async {
    expect((await container(const {})).read(firstRunProvider), isTrue);
    final updating = await container({'nickname': 'Ann'});
    expect(updating.read(firstRunProvider), isFalse);
    await pumpEventQueue();
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool('first_run_done'), isTrue, reason: 'marked done');
  });

  group('screens', () {
    late FakePlatform platform;
    late SharedPreferences prefs;

    Future<void> pump(WidgetTester tester) async {
      SharedPreferences.setMockInitialValues(const {});
      prefs = await SharedPreferences.getInstance();
      platform = FakePlatform();
      addTearDown(platform.dispose);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            ...platform.overrides,
            sharedPreferencesProvider.overrideWithValue(prefs),
          ],
          child: LocalizedTestApp(
            home: Consumer(
              builder: (context, ref, _) => ref.watch(firstRunProvider)
                  ? const FirstRunScreen()
                  : const Text('server list'),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    Future<void> next(WidgetTester tester) async {
      await tester.tap(find.text('Next'));
      await tester.pumpAndSettle();
    }

    testWidgets('steps through every choice to the end', (tester) async {
      await pump(tester);
      expect(find.text('Welcome, step 1 of 8'), findsOneWidget);

      await next(tester);
      expect(find.text('Your name, step 2 of 8'), findsOneWidget);
      await tester.enterText(find.byType(TextField), 'Beka');
      await next(tester);
      expect(prefs.getString('nickname'), 'Beka');

      expect(find.text('Gender, step 3 of 8'), findsOneWidget);
      await next(tester);
      expect(find.text('Speaking events, step 4 of 8'), findsOneWidget);
      await tester.tap(find.text('Text-to-speech engine'));
      await tester.pumpAndSettle();
      await next(tester);
      expect(prefs.getString('speech_output'), 'tts');

      expect(find.text('Voice activation, step 5 of 8'), findsOneWidget);
      await tester.tap(find.text('Silero'));
      await tester.pumpAndSettle();
      await next(tester);

      expect(find.text('Permissions, step 6 of 8'), findsOneWidget);
      expect(find.text('To talk in channels'), findsOneWidget);
      await tester.tap(find.text('Allow').first);
      await tester.pumpAndSettle();
      expect(platform.permissions.requested, ['microphone']);
      expect(find.text('Allowed'), findsOneWidget);
      await next(tester);

      expect(find.text('Staying connected, step 7 of 8'), findsOneWidget);
      await next(tester);
      expect(find.text('All set, step 8 of 8'), findsOneWidget);
      await tester.tap(find.text('Start'));
      await tester.pumpAndSettle();

      expect(find.text('server list'), findsOneWidget);
      expect(prefs.getBool('first_run_done'), isTrue);
      expect(prefs.getString('vad_engine'), 'silero');
      expect(platform.permissions.grantedOnes, {AppPermission.microphone});
    });

    testWidgets('can be skipped from any step', (tester) async {
      await pump(tester);
      await next(tester);
      await tester.tap(find.text('Skip setup'));
      await tester.pumpAndSettle();
      expect(find.text('server list'), findsOneWidget);
      expect(prefs.getBool('first_run_done'), isTrue);
    });
  });
}
