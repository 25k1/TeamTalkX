import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/recording/recording_controller.dart';
import '../../domain/recording.dart';
import '../../l10n/l10n.dart';
import '../a11y/accessible_menu.dart';
import '../common/ui.dart';

extension RecordingModeLabel on RecordingMode {
  String label(AppLocalizations l10n) => switch (this) {
    RecordingMode.mixed => l10n.recordingModeMixed,
    RecordingMode.perUser => l10n.recordingModePerUser,
  };
}

extension RecordingFormatLabel on RecordingFormat {
  String label(AppLocalizations l10n) => switch (this) {
    RecordingFormat.wav => l10n.recordingFormatWav,
    RecordingFormat.oggOpus => l10n.recordingFormatOggOpus,
  };
}

class RecordingSettingsView extends ConsumerWidget {
  const RecordingSettingsView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final settings = ref.watch(recordingSettingsProvider);
    final notifier = ref.read(recordingSettingsProvider.notifier);
    final folder = settings.folder;
    return ListView(
      children: [
        ListTile(
          leading: const Icon(Icons.people),
          title: Text(l10n.recordingMode),
          subtitle: Text(settings.mode.label(l10n)),
          onTap: () async {
            final mode = await showSingleChoiceMenu<RecordingMode>(
              context,
              title: l10n.recordingMode,
              options: {for (final m in RecordingMode.values) m: m.label(l10n)},
              selected: settings.mode,
            );
            if (mode != null) notifier.setMode(mode);
          },
        ),
        ListTile(
          leading: const Icon(Icons.audio_file),
          title: Text(l10n.recordingFormat),
          subtitle: Text(settings.format.label(l10n)),
          onTap: () async {
            final format = await showSingleChoiceMenu<RecordingFormat>(
              context,
              title: l10n.recordingFormat,
              options: {
                for (final f in RecordingFormat.values) f: f.label(l10n),
              },
              selected: settings.format,
            );
            if (format != null) notifier.setFormat(format);
          },
        ),
        ListTile(
          leading: const Icon(Icons.folder_open),
          title: Text(l10n.recordingFolder),
          subtitle: Text(folder?.name ?? l10n.recordingDefaultFolder),
          onTap: () async {
            final messenger = ScaffoldMessenger.of(context);
            if (!await notifier.pickFolder()) return;
            final name = ref.read(recordingSettingsProvider).folder?.name;
            messenger.showMessage(l10n.recordingFolderPicked(name ?? ''));
          },
        ),
        if (folder != null)
          ListTile(
            leading: const Icon(Icons.folder_off),
            title: Text(l10n.recordingFolderForget),
            onTap: notifier.clearFolder,
          ),
        Padding(
          padding: const EdgeInsets.all(16),
          child: Text(l10n.recordingNote),
        ),
      ],
    );
  }
}
