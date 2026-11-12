import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../diagnostics/log.dart';
import '../../domain/chat_history.dart';
import '../../domain/events.dart';
import '../../domain/formatting.dart';
import '../../domain/models.dart';
import '../../l10n/l10n.dart';
import '../connection/client_events.dart';
import '../connection/connection_providers.dart';
import '../settings/locale_providers.dart';
import 'chat_history.dart';
import 'chat_templates.dart';

enum ChatEntryKind {
  channelMessage,
  broadcast,
  privateMessage,
  log,
  serverName,
  serverMotd,
  joinedChannel,
  channelTopic,
  channelQuota,
}

extension ChatEntryTemplate on ChatEntryKind {
  ChatTemplate get template => switch (this) {
    ChatEntryKind.channelMessage => ChatTemplate.channelMessage,
    ChatEntryKind.broadcast => ChatTemplate.broadcastMessage,
    ChatEntryKind.privateMessage => ChatTemplate.privateMessage,
    ChatEntryKind.log => ChatTemplate.logMessage,
    ChatEntryKind.serverName => ChatTemplate.serverName,
    ChatEntryKind.serverMotd => ChatTemplate.serverMotd,
    ChatEntryKind.joinedChannel => ChatTemplate.joinedChannel,
    ChatEntryKind.channelTopic => ChatTemplate.channelTopic,
    ChatEntryKind.channelQuota => ChatTemplate.channelQuota,
  };
}

class ChatEntry {
  ChatEntry({
    required this.kind,
    this.text = '',
    this.senderName = '',
    this.fromMe = false,
    this.vars = const {},
    this.id,
    this.unread = false,
    DateTime? time,
  }) : time = time ?? DateTime.now();

  factory ChatEntry.stored(StoredMessage m) => ChatEntry(
    kind: switch (m.kind) {
      StoredMessageKind.channel => ChatEntryKind.channelMessage,
      StoredMessageKind.broadcast => ChatEntryKind.broadcast,
      StoredMessageKind.private => ChatEntryKind.privateMessage,
    },
    text: m.text,
    senderName: m.sender,
    fromMe: m.fromMe,
    id: m.id,
    unread: !m.read && !m.fromMe,
    time: m.time,
  );

  final ChatEntryKind kind;
  final String senderName;
  final String text;
  final bool fromMe;
  final DateTime time;

  final Map<String, String> vars;

  final int? id;

  final bool unread;

  ChatEntry asRead() => ChatEntry(
    kind: kind,
    text: text,
    senderName: senderName,
    fromMe: fromMe,
    vars: vars,
    id: id,
    time: time,
  );
}

mixin HistoryBatching {
  Future<void> _saving = Future.value();
  final _toMarkRead = <int>{};
  Timer? _markTimer;

  void inOrder(Future<void> Function() work) {
    _saving = _saving.then((_) => work()).onError<Object>((e, st) {
      appLog.w('chat', 'Saving a message failed', e, st);
    });
  }

  void markReadSoon(ChatHistory history, int id, void Function(Set<int>) done) {
    _toMarkRead.add(id);
    _markTimer ??= Timer(const Duration(milliseconds: 300), () {
      _markTimer = null;
      final ids = {..._toMarkRead};
      _toMarkRead.clear();
      unawaited(history.markRead(ids));
      done(ids);
    });
  }

  void cancelBatching() => _markTimer?.cancel();
}

List<ChatEntry> markedRead(List<ChatEntry> entries, Set<int> ids) => [
  for (final e in entries) e.unread && ids.contains(e.id) ? e.asRead() : e,
];

final chatProvider = NotifierProvider<ChatNotifier, List<ChatEntry>>(
  ChatNotifier.new,
);

class ChatNotifier extends Notifier<List<ChatEntry>> with HistoryBatching {
  static const maxEntries = 300;
  static const pageSize = 100;

  String? _conversation;

  bool _mayHaveOlder = false;
  bool _loadingOlder = false;

  bool get mayHaveOlder => _mayHaveOlder;

  ChatHistory get _history => ref.read(chatHistoryProvider);

  @override
  List<ChatEntry> build() {
    ref.listenClientEvents(_onEvent);
    ref.listen(connectionProvider, (previous, next) {
      if (next is LoggedIn && previous is! LoggedIn) _onLoggedIn();
    });
    ref.onDispose(cancelBatching);
    return const [];
  }

  void _onLoggedIn() {
    final history = _history;
    final server = history.server;
    final entry = ref.read(connectionProvider.notifier).currentEntry;
    if (server == null || entry == null) return;
    unawaited(history.rememberServer(server, entry.displayName));
    unawaited(history.prune());
  }

