import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/settings/settings_providers.dart';
import '../../domain/media_keys.dart';
import '../../l10n/l10n.dart';
import '../a11y/accessible_menu.dart';
import '../common/labels.dart';
import 'settings_widgets.dart';

class MediaKeysScreen extends ConsumerWidget {
  const MediaKeysScreen({super.key});

  static const _none = '';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final bindings = ref.watch(settingsProvider.select((s) => s.keyBindings));
    final notifier = ref.read(settingsProvider.notifier);

    Widget tile(MediaKey key, KeyPress press) {
      final action = bindings.actionFor(key, press);
      final title = l10n.mediaKeyBinding(key.label(l10n), press.label(l10n));
      return ListTile(
        title: Text(title),
        subtitle: Text(action?.label(l10n) ?? l10n.keyActionNone),
        onTap: () async {
          final picked = await showSingleChoiceMenu<String>(
            context,
            title: title,
            options: {
              _none: l10n.keyActionNone,
              for (final a in KeyAction.values)
                if (a.availableFor(press)) a.name: a.label(l10n),
            },
            selected: action?.name ?? _none,
          );
          if (picked == null) return;
          notifier.setKeyAction(key, press, KeyAction.fromName(picked));
        },
      );
    }

    return Scaffold(
      appBar: AppBar(title: Text(l10n.settingsMediaKeys)),
      body: ListView(
        children: [
          ListTile(title: Text(l10n.mediaKeysIntro)),
          for (final key in MediaKey.values) ...[
            SectionHeader(key.label(l10n)),
            for (final press in KeyPress.values) tile(key, press),
          ],
        ],
      ),
    );
  }
}
