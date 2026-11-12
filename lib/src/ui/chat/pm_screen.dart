import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/chat/pm_providers.dart';
import '../../app/connection/connection_providers.dart';
import '../../app/platform_services.dart';
import '../../l10n/l10n.dart';
import '../common/command_runner.dart';
import 'history_list.dart';
import 'message_text.dart';

class PmScreen extends ConsumerStatefulWidget {
  const PmScreen({super.key, required this.userId});

  final int userId;

  @override
  ConsumerState<PmScreen> createState() => _PmScreenState();
}

class _PmScreenState extends ConsumerState<PmScreen> {
  final _input = TextEditingController();
  Timer? _typingStop;
  bool _sentTyping = false;

  static const _typingIdle = Duration(seconds: 7);

  @override
  void initState() {
    super.initState();
    unawaited(ref.read(pmNotificationsProvider).cancel(widget.userId));
    unawaited(ref.read(pmProvider.notifier).ensureLoaded(widget.userId));
  }

  void _onInputChanged(String text) {
    final notifier = ref.read(pmProvider.notifier);
    if (text.isEmpty) {
      _stopTyping();
      return;
    }
    if (!_sentTyping) {
      _sentTyping = true;
      notifier.sendTypingStatus(widget.userId, typing: true);
    }
    _typingStop?.cancel();
    _typingStop = Timer(_typingIdle, _stopTyping);
  }

  void _stopTyping() {
    _typingStop?.cancel();
    if (_sentTyping) {
      _sentTyping = false;
      ref
          .read(pmProvider.notifier)
          .sendTypingStatus(widget.userId, typing: false);
    }
  }

  Future<void> _send() async {
    final text = _input.text;
    if (text.trim().isEmpty) return;
    _input.clear();
    _stopTyping();
    await ref.runCommand(
      ScaffoldMessenger.of(context),
      () => ref.read(pmProvider.notifier).send(widget.userId, text),
      errorLabel: (l) => l.actionSend,
    );
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(serverStateTickProvider);
    final client = ref.watch(teamTalkClientProvider);
    final user = client.state.users[widget.userId];
    final entries = ref.watch(pmProvider)[widget.userId] ?? const [];
    final online = user != null;
    final isTyping = ref.watch(typingUsersProvider).contains(widget.userId);
    final l10n = context.l10n;
    final title = user?.displayName ?? l10n.pmTitle;

    return Scaffold(
      appBar: AppBar(
        title: Semantics(
          label: isTyping ? l10n.pmTypingLabel(title) : title,
          excludeSemantics: true,
          header: true,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title),
              if (isTyping)
                Text(
                  l10n.pmTyping,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
            ],
          ),
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: HistoryList(
              entries: entries,
              active: true,
              empty: Center(child: Text(l10n.pmNoMessages)),
              onReached: (entry) =>
                  ref.read(pmProvider.notifier).markRead(widget.userId, entry),
              onTopReached: () => unawaited(
                ref.read(pmProvider.notifier).loadOlder(widget.userId),
              ),
              itemBuilder: (context, entry) {
                final local = entry.time.toLocal();
                final now = DateTime.now();
                final time = TimeOfDay.fromDateTime(local).format(context);
                final today =
                    local.year == now.year &&
                    local.month == now.month &&
                    local.day == now.day;
                final when = today
                    ? time
                    : '${MaterialLocalizations.of(context).formatShortDate(local)} $time';
                return ListTile(
                  dense: true,
                  leading: unreadMarker(context, entry),
                  title: Text(
                    entry.fromMe ? l10n.pmYou : entry.senderName,
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: entry.fromMe
                          ? Theme.of(context).colorScheme.primary
                          : null,
                    ),
                  ),
                  subtitle: MessageText(entry.text),
                  trailing: Text(
                    when,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                );
              },
            ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 8, 8),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _input,
                      enabled: online,
                      decoration: InputDecoration(
                        labelText: online
                            ? l10n.commonMessage
                            : l10n.pmUserOffline,
                      ),
                      textInputAction: TextInputAction.send,
                      onChanged: _onInputChanged,
                      onSubmitted: (_) => _send(),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.send),
                    tooltip: l10n.commonSend,
                    onPressed: online ? _send : null,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _typingStop?.cancel();
    _input.dispose();
    super.dispose();
  }
}
