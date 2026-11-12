import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/chat/chat_templates.dart';
import '../../l10n/l10n.dart';
import '../a11y/dialogs.dart';
import '../common/insert_variable_button.dart';
import '../common/labels.dart';
import '../common/text_controllers.dart';
import '../common/ui.dart';

class ChatTemplatesScreen extends ConsumerWidget {
  const ChatTemplatesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(chatTemplatesProvider);
    final notifier = ref.read(chatTemplatesProvider.notifier);
    final l10n = context.l10n;
    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.chatTemplatesTitle),
        actions: [
          IconButton(
            icon: const Icon(Icons.restore),
            tooltip: l10n.chatTemplatesResetAll,
            onPressed: () async {
              if (await confirm(
                context,
                title: l10n.chatTemplatesResetAllConfirm,
                confirmLabel: l10n.chatTemplatesResetAllButton,
              )) {
                ref.read(chatTemplatesProvider.notifier).resetAll();
              }
            },
          ),
        ],
      ),
      body: ListView(
        children: [
          for (final template in ChatTemplate.values)
            ListTile(
              title: Text(template.label(l10n)),
              subtitle: Text(
                notifier.of(template),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              onTap: () => pushScreen(
                context,
                ChatTemplateEditScreen(template: template),
              ),
            ),
        ],
      ),
    );
  }
}

class ChatTemplateEditScreen extends ConsumerStatefulWidget {
  const ChatTemplateEditScreen({super.key, required this.template});

  final ChatTemplate template;

  @override
  ConsumerState<ChatTemplateEditScreen> createState() =>
      _ChatTemplateEditScreenState();
}

class _ChatTemplateEditScreenState extends ConsumerState<ChatTemplateEditScreen>
    with TextControllers {
  late final TextEditingController _controller;

  ChatTemplate get _template => widget.template;
  ChatTemplatesNotifier get _notifier =>
      ref.read(chatTemplatesProvider.notifier);

  @override
  void initState() {
    super.initState();
    _controller = textController(_notifier.of(_template));
  }

  void _save(String value) => _notifier.setTemplate(_template, value);

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Scaffold(
      appBar: AppBar(title: Text(_template.label(l10n))),
      body: ListView(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: TextField(
              controller: _controller,
              maxLines: null,
              decoration: InputDecoration(
                labelText: l10n.chatTemplateField,
                helperText: l10n.chatTemplateFieldHelp,
              ),
              onChanged: _save,
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Wrap(
              spacing: 8,
              children: [
                InsertVariableButton(
                  controller: _controller,
                  variables: _template.variableDescriptions(l10n),
                  onChanged: _save,
                ),
                TextButton.icon(
                  icon: const Icon(Icons.restore),
                  label: Text(l10n.commonResetToDefault),
                  onPressed: () {
                    _notifier.reset(_template);
                    setControllerText(_controller, _notifier.of(_template));
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class TimestampScreen extends ConsumerStatefulWidget {
  const TimestampScreen({super.key});

  @override
  ConsumerState<TimestampScreen> createState() => _TimestampScreenState();
}

class _TimestampScreenState extends ConsumerState<TimestampScreen>
    with TextControllers {
  late final TextEditingController _controller;

  TimestampFormatNotifier get _notifier =>
      ref.read(timestampFormatProvider.notifier);

  @override
  void initState() {
    super.initState();
    _controller = textController(ref.read(timestampFormatProvider));
  }

  @override
  Widget build(BuildContext context) {
    final preview = formatTimestamp(
      ref.watch(timestampFormatProvider),
      DateTime.now(),
    );
    final l10n = context.l10n;
    return Scaffold(
      appBar: AppBar(title: Text(l10n.timestampTitle)),
      body: ListView(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: TextField(
              controller: _controller,
              maxLines: null,
              decoration: InputDecoration(
                labelText: l10n.timestampField,
                helperText: l10n.timestampFieldHelp('{date}'),
              ),
              onChanged: _notifier.set,
            ),
          ),
          ListTile(title: Text(l10n.timestampPreview), subtitle: Text(preview)),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Wrap(
              spacing: 8,
              children: [
                InsertVariableButton(
                  controller: _controller,
                  variables: timestampVariableDescriptions(l10n),
                  onChanged: _notifier.set,
                ),
                TextButton.icon(
                  icon: const Icon(Icons.restore),
                  label: Text(l10n.commonResetToDefault),
                  onPressed: () {
                    setControllerText(_controller, defaultTimestampFormat);
                    _notifier.set(defaultTimestampFormat);
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
