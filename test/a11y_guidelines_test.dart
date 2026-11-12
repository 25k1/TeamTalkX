import 'package:drift/native.dart';
import 'package:flutter/material.dart' hide ConnectionState;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:teamtalkx/src/app/connection/connection_providers.dart';
import 'package:teamtalkx/src/app/pure_teamtalk_client.dart';
import 'package:teamtalkx/src/app/security/certificate_trust.dart';
import 'package:teamtalkx/src/app/servers/public_servers_providers.dart';
import 'package:teamtalkx/src/app/settings/settings_providers.dart';
import 'package:teamtalkx/src/data/app_database.dart';
import 'package:teamtalkx/src/domain/certificate.dart';
import 'package:teamtalkx/src/domain/events.dart';
import 'package:teamtalkx/src/domain/models.dart';
import 'package:teamtalkx/src/domain/server_entry.dart';
import 'package:teamtalkx/src/domain/teamtalk_client.dart';
import 'package:teamtalkx/src/domain/tt_types.dart';
import 'package:teamtalkx/src/l10n/l10n.dart';
import 'package:teamtalkx/src/ui/app.dart';
import 'package:teamtalkx/src/ui/channels/channel_edit_screen.dart';
import 'package:teamtalkx/src/ui/channels/channel_info_screen.dart';
import 'package:teamtalkx/src/ui/channels/main_screen.dart';
import 'package:teamtalkx/src/ui/channels/media_stream_screen.dart';
import 'package:teamtalkx/src/ui/chat/chat_templates_screen.dart';
import 'package:teamtalkx/src/ui/chat/pm_screen.dart';
import 'package:teamtalkx/src/ui/first_run/first_run_screen.dart';
import 'package:teamtalkx/src/ui/security/trusted_certificates_screen.dart';
import 'package:teamtalkx/src/ui/servers/bearware_login_screen.dart';
import 'package:teamtalkx/src/ui/servers/server_details_screen.dart';
import 'package:teamtalkx/src/ui/servers/server_edit_screen.dart';
import 'package:teamtalkx/src/ui/servers/server_list_screen.dart';
import 'package:teamtalkx/src/ui/servers/server_properties_screen.dart';
import 'package:teamtalkx/src/ui/servers/server_statistics_screen.dart';
import 'package:teamtalkx/src/ui/settings/feedback_settings.dart';
import 'package:teamtalkx/src/ui/settings/settings_screen.dart';
import 'package:teamtalkx/src/ui/users/banned_users_screen.dart';
import 'package:teamtalkx/src/ui/users/online_users_screen.dart';
import 'package:teamtalkx/src/ui/users/remembered_users_screen.dart';
import 'package:teamtalkx/src/ui/users/user_accounts_screen.dart';
import 'package:teamtalkx/src/ui/users/user_detail_screen.dart';
import 'package:teamtalkx/src/ui/voice/mic_test_screen.dart';

import 'support/fake_platform.dart';
import 'support/fake_voice_client.dart';

enum _Look {
  light(Brightness.light, highContrast: false),
  dark(Brightness.dark, highContrast: false),
  highContrastLight(Brightness.light, highContrast: true),
  highContrastDark(Brightness.dark, highContrast: true),

  largeText(Brightness.light, highContrast: false, textScale: 2);

  const _Look(
    this.brightness, {
    required this.highContrast,
    this.textScale = 1,
  });

  final Brightness brightness;
  final bool highContrast;
  final double textScale;
}

const _guidelines = <AccessibilityGuideline>[
  androidTapTargetGuideline,
  labeledTapTargetGuideline,
  textContrastGuideline,
];

Future<List<String>> _failures(WidgetTester tester) async {
  final out = <String>[];
  for (final g in _guidelines) {
    final result = await g.evaluate(tester);
    if (!result.passed) out.add('${g.description}: ${result.reason}');
  }
  return out;
}

Map<String, Widget Function()> _offlineScreens() => {
  'server list': () => const ServerListScreen(),
  'server details': () => ServerDetailsScreen(
    entry: _servers.first,
    index: 0,
    onConnect: () {},
    onEdit: () {},
    onFavorite: () {},
  ),
  'server edit (new)': () => const ServerEditScreen(),
  'server edit': () => ServerEditScreen(entry: _servers.first),
  'BearWare login': () => const BearwareLoginScreen(),
  'first run': () => const FirstRunScreen(),
  'settings': () => const SettingsScreen(),
  for (final (i, section) in settingsSections().indexed)
    'settings section $i': () => Builder(
      builder: (context) =>
          section.screen?.call(context) ??
          Scaffold(
            appBar: AppBar(title: Text(section.title(context.l10n))),
            body: Builder(builder: section.builder!),
          ),
    ),
  'speech': () => const SpeechSettingsScreen(),
  'sounds': () => const SoundSettingsScreen(),
  'chat templates': () => const ChatTemplatesScreen(),
  'timestamp': () => const TimestampScreen(),
  'mic test': () => const MicTestScreen(),
  'trusted certificates': () => const TrustedCertificatesScreen(),
  'remembered users': () => const RememberedUsersScreen(),
};

