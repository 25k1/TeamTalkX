import 'dart:async';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import '../../diagnostics/log.dart';
import '../../domain/events.dart';
import '../../domain/models.dart';
import '../announcer.dart';
import '../connection/client_events.dart';
import '../connection/connection_providers.dart';
import '../platform_services.dart';
import '../settings/locale_providers.dart';
import 'sort.dart';

enum FileSortField { name, size, owner, date }

final fileSortProvider =
    NotifierProvider<FileSortNotifier, SortState<FileSortField>>(
      FileSortNotifier.new,
    );

class FileSortNotifier extends SortNotifier<FileSortField> {
  @override
  FileSortField get defaultField => FileSortField.name;
}

final fileSearchProvider = NotifierProvider<FileSearchNotifier, String>(
  FileSearchNotifier.new,
);

class FileSearchNotifier extends Notifier<String> {
  @override
  String build() => '';

  void set(String query) => state = query;
  void clear() => state = '';
}

final fileSelectionProvider = NotifierProvider<FileSelectionNotifier, Set<int>>(
  FileSelectionNotifier.new,
);

class FileSelectionNotifier extends Notifier<Set<int>> {
  @override
  Set<int> build() {
    final client = ref.read(teamTalkClientProvider);
    ref.listenClientEvents((event) {
      switch (event) {
        case UserJoinedEvent(:final user) when user.id == client.state.myUserId:
          state = const {};
        case ConLostEvent() || MyselfLoggedOutEvent():
          state = const {};
        default:
          break;
      }
    });
    return const {};
  }

  bool isSelected(int fileId) => state.contains(fileId);

  void toggle(int fileId) {
    state = state.contains(fileId)
        ? ({...state}..remove(fileId))
        : {...state, fileId};
  }

  void clear() => state = const {};
}

List<TtRemoteFile> sortAndFilterFiles(
  List<TtRemoteFile> files,
  SortState<FileSortField> sort,
  String query,
) {
  final needle = query.trim().toLowerCase();
  final result = [
    for (final file in files)
      if (needle.isEmpty || file.fileName.toLowerCase().contains(needle)) file,
  ];

  int cmp(TtRemoteFile a, TtRemoteFile b) => switch (sort.field) {
    FileSortField.name => a.fileName.toLowerCase().compareTo(
      b.fileName.toLowerCase(),
    ),
    FileSortField.size => a.fileSize.compareTo(b.fileSize),
    FileSortField.owner => a.username.toLowerCase().compareTo(
      b.username.toLowerCase(),
    ),
    FileSortField.date => a.uploadTime.compareTo(b.uploadTime),
  };

  result.sort((a, b) {
    final primary = cmp(a, b);
    final ordered = primary != 0
        ? primary
        : a.fileName.toLowerCase().compareTo(b.fileName.toLowerCase());
    return sort.ascending ? ordered : -ordered;
  });
  return result;
}

final visibleFilesProvider = Provider<List<TtRemoteFile>>((ref) {
  ref.watch(serverStateTickProvider);
  final state = ref.watch(teamTalkClientProvider).state;
  final channelId = state.joinedChannelId;
  if (channelId <= 0) return const [];

  return sortAndFilterFiles(
    state.filesInChannel(channelId),
    ref.watch(fileSortProvider),
    ref.watch(fileSearchProvider),
  );
});

final fileTransfersProvider =
    NotifierProvider<FileTransfersNotifier, Map<int, TtFileTransfer>>(
      FileTransfersNotifier.new,
    );

class FileTransfersNotifier extends Notifier<Map<int, TtFileTransfer>> {
  Timer? _pollTimer;
  final _savedPaths = <int, String>{};

  final _announcedQuarter = <int, int>{};
  final _saved = StreamController<SavedDownload>.broadcast();

  Stream<SavedDownload> get saved => _saved.stream;

  String? savedPath(int transferId) => _savedPaths[transferId];

