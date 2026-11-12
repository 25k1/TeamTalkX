import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart' show CustomSemanticsAction;
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../l10n/l10n.dart';
import '../common/ui.dart';

final _urlRegex = RegExp(r'(https?://|www\.)[^\s]+', caseSensitive: false);

class MessageText extends StatelessWidget {
  const MessageText(this.text, {super.key, this.style, this.copyText});

  final String text;
  final TextStyle? style;

  final String? copyText;

  Uri? _uri(String raw) =>
      Uri.tryParse(raw.toLowerCase().startsWith('http') ? raw : 'https://$raw');

  Future<void> _open(String raw) async {
    final uri = _uri(raw);
    if (uri != null) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  void _copy(BuildContext context) {
    unawaited(Clipboard.setData(ClipboardData(text: copyText ?? text)));
    ScaffoldMessenger.of(context).showMessage(context.l10n.chatMessageCopied);
  }

  Future<void> _showMenu(BuildContext context, Offset position) async {
    final overlay = Overlay.of(context).context.findRenderObject() as RenderBox;
    final action = await showMenu<VoidCallback>(
      context: context,
      position: RelativeRect.fromRect(
        position & const Size(40, 40),
        Offset.zero & overlay.size,
      ),
      items: [
        PopupMenuItem<VoidCallback>(
          value: () => _copy(context),
          child: Text(context.l10n.chatCopyMessage),
        ),
      ],
    );
    action?.call();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final linkStyle = (style ?? const TextStyle()).copyWith(
      color: scheme.primary,
      decoration: TextDecoration.underline,
    );

    final spans = <InlineSpan>[];
    var last = 0;
    for (final match in _urlRegex.allMatches(text)) {
      if (match.start > last) {
        spans.add(TextSpan(text: text.substring(last, match.start)));
      }
      final raw = match.group(0)!;
      spans.add(
        WidgetSpan(
          alignment: PlaceholderAlignment.baseline,
          baseline: TextBaseline.alphabetic,
          child: Semantics(
            link: true,
            linkUrl: _uri(raw),
            child: GestureDetector(
              onTap: () => _open(raw),
              child: Text(raw, style: linkStyle),
            ),
          ),
        ),
      );
      last = match.end;
    }
    if (last < text.length) {
      spans.add(TextSpan(text: text.substring(last)));
    }

    return Semantics(
      customSemanticsActions: {
        CustomSemanticsAction(label: context.l10n.chatCopyMessage): () =>
            _copy(context),
      },
      child: GestureDetector(
        excludeFromSemantics: true,
        onLongPressStart: (details) =>
            _showMenu(context, details.globalPosition),
        child: Text.rich(TextSpan(style: style, children: spans)),
      ),
    );
  }
}