typedef _Online = (
  Widget Function() screen, {
  Future<void> Function(WidgetTester, TeamTalkClient)? prepare,
  String shows,
});

Map<String, _Online> _onlineScreens() => {
  'main, channels': (() => const MainScreen(), prepare: null, shows: 'Ann'),
  'main, chat': (
    () => const MainScreen(),
    prepare: (t, client) async {
      await _tap(t, Icons.chat);
      client.applyLocalEvent(UserTextMessageEvent(_message(TtMsgType.channel)));
      await t.pumpAndSettle();
    },
    shows: 'Hello there',
  ),
  'main, files': (
    () => const MainScreen(),
    prepare: (t, _) => _tap(t, Icons.folder),
    shows: 'notes.txt',
  ),
  'main, menu': (
    () => const MainScreen(),
    prepare: (t, _) async {
      t.state<ScaffoldState>(find.byType(Scaffold).first).openDrawer();
      await t.pumpAndSettle();
    },
    shows: 'Change nickname',
  ),
  'main, title menu': (
    () => const MainScreen(),
    prepare: (t, _) async {
      await t.longPress(
        find.descendant(of: find.byType(AppBar), matching: find.text('Lobby')),
      );
      await t.pumpAndSettle();
    },
    shows: 'Disconnect',
  ),
  'main, status dialog': (
    () => const MainScreen(),
    prepare: (t, _) async {
      t.state<ScaffoldState>(find.byType(Scaffold).first).openDrawer();
      await t.pumpAndSettle();
      await t.tap(find.text('Change status'));
      await t.pumpAndSettle();
    },
    shows: 'Back soon',
  ),
  'channel info': (
    () => const ChannelInfoScreen(channelId: 2),
    prepare: null,
    shows: 'Talk here',
  ),
  'channel edit': (
    () => const ChannelEditScreen.edit(channelId: 2),
    prepare: null,
    shows: 'Lobby',
  ),
  'channel create': (
    () => const ChannelEditScreen.create(parentId: 1),
    prepare: null,
    shows: '',
  ),
  'private messages': (
    () => const PmScreen(userId: 8),
    prepare: (t, client) async {
      client.applyLocalEvent(UserTextMessageEvent(_message(TtMsgType.user)));
      await t.pumpAndSettle();
    },
    shows: 'Hello there',
  ),
  'user details': (
    () => const UserDetailScreen(userId: 8),
    prepare: null,
    shows: 'Back soon',
  ),
  'online users': (
    () => const OnlineUsersScreen(),
    prepare: null,
    shows: 'Bob',
  ),
  'user accounts': (
    () => const UserAccountsScreen(),
    prepare: null,
    shows: 'ann',
  ),
  'user account edit': (
    () => const UserAccountEditScreen(),
    prepare: null,
    shows: '',
  ),
  'banned users': (
    () => const BannedUsersScreen(),
    prepare: null,
    shows: 'Spammer',
  ),
  'server properties': (
    () => const ServerPropertiesScreen(),
    prepare: null,
    shows: '',
  ),
  'server statistics': (
    () => const ServerStatisticsScreen(),
    prepare: null,
    shows: '',
  ),
  'media stream': (() => const MediaStreamScreen(), prepare: null, shows: ''),
};

TtTextMessage _message(TtMsgType type) => TtTextMessage(
  type: type,
  fromUserId: 8,
  fromUsername: 'ann',
  toUserId: type == TtMsgType.user ? 7 : 0,
  channelId: type == TtMsgType.channel ? 2 : 0,
  text: 'Hello there',
  more: false,
);

Future<void> _tap(WidgetTester tester, IconData icon) async {
  await tester.tap(find.byIcon(icon).last);
  await tester.pumpAndSettle();
}

const _servers = [
  ServerEntry(name: 'Home', host: 'home.example', favorite: true),
  ServerEntry(name: 'Club', host: 'club.example', username: 'ann'),
];

TtUser _user(int id, String nickname, int channelId) => TtUser(
  id: id,
  username: nickname.toLowerCase(),
  nickname: nickname,
  statusMessage: id == 8 ? 'Back soon' : '',
  channelId: channelId,
  userState: 0,
  userType: 1,
  clientName: 'TeamTalkX',
);

TtChannel _channel(int id, String name, {bool hasPassword = false}) =>
    TtChannel(
      id: id,
      parentId: id == 1 ? 0 : 1,
      name: id == 1 ? '' : name,
      topic: id == 2 ? 'Talk here' : '',
      hasPassword: hasPassword,
      maxUsers: 100,
      channelType: ChannelTypes.permanent,
    );

class _OnlineClient extends PureTeamTalkClient {
  @override
  TtChannelConfig getChannelConfig(int channelId) =>
      const TtChannelConfig(name: 'Lobby', topic: 'Talk here', maxUsers: 100);

