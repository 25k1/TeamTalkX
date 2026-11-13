import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/chat/chat_providers.dart';
import '../../app/chat/chat_templates.dart';
import '../../app/connection/connection_providers.dart';
import '../../l10n/l10n.dart';
import '../common/command_runner.dart';
import 'history_list.dart';
import 'message_text.dart';

class ChatView extends ConsumerStatefulWidget {
  const ChatView({super.key, this.active = true});

  final bool active;

  @override
  ConsumerState<ChatView> createState() => _ChatViewState();
}

class _ChatViewState extends ConsumerState<ChatView> {
  final _input = TextEditingController();

  Future<void> _send() async {
    final text = _input.text.trim();
    if (text.isEmpty) return;
    _input.clear();
    await ref.runCommand(
      ScaffoldMessenger.of(context),
      () => ref.read(chatProvider.notifier).sendToCurrentChannel(text),
      errorLabel: (l) => l.actionSend,
    );
  }

  @override
  Widget build(BuildContext context) {
    final entries = ref.watch(chatProvider);
    final client = ref.watch(teamTalkClientProvider);
    ref.watch(serverStateTickProvider);
    final inChannel = client.state.joinedChannelId > 0;
    final l10n = context.l10n;

    return Column(
      children: [
        Expanded(
          child: HistoryList(
            entries: entries,
            active: widget.active,
            empty: Center(child: Text(l10n.chatNoMessages)),
            itemBuilder: (context, entry) => _ChatEntryTile(entry: entry),
            onReached: ref.read(chatProvider.notifier).markRead,
            onTopReached: () =>
                unawaited(ref.read(chatProvider.notifier).loadOlder()),
          ),
        ),
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(8, 4, 8, 4),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _input,
                    textCapitalization: TextCapitalization.sentences,
                    enabled: inChannel,
                    decoration: InputDecoration(
                      labelText: inChannel
                          ? l10n.commonMessage
                          : l10n.chatJoinToChat,
                    ),
                    textInputAction: TextInputAction.send,
                    onSubmitted: (_) => _send(),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.send),
                  tooltip: l10n.commonSend,
                  onPressed: inChannel ? _send : null,
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }
}

class _ChatEntryTile extends ConsumerWidget {
  const _ChatEntryTile({required this.entry});

  final ChatEntry entry;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final date = formatTimestamp(
      ref.watch(timestampFormatProvider),
      entry.time,
    );

    final vars = <String, String>{
      '{date}': date,
      switch (entry.kind) {
        ChatEntryKind.channelMessage ||
        ChatEntryKind.broadcast ||
        ChatEntryKind.privateMessage => '{user}',
        _ => '{ignore}',
      }: entry.senderName,
      '{content}': entry.text,
      ...entry.vars,
    };

    ref.watch(chatTemplatesProvider);
    final text = ref
        .read(chatTemplatesProvider.notifier)
        .format(entry.kind.template, vars);

    const messageKinds = {
      ChatEntryKind.channelMessage,
      ChatEntryKind.broadcast,
      ChatEntryKind.privateMessage,
    };
    return ListTile(
      dense: true,
      leading: unreadMarker(context, entry),
      title: MessageText(
        text,
        copyText: messageKinds.contains(entry.kind) ? entry.text : text,
        style: entry.fromMe
            ? TextStyle(color: theme.colorScheme.onSurfaceVariant)
            : null,
      ),
    );
  }
}
