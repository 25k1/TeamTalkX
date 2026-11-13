import 'package:flutter/material.dart' show Icons;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:teamtalkx/src/app/connection/connection_providers.dart';
import 'package:teamtalkx/src/app/servers/public_server_filter.dart';
import 'package:teamtalkx/src/app/servers/public_servers_providers.dart';
import 'package:teamtalkx/src/app/servers/server_list_providers.dart';
import 'package:teamtalkx/src/app/settings/settings_providers.dart';
import 'package:teamtalkx/src/domain/server_entry.dart';
import 'package:teamtalkx/src/ui/servers/server_list_screen.dart';

import 'support/fake_platform.dart';
import 'support/fake_voice_client.dart';
import 'support/localized_app.dart';

class _Session extends SessionController {
  final connects = <String>[];

  @override
  ConnectionState build() => const Disconnected();

  @override
  Future<void> connect(ServerEntry entry, {int? listIndex}) async {
    connects.add(entry.host);
    throw const ConnectCancelled();
  }
}

const _public = [
  ServerEntry(
    name: 'Quiet',
    host: 'quiet.example',
    country: 'Georgia',
    listingType: ServerListingType.public,
  ),
  ServerEntry(
    name: 'Busy',
    host: 'busy.example',
    country: 'Denmark',
    userCount: 12,
    listingType: ServerListingType.official,
  ),
  ServerEntry(
    name: 'Middle',
    host: 'middle.example',
    country: 'Georgia',
    userCount: 3,
    listingType: ServerListingType.public,
  ),
];

