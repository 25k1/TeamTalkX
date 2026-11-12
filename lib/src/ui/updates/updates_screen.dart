import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/app_info.dart';
import '../../app/platform_services.dart';
import '../../app/updates/update_controller.dart';
import '../../domain/app_update.dart';
import '../../l10n/l10n.dart';
import '../a11y/dialogs.dart';
import '../common/ui.dart';

class UpdatesScreen extends ConsumerWidget {
  const UpdatesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) => Scaffold(
    appBar: AppBar(title: Text(context.l10n.settingsUpdates)),
    body: const UpdatesView(),
  );
}

class UpdatesView extends ConsumerWidget {
  const UpdatesView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final state = ref.watch(updateControllerProvider);
    final controller = ref.read(updateControllerProvider.notifier);
    final version = ref.watch(appVersionProvider);
    final last = controller.lastCheck;
    final lastText = last == null
        ? l10n.updateNeverChecked
        : l10n.updateLastChecked(
            MaterialLocalizations.of(context).formatMediumDate(last),
          );

    final status = switch (state) {
      UpdateIdle() => lastText,
      UpdateChecking() => l10n.updateChecking,
      UpdateUpToDate() => '${l10n.updateUpToDate}. $lastText',
      UpdateAvailable(:final release) => l10n.updateAvailable(
        '${release.version}',
      ),
      UpdateDownloading(:final fraction) => l10n.updateDownloading(
        ((fraction ?? 0) * 100).round(),
      ),
      UpdateReady(:final release) => l10n.updateReady('${release.version}'),
      UpdateFailed(:final reason) => _problem(l10n, reason),
    };
    final release = switch (state) {
      UpdateAvailable(:final release) ||
      UpdateDownloading(:final release) ||
      UpdateReady(:final release) => release,
      UpdateFailed(:final release) => release,
      _ => null,
    };

    return ListView(
      children: [
        ListTile(
          leading: const Icon(Icons.info_outline),
          title: Text(l10n.aboutVersion(version)),
        ),
        Semantics(
          liveRegion: true,
          child: ListTile(
            leading: const Icon(Icons.system_update),
            title: Text(status),
            subtitle: switch (state) {
              UpdateDownloading(:final fraction) => LinearProgressIndicator(
                value: fraction,
              ),
              _ => null,
            },
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              if (release != null)
                OutlinedButton.icon(
                  icon: const Icon(Icons.article),
                  label: Text(l10n.updateWhatsNew),
                  onPressed: () => showWhatsNew(context, release),
                ),
              if (state is UpdateAvailable ||
                  (state is UpdateFailed && release != null))
                FilledButton.icon(
                  icon: const Icon(Icons.download),
                  label: Text(l10n.updateDownload),
                  onPressed: () => startUpdateDownload(context, ref, release!),
                ),
              if (state is UpdateDownloading)
                OutlinedButton.icon(
                  icon: const Icon(Icons.cancel),
                  label: Text(l10n.commonCancel),
                  onPressed: controller.cancelDownload,
                ),
              if (state is UpdateReady)
                FilledButton.icon(
                  icon: const Icon(Icons.install_mobile),
                  label: Text(l10n.updateInstall),
                  onPressed: () => installUpdate(context, ref),
                ),
              if (state is! UpdateDownloading && state is! UpdateChecking)
                OutlinedButton.icon(
                  icon: const Icon(Icons.refresh),
                  label: Text(l10n.updateCheckNow),
                  onPressed: () => unawaited(controller.check()),
                ),
            ],
          ),
        ),
        SwitchListTile(
          secondary: const Icon(Icons.science),
          title: Text(l10n.updateBetas),
          subtitle: Text(l10n.updateBetasSub),
          value: controller.betas,
          onChanged: (v) {
            controller.setBetas(v);
            unawaited(controller.check());
          },
        ),
        ListTile(subtitle: Text(l10n.updateAbout)),
      ],
    );
  }

  static String _problem(AppLocalizations l10n, UpdateProblem reason) =>
      switch (reason) {
        UpdateProblem.check => l10n.updateProblemCheck,
        UpdateProblem.download => l10n.updateProblemDownload,
        UpdateProblem.noApk => l10n.updateProblemNoApk,
        UpdateProblem.checksum => l10n.updateProblemChecksum,
        UpdateProblem.signature => l10n.updateProblemSignature,
        UpdateProblem.install => l10n.updateProblemInstall,
      };
}

Future<void> showWhatsNew(BuildContext context, AppRelease release) =>
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(context.l10n.updateWhatsNewIn('${release.version}')),
        content: SingleChildScrollView(
          child: Text(
            release.notes.trim().isEmpty
                ? context.l10n.updateNoNotes
                : release.notes.trim(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(context.l10n.commonOk),
          ),
        ],
      ),
    );

Future<void> startUpdateDownload(
  BuildContext context,
  WidgetRef ref,
  AppRelease release,
) async {
  final l10n = context.l10n;
  final device = await ref.read(appUpdaterProvider).device();
  final size = release.apkFor(device.abis)?.size ?? 0;
  if (await ref.read(appUpdaterProvider).isMetered()) {
    if (!context.mounted) return;
    final go = await confirm(
      context,
      title: l10n.updateMeteredTitle,
      message: l10n.updateMeteredBody(localizedFileSize(l10n, size)),
      confirmLabel: l10n.updateDownload,
    );
    if (!go) return;
  }
  unawaited(ref.read(updateControllerProvider.notifier).download(release));
}

Future<void> installUpdate(BuildContext context, WidgetRef ref) async {
  final messenger = ScaffoldMessenger.of(context);
  final l10n = context.l10n;
  final started = await ref.read(updateControllerProvider.notifier).install();
  if (!started) messenger.showMessage(l10n.updateAllowInstall);
}