  @override
  Future<void> listUserAccounts({int index = 0, int count = 1000}) async =>
      applyLocalEvent(
        const UserAccountEvent(TtUserAccount(username: 'ann', note: 'Host')),
      );

  @override
  Future<void> listBans({
    int channelId = 0,
    int index = 0,
    int count = 1000,
  }) async => applyLocalEvent(
    const BannedUserEvent(
      TtBannedUser(
        ipAddress: '192.0.2.1',
        channelPath: '/',
        banTime: '2026/11/12 10:00',
        nickname: 'Spammer',
        username: '',
        banTypes: 0,
      ),
    ),
  );
}

PureTeamTalkClient _onlineClient() {
  final client = _OnlineClient();
  for (final event in <TtEvent>[
    const MyselfLoggedInEvent(7, userRights: 0x7fffffff),
    const ServerUpdateEvent(TtServerInfo(name: 'Home', motd: 'Welcome')),
    ChannelNewEvent(_channel(1, '')),
    ChannelNewEvent(_channel(2, 'Lobby')),
    ChannelNewEvent(_channel(3, 'Music', hasPassword: true)),
    UserLoggedInEvent(_user(7, 'Me', 2)),
    UserLoggedInEvent(_user(8, 'Ann', 2)),
    UserLoggedInEvent(_user(9, 'Bob', 3)),
    const FileNewEvent(
      TtRemoteFile(
        channelId: 2,
        fileId: 1,
        fileName: 'notes.txt',
        fileSize: 1200,
        username: 'ann',
        uploadTime: '2026/11/12 10:00',
      ),
    ),
  ]) {
    client.applyLocalEvent(event);
  }
  return client;
}

class _Session extends SessionController {
  _Session(this._initial);

  final ConnectionState _initial;

  @override
  ConnectionState build() => _initial;
}

Future<void> _check(
  WidgetTester tester,
  _Look look,
  Widget home, {
  required bool online,
  Future<void> Function(WidgetTester, TeamTalkClient)? prepare,
  String shows = '',
}) async {
  SharedPreferences.setMockInitialValues({
    'app_language': 'english',
    'speech_output': 'tts',
    'first_run_done': true,
    'server_list': ServerEntry.encodeList(_servers),
  });
  final prefs = await SharedPreferences.getInstance();
  final platform = FakePlatform();
  final TeamTalkClient client = online ? _onlineClient() : FakeVoiceClient();
  final db = AppDatabase(NativeDatabase.memory());
  addTearDown(() async {
    await db.close();
    await platform.dispose();
    if (client case final FakeVoiceClient c) await c.close();
  });
  tester.view
    ..physicalSize = const Size(1080, 2400)
    ..devicePixelRatio = 2.625;
  addTearDown(tester.view.reset);
  final semantics = tester.ensureSemantics();
  await tester.pumpWidget(
    ProviderScope(
      overrides: <Override>[
        ...platform.overrides,
        sharedPreferencesProvider.overrideWithValue(prefs),
        teamTalkClientProvider.overrideWithValue(client),
        connectionProvider.overrideWith(
          () => _Session(online ? const LoggedIn(7) : const Disconnected()),
        ),
        publicServersProvider.overrideWith((ref) async => _servers),
        appDatabaseProvider.overrideWithValue(db),
        certificatePinsProvider.overrideWith(
          (ref) => Stream.value([
            CertificatePin.authority(
              endpoint: 'b.example:10443',
              subject: '/CN=b.example',
              issuer: '/CN=Some CA',
              notAfter: DateTime.utc(2027),
              savedAt: DateTime.utc(2026),
            ),
          ]),
        ),
      ],
      child: MaterialApp(
        theme: appTheme(look.brightness, highContrast: look.highContrast),
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: home,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(look.textScale)),
          child: child!,
        ),
      ),
    ),
  );
  await tester.runAsync(
    () => Future<void>.delayed(const Duration(milliseconds: 100)),
  );
  await tester.pumpAndSettle(const Duration(milliseconds: 400));
  await prepare?.call(tester, client);
  if (shows.isNotEmpty) expect(find.textContaining(shows), findsWidgets);
  expect(await _failures(tester), isEmpty);
  semantics.dispose();
  await tester.pumpWidget(const SizedBox());
  await tester.pump();
  if (client case final PureTeamTalkClient c) c.dispose();
}

void main() {
  for (final MapEntry(key: name, value: screen) in _offlineScreens().entries) {
    for (final look in _Look.values) {
      testWidgets('$name, ${look.name}', (tester) async {
        await _check(tester, look, screen(), online: false);
      });
    }
  }
  for (final MapEntry(key: name, value: (screen, :prepare, :shows))
      in _onlineScreens().entries) {
    for (final look in _Look.values) {
      testWidgets('$name, ${look.name}', (tester) async {
        await _check(
          tester,
          look,
          screen(),
          online: true,
          prepare: prepare,
          shows: shows,
        );
      });
    }
  }
}
