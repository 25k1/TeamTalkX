import 'package:flutter/material.dart';
import 'package:teamtalkx/src/data/app_database.dart';
import 'package:teamtalkx/src/data/chat_history_store.dart';
import 'package:teamtalkx/src/domain/chat_history.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(
    const MaterialApp(
      home: Scaffold(body: Center(child: Text('Chat history check'))),
    ),
  );
  void log(String line) => debugPrint('TTX-BENCH $line');
  final db = AppDatabase.open();
  const server = 's5-check.invalid:1';
  try {
    final store = ChatHistoryStore(db);
    final id = await store.add(
      StoredMessage(
        server: server,
        conversation: 'c:/',
        kind: StoredMessageKind.channel,
        sender: 'check',
        fromMe: false,
        text: 'ქართული ✓',
        time: DateTime.now(),
      ),
    );
    final page = await store.page(server, 'c:/');
    log('saved $id, read back "${page.single.text}"');
    log('unread before: ${await store.unreadCounts(server)}');
    await store.markRead([id]);
    log('unread after: ${await store.unreadCounts(server)}');
    await store.clearServer(server);
    log('after clearing: ${(await store.page(server, 'c:/')).length}');
    log(
      'schema ${db.schemaVersion}, pins kept: '
      '${(await db.select(db.certificatePins).get()).length}',
    );
  } on Object catch (e, st) {
    log('FAIL: $e\n$st');
  } finally {
    await db.close();
  }
  debugPrint('TTX-BENCH done');
}