  @override
  Map<int, TtFileTransfer> build() {
    ref.listenClientEvents((event) {
      switch (event) {
        case FileTransferEvent(:final transfer):
          final autoClear =
              transfer.status == TtFileTransferStatus.finished &&
              !transfer.inbound;
          state = autoClear
              ? ({...state}..remove(transfer.transferId))
              : {...state, transfer.transferId: transfer};
          _syncPolling();
          if (transfer.inbound &&
              transfer.status == TtFileTransferStatus.finished) {
            unawaited(_publish(transfer));
          }
          if (transfer.inbound &&
              transfer.status != TtFileTransferStatus.active &&
              transfer.status != TtFileTransferStatus.finished) {
            unawaited(_deleteTemp(transfer.localFilePath));
          }
        case ConLostEvent() || MyselfLoggedOutEvent():
          state = const {};
          _syncPolling();
        default:
          break;
      }
    });
    ref.onDispose(() {
      _pollTimer?.cancel();
      unawaited(_saved.close());
    });
    return const {};
  }

  Future<void> _publish(TtFileTransfer transfer) async {
    try {
      final saved = await ref
          .read(downloadsProvider)
          .publish(transfer.localFilePath, transfer.remoteFileName);
      _savedPaths[transfer.transferId] = saved.path;
      _update(transfer, localFilePath: saved.uri);
      if (!_saved.isClosed) {
        _saved.add(
          SavedDownload(
            transferId: transfer.transferId,
            name: transfer.remoteFileName,
            path: saved.path,
            uri: saved.uri,
          ),
        );
      }
    } on Object catch (e, st) {
      appLog.w('files', 'Saving download ${transfer.transferId} failed', e, st);
      _update(transfer, status: TtFileTransferStatus.error);
    } finally {
      await _deleteTemp(transfer.localFilePath);
    }
  }

  void _update(
    TtFileTransfer transfer, {
    String? localFilePath,
    TtFileTransferStatus? status,
  }) {
    if (!state.containsKey(transfer.transferId)) return;
    state = {
      ...state,
      transfer.transferId: TtFileTransfer(
        status: status ?? transfer.status,
        transferId: transfer.transferId,
        channelId: transfer.channelId,
        localFilePath: localFilePath ?? transfer.localFilePath,
        remoteFileName: transfer.remoteFileName,
        fileSize: transfer.fileSize,
        transferred: transfer.transferred,
        inbound: transfer.inbound,
      ),
    };
  }

  static Future<void> _deleteTemp(String path) async {
    if (path.startsWith('content://')) return;
    try {
      final dir = File(path).parent;
      if (RegExp(r'[\\/]downloads[\\/][^\\/]+$').hasMatch(dir.path)) {
        await dir.delete(recursive: true);
      }
    } on FileSystemException catch (_) {}
  }

  void _syncPolling() {
    final anyActive = state.values.any(
      (t) => t.status == TtFileTransferStatus.active,
    );
    if (anyActive) {
      _pollTimer ??= Timer.periodic(
        const Duration(milliseconds: 250),
        (_) => _poll(),
      );
    } else {
      _pollTimer?.cancel();
      _pollTimer = null;
    }
  }

  void _poll() {
    final client = ref.read(teamTalkClientProvider);
    var changed = false;
    final next = {...state};
    for (final entry in state.entries) {
      if (entry.value.status != TtFileTransferStatus.active) continue;
      final info = client.getFileTransferInfo(entry.key);
      if (info != null && info.transferred != entry.value.transferred) {
        next[entry.key] = info;
        changed = true;
        _announceProgress(info);
      }
    }
    if (changed) state = next;
  }

  void _announceProgress(TtFileTransfer t) {
    if (t.fileSize <= 0) return;
    final quarter = (t.transferred * 4 / t.fileSize).floor();
    if (quarter <= (_announcedQuarter[t.transferId] ?? 0) || quarter >= 4) {
      return;
    }
    _announcedQuarter[t.transferId] = quarter;
    ref
        .read(announcerProvider)
        .announce(
          ref
              .read(appLocalizationsProvider)
              .transferProgressAnnounce(t.remoteFileName, quarter * 25),
        );
  }

