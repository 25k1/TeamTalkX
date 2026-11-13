import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/chat_history_store.dart';
import '../../diagnostics/log.dart';
import '../../domain/chat_history.dart';
import '../connection/connection_providers.dart';
import '../security/certificate_trust.dart';
import '../settings/settings_providers.dart';

final chatHistoryStoreProvider = Provider<ChatHistoryStore>(
  (ref) => ChatHistoryStore(ref.watch(appDatabaseProvider)),
);

final chatHistoryProvider = Provider<ChatHistory>((ref) {
  final history = ChatHistory(ref);
  ref.onDispose(history.dispose);
  ref.listen(chatSettingsProvider.select((s) => s.chatRetentionDays), (_, _) {
    unawaited(history.prune());
  });
  return history;
});

class ChatHistory {
  ChatHistory(this._ref);

  final Ref _ref;
  final _changes = StreamController<void>.broadcast();
  bool _failed = false;

  Stream<void> get changes => _changes.stream;

  String? get server {
    final entry = _ref.read(connectionProvider.notifier).currentEntry;
    return entry == null ? null : chatServerKey(entry.host, entry.tcpPort);
  }

  Future<T?> _use<T>(Future<T> Function(ChatHistoryStore store) work) async {
    if (_failed) return null;
    try {
      return await work(_ref.read(chatHistoryStoreProvider));
    } on Object catch (e, st) {
      _failed = true;
      appLog.w('chat', 'Chat history unavailable; this session only', e, st);
      return null;
    }
  }

  void _changed() {
    if (!_changes.isClosed) _changes.add(null);
  }

  Future<int?> save(StoredMessage message) async {
    final id = await _use((s) => s.add(message));
    if (id != null) _changed();
    return id;
  }

  Future<List<StoredMessage>> page(
    String server,
    String conversation, {
    int? beforeId,
    int limit = 100,
  }) async =>
      await _use(
        (s) => s.page(server, conversation, beforeId: beforeId, limit: limit),
      ) ??
      const [];

  Future<void> markRead(Iterable<int> ids) async {
    await _use((s) => s.markRead(ids));
    _changed();
  }

  Future<Map<String, int>> unreadCounts(String server) async =>
      await _use((s) => s.unreadCounts(server)) ?? const {};

  Future<void> rememberServer(String server, String name) =>
      _use((s) => s.rememberServer(server, name));

  Future<void> prune() async {
    final days = _ref.read(chatSettingsProvider).chatRetentionDays;
    if (days <= 0) return;
    final removed = await _use(
      (s) => s.prune(DateTime.now().subtract(Duration(days: days))),
    );
    if ((removed ?? 0) > 0) {
      appLog.i('chat', 'Removed $removed messages older than $days days');
      _changed();
    }
  }

  Future<List<ChatServerSummary>> servers() async =>
      await _use((s) => s.servers()) ?? const [];

  Future<void> clearServer(String server) async {
    await _use((s) => s.clearServer(server));
    _changed();
  }

  Future<void> clearAll() async {
    await _use((s) => s.clearAll());
    _changed();
  }

  void dispose() => unawaited(_changes.close());
}

final unreadCountsProvider =
    NotifierProvider<UnreadCountsNotifier, Map<String, int>>(
      UnreadCountsNotifier.new,
    );

class UnreadCountsNotifier extends Notifier<Map<String, int>> {
  int _generation = 0;

  @override
  Map<String, int> build() {
    final history = ref.watch(chatHistoryProvider);
    final sub = history.changes.listen((_) => unawaited(_refresh()));
    ref.onDispose(sub.cancel);
    ref.listen(connectionProvider, (_, next) {
      if (next is LoggedIn) unawaited(_refresh());
      if (next is Disconnected) state = const {};
    });
    return const {};
  }

  Future<void> _refresh() async {
    final history = ref.read(chatHistoryProvider);
    final server = history.server;
    final generation = ++_generation;
    final counts = server == null
        ? const <String, int>{}
        : await history.unreadCounts(server);
    if (ref.mounted && generation == _generation) state = counts;
  }
}
