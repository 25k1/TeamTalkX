import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:teamtalkx/src/app/connection/connection_providers.dart';
import 'package:teamtalkx/src/app/servers/public_servers_providers.dart';
import 'package:teamtalkx/src/app/servers/server_list_providers.dart';
import 'package:teamtalkx/src/app/settings/settings_providers.dart';
import 'package:teamtalkx/src/domain/server_entry.dart';
import 'package:teamtalkx/src/ui/servers/server_list_screen.dart';
import 'package:teamtalkx/src/ui/servers/server_offer.dart';

import 'support/fake_platform.dart';
import 'support/fake_voice_client.dart';
import 'support/localized_app.dart';

const _link =
    'tt://tt.example?tcpport=10443&encrypted=true&username=me'
    '&password=pw&channel=/Room/';

const _twoServers = '''<?xml version="1.0" encoding="UTF-8"?>
<teamtalk version="5.0">
  <host><name>One</name><address>one.example</address><tcpport>10333</tcpport>
    <auth><username>a</username><password>secret</password></auth></host>
  <host><name>Two</name><address>two.example</address><tcpport>10333</tcpport></host>
</teamtalk>''';

void main() {
  late FakePlatform platform;
  late ProviderContainer container;

  Future<void> pumpList(WidgetTester tester) async {
    SharedPreferences.setMockInitialValues(const {'app_language': 'english'});
    final prefs = await SharedPreferences.getInstance();
    platform = FakePlatform();
    final client = FakeVoiceClient();
    addTearDown(() async {
      await platform.dispose();
      await client.close();
    });
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          ...platform.overrides,
          sharedPreferencesProvider.overrideWithValue(prefs),
          teamTalkClientProvider.overrideWithValue(client),
          publicServersProvider.overrideWith((ref) async => const []),
        ],
        child: const LocalizedTestApp(home: ServerListScreen()),
      ),
    );
    await tester.pumpAndSettle();
    container = ProviderScope.containerOf(
      tester.element(find.byType(ServerListScreen)),
    );
  }

  testWidgets('a link is described and connects only when asked', (
    tester,
  ) async {
    await pumpList(tester);
    platform.deepLinks.link.add(_link);
    await tester.pumpAndSettle();

    expect(find.text('Open server link?'), findsOneWidget);
    expect(find.text('Address: tt.example:10443'), findsOneWidget);
    expect(find.text('Encrypted connection'), findsOneWidget);
    expect(find.text('Logs in as me'), findsOneWidget);
    expect(find.text('Includes a password'), findsOneWidget);
    expect(find.text('Joins channel /Room/'), findsOneWidget);
    expect(container.read(connectionProvider), isA<Disconnected>());

    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(container.read(connectionProvider), isA<Disconnected>());
    expect(container.read(serverListProvider).value, isEmpty);
  });

  testWidgets('a link can be saved without connecting', (tester) async {
    await pumpList(tester);
    platform.deepLinks.link.add(_link);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Add to my servers'));
    await tester.pumpAndSettle();

    final saved = container.read(serverListProvider).value!.single;
    expect(saved.host, 'tt.example');
    expect(saved.password, 'pw');
    expect(container.read(connectionProvider), isA<Disconnected>());
  });

  testWidgets('a file with several servers is imported once confirmed', (
    tester,
  ) async {
    await pumpList(tester);
    platform.deepLinks.file.add(_twoServers);
    await tester.pumpAndSettle();

    expect(find.text('Import 2 servers?'), findsOneWidget);
    expect(find.text('One, one.example:10333'), findsOneWidget);
    expect(find.text('1 of them includes passwords.'), findsOneWidget);
    expect(container.read(serverListProvider).value, isEmpty);

    await tester.tap(find.text('Import'));
    await tester.pumpAndSettle();
    expect(container.read(serverListProvider).value, hasLength(2));
  });

  testWidgets('a file with one server is offered like a link (D149)', (
    tester,
  ) async {
    await pumpList(tester);
    platform.deepLinks.file.add(
      _twoServers.replaceAll(RegExp(r'<host><name>Two.*?</host>'), ''),
    );
    await tester.pumpAndSettle();
    expect(find.text('Open server file?'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(container.read(serverListProvider).value, isEmpty);
  });

  testWidgets('export asks about passwords, and leaves them out by default', (
    tester,
  ) async {
    const entries = [
      ServerEntry(host: 'a.example', password: 'pw'),
      ServerEntry(host: 'b.example'),
    ];
    SharedPreferences.setMockInitialValues(const {'app_language': 'english'});
    final prefs = await SharedPreferences.getInstance();
    bool? include;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
        child: LocalizedTestApp(
          home: Builder(
            builder: (context) => TextButton(
              onPressed: () async =>
                  include = await askExportPasswords(context, entries),
              child: const Text('export'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('export'));
    await tester.pumpAndSettle();
    expect(find.text('Include passwords?'), findsOneWidget);
    await tester.tap(find.text('Leave out'));
    await tester.pumpAndSettle();
    expect(include, isFalse);
    expect(withoutPasswords(entries).every((e) => e.password.isEmpty), isTrue);

    include = null;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
        child: LocalizedTestApp(
          home: Builder(
            builder: (context) => TextButton(
              onPressed: () async => include = await askExportPasswords(
                context,
                const [ServerEntry(host: 'b.example')],
              ),
              child: const Text('export'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('export'));
    await tester.pumpAndSettle();
    expect(find.text('Include passwords?'), findsNothing);
    expect(include, isFalse);
  });
}
