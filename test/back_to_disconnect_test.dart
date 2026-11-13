import 'package:drift/native.dart';
import 'package:flutter/material.dart' hide ConnectionState;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:teamtalkx/src/app/connection/connection_providers.dart';
import 'package:teamtalkx/src/app/pure_teamtalk_client.dart';
import 'package:teamtalkx/src/app/security/certificate_trust.dart';
import 'package:teamtalkx/src/app/settings/settings_providers.dart';
import 'package:teamtalkx/src/data/app_database.dart';
import 'package:teamtalkx/src/domain/events.dart';
import 'package:teamtalkx/src/domain/models.dart';
import 'package:teamtalkx/src/domain/tt_types.dart';
import 'package:teamtalkx/src/l10n/l10n.dart';
import 'package:teamtalkx/src/ui/channels/main_screen.dart';

import 'support/fake_platform.dart';

class _Session extends SessionController {
  int disconnects = 0;

  @override
  ConnectionState build() => const LoggedIn(7);

  @override
  Future<void> disconnect() async => disconnects++;
}

PureTeamTalkClient _client() {
  final client = PureTeamTalkClient();
  for (final event in <TtEvent>[
    const MyselfLoggedInEvent(7),
    const ServerUpdateEvent(TtServerInfo(name: 'Home', motd: '')),
    const ChannelNewEvent(
      TtChannel(
        id: 1,
        parentId: 0,
        name: '',
        topic: '',
        hasPassword: false,
        maxUsers: 100,
        channelType: ChannelTypes.permanent,
      ),
    ),
    const UserLoggedInEvent(
      TtUser(
        id: 7,
        username: 'me',
        nickname: 'Me',
        statusMessage: '',
        channelId: 1,
        userState: 0,
        userType: 1,
        clientName: 'TeamTalkX',
      ),
    ),
  ]) {
    client.applyLocalEvent(event);
  }
  return client;
}

void main() {
  late FakePlatform platform;
  late _Session session;

  Future<void> pumpMain(
    WidgetTester tester, {
    Map<String, Object> prefs = const {},
  }) async {
    SharedPreferences.setMockInitialValues({
      'app_language': 'english',
      'speech_output': 'tts',
      'first_run_done': true,
      ...prefs,
    });
    final shared = await SharedPreferences.getInstance();
    platform = FakePlatform();
    session = _Session();
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(() async {
      await db.close();
      await platform.dispose();
    });
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          ...platform.overrides,
          sharedPreferencesProvider.overrideWithValue(shared),
          teamTalkClientProvider.overrideWithValue(_client()),
          connectionProvider.overrideWith(() => session),
          appDatabaseProvider.overrideWithValue(db),
        ],
        child: const MaterialApp(
          locale: Locale('en'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: MainScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> pressBack(WidgetTester tester) async {
    await tester.binding.handlePopRoute();
    await tester.pump();
  }

  testWidgets('the first back only shows a hint, which TTS does not speak', (
    tester,
  ) async {
    await pumpMain(tester);
    await pressBack(tester);
    expect(find.text('Press back again to disconnect'), findsOneWidget);
    expect(
      platform.tts.spoken,
      isNot(contains('Press back again to disconnect')),
    );
    expect(session.disconnects, 0);
    await pressBack(tester);
    expect(session.disconnects, 1);
  });

  testWidgets('with the setting off, one back disconnects', (tester) async {
    await pumpMain(tester, prefs: {'back_twice_to_disconnect': false});
    await pressBack(tester);
    expect(session.disconnects, 1);
    expect(find.text('Press back again to disconnect'), findsNothing);
  });
}
