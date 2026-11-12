import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/announcer.dart';
import '../../app/connection/connection_providers.dart';
import '../../app/settings/locale_providers.dart';
import '../../app/users/user_selection_providers.dart';
import '../../domain/models.dart';
import '../../l10n/l10n.dart';
import '../a11y/accessible_menu.dart';
import '../a11y/accessible_widgets.dart';
import '../common/ui.dart';

class UserSelectionPanel extends ConsumerWidget {
  const UserSelectionPanel({super.key, required this.count});

  final int count;

  Future<void> _pickAndMove(BuildContext context, WidgetRef ref) async {
    final client = ref.read(teamTalkClientProvider);
    final channels = client.state.channels.values.toList()
      ..sort(
        (a, b) => client
            .channelPath(a.id)
            .toLowerCase()
            .compareTo(client.channelPath(b.id).toLowerCase()),
      );
    String labelFor(TtChannel c) {
      if (c.isRoot) {
        final name = client.state.serverInfo.name;
        return name.isEmpty ? '/' : name;
      }
      final path = client.channelPath(c.id);
      return path.isEmpty ? c.name : path;
    }

    final channelId = await showAccessibleMenu<int>(
      context,
      title: context.l10n.selectionMoveToChannel,
      items: [for (final c in channels) MenuItemSpec<int>(c.id, labelFor(c))],
    );
    if (channelId == null || !context.mounted) return;
    await moveSelectedUsers(context, ref, channelId);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final l10n = context.l10n;
    final label = l10n.selectionUsersSelected(count);
    void clear() {
      ref.read(userSelectionProvider.notifier).clear();
      ref.read(announcerProvider).announce(l10n.commonSelectionCleared);
    }

    return Material(
      color: scheme.surfaceContainerHighest,
      child: SafeArea(
        bottom: false,
        child: Row(
          children: [
            AccessibleIconButton(
              icon: Icons.close,
              label: l10n.commonUndoSelection,
              onPressed: clear,
            ),
            Expanded(
              child: Semantics(
                liveRegion: true,
                child: Text(
                  label,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
            ),
            Semantics(
              label: l10n.selectionMoveTo,
              button: true,
              excludeSemantics: true,
              onTap: () => _pickAndMove(context, ref),
              child: TextButton.icon(
                icon: const Icon(Icons.drive_file_move),
                label: Text(l10n.selectionMoveTo),
                onPressed: () => _pickAndMove(context, ref),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

Future<void> moveSelectedUsers(
  BuildContext context,
  WidgetRef ref,
  int channelId,
) async {
  final messenger = ScaffoldMessenger.of(context);
  final (moved, selected) = await ref
      .read(userSelectionProvider.notifier)
      .moveTo(channelId);
  if (moved < selected) {
    messenger.showMessage(
      ref.read(appLocalizationsProvider).selectionSomeNotMoved,
    );
  }
}
