import 'package:drift/drift.dart';

import '../domain/chat_history.dart';
import 'app_database.dart';

class ChatHistoryStore {
  ChatHistoryStore(this._db);

  final AppDatabase _db;

  $ChatMessagesTable get _messages => _db.chatMessages;

  Future<int> add(StoredMessage m) => _db
      .into(_messages)
      .insert(
        ChatMessagesCompanion.insert(
          server: m.server,
          conversation: m.conversation,
          kind: m.kind.name,
          sender: m.sender,
          fromMe: m.fromMe,
          body: m.text,
          sentAt: m.time,
          read: Value(m.read || m.fromMe),
        ),
      );

  Future<List<StoredMessage>> page(
    String server,
    String conversation, {
    int? beforeId,
    int limit = 100,
  }) async {
    final query = _db.select(_messages)
      ..where(
        (t) =>
            t.server.equals(server) &
            t.conversation.equals(conversation) &
            (beforeId == null
                ? const Constant(true)
                : t.id.isSmallerThanValue(beforeId)),
      )
      ..orderBy([(t) => OrderingTerm.desc(t.id)])
      ..limit(limit);
    final rows = await query.get();
    return [for (final row in rows.reversed) _message(row)];
  }

  Future<int?> firstUnread(String server, String conversation) async {
    final query = _db.selectOnly(_messages)
      ..addColumns([_messages.id.min()])
      ..where(
        _messages.server.equals(server) &
            _messages.conversation.equals(conversation) &
            _messages.read.equals(false),
      );
    return (await query.getSingle()).read(_messages.id.min());
  }

  Future<Map<String, int>> unreadCounts(String server) async {
    final count = _messages.id.count();
    final query = _db.selectOnly(_messages)
      ..addColumns([_messages.conversation, count])
      ..where(_messages.server.equals(server) & _messages.read.equals(false))
      ..groupBy([_messages.conversation]);
    return {
      for (final row in await query.get())
        row.read(_messages.conversation)!: row.read(count) ?? 0,
    };
  }

  Future<void> markRead(Iterable<int> ids) async {
    final list = ids.toList();
    if (list.isEmpty) return;
    await (_db.update(_messages)..where((t) => t.id.isIn(list))).write(
      const ChatMessagesCompanion(read: Value(true)),
    );
  }

  Future<int> prune(DateTime before) => (_db.delete(
    _messages,
  )..where((t) => t.sentAt.isSmallerThanValue(before))).go();

  Future<void> rememberServer(String server, String name) => _db
      .into(_db.chatServers)
      .insertOnConflictUpdate(
        ChatServersCompanion.insert(server: server, name: name),
      );

  Future<List<ChatServerSummary>> servers() async {
    final count = _messages.id.count();
    final query = _db.selectOnly(_messages)
      ..addColumns([_messages.server, count])
      ..groupBy([_messages.server]);
    final counts = {
      for (final row in await query.get())
        row.read(_messages.server)!: row.read(count) ?? 0,
    };
    final names = {
      for (final row in await _db.select(_db.chatServers).get())
        row.server: row.name,
    };
    final summaries = [
      for (final MapEntry(key: server, value: messages) in counts.entries)
        ChatServerSummary(
          server: server,
          name: names[server] ?? server,
          messages: messages,
        ),
    ]..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return summaries;
  }

  Future<void> clearServer(String server) async {
    await (_db.delete(_messages)..where((t) => t.server.equals(server))).go();
    await (_db.delete(
      _db.chatServers,
    )..where((t) => t.server.equals(server))).go();
  }

  Future<void> clearAll() async {
    await _db.delete(_messages).go();
    await _db.delete(_db.chatServers).go();
  }

  StoredMessage _message(ChatMessageRow row) => StoredMessage(
    id: row.id,
    server: row.server,
    conversation: row.conversation,
    kind: StoredMessageKind.values.firstWhere(
      (k) => k.name == row.kind,
      orElse: () => StoredMessageKind.channel,
    ),
    sender: row.sender,
    fromMe: row.fromMe,
    text: row.body,
    time: row.sentAt,
    read: row.read,
  );
}
