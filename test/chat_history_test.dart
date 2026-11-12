import 'package:drift/native.dart';
import 'package:flutter/material.dart' hide ConnectionState;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:teamtalkx/src/app/chat/chat_history.dart';
import 'package:teamtalkx/src/app/chat/chat_providers.dart';
import 'package:teamtalkx/src/app/chat/pm_providers.dart';
import 'package:teamtalkx/src/app/connection/connection_providers.dart';
import 'package:teamtalkx/src/app/security/certificate_trust.dart';
import 'package:teamtalkx/src/app/settings/settings_providers.dart';
import 'package:teamtalkx/src/data/app_database.dart';
import 'package:teamtalkx/src/data/chat_history_store.dart';
import 'package:teamtalkx/src/domain/chat_history.dart';
import 'package:teamtalkx/src/domain/events.dart';
import 'package:teamtalkx/src/domain/models.dart';
import 'package:teamtalkx/src/domain/server_entry.dart';
import 'package:teamtalkx/src/ui/chat/history_list.dart';

import 'support/fake_platform.dart';
import 'support/fake_voice_client.dart';
import 'support/localized_app.dart';

const _entry = ServerEntry(name: 'Home', host: 'TT.example', tcpPort: 10333);

class _Connection extends SessionController {
  @override
  ConnectionState build() => const LoggedIn(7);
  @override
  ServerEntry? get currentEntry => _entry;
}

class _ChatClient extends FakeVoiceClient {
  final sent = <(int, String)>[];
  @override
  String channelPath(int channelId) => channelId == 1 ? '/Room/' : '/';
  @override
  Future<void> sendUserMessage(int userId, String text) async =>
      sent.add((userId, text));
}

TtUser _user(int id, String username, String nickname) => TtUser(
  id: id,
  username: username,
  nickname: nickname,
  statusMessage: '',
  channelId: 1,
  userState: 0,
  userType: 1,
  clientName: '',
);

TtTextMessage _text(TtMsgType type, int from, String text, {int to = 0}) =>
    TtTextMessage(
      type: type,
      fromUserId: from,
      fromUsername: '',
      toUserId: to,
      channelId: 1,
      text: text,
      more: false,
    );

StoredMessage _stored(String text, {DateTime? time, String conv = 'c:/'}) =>
    StoredMessage(
      server: 's:1',
      conversation: conv,
      kind: StoredMessageKind.channel,
      sender: 'Ann',
      fromMe: false,
      text: text,
      time: time ?? DateTime.now(),
    );

