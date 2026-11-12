import 'dart:async';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import '../../diagnostics/log.dart';
import '../../domain/failure.dart';
import '../../domain/recording.dart';
import '../../domain/tt_types.dart' show ChannelTypes;
import '../../l10n/failure_messages.dart';
import '../../platform/recording_folder.dart';
import '../announcer.dart';
import '../connection/connection_providers.dart';
import '../platform_services.dart';
import '../settings/locale_providers.dart';
import '../settings/settings_providers.dart';

class RecordingSettings {
  const RecordingSettings({
    this.mode = RecordingMode.mixed,
    this.format = RecordingFormat.oggOpus,
    this.folder,
  });

  final RecordingMode mode;
  final RecordingFormat format;

  final PickedFolder? folder;

  RecordingSettings copyWith({
    RecordingMode? mode,
    RecordingFormat? format,
    PickedFolder? Function()? folder,
  }) => RecordingSettings(
    mode: mode ?? this.mode,
    format: format ?? this.format,
    folder: folder == null ? this.folder : folder(),
  );
}

final recordingSettingsProvider =
    NotifierProvider<RecordingSettingsNotifier, RecordingSettings>(
      RecordingSettingsNotifier.new,
    );

class RecordingSettingsNotifier extends Notifier<RecordingSettings> {
  static const _modeKey = 'recording_mode';
  static const _formatKey = 'recording_format';
  static const _treeKey = 'recording_folder';
  static const _nameKey = 'recording_folder_name';

  @override
  RecordingSettings build() {
    final prefs = ref.read(sharedPreferencesProvider);
    final tree = prefs.getString(_treeKey);
    return RecordingSettings(
      mode:
          RecordingMode.values.asNameMap()[prefs.getString(_modeKey)] ??
          RecordingMode.mixed,
      format:
          RecordingFormat.values.asNameMap()[prefs.getString(_formatKey)] ??
          RecordingFormat.oggOpus,
      folder: tree == null || tree.isEmpty
          ? null
          : PickedFolder(tree: tree, name: prefs.getString(_nameKey) ?? ''),
    );
  }

  void setMode(RecordingMode mode) {
    unawaited(
      ref.read(sharedPreferencesProvider).setString(_modeKey, mode.name),
    );
    state = state.copyWith(mode: mode);
  }

  void setFormat(RecordingFormat format) {
    unawaited(
      ref.read(sharedPreferencesProvider).setString(_formatKey, format.name),
    );
    state = state.copyWith(format: format);
  }

  Future<bool> pickFolder() async {
    final folders = ref.read(recordingFolderProvider);
    final picked = await folders.pick();
    if (picked == null || !ref.mounted) return false;
    final previous = state.folder;
    if (previous != null && previous.tree != picked.tree) {
      await folders.release(previous.tree);
    }
    final prefs = ref.read(sharedPreferencesProvider);
    await prefs.setString(_treeKey, picked.tree);
    await prefs.setString(_nameKey, picked.name);
    if (!ref.mounted) return true;
    state = state.copyWith(folder: () => picked);
    return true;
  }

  Future<void> clearFolder() async {
    final previous = state.folder;
    if (previous == null) return;
    await ref.read(recordingFolderProvider).release(previous.tree);
    final prefs = ref.read(sharedPreferencesProvider);
    await prefs.remove(_treeKey);
    await prefs.remove(_nameKey);
    if (!ref.mounted) return;
    state = state.copyWith(folder: () => null);
  }
}

final recordingCacheProvider = Provider<Future<Directory> Function()>(
  (ref) => () async {
    final cache = await getApplicationCacheDirectory();
    return Directory('${cache.path}${Platform.pathSeparator}recordings');
  },
);

sealed class RecordingState {
  const RecordingState();
}

final class RecordingIdle extends RecordingState {
  const RecordingIdle();
}

final class RecordingStarting extends RecordingState {
  const RecordingStarting();
}

final class RecordingActive extends RecordingState {
  const RecordingActive(this.startedAt);
  final DateTime startedAt;
}

final class RecordingSaving extends RecordingState {
  const RecordingSaving();
}

final recordingProvider = NotifierProvider<RecordingController, RecordingState>(
  RecordingController.new,
);

class RecordingController extends Notifier<RecordingState> {
  String _dir = '';

  final _names = <int, String>{};

  @override
  RecordingState build() {
    ref
      ..listen(connectionProvider, (_, next) {
        if (next is! LoggedIn && state is RecordingActive) {
          unawaited(stop());
        }
      })
      ..listen(serverStateTickProvider, (_, _) => _onServerState());
    return const RecordingIdle();
  }

  bool get isRecording => state is RecordingActive;

  void _announce(String text) => ref.read(announcerProvider).announce(text);

  bool _channelForbids() {
    final s = ref.read(teamTalkClientProvider).state;
    final channel = s.channels[s.joinedChannelId];
    return channel != null &&
        (channel.channelType & ChannelTypes.noRecording) != 0;
  }

  void _onServerState() {
    if (state is! RecordingActive) return;
    _collectNames();
    if (_channelForbids()) {
      _announce(ref.read(appLocalizationsProvider).recordingStoppedNotAllowed);
      unawaited(stop(announce: false));
    }
  }

  void _collectNames() {
    for (final user in ref.read(teamTalkClientProvider).state.users.values) {
      if (user.nickname.isNotEmpty) _names[user.id] = user.nickname;
    }
  }

  Future<void> toggle() => switch (state) {
    RecordingActive() => stop(),
    RecordingIdle() => start(),
    RecordingStarting() || RecordingSaving() => Future.value(),
  };

