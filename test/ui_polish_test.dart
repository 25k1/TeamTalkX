import 'package:flutter/material.dart' hide ConnectionState;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:teamtalkx/src/app/connection/connection_providers.dart';
import 'package:teamtalkx/src/app/servers/public_servers_providers.dart';
import 'package:teamtalkx/src/app/servers/server_list_providers.dart';
import 'package:teamtalkx/src/app/settings/settings_providers.dart';
import 'package:teamtalkx/src/domain/events.dart';
import 'package:teamtalkx/src/domain/models.dart';
import 'package:teamtalkx/src/domain/server_entry.dart';
import 'package:teamtalkx/src/ui/a11y/context_menu_row.dart';
import 'package:teamtalkx/src/ui/app.dart';
import 'package:teamtalkx/src/ui/common/text_controllers.dart';
import 'package:teamtalkx/src/ui/common/unsaved_changes.dart';
import 'package:teamtalkx/src/ui/servers/server_list_screen.dart';
import 'package:teamtalkx/src/ui/users/online_users_screen.dart';

import 'support/fake_platform.dart';
import 'support/fake_voice_client.dart';
import 'support/localized_app.dart';

class _Form extends StatefulWidget {
  const _Form();
  @override
  State<_Form> createState() => _FormState();
}

class _FormState extends State<_Form> with TextControllers, UnsavedChanges {
  late final TextEditingController _name;
  bool _flag = false;
  int saves = 0;

  @override
  List<Object?> get formValues => [_flag];

  @override
  void initState() {
    super.initState();
    _name = textController('Lobby');
    markSaved();
  }

  @override
  Widget build(BuildContext context) => guardUnsaved(
    save: () {
      saves++;
      Navigator.of(context).pop();
    },
    child: Scaffold(
      appBar: AppBar(),
      body: Column(
        children: [
          TextField(controller: _name),
          Switch(value: _flag, onChanged: (v) => setState(() => _flag = v)),
        ],
      ),
    ),
  );
}

TtUser _user(int id, String nickname, String username) => TtUser(
  id: id,
  username: username,
  nickname: nickname,
  statusMessage: '',
  channelId: 1,
  userState: 0,
  userType: 1,
  clientName: '',
);

class _Client extends FakeVoiceClient {
  @override
  String channelPath(int channelId) => '/';
  @override
  bool isChannelOperator(int userId, int channelId) => false;
}

void main() {
  late SharedPreferences prefs;

  Future<void> pumpHome(
    WidgetTester tester,
    Widget home, {
    List<Override> overrides = const [],
    Map<String, Object> values = const {},
  }) async {
    SharedPreferences.setMockInitialValues({
      'app_language': 'english',
      'speech_output': 'tts',
      ...values,
    });
    prefs = await SharedPreferences.getInstance();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          ...overrides,
        ],
        child: LocalizedTestApp(home: home),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('leaving with unsaved changes asks first', (tester) async {
    await pumpHome(
      tester,
      Builder(
        builder: (context) => TextButton(
          onPressed: () => Navigator.of(
            context,
          ).push(MaterialPageRoute<void>(builder: (_) => const _Form())),
          child: const Text('open'),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.text('open'), findsOneWidget);

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Lounge');
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.text('Unsaved changes'), findsOneWidget);
    await tester.tap(find.text('Keep editing'));
    await tester.pumpAndSettle();
    expect(find.text('Lounge'), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'Lobby');
    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();
    await tester.pageBack();
    await tester.pumpAndSettle();
    await tester.tap(find.text('Discard'));
    await tester.pumpAndSettle();
    expect(find.text('open'), findsOneWidget);
  });

  testWidgets('a removed server comes back with Undo', (tester) async {
    serverListStartupHandled = true;
    final platform = FakePlatform();
    final client = FakeVoiceClient();
    addTearDown(() async {
      await platform.dispose();
      await client.close();
    });
    await pumpHome(
      tester,
      const ServerListScreen(),
      values: {
        'server_list': ServerEntry.encodeList(const [
          ServerEntry(name: 'Home', host: 'home.example', password: 'pw'),
        ]),
      },
      overrides: [
        ...platform.overrides,
        teamTalkClientProvider.overrideWithValue(client),
        publicServersProvider.overrideWith((ref) async => const []),
      ],
    );
    await tester.tap(
      find.descendant(
        of: find.byType(ContextMenuRow),
        matching: find.byIcon(Icons.more_vert),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Remove'));
    await tester.pumpAndSettle();
    expect(find.text('Home removed'), findsOneWidget);
    final container = ProviderScope.containerOf(
      tester.element(find.byType(ServerListScreen)),
    );
    expect(container.read(serverListProvider).value, isEmpty);

    await tester.tap(find.text('Undo'));
    await tester.pumpAndSettle();
    final back = container.read(serverListProvider).value!.single;
    expect(back.name, 'Home');
    expect(back.password, 'pw');
  });

  testWidgets('online users can be searched', (tester) async {
    final platform = FakePlatform();
    final client = _Client()..addMe();
    client.state
      ..apply(UserLoggedInEvent(_user(8, 'Ann', 'ann')))
      ..apply(UserLoggedInEvent(_user(9, 'Bob', 'bobby')));
    addTearDown(() async {
      await platform.dispose();
      await client.close();
    });
    await pumpHome(
      tester,
      const OnlineUsersScreen(),
      overrides: [
        ...platform.overrides,
        teamTalkClientProvider.overrideWithValue(client),
      ],
    );
    expect(find.byType(ContextMenuRow), findsNWidgets(3));
    await tester.enterText(find.byType(TextField), 'bob');
    await tester.pumpAndSettle();
    expect(find.byType(ContextMenuRow), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'zzz');
    await tester.pumpAndSettle();
    expect(find.text('Nothing matches "zzz"'), findsOneWidget);
  });

  test('high contrast strengthens outlines', () {
    final plain = appTheme(Brightness.light, highContrast: false);
    final strong = appTheme(Brightness.light, highContrast: true);
    expect(strong.dividerTheme.color, strong.colorScheme.onSurface);
    expect(plain.dividerTheme.color, isNull);
    expect(
      strong.colorScheme.primary,
      isNot(plain.colorScheme.primary),
      reason: 'the stronger contrast level',
    );
  });

  test('the theme setting is kept', () async {
    SharedPreferences.setMockInitialValues(const {});
    final c = ProviderContainer(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(
          await SharedPreferences.getInstance(),
        ),
      ],
    );
    addTearDown(c.dispose);
    c.read(settingsProvider.notifier)
      ..setTheme(AppTheme.dark)
      ..setHighContrast(true);
    final shared = await SharedPreferences.getInstance();
    expect(shared.getString('theme'), 'dark');
    expect(shared.getBool('high_contrast'), isTrue);
  });
}
