import 'package:flutter/material.dart' hide ConnectionState;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/connection/connection_providers.dart';
import '../../app/updates/update_controller.dart';
import '../../l10n/l10n.dart';
import '../channels/main_screen.dart';
import '../common/ui.dart';
import '../updates/updates_screen.dart';

Widget? updateBanner(
  BuildContext context,
  WidgetRef ref,
  ConnectionState connection,
) {
  if (connection is! Disconnected) return null;
  final l10n = context.l10n;
  final text = switch (ref.watch(updateControllerProvider)) {
    UpdateAvailable(:final release) => l10n.updateAvailable(
      '${release.version}',
    ),
    UpdateReady(:final release) => l10n.updateReady('${release.version}'),
    _ => null,
  };
  if (text == null) return null;
  return Material(
    color: Theme.of(context).colorScheme.tertiaryContainer,
    child: ListTile(
      leading: const Icon(Icons.system_update),
      title: Text(text),
      trailing: TextButton(
        onPressed: () => pushScreen(context, const UpdatesScreen()),
        child: Text(l10n.serverBannerOpen),
      ),
    ),
  );
}

Widget? connectionBanner(
  BuildContext context,
  WidgetRef ref,
  ConnectionState connection,
) {
  final l10n = context.l10n;
  final entry = ref.read(connectionProvider.notifier).currentEntry;
  if (entry == null || connection is Disconnected) return null;
  final connecting = connection is Connecting || connection is LoggingIn;
  return Material(
    color: Theme.of(context).colorScheme.secondaryContainer,
    child: Semantics(
      liveRegion: true,
      child: ListTile(
        leading: connecting
            ? const SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Icon(Icons.link),
        title: Text(
          connecting
              ? l10n.serverBannerConnecting(entry.displayName)
              : l10n.serverBannerConnected(entry.displayName),
        ),
        trailing: TextButton(
          onPressed: connecting
              ? () => ref.read(connectionProvider.notifier).disconnect()
              : () => pushScreen(context, const MainScreen()),
          child: Text(connecting ? l10n.commonCancel : l10n.serverBannerOpen),
        ),
      ),
    ),
  );
}