  void cancel(int transferId) {
    ref.read(teamTalkClientProvider).cancelFileTransfer(transferId);
    state = {...state}..remove(transferId);
    _syncPolling();
  }

  void dismiss(int transferId) {
    state = {...state}..remove(transferId);
    _syncPolling();
  }
}

Future<String> downloadPathFor(String fileName) async {
  final cache = await getApplicationCacheDirectory();
  final sep = Platform.pathSeparator;
  final dir = Directory(
    '${cache.path}${sep}downloads$sep${DateTime.now().microsecondsSinceEpoch}',
  );
  await dir.create(recursive: true);
  return '${dir.path}$sep$fileName';
}

class SavedDownload {
  const SavedDownload({
    required this.transferId,
    required this.name,
    required this.path,
    required this.uri,
  });

  final int transferId;
  final String name;

  final String path;
  final String uri;
}

class QueuedTransfer {
  const QueuedTransfer({
    required this.id,
    required this.inbound,
    required this.channelId,
    required this.name,
    required this.localPath,
    this.fileId = 0,
  });

  final int id;
  final bool inbound;
  final int channelId;
  final String name;
  final String localPath;

  final int fileId;
}

final transferQueueProvider =
    NotifierProvider<TransferQueueNotifier, List<QueuedTransfer>>(
      TransferQueueNotifier.new,
    );

class TransferQueueNotifier extends Notifier<List<QueuedTransfer>> {
  static const parallel = 2;

  int _nextId = 1;

  int _starting = 0;
  final _known = <int>{};

  @override
  List<QueuedTransfer> build() {
    ref.listenClientEvents((event) {
      switch (event) {
        case FileTransferEvent(:final transfer):
          if (_known.add(transfer.transferId) && _starting > 0) _starting--;
          if (transfer.status != TtFileTransferStatus.active) _pump();
        case ConLostEvent() || MyselfLoggedOutEvent():
          state = const [];
          _starting = 0;
          _known.clear();
        default:
          break;
      }
    });
    return const [];
  }

  int get _running =>
      _starting +
      ref
          .read(fileTransfersProvider)
          .values
          .where((t) => t.status == TtFileTransferStatus.active)
          .length;

  bool download(TtRemoteFile file, String localPath) => _add(
    QueuedTransfer(
      id: _nextId++,
      inbound: true,
      channelId: file.channelId,
      fileId: file.fileId,
      name: file.fileName,
      localPath: localPath,
    ),
  );

  bool upload(int channelId, String localPath, String name) => _add(
    QueuedTransfer(
      id: _nextId++,
      inbound: false,
      channelId: channelId,
      name: name,
      localPath: localPath,
    ),
  );

  bool _add(QueuedTransfer item) {
    state = [...state, item];
    _pump();
    return state.any((q) => q.id == item.id);
  }

  void cancel(int id) => state = [
    for (final q in state)
      if (q.id != id) q,
  ];

  void _pump() {
    while (state.isNotEmpty && _running < parallel) {
      final next = state.first;
      state = state.sublist(1);
      _starting++;
      unawaited(_start(next));
    }
  }

  Future<void> _start(QueuedTransfer item) async {
    final client = ref.read(teamTalkClientProvider);
    try {
      if (item.inbound) {
        await client.recvFile(item.channelId, item.fileId, item.localPath);
      } else {
        await client.sendFile(item.channelId, item.localPath);
      }
    } on Object catch (e, st) {
      appLog.w('files', 'Starting the transfer of ${item.name} failed', e, st);
      if (_starting > 0) _starting--;
      ref
          .read(announcerProvider)
          .announce(
            ref.read(appLocalizationsProvider).eventTransferFailed(item.name),
          );
      _pump();
    }
  }
}
