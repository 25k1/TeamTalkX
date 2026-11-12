import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show ScrollCacheExtent;

import '../../app/chat/chat_providers.dart';
import '../../l10n/l10n.dart';

class HistoryList extends StatefulWidget {
  const HistoryList({
    super.key,
    required this.entries,
    required this.active,
    required this.itemBuilder,
    required this.onReached,
    required this.onTopReached,
    required this.empty,
  });

  final List<ChatEntry> entries;
  final bool active;
  final Widget Function(BuildContext context, ChatEntry entry) itemBuilder;
  final void Function(ChatEntry entry) onReached;
  final VoidCallback onTopReached;
  final Widget empty;

  @override
  State<HistoryList> createState() => _HistoryListState();
}

class _HistoryListState extends State<HistoryList> {
  final _scroll = ScrollController();
  final _keys = <int, GlobalKey>{};
  bool _jumping = false;

  final _reached = <int>{};
  bool _jumpedOnOpen = false;

  ChatEntry? get _firstUnread =>
      widget.entries.where((e) => e.unread).firstOrNull;

  @override
  void didUpdateWidget(HistoryList old) {
    super.didUpdateWidget(old);
    if (!widget.active) _jumpedOnOpen = false;
  }

  void _maybeJumpOnOpen() {
    if (_jumpedOnOpen || !widget.active || _firstUnread == null) return;
    _jumpedOnOpen = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(_jumpToFirstUnread());
    });
  }

  Future<void> _jumpToFirstUnread() async {
    final target = _firstUnread;
    final id = target?.id;
    if (target == null || id == null || !_scroll.hasClients) return;
    final key = _keys.putIfAbsent(id, GlobalKey.new);
    setState(() => _jumping = true);
    try {
      for (var i = 0; i < 200 && mounted; i++) {
        final context = key.currentContext;
        if (context != null) {
          if (!context.mounted) break;
          await Scrollable.ensureVisible(context, alignment: 0.2);
          break;
        }
        final position = _scroll.position;
        if (position.pixels >= position.maxScrollExtent) break;
        _scroll.jumpTo(
          (position.pixels + position.viewportDimension).clamp(
            0,
            position.maxScrollExtent,
          ),
        );
        await WidgetsBinding.instance.endOfFrame;
      }
    } finally {
      if (mounted) setState(() => _jumping = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final entries = widget.entries;
    if (entries.isEmpty) return widget.empty;
    _maybeJumpOnOpen();
    final unread = entries.where((e) => e.unread).length;
    final l10n = context.l10n;
    return Column(
      children: [
        if (unread > 0)
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: TextButton.icon(
              icon: const Icon(Icons.vertical_align_top),
              label: Text(l10n.chatJumpToFirstUnread(unread)),
              onPressed: _jumpToFirstUnread,
            ),
          ),
        Expanded(
          child: ListView.builder(
            controller: _scroll,
            reverse: true,
            scrollCacheExtent: const ScrollCacheExtent.pixels(0),
            itemCount: entries.length,
            itemBuilder: (context, index) {
              final entry = entries[entries.length - 1 - index];
              if (index == entries.length - 1) {
                WidgetsBinding.instance.addPostFrameCallback(
                  (_) => widget.onTopReached(),
                );
              }
              final id = entry.id;
              if (entry.unread &&
                  widget.active &&
                  !_jumping &&
                  id != null &&
                  _reached.add(id)) {
                WidgetsBinding.instance.addPostFrameCallback(
                  (_) => widget.onReached(entry),
                );
              }
              return KeyedSubtree(
                key: id == null ? null : _keys.putIfAbsent(id, GlobalKey.new),
                child: widget.itemBuilder(context, entry),
              );
            },
          ),
        ),
      ],
    );
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }
}

Widget? unreadMarker(BuildContext context, ChatEntry entry) => entry.unread
    ? Icon(
        Icons.circle,
        size: 10,
        color: Theme.of(context).colorScheme.primary,
        semanticLabel: context.l10n.chatUnread,
      )
    : null;