  void _onEvent(TtEvent event) {
    final client = ref.read(teamTalkClientProvider);
    switch (event) {
      case UserTextMessageEvent(:final message):
        final sender = client.state.users[message.fromUserId];
        final senderName = sender?.displayName ?? message.fromUsername;
        final fromMe = message.fromUserId == client.state.myUserId;
        switch (message.type) {
          case TtMsgType.channel:
            _addMessage(
              StoredMessageKind.channel,
              senderName,
              message.text,
              fromMe: fromMe,
            );
          case TtMsgType.broadcast:
            _addMessage(
              StoredMessageKind.broadcast,
              senderName,
              message.text,
              fromMe: false,
            );
          case TtMsgType.user || TtMsgType.custom:
            break;
        }
      case ServerUpdateEvent(:final info):
        _add(
          ChatEntry(
            kind: ChatEntryKind.serverName,
            vars: {'{server}': info.name},
          ),
        );
        if (info.motd.isNotEmpty) {
          _add(
            ChatEntry(
              kind: ChatEntryKind.serverMotd,
              vars: {'{MOTD}': info.motd},
            ),
          );
        }
      case UserJoinedEvent(:final user) when user.id == client.state.myUserId:
        _addJoinedChannel(user.channelId);
        unawaited(_showConversation(user.channelId));
      case ConSuccessEvent():
        addLog(ref.read(appLocalizationsProvider).chatLogConnected);
      case MyselfLoggedInEvent():
        addLog(ref.read(appLocalizationsProvider).chatLogLoggedIn);
      case ConLostEvent():
        addLog(ref.read(appLocalizationsProvider).chatLogConnectionLost);
      case MyselfLoggedOutEvent():
        state = const [];
        _conversation = null;
      default:
        break;
    }
  }

  void _addMessage(
    StoredMessageKind kind,
    String sender,
    String text, {
    required bool fromMe,
  }) {
    final time = DateTime.now();
    final server = _history.server;
    final conversation =
        _conversation ??
        channelConversation(
          ref
              .read(teamTalkClientProvider)
              .channelPath(
                ref.read(teamTalkClientProvider).state.joinedChannelId,
              ),
        );
    inOrder(() async {
      final message = StoredMessage(
        server: server ?? '',
        conversation: conversation,
        kind: kind,
        sender: sender,
        fromMe: fromMe,
        text: text,
        time: time,
      );
      final id = server == null ? null : await _history.save(message);
      final entry = ChatEntry.stored(
        StoredMessage(
          id: id,
          server: message.server,
          conversation: conversation,
          kind: kind,
          sender: sender,
          fromMe: fromMe,
          text: text,
          time: time,
        ),
      );
      if (conversation == _conversation || _conversation == null) _add(entry);
    });
  }

  Future<void> _showConversation(int channelId) async {
    final client = ref.read(teamTalkClientProvider);
    final conversation = channelConversation(client.channelPath(channelId));
    _conversation = conversation;
    final server = _history.server;
    final saved = server == null
        ? const <StoredMessage>[]
        : await _history.page(server, conversation, limit: pageSize);
    if (_conversation != conversation) return;
    _mayHaveOlder = saved.length == pageSize;
    final logs = state.where((e) => e.id == null && !_isMessage(e));
    state = [...saved.map(ChatEntry.stored), ...logs]
      ..sort((a, b) => a.time.compareTo(b.time));
  }

  static bool _isMessage(ChatEntry e) =>
      e.kind == ChatEntryKind.channelMessage ||
      e.kind == ChatEntryKind.broadcast ||
      e.kind == ChatEntryKind.privateMessage;

  Future<void> loadOlder() async {
    final server = _history.server;
    final conversation = _conversation;
    if (!_mayHaveOlder || _loadingOlder || server == null) return;
    if (conversation == null) return;
    final oldest = state.where((e) => e.id != null).firstOrNull?.id;
    if (oldest == null) return;
    _loadingOlder = true;
    try {
      final older = await _history.page(
        server,
        conversation,
        beforeId: oldest,
        limit: pageSize,
      );
      if (_conversation != conversation) return;
      _mayHaveOlder = older.length == pageSize;
      state = [...older.map(ChatEntry.stored), ...state];
    } finally {
      _loadingOlder = false;
    }
  }

  void markRead(ChatEntry entry) {
    final id = entry.id;
    if (!entry.unread || id == null) return;
    markReadSoon(_history, id, (ids) => state = markedRead(state, ids));
  }

  void _addJoinedChannel(int channelId) {
    final client = ref.read(teamTalkClientProvider);
    final channel = client.state.channels[channelId];
    if (channel == null) return;
    final vars = {
      '{channelpath}': client.channelPath(channelId),
      '{channelname}': channel.name,
      '{channeltopic}': channel.topic,
      '{quota}': localizedFileSize(
        ref.read(appLocalizationsProvider),
        client.getChannelConfig(channelId).diskQuotaKB * 1024,
      ),
    };
    _add(ChatEntry(kind: ChatEntryKind.joinedChannel, vars: vars));
    _add(ChatEntry(kind: ChatEntryKind.channelTopic, vars: vars));
    _add(ChatEntry(kind: ChatEntryKind.channelQuota, vars: vars));
  }

  void addLog(String text) =>
      _add(ChatEntry(kind: ChatEntryKind.log, text: text));

  void _add(ChatEntry entry) {
    state = capped([...state, entry], maxEntries + pageSize * 10);
  }

  Future<void> sendToCurrentChannel(String text) async {
    final client = ref.read(teamTalkClientProvider);
    final channelId = client.state.joinedChannelId;
    if (channelId <= 0 || text.trim().isEmpty) return;
    await client.sendChannelMessage(channelId, text.trim());
  }
}

final channelChatUnreadProvider = Provider<int>((ref) {
  final counts = ref.watch(unreadCountsProvider);
  ref.watch(serverStateTickProvider);
  final client = ref.watch(teamTalkClientProvider);
  final channelId = client.state.joinedChannelId;
  if (channelId <= 0) return 0;
  return counts[channelConversation(client.channelPath(channelId))] ?? 0;
});