void main() {
  late FakePlatform platform;
  late ProviderContainer container;
  late _Session session;

  Future<void> pump(
    WidgetTester tester, {
    List<ServerEntry> mine = const [],
    Map<String, Object> prefs = const {},
  }) async {
    serverListStartupHandled = false;
    serverListStartupReported = false;
    SharedPreferences.setMockInitialValues({
      'app_language': 'english',
      'speech_output': 'tts',
      'server_list': ServerEntry.encodeList(mine),
      ...prefs,
    });
    final shared = await SharedPreferences.getInstance();
    platform = FakePlatform();
    final client = FakeVoiceClient();
    session = _Session();
    addTearDown(() async {
      await platform.dispose();
      await client.close();
    });
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          ...platform.overrides,
          sharedPreferencesProvider.overrideWithValue(shared),
          teamTalkClientProvider.overrideWithValue(client),
          connectionProvider.overrideWith(() => session),
          publicServersProvider.overrideWith((ref) async => _public),
        ],
        child: const LocalizedTestApp(home: ServerListScreen()),
      ),
    );
    await tester.pumpAndSettle();
    container = ProviderScope.containerOf(
      tester.element(find.byType(ServerListScreen)),
    );
  }

  Finder row(String name) => find.bySemanticsLabel(RegExp('^$name(, |\$)'));

  testWidgets('favorites come first, under their own heading', (tester) async {
    await pump(
      tester,
      mine: const [
        ServerEntry(name: 'Club', host: 'club.example'),
        ServerEntry(name: 'Home', host: 'home.example', favorite: true),
      ],
    );
    expect(find.text('Favorites'), findsOneWidget);
    expect(find.text('My servers'), findsOneWidget);
    final home = tester.getTopLeft(find.text('Home')).dy;
    final club = tester.getTopLeft(find.text('Club')).dy;
    expect(home, lessThan(club));

    await container
        .read(serverListProvider.notifier)
        .setFavorite(0, favorite: true);
    await tester.pumpAndSettle();
    expect(find.text('My servers'), findsNothing, reason: 'all favorites');
  });

  testWidgets('public filters hide servers and are remembered', (tester) async {
    await pump(tester);
    await tester.tap(find.text('Public'));
    await tester.pumpAndSettle();
    final busy = tester.getTopLeft(find.text('Busy')).dy;
    final middle = tester.getTopLeft(find.text('Middle')).dy;
    expect(busy, lessThan(middle));

    container
        .read(publicServerFilterProvider.notifier)
        .set(const PublicServerFilter(country: 'Georgia', minUsers: 1));
    await tester.pumpAndSettle();
    expect(find.text('Busy'), findsNothing);
    expect(find.text('Quiet'), findsNothing);
    expect(find.text('Middle'), findsOneWidget);
    expect(find.text('2 servers hidden by filters'), findsOneWidget);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('public_filter_country'), 'Georgia');

    await tester.tap(find.text('2 servers hidden by filters'));
    await tester.pumpAndSettle();
    expect(find.text('Quiet'), findsOneWidget);
  });

  testWidgets('filters and order are chosen in the accessible menu', (
    tester,
  ) async {
    await pump(tester);
    await tester.tap(find.text('Public'));
    await tester.pumpAndSettle();
    expect(
      find.text('any country, any number of users, Most users'),
      findsOneWidget,
    );
    await tester.tap(find.text('Filter and sort'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Users: Any'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('At least 5'));
    await tester.pumpAndSettle();
    expect(find.text('Busy'), findsOneWidget);
    expect(find.text('Middle'), findsNothing);
    expect(container.read(publicServerFilterProvider).minUsers, 5);

    await tester.tap(find.text('Filter and sort'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Clear filters'));
    await tester.pumpAndSettle();
    expect(find.text('Middle'), findsOneWidget);
  });

  testWidgets('connects on startup to the one server marked', (tester) async {
    await pump(
      tester,
      mine: const [
        ServerEntry(name: 'A', host: 'a.example'),
        ServerEntry(name: 'B', host: 'b.example', connectOnStartup: true),
      ],
    );
    expect(session.connects, ['b.example']);

    await container
        .read(serverListProvider.notifier)
        .setConnectOnStartup(0, connect: true);
    final servers = container.read(serverListProvider).value!;
    expect(servers.map((s) => s.connectOnStartup), [true, false]);
  });

  testWidgets('details show everything about a server', (tester) async {
    await pump(
      tester,
      mine: [
        ServerEntry(
          name: 'Home',
          host: 'home.example',
          lastConnected: DateTime.now(),
        ),
      ],
    );
    final semantics = tester.ensureSemantics();
    expect(row('Home'), findsOneWidget);
    await tester.longPress(find.text('Home'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Details'));
    await tester.pumpAndSettle();
    expect(find.text('Address'), findsOneWidget);
    expect(find.textContaining('today at'), findsOneWidget);
    expect(find.text('home.example:10333'), findsOneWidget);
    await tester.tap(find.text('Add to favorites'));
    await tester.pumpAndSettle();
    expect(container.read(serverListProvider).value!.single.favorite, isTrue);
    expect(find.text('Remove from favorites'), findsOneWidget);
    semantics.dispose();
  });

  testWidgets('rows read the name first, briefly', (tester) async {
    await pump(
      tester,
      mine: const [
        ServerEntry(
          name: 'Home',
          host: 'busy.example',
          favorite: true,
          encrypted: true,
        ),
      ],
    );
    final semantics = tester.ensureSemantics();
    expect(
      find.bySemanticsLabel('Home, favorite, 12 users, encrypted'),
      findsOneWidget,
    );
    await tester.tap(find.text('Public'));
    await tester.pumpAndSettle();
    expect(
      find.bySemanticsLabel('Busy, official server, 12 users, Denmark'),
      findsOneWidget,
    );
    semantics.dispose();
  });

  testWidgets('servers move within their group', (tester) async {
    await pump(
      tester,
      mine: const [
        ServerEntry(name: 'A', host: 'a.example'),
        ServerEntry(name: 'Fav', host: 'f.example', favorite: true),
        ServerEntry(name: 'B', host: 'b.example'),
        ServerEntry(name: 'C', host: 'c.example'),
      ],
    );
    await tester.longPress(find.text('C'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Move to top'));
    await tester.pumpAndSettle();
    final names = container
        .read(serverListProvider)
        .value!
        .map((s) => s.name)
        .toList();
    expect(names, ['C', 'Fav', 'A', 'B'], reason: 'Fav keeps its place');
    expect(platform.tts.spoken.last, 'C, 1 of 3');
    expect(find.byIcon(Icons.drag_handle), findsNWidgets(4));

    container
        .read(publicServerFilterProvider.notifier)
        .set(const PublicServerFilter(mineSort: MineSort.name));
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.drag_handle), findsNothing);
  });

  testWidgets('duplicate copies everything and opens the copy', (tester) async {
    await pump(
      tester,
      mine: const [
        ServerEntry(
          name: 'Home',
          host: 'home.example',
          username: 'me',
          connectOnStartup: true,
        ),
        ServerEntry(name: 'Other', host: 'other.example'),
      ],
    );
    await tester.longPress(find.text('Home'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Duplicate'));
    await tester.pumpAndSettle();
    final servers = container.read(serverListProvider).value!;
    expect(servers.map((s) => s.name), ['Home', 'Home (copy)', 'Other']);
    expect(servers[1].username, 'me');
    expect(servers[1].connectOnStartup, isFalse, reason: 'only one');
    expect(find.text('Home (copy)'), findsWidgets, reason: 'edit screen');
  });

  testWidgets('with no servers, the ways to get some', (tester) async {
    await pump(tester);
    expect(find.text('No servers yet'), findsOneWidget);
    await tester.tap(find.text('Browse public servers'));
    await tester.pumpAndSettle();
    expect(find.text('Busy'), findsOneWidget);
  });

  test('a login records when, and a remembered channel keeps it', () async {
    SharedPreferences.setMockInitialValues({
      'server_list': ServerEntry.encodeList(const [
        ServerEntry(name: 'Home', host: 'home.example', favorite: true),
      ]),
    });
    final c = ProviderContainer(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(
          await SharedPreferences.getInstance(),
        ),
      ],
    );
    addTearDown(c.dispose);
    await c.read(serverListProvider.future);
    final notifier = c.read(serverListProvider.notifier);
    final when = DateTime.utc(2026, 11, 11, 9);
    await notifier.markConnected(
      const ServerEntry(host: 'home.example'),
      now: when,
    );
    await notifier.updateChannel(
      0,
      const ServerEntry(host: 'home.example'),
      path: '/Room/',
      password: '',
    );
    final saved = c.read(serverListProvider).value!.single;
    expect(saved.lastConnected, when);
    expect(saved.channel, '/Room/');
    expect(saved.favorite, isTrue);
  });

  testWidgets('the end of startup is reported once the list is shown', (
    tester,
  ) async {
    await pump(
      tester,
      mine: const [ServerEntry(name: 'Home', host: 'home.example')],
    );
    expect(platform.startupDone, 1);
    expect(serverListStartupReported, isTrue);
  });
}