  Future<void> start() async {
    if (state is! RecordingIdle) return;
    final l10n = ref.read(appLocalizationsProvider);
    if (ref.read(connectionProvider) is! LoggedIn) {
      _announce(l10n.failureMessage(const NotConnected()));
      return;
    }
    if (_channelForbids()) {
      _announce(l10n.recordingNotAllowed);
      return;
    }
    state = const RecordingStarting();
    final client = ref.read(teamTalkClientProvider);
    final settings = ref.read(recordingSettingsProvider);
    final now = DateTime.now();
    final baseName = _fileName('${_timestamp(now)} ${_place()}');
    try {
      final root = await ref.read(recordingCacheProvider)();
      final dir = Directory(
        '${root.path}${Platform.pathSeparator}'
        '${now.millisecondsSinceEpoch} $baseName',
      );
      await dir.create(recursive: true);
      await client.startRecording(
        directory: dir.path,
        mode: settings.mode,
        format: settings.format,
      );
      if (!ref.mounted) return;
      _dir = dir.path;
      _names.clear();
      _collectNames();
      state = RecordingActive(now);
      _announce(l10n.recordingStarted);
      appLog.i(
        'recording',
        'Recording started (${settings.mode.name}, '
            '${settings.format.name})',
      );
    } on TtFailure catch (e) {
      if (!ref.mounted) return;
      state = const RecordingIdle();
      _announce(l10n.failureMessage(e));
    } on FileSystemException catch (e) {
      appLog.w('recording', 'The recording folder could not be made', e);
      if (!ref.mounted) return;
      state = const RecordingIdle();
      _announce(l10n.failureMessage(const RecordingFailed()));
    }
  }

  Future<void> stop({bool announce = true}) async {
    if (state is! RecordingActive) return;
    state = const RecordingSaving();
    _collectNames();
    final names = Map.of(_names);
    final dir = _dir;
    await ref.read(teamTalkClientProvider).stopRecording();
    if (!ref.mounted) return;
    final saved = await _saveAll(current: dir, names: names);
    if (!ref.mounted) return;
    state = const RecordingIdle();
    if (!announce) return;
    final l10n = ref.read(appLocalizationsProvider);
    _announce(switch (saved) {
      _Saved(failed: true) => l10n.recordingSaveFailed,
      _Saved(count: 0) => l10n.recordingNothing,
      _Saved(:final count, :final where) => l10n.recordingSaved(count, where),
    });
  }

  Future<_Saved> _saveAll({
    required String current,
    required Map<int, String> names,
  }) async {
    final root = await ref.read(recordingCacheProvider)();
    if (!root.existsSync()) return const _Saved(0, '');
    final settings = ref.read(recordingSettingsProvider);
    final l10n = ref.read(appLocalizationsProvider);
    var count = 0;
    var failed = false;
    var where = settings.folder?.name ?? l10n.recordingDefaultFolder;
    for (final dir in root.listSync().whereType<Directory>()) {
      final name = dir.path.split(Platform.pathSeparator).last;
      final space = name.indexOf(' ');
      final base = space < 0 ? name : name.substring(space + 1);
      final isCurrent = dir.path == current;
      for (final file in dir.listSync().whereType<File>()) {
        final fileName = file.path.split(Platform.pathSeparator).last;
        final ext = fileName.split('.').last;
        final userId = recordingFileUserId(fileName);
        final target = userId == null
            ? '$base.$ext'
            : _fileName(
                '$base - '
                '${(isCurrent ? names[userId] : null) ?? l10n.recordingUser(userId)}'
                '.$ext',
              );
        if (file.lengthSync() == 0) {
          file.deleteSync();
          continue;
        }
        final result = await _save(file, target, settings.folder);
        if (result == null) {
          failed = true;
        } else {
          count++;
          where = result;
        }
      }
      try {
        if (dir.listSync().isEmpty) dir.deleteSync();
      } on FileSystemException catch (_) {}
    }
    return _Saved(count, where, failed: failed);
  }

  Future<String?> _save(File file, String name, PickedFolder? folder) async {
    if (folder != null) {
      try {
        await ref
            .read(recordingFolderProvider)
            .save(folder.tree, file.path, name);
        return folder.name;
      } on RecordingFolderUnwritable {
        appLog.w('recording', 'The recordings folder could not be written');
      }
    }
    try {
      final published = await ref
          .read(downloadsProvider)
          .publish(file.path, name);
      final path = published.path;
      final slash = path.lastIndexOf('/');
      return slash < 0 ? path : path.substring(0, slash);
    } on Exception catch (e) {
      appLog.w('recording', 'A recording could not be saved', e);
      return null;
    }
  }

  String _place() {
    final client = ref.read(teamTalkClientProvider);
    final s = client.state;
    final channel = s.channels[s.joinedChannelId];
    if (channel != null && !channel.isRoot) return channel.name;
    return ref.read(connectionProvider.notifier).currentEntry?.displayName ??
        s.serverInfo.name;
  }
}

class _Saved {
  const _Saved(this.count, this.where, {this.failed = false});
  final int count;
  final String where;
  final bool failed;
}

String _two(int n) => n.toString().padLeft(2, '0');

String _timestamp(DateTime t) =>
    '${t.year}-${_two(t.month)}-${_two(t.day)} '
    '${_two(t.hour)}-${_two(t.minute)}-${_two(t.second)}';

String _fileName(String name) =>
    name.replaceAll(RegExp(r'[\\/:*?"<>|\x00-\x1F]'), '_').trim();
