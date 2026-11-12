import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/chat_history.dart';
import '../../domain/events.dart';
import '../../domain/models.dart';
import '../connection/client_events.dart';
import '../connection/connection_providers.dart';
import '../platform_services.dart';
import '../settings/locale_providers.dart';
import '../settings/settings_providers.dart';
import '../settings/sound_player.dart';
import 'chat_history.dart';
import 'chat_providers.dart';

bool? parseTypingMessage(TtTextMessage message) {
  if (message.type != TtMsgType.custom) return null;
  final parts = message.text.split('\r\n');
  if (parts.length < 2 || parts[0] != 'typing') return null;
  return parts[1] == '1';
}

final typingUsersProvider = NotifierProvider<TypingUsersNotifier, Set<int>>(
  TypingUsersNotifier.new,
);

class TypingUsersNotifier extends Notifier<Set<int>> {
  final _timeouts = <int, Timer>{};

  static const _timeout = Duration(seconds: 10);

  @override
  Set<int> build() {
    ref.listenClientEvents((event) {
      switch (event) {
        case UserTextMessageEvent(:final message):
          final typing = parseTypingMessage(message);
          if (typing == null) {
            if (message.type == TtMsgType.user &&
                state.contains(message.fromUserId)) {
              _setTyping(message.fromUserId, false);
            }
            return;
          }
          _setTyping(message.fromUserId, typing);
        case ConLostEvent() || MyselfLoggedOutEvent():
          for (final timer in _timeouts.values) {
            timer.cancel();
          }
          _timeouts.clear();
          state = const {};
        default:
          break;
      }
    });
    ref.onDispose(() {
      for (final timer in _timeouts.values) {
        timer.cancel();
      }
    });
    return const {};
  }

  void _setTyping(int userId, bool typing) {
    _timeouts.remove(userId)?.cancel();
    if (typing) {
      if (!state.contains(userId)) {
        unawaited(ref.read(soundPlayerProvider).play(SoundEvent.typing));
        state = {...state, userId};
      }
      _timeouts[userId] = Timer(_timeout, () => _setTyping(userId, false));
    } else if (state.contains(userId)) {
      state = {...state}..remove(userId);
    }
  }
}

final pmProvider = NotifierProvider<PmNotifier, Map<int, List<ChatEntry>>>(
  PmNotifier.new,
);

class PmNotifier extends Notifier<Map<int, List<ChatEntry>>>
    with HistoryBatching {
  static const pageSize = 100;

  final _conversations = <int, String>{};
  final _loaded = <int, Future<void>>{};
  final _mayHaveOlder = <int>{};

  ChatHistory get _history => ref.read(chatHistoryProvider);

  bool mayHaveOlder(int userId) => _mayHaveOlder.contains(userId);

  String? conversationOf(int userId) {
    final known = _conversations[userId];
    if (known != null) return known;
    final user = ref.read(teamTalkClientProvider).state.users[userId];
    if (user == null) return null;
    return _conversations[userId] = privateConversation(
      username: user.username,
      nickname: user.nickname,
    );
  }

  @override
  Map<int, List<ChatEntry>> build() {
    ref.listenClientEvents((event) {
      switch (event) {
        case UserTextMessageEvent(:final message)
            when message.type == TtMsgType.user:
          final state = ref.read(teamTalkClientProvider).state;
          final fromMe = message.fromUserId == state.myUserId;
          final otherParty = fromMe ? message.toUserId : message.fromUserId;
          final sender =
              state.users[message.fromUserId]?.displayName ??
              message.fromUsername;
          _record(otherParty, sender, message.text, fromMe: fromMe);
          if (!fromMe) {
            unawaited(
              ref
                  .read(pmNotificationsProvider)
                  .show(
                    userId: otherParty,
                    title: sender,
                    message: message.text,
                  ),
            );
          }
        case ConLostEvent() || MyselfLoggedOutEvent():
          state = const {};
          _conversations.clear();
          _loaded.clear();
          _mayHaveOlder.clear();
        default:
          break;
      }
    });
    ref.onDispose(cancelBatching);
    return const {};
  }

  Future<void> ensureLoaded(int userId) =>
      _loaded[userId] ??= _loadNewest(userId);

  Future<void> _loadNewest(int userId) async {
    final server = _history.server;
    final conversation = conversationOf(userId);
    if (server == null || conversation == null) return;
    final saved = await _history.page(server, conversation, limit: pageSize);
    if (saved.length == pageSize) _mayHaveOlder.add(userId);
    final current = state[userId] ?? const <ChatEntry>[];
    final savedIds = {for (final m in saved) m.id};
    state = {
      ...state,
      userId: [
        ...saved.map(ChatEntry.stored),
        ...current.where((e) => e.id == null || !savedIds.contains(e.id)),
      ],
    };
  }

  Future<void> loadOlder(int userId) async {
    final server = _history.server;
    final conversation = conversationOf(userId);
    if (server == null || conversation == null) return;
    if (!_mayHaveOlder.remove(userId)) return;
    final entries = state[userId] ?? const <ChatEntry>[];
    final oldest = entries.where((e) => e.id != null).firstOrNull?.id;
    if (oldest == null) return;
    final older = await _history.page(
      server,
      conversation,
      beforeId: oldest,
      limit: pageSize,
    );
    if (older.length == pageSize) _mayHaveOlder.add(userId);
    state = {
      ...state,
      userId: [...older.map(ChatEntry.stored), ...?state[userId]],
    };
  }

  void _record(int userId, String sender, String text, {required bool fromMe}) {
    final server = _history.server;
    final conversation = conversationOf(userId);
    final time = DateTime.now();
    inOrder(() async {
      await ensureLoaded(userId);
      final message = StoredMessage(
        server: server ?? '',
        conversation: conversation ?? '',
        kind: StoredMessageKind.private,
        sender: sender,
        fromMe: fromMe,
        text: text,
        time: time,
      );
      final id = server == null || conversation == null
          ? null
          : await _history.save(message);
      _append(
        userId,
        ChatEntry.stored(
          StoredMessage(
            id: id,
            server: message.server,
            conversation: message.conversation,
            kind: message.kind,
            sender: sender,
            fromMe: fromMe,
            text: text,
            time: time,
          ),
        ),
      );
    });
  }

  void _append(int userId, ChatEntry entry) {
    state = {
      ...state,
      userId: [...(state[userId] ?? const <ChatEntry>[]), entry],
    };
  }

  void markRead(int userId, ChatEntry entry) {
    final id = entry.id;
    if (!entry.unread || id == null) return;
    markReadSoon(_history, id, (ids) {
      state = {
        for (final MapEntry(:key, :value) in state.entries)
          key: markedRead(value, ids),
      };
    });
  }

  Future<void> send(int userId, String text) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return;
    final client = ref.read(teamTalkClientProvider);
    await client.sendUserMessage(userId, trimmed);
    _record(
      userId,
      ref.read(appLocalizationsProvider).pmYou,
      trimmed,
      fromMe: true,
    );
  }

  void sendTypingStatus(int userId, {required bool typing}) {
    ref
        .read(teamTalkClientProvider)
        .sendCustomMessage(userId, 'typing\r\n${typing ? '1' : '0'}')
        .ignore();
  }
}

final pmUnreadProvider = Provider.family<int, int>((ref, userId) {
  final counts = ref.watch(unreadCountsProvider);
  final conversation = ref.read(pmProvider.notifier).conversationOf(userId);
  return conversation == null ? 0 : counts[conversation] ?? 0;
});
