import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/announcer.dart';
import '../../app/connection/connection_providers.dart';
import '../../app/files/file_providers.dart';
import '../../app/platform_services.dart';
import '../../app/settings/locale_providers.dart';
import '../../diagnostics/log.dart';
import '../../domain/models.dart';
import '../../domain/tt_types.dart';
import '../../l10n/l10n.dart';
import '../a11y/accessible_menu.dart';
import '../a11y/accessible_widgets.dart';
import '../a11y/context_menu_row.dart';
import '../a11y/dialogs.dart';
import '../common/command_runner.dart';
import '../common/labels.dart';
import '../common/ui.dart';

class FilesView extends ConsumerStatefulWidget {
  const FilesView({super.key});

  @override
  ConsumerState<FilesView> createState() => _FilesViewState();
}

class _FilesViewState extends ConsumerState<FilesView> {
  final _searchController = TextEditingController();
  bool _searchOpen = false;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _closeSearch() {
    setState(() => _searchOpen = false);
    _searchController.clear();
    ref.read(fileSearchProvider.notifier).clear();
  }

  Future<bool> _confirmOverride(String fileName) => confirm(
    context,
    title: context.l10n.filesOverrideTitle(fileName),
    confirmLabel: context.l10n.filesOverride,
  );

  Future<String?> _resolveDownloadPath(String fileName) async {
    final downloads = ref.read(downloadsProvider);
    try {
      if (await downloads.exists(fileName)) {
        if (!mounted || !await _confirmOverride(fileName)) return null;
        await downloads.remove(fileName);
      }
    } on PlatformException catch (e) {
      appLog.w('files', 'Could not check for an existing download', e);
    }
    return downloadPathFor(fileName);
  }

  Future<void> _upload() async {
    final client = ref.read(teamTalkClientProvider);
    final channelId = client.state.joinedChannelId;
    if (channelId <= 0) return;
    final file = await openFile();
    if (file == null) return;
    final clashes = client.state
        .filesInChannel(channelId)
        .any((f) => f.fileName == file.name);
    if (clashes) {
      if (!mounted || !await _confirmOverride(file.name)) return;
    }
    final waits = ref
        .read(transferQueueProvider.notifier)
        .upload(channelId, file.path, file.name);
    final l10n = ref.read(appLocalizationsProvider);
    ref
        .read(announcerProvider)
        .announce(
          waits ? l10n.transferQueued(file.name) : l10n.filesUploadStarted,
        );
  }

  Future<void> _download(TtRemoteFile file) async {
    final path = await _resolveDownloadPath(file.fileName);
    if (path == null) return;
    final waits = ref.read(transferQueueProvider.notifier).download(file, path);
    final l10n = ref.read(appLocalizationsProvider);
    ref
        .read(announcerProvider)
        .announce(
          waits
              ? l10n.transferQueued(file.fileName)
              : l10n.filesDownloadStarted,
        );
  }

  Future<void> _downloadSelected(List<TtRemoteFile> files) async {
    final selected = ref.read(fileSelectionProvider);
    final queue = ref.read(transferQueueProvider.notifier);
    final targets = files.where((f) => selected.contains(f.fileId)).toList();
    if (targets.isEmpty) return;
    var started = 0;
    for (final file in targets) {
      final path = await _resolveDownloadPath(file.fileName);
      if (path == null) continue;
      queue.download(file, path);
      started++;
    }
    ref.read(fileSelectionProvider.notifier).clear();
    ref
        .read(announcerProvider)
        .announce(ref.read(appLocalizationsProvider).filesDownloading(started));
  }

  Future<void> _delete(TtRemoteFile file) async {
    final messenger = ScaffoldMessenger.of(context);
    final confirmed = await confirm(
      context,
      title: context.l10n.filesDeleteTitle(file.fileName),
      confirmLabel: context.l10n.commonDelete,
    );
    if (!confirmed) return;
    await ref.runCommand(
      messenger,
      () => ref
          .read(teamTalkClientProvider)
          .deleteFile(file.channelId, file.fileId),
      errorLabel: (l) => l.actionDelete,
    );
  }

  void _toggleSelect(TtRemoteFile file) {
    final wasSelected = ref.read(fileSelectionProvider).contains(file.fileId);
    ref.read(fileSelectionProvider.notifier).toggle(file.fileId);
    ref
        .read(announcerProvider)
        .announce(
          wasSelected
              ? context.l10n.userDeselected(file.fileName)
              : context.l10n.userSelected(file.fileName),
        );
  }

  Future<void> _showSort() => showSortFor<FileSortField>(
    context,
    title: context.l10n.filesSortTitle,
    fields: FileSortField.values,
    labelOf: (f) => f.label(context.l10n),
    current: ref.read(fileSortProvider),
    notifier: ref.read(fileSortProvider.notifier),
    announce: ref.read(announcerProvider).announce,
  );

