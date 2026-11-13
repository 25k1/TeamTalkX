import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' show ListView, Scrollable, TextField;
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:teamtalkx/src/app/settings/settings_providers.dart';
import 'package:teamtalkx/src/ui/settings/settings_screen.dart';

import 'support/localized_app.dart';

Future<void> pumpSettings(WidgetTester tester) async {
  SharedPreferences.setMockInitialValues(const {});
  final prefs = await SharedPreferences.getInstance();
  await tester.pumpWidget(
    ProviderScope(
      overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
      child: const LocalizedTestApp(home: SettingsScreen()),
    ),
  );
}

final _sections = find.descendant(
  of: find.byType(ListView),
  matching: find.byType(Scrollable),
);

void main() {
  testWidgets('settings root lists all sections', (tester) async {
    await pumpSettings(tester);
    for (final title in [
      'General',
      'Audio',
      'Voice activation',
      'Keys and buttons',
      'Calls and interruptions',
      'Events',
      'Chat and history',
      'Server list',
      'Privacy and diagnostics',
      'Updates',
      'About',
    ]) {
      await tester.scrollUntilVisible(
        find.text(title),
        100,
        scrollable: _sections,
      );
      expect(find.text(title), findsOneWidget);
    }
  });

  testWidgets('voice enhancement is found and changed', (tester) async {
    await pumpSettings(tester);
    await tester.enterText(find.byType(TextField), 'voice enhancement');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Voice enhancement').first);
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('Voice enhancement'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.text('Voice enhancement'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Better: also cleans up low-quality voices'));
    await tester.pumpAndSettle();
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('voice_enhancement'), 'better');
    expect(
      find.text('Better: also cleans up low-quality voices'),
      findsOneWidget,
    );
  });

  testWidgets('search finds a setting and opens where it is', (tester) async {
    await pumpSettings(tester);
    await tester.enterText(find.byType(TextField), 'media keys');
    await tester.pumpAndSettle();
    expect(find.text('Keys and buttons'), findsOneWidget, reason: 'path');
    await tester.tap(find.text('Media keys').first);
    await tester.pumpAndSettle();
    expect(find.textContaining('Keys without an action'), findsOneWidget);

    await tester.pageBack();
    await tester.pumpAndSettle();
    await tester.pageBack();
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'kicked from');
    await tester.pumpAndSettle();
    expect(find.text('Kicked from the server'), findsOneWidget);
    expect(find.text('2 settings found'), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'no such setting here');
    await tester.pumpAndSettle();
    expect(find.text('No setting matches'), findsOneWidget);
  });

  testWidgets('export diagnostics saves a report to Downloads', (tester) async {
    const channel = MethodChannel('org.gozaltech.teamtalkx/export');
    final calls = <MethodCall>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
      call,
    ) async {
      calls.add(call);
      return 'Download/report.txt';
    });
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        channel,
        null,
      ),
    );
    await pumpSettings(tester);
    await tester.scrollUntilVisible(
      find.text('Privacy and diagnostics'),
      100,
      scrollable: _sections,
    );
    await tester.tap(find.text('Privacy and diagnostics'));
    await tester.pumpAndSettle();

    await tester.runAsync(() async {
      await tester.tap(find.text('Export diagnostics'));
      await Future<void>.delayed(const Duration(milliseconds: 100));
    });
    await tester.pumpAndSettle();

    final call = calls.single;
    expect(call.method, 'saveToDownloads');
    final args = call.arguments as Map<Object?, Object?>;
    expect(
      args['fileName'] as String,
      matches(RegExp(r'^teamtalkx-diagnostics-\d{8}-\d{4}\.txt$')),
    );
    expect(args['content'] as String, startsWith('TeamTalkX diagnostics'));
    expect(find.text('Exported to Download/report.txt'), findsOneWidget);
  });

  testWidgets('events section lists subcategories and events', (tester) async {
    await pumpSettings(tester);
    await tester.tap(find.text('Events'));
    await tester.pumpAndSettle();
    expect(find.text('Speech'), findsOneWidget);
    expect(find.text('Sound'), findsOneWidget);
    expect(find.text('User logs in'), findsOneWidget);
  });

  testWidgets('events speech subcategory renders its content', (tester) async {
    await pumpSettings(tester);
    await tester.tap(find.text('Events'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Speech'));
    await tester.pumpAndSettle();
    expect(find.text('Speak events through'), findsOneWidget);
    expect(find.text('Screen reader'), findsOneWidget);
    expect(find.text('Nothing'), findsOneWidget);
  });

  testWidgets('keys section holds push-to-talk and media keys', (tester) async {
    await pumpSettings(tester);
    await tester.tap(find.text('Keys and buttons'));
    await tester.pumpAndSettle();
    expect(find.text('Hardware push-to-talk key'), findsOneWidget);
    expect(find.text('Media keys'), findsOneWidget);
  });

  testWidgets('events sound subcategory renders its content', (tester) async {
    await pumpSettings(tester);
    await tester.tap(find.text('Events'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Sound'));
    await tester.pumpAndSettle();
    expect(find.text('Play event sounds'), findsOneWidget);
  });

  testWidgets('speech section with TTS output renders engine controls', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;

    const channel = MethodChannel('org.gozaltech.teamtalkx/tts');
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      channel,
      (call) async => switch (call.method) {
        'getEngines' => [
          {'name': 'com.google.tts', 'label': 'Google TTS'},
          {'name': 'com.acme.tts', 'label': 'Acme TTS'},
        ],
        'getLanguages' => ['en-US', 'ka-GE'],
        'getVoices' => [
          {'name': 'en-us-x-1', 'locale': 'en-US'},
          {'name': 'ka-ge-x-1', 'locale': 'ka-GE'},
        ],
        'init' => true,
        _ => null,
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        channel,
        null,
      ),
    );

    SharedPreferences.setMockInitialValues(const {
      'speech_output': 'tts',
      'tts_accessibility_stream': true,
    });
    final prefs = await SharedPreferences.getInstance();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
        child: const LocalizedTestApp(home: SettingsScreen()),
      ),
    );
    await tester.tap(find.text('Events'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Speech'));
    await tester.pumpAndSettle();

    expect(find.text('Use accessibility audio stream'), findsOneWidget);
    expect(find.text('Engine'), findsOneWidget);

    await tester.tap(find.text('Engine'));
    await tester.pumpAndSettle();
    expect(find.text('Google TTS'), findsOneWidget);
    await tester.tap(find.text('Acme TTS'));
    await tester.pumpAndSettle();
    expect(prefs.getString('tts_engine'), 'com.acme.tts');

    await tester.scrollUntilVisible(find.text('Speech volume'), 200);
    expect(find.text('Speech volume'), findsOneWidget);

    debugDefaultTargetPlatformOverride = null;
  });
}