void main() {
  test('a database from S1 gains the chat tables', () async {
    final db = AppDatabase(
      NativeDatabase.memory(
        setup: (raw) {
          raw
            ..execute(
              'CREATE TABLE certificate_pins (endpoint TEXT NOT NULL, '
              'sha256 TEXT NULL, subject TEXT NOT NULL, issuer TEXT NOT NULL, '
              'not_after INTEGER NOT NULL, saved_at INTEGER NOT NULL, '
              'PRIMARY KEY (endpoint))',
            )
            ..execute(
              "INSERT INTO certificate_pins VALUES ('a:1', 'ab', '', '', 0, 0)",
            )
            ..execute('PRAGMA user_version = 1');
        },
      ),
    );
    addTearDown(db.close);
    final store = ChatHistoryStore(db);
    await store.add(_stored('after upgrade'));
    expect((await store.page('s:1', 'c:/')).single.text, 'after upgrade');
    expect(await db.select(db.certificatePins).get(), hasLength(1));
  });

  group('ChatHistoryStore', () {
    late AppDatabase db;
    late ChatHistoryStore store;
    setUp(() {
      db = AppDatabase(NativeDatabase.memory());
      store = ChatHistoryStore(db);
    });
    tearDown(() => db.close());

    test('pages a conversation, oldest first', () async {
      for (var i = 0; i < 5; i++) {
        await store.add(_stored('m$i'));
      }
      await store.add(_stored('other', conv: 'c:/Other/'));
      final newest = await store.page('s:1', 'c:/', limit: 2);
      expect(newest.map((m) => m.text), ['m3', 'm4']);
      final older = await store.page(
        's:1',
        'c:/',
        beforeId: newest.first.id,
        limit: 10,
      );
      expect(older.map((m) => m.text), ['m0', 'm1', 'm2']);
    });

    test('unread until marked; own messages are read', () async {
      final a = await store.add(_stored('a'));
      await store.add(_stored('b'));
      await store.add(
        StoredMessage(
          server: 's:1',
          conversation: 'c:/',
          kind: StoredMessageKind.channel,
          sender: 'me',
          fromMe: true,
          text: 'mine',
          time: DateTime.now(),
        ),
      );
      expect(await store.unreadCounts('s:1'), {'c:/': 2});
      expect(await store.firstUnread('s:1', 'c:/'), a);
      await store.markRead([a]);
      expect(await store.unreadCounts('s:1'), {'c:/': 1});
    });

    test('prunes old messages and clears per server or all', () async {
      await store.add(
        _stored(
          'old',
          time: DateTime.now().subtract(const Duration(days: 100)),
        ),
      );
      await store.add(_stored('new'));
      await store.rememberServer('s:1', 'Home');
      expect(
        await store.prune(DateTime.now().subtract(const Duration(days: 90))),
        1,
      );
      final servers = await store.servers();
      expect(servers.single.name, 'Home');
      expect(servers.single.messages, 1);
      await store.clearServer('s:1');
      expect(await store.servers(), isEmpty);
    });
  });

  group('chat', () {
    late AppDatabase db;
    late FakePlatform platform;
    late _ChatClient client;
    late ProviderContainer c;

    Future<void> start({Map<String, Object> prefs = const {}}) async {
      SharedPreferences.setMockInitialValues({
        'speech_output': 'tts',
        ...prefs,
      });
      final shared = await SharedPreferences.getInstance();
      platform = FakePlatform();
      client = _ChatClient()..addMe();
      client.state.apply(UserLoggedInEvent(_user(8, 'ann', 'Ann')));
      c = ProviderContainer(
        overrides: [
          ...platform.overrides,
          sharedPreferencesProvider.overrideWithValue(shared),
          teamTalkClientProvider.overrideWithValue(client),
          connectionProvider.overrideWith(_Connection.new),
          appDatabaseProvider.overrideWithValue(db),
        ],
      );
      c
        ..listen(chatProvider, (_, _) {})
        ..listen(pmProvider, (_, _) {})
        ..listen(unreadCountsProvider, (_, _) {});
      await pumpEventQueue();
    }

    Future<void> stop() async {
      c.dispose();
      await platform.dispose();
      await client.close();
    }

    Future<void> settle() async {
      await pumpEventQueue();
      await Future<void>.delayed(const Duration(milliseconds: 20));
      await pumpEventQueue();
    }

    void emit(TtEvent event) {
      client.state.apply(event);
      client.eventController.add(event);
    }

    setUp(() => db = AppDatabase(NativeDatabase.memory()));
    tearDown(() => db.close());

    test('channel messages are saved and come back next session', () async {
      await start();
      emit(UserJoinedEvent(_user(7, '', 'me')));
      await settle();
      emit(UserTextMessageEvent(_text(TtMsgType.channel, 8, 'hello')));
      emit(UserTextMessageEvent(_text(TtMsgType.broadcast, 8, 'all')));
      await settle();

      final messages = c.read(chatProvider).where((e) => e.id != null).toList();
      expect(messages.map((e) => e.text), ['hello', 'all']);
      expect(messages.every((e) => e.unread), isTrue);
      expect(c.read(unreadCountsProvider), {'c:/Room/': 2});

      c.read(chatProvider.notifier).markRead(messages.first);
      await Future<void>.delayed(const Duration(milliseconds: 400));
      await settle();
      expect(c.read(unreadCountsProvider), {'c:/Room/': 1});
      await stop();

      await start();
      emit(UserJoinedEvent(_user(7, '', 'me')));
      await settle();
      final again = c.read(chatProvider).where((e) => e.id != null).toList();
      expect(again.map((e) => e.text), ['hello', 'all']);
      expect(again.map((e) => e.unread), [false, true]);
      await stop();
    });

    test('private chat is kept by username across sessions (D152)', () async {
      await start();
      emit(UserTextMessageEvent(_text(TtMsgType.user, 8, 'psst', to: 7)));
      await settle();
      expect(c.read(pmProvider)[8]!.single.text, 'psst');
      expect(c.read(pmUnreadProvider(8)), 1);
      await c.read(pmProvider.notifier).send(8, 'hi back');
      await settle();
      expect(client.sent, [(8, 'hi back')]);
      await stop();

      await start();
      client.state.apply(UserLoggedInEvent(_user(9, 'ann', 'Annie')));
      await c.read(pmProvider.notifier).ensureLoaded(9);
      final history = c.read(pmProvider)[9]!;
      expect(history.map((e) => e.text), ['psst', 'hi back']);
      expect(history.map((e) => e.fromMe), [false, true]);
      await stop();
    });

    test('a guest without a username is kept by nickname', () {
      expect(
        privateConversation(username: '', nickname: 'Guest 1'),
        'n:Guest 1',
      );
      expect(privateConversation(username: 'ann', nickname: 'x'), 'u:ann');
      expect(chatServerKey('TT.example', 10333), 'tt.example:10333');
    });

    test('messages older than the retention are dropped (D48)', () async {
      final store = ChatHistoryStore(db);
      await store.add(
        StoredMessage(
          server: 'tt.example:10333',
          conversation: 'c:/Room/',
          kind: StoredMessageKind.channel,
          sender: 'Ann',
          fromMe: false,
          text: 'ancient',
          time: DateTime.now().subtract(const Duration(days: 40)),
        ),
      );
      await start(prefs: {'chat_retention_days': 30});
      await c.read(chatHistoryProvider).prune();
      expect(await store.page('tt.example:10333', 'c:/Room/'), isEmpty);
      await stop();
    });
  });

  group('HistoryList', () {
    List<ChatEntry> entries(int unread) => [
      for (var i = 0; i < 3; i++)
        ChatEntry(
          kind: ChatEntryKind.channelMessage,
          text: 'm$i',
          id: i + 1,
          unread: i >= 3 - unread,
        ),
    ];

    Future<List<ChatEntry>> pump(
      WidgetTester tester, {
      required bool active,
    }) async {
      SharedPreferences.setMockInitialValues(const {'app_language': 'english'});
      final prefs = await SharedPreferences.getInstance();
      final reached = <ChatEntry>[];
      await tester.pumpWidget(
        ProviderScope(
          overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
          child: LocalizedTestApp(
            home: Scaffold(
              body: HistoryList(
                entries: entries(2),
                active: active,
                empty: const SizedBox(),
                itemBuilder: (context, e) => ListTile(
                  leading: unreadMarker(context, e),
                  title: Text(e.text),
                ),
                onReached: reached.add,
                onTopReached: () {},
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      return reached;
    }

    testWidgets('messages on a hidden tab stay unread (D154)', (tester) async {
      final reached = await pump(tester, active: false);
      expect(reached, isEmpty);
      expect(find.text('Jump to first unread (2)'), findsOneWidget);
    });

    testWidgets('messages on screen are reached', (tester) async {
      final semantics = tester.ensureSemantics();
      final reached = await pump(tester, active: true);
      expect(reached.map((e) => e.text), unorderedEquals(['m1', 'm2']));
      expect(find.bySemanticsLabel(RegExp('^Unread')), findsNWidgets(2));
      semantics.dispose();
    });
  });
}