  @override
  Widget build(BuildContext context) {
    ref.watch(serverStateTickProvider);
    final client = ref.watch(teamTalkClientProvider);
    final state = client.state;
    final channelId = state.joinedChannelId;

    if (channelId <= 0) {
      return Center(child: Text(context.l10n.filesJoinToSee));
    }

    final files = ref.watch(visibleFilesProvider);
    final selection = ref.watch(fileSelectionProvider);
    final transfers = ref.watch(fileTransfersProvider).values.toList();
    final queued = ref.watch(transferQueueProvider);
    final canUpload = state.hasRight(UserRights.uploadFiles);
    final canDownload = state.hasRight(UserRights.downloadFiles);
    final searching = ref.watch(fileSearchProvider).isNotEmpty;

    return Column(
      children: [
        _toolbar(canUpload: canUpload, canDownload: canDownload, files: files),
        Expanded(
          child: ListView(
            children: [
              if (transfers.isNotEmpty || queued.isNotEmpty) ...[
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
                  child: Semantics(
                    header: true,
                    child: Text(
                      context.l10n.filesTransfers,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ),
                ),
                for (final transfer in transfers)
                  _TransferTile(transfer: transfer),
                for (final item in queued) _QueuedTile(item: item),
                const Divider(),
              ],
              if (files.isEmpty)
                Padding(
                  padding: const EdgeInsets.all(24),
                  child: Center(
                    child: Text(
                      searching
                          ? context.l10n.filesNoMatch
                          : context.l10n.filesNone,
                    ),
                  ),
                ),
              for (final file in files)
                _fileTile(file, selection: selection, canDownload: canDownload),
            ],
          ),
        ),
      ],
    );
  }

  Widget _toolbar({
    required bool canUpload,
    required bool canDownload,
    required List<TtRemoteFile> files,
  }) {
    final scheme = Theme.of(context).colorScheme;
    final selectionCount = ref.watch(fileSelectionProvider).length;
    final sort = ref.watch(fileSortProvider);
    final l10n = context.l10n;
    final sortText = sortLabel(l10n, sort, (f) => f.label(l10n));

    Widget content;
    if (selectionCount > 0) {
      final label = l10n.filesSelected(selectionCount);
      content = Row(
        children: [
          AccessibleIconButton(
            icon: Icons.close,
            label: l10n.commonUndoSelection,
            onPressed: () {
              ref.read(fileSelectionProvider.notifier).clear();
              ref.read(announcerProvider).announce(l10n.commonSelectionCleared);
            },
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
          if (canDownload)
            AccessibleIconButton(
              icon: Icons.download,
              label: l10n.filesDownloadSelected,
              onPressed: () => _downloadSelected(files),
            ),
        ],
      );
    } else if (_searchOpen) {
      content = Row(
        children: [
          AccessibleIconButton(
            icon: Icons.arrow_back,
            label: l10n.filesCloseSearch,
            onPressed: _closeSearch,
          ),
          Expanded(
            child: TextField(
              controller: _searchController,
              autofocus: true,
              textInputAction: TextInputAction.search,
              decoration: InputDecoration(
                hintText: l10n.filesSearch,
                border: InputBorder.none,
              ),
              onChanged: (value) =>
                  ref.read(fileSearchProvider.notifier).set(value),
            ),
          ),
          if (_searchController.text.isNotEmpty)
            AccessibleIconButton(
              icon: Icons.clear,
              label: l10n.commonClearSearch,
              onPressed: () {
                _searchController.clear();
                ref.read(fileSearchProvider.notifier).clear();
                setState(() {});
              },
            ),
        ],
      );
    } else {
      content = Row(
        children: [
          AccessibleIconButton(
            icon: Icons.search,
            label: l10n.filesSearch,
            onPressed: () => setState(() => _searchOpen = true),
          ),
          AccessibleIconButton(
            icon: Icons.sort,
            label: sortText,
            onPressed: _showSort,
          ),
          const Spacer(),
          if (canUpload)
            AccessibleIconButton(
              icon: Icons.upload_file,
              label: l10n.filesUpload,
              onPressed: _upload,
            ),
        ],
      );
    }

    return Material(
      color: scheme.surfaceContainerHighest,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: content,
      ),
    );
  }

  Widget _fileTile(
    TtRemoteFile file, {
    required Set<int> selection,
    required bool canDownload,
  }) {
    final selectionMode = selection.isNotEmpty;
    final selected = selection.contains(file.fileId);

    void toggle() => _toggleSelect(file);

    final l10n = context.l10n;
    final details = [
      localizedFileSize(l10n, file.fileSize),
      file.username,
      if (file.uploadTime.isNotEmpty) file.uploadTime,
    ].join(' ');

    return ContextMenuRow(
      semanticsLabel: '${file.fileName}, $details',
      selected: selectionMode ? selected : null,
      onTap: selectionMode
          ? toggle
          : (canDownload ? () => _download(file) : null),
      onLongPress: selectionMode ? toggle : null,
      menuTitle: file.fileName,
      actions: selectionMode
          ? [
              RowAction(
                selected ? l10n.commonDeselect : l10n.commonSelect,
                toggle,
              ),
            ]
          : [
              if (canDownload)
                RowAction(
                  l10n.commonDownload,
                  () => _download(file),
                  icon: Icons.download,
                ),
              RowAction(
                l10n.commonSelect,
                toggle,
                icon: Icons.check_box_outlined,
              ),
              RowAction(
                l10n.commonDelete,
                () => _delete(file),
                icon: Icons.delete,
              ),
            ],
      child: ListTile(
        leading: Icon(
          selectionMode
              ? (selected ? Icons.check_circle : Icons.radio_button_unchecked)
              : Icons.insert_drive_file,
        ),
        title: Text(file.fileName),
        subtitle: Text(details),
        selected: selected,
      ),
    );
  }
}

class _TransferTile extends ConsumerWidget {
  const _TransferTile({required this.transfer});

  final TtFileTransfer transfer;

  Future<void> _openFile(BuildContext context, WidgetRef ref) async {
    final messenger = ScaffoldMessenger.of(context);
    final l10n = context.l10n;
    final opened = await ref
        .read(downloadsProvider)
        .open(transfer.localFilePath);
    if (!opened) messenger.showMessage(l10n.filesNoAppToOpen);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final direction = transfer.inbound
        ? l10n.transferDownloading
        : l10n.transferUploading;
    final percent = (transfer.progress * 100).round();
    final savedPath = ref
        .read(fileTransfersProvider.notifier)
        .savedPath(transfer.transferId);
    final (statusText, active) = switch (transfer.status) {
      TtFileTransferStatus.active => (
        l10n.transferProgress(direction, percent),
        true,
      ),
      TtFileTransferStatus.finished => (
        savedPath == null
            ? l10n.transferCompleted
            : '${l10n.transferCompleted}, ${l10n.filesSavedTo(savedPath)}',
        false,
      ),
      TtFileTransferStatus.error => (l10n.transferFailed, false),
      TtFileTransferStatus.closed => (l10n.transferCancelled, false),
    };
    final downloaded =
        !active &&
        transfer.inbound &&
        transfer.status == TtFileTransferStatus.finished &&
        transfer.localFilePath.startsWith('content://');

    void cancel() =>
        ref.read(fileTransfersProvider.notifier).cancel(transfer.transferId);
    void dismiss() =>
        ref.read(fileTransfersProvider.notifier).dismiss(transfer.transferId);

    return ContextMenuRow(
      semanticsLabel: '${transfer.remoteFileName}, $statusText',
      menuTitle: transfer.remoteFileName,
      onTap: downloaded ? () => _openFile(context, ref) : null,
      actions: [
        if (active)
          RowAction(l10n.transferCancel, cancel, icon: Icons.cancel)
        else ...[
          if (downloaded)
            RowAction(
              l10n.transferOpenFile,
              () => _openFile(context, ref),
              icon: Icons.open_in_new,
            ),
          RowAction(l10n.transferRemove, dismiss, icon: Icons.clear),
        ],
      ],
      child: ListTile(
        leading: Icon(transfer.inbound ? Icons.download : Icons.upload),
        title: Text(transfer.remoteFileName),
        subtitle: active
            ? LinearProgressIndicator(value: transfer.progress)
            : Text(statusText),
        trailing: active
            ? IconButton(
                icon: const Icon(Icons.cancel),
                tooltip: l10n.commonCancel,
                onPressed: cancel,
              )
            : null,
      ),
    );
  }
}

class _QueuedTile extends ConsumerWidget {
  const _QueuedTile({required this.item});

  final QueuedTransfer item;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final status = item.inbound
        ? l10n.transferQueuedDownload
        : l10n.transferQueuedUpload;
    void cancel() => ref.read(transferQueueProvider.notifier).cancel(item.id);
    return ContextMenuRow(
      semanticsLabel: '${item.name}, $status',
      menuTitle: item.name,
      actions: [RowAction(l10n.transferCancel, cancel, icon: Icons.cancel)],
      child: ListTile(
        leading: Icon(item.inbound ? Icons.download : Icons.upload),
        title: Text(item.name),
        subtitle: Text(status),
      ),
    );
  }
}
