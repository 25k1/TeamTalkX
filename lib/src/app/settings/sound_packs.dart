import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../diagnostics/log.dart';
import '../../platform/sound_pack_folder.dart';
import '../platform_services.dart';
import 'persisted_notifier.dart';
import 'settings_providers.dart';

const _majorlyFiles = {
  'broadcast_message',
  'channel_message',
  'fileupdate',
  'user_join',
  'user_left',
  'serverlost',
  'user_message',
  'voiceact_off',
  'voiceact_on',
  'voiceact_disable',
  'voiceact_enable',
};

const _extensions = ['wav', 'ogg', 'mp3', 'm4a', 'opus', 'flac'];

enum SoundPackKind { defaultPack, bundled, folder }

sealed class SoundSource {
  const SoundSource();
}

final class AssetSound extends SoundSource {
  const AssetSound(this.asset);
  final String asset;

  @override
  String toString() => 'asset $asset';
}

final class FileSound extends SoundSource {
  const FileSound(this.path);
  final String path;

  @override
  String toString() => 'file $path';
}

final class FolderSound extends SoundSource {
  const FolderSound(this.file);
  final PackSoundFile file;

  @override
  String toString() => 'folder sound ${file.name}';
}

class SoundPack {
  const SoundPack({
    required this.id,
    required this.name,
    required this.kind,
    this.assetDir = '',
    this.available = const {},
    this.files = const {},
  });

  factory SoundPack.folder(PackFolderContents contents) => SoundPack(
    id: 'dir:${contents.name}',
    name: contents.name,
    kind: SoundPackKind.folder,
    files: {for (final f in contents.sounds) f.name.toLowerCase(): f},
  );

  static const default_ = SoundPack(
    id: 'default',
    name: 'Default',
    kind: SoundPackKind.defaultPack,
  );
  static const majorly = SoundPack(
    id: 'majorly',
    name: 'Majorly',
    kind: SoundPackKind.bundled,
    assetDir: 'soundpacks/majorly',
    available: _majorlyFiles,
  );

  final String id;
  final String name;
  final SoundPackKind kind;

  final String assetDir;

  final Set<String> available;

  final Map<String, PackSoundFile> files;

  SoundSource? sourceFor(SoundEvent event) {
    switch (kind) {
      case SoundPackKind.defaultPack:
        return null;
      case SoundPackKind.bundled:
        return available.contains(event.packName)
            ? AssetSound('$assetDir/${event.packName}.wav')
            : null;
      case SoundPackKind.folder:
        for (final ext in _extensions) {
          final file = files['${event.packName}.$ext'.toLowerCase()];
          if (file != null) return FolderSound(file);
        }
        return null;
    }
  }
}

final soundPackFolderSettingProvider =
    NotifierProvider<SoundPackFolderSetting, PickedFolder?>(
      SoundPackFolderSetting.new,
    );

class SoundPackFolderSetting extends Notifier<PickedFolder?> {
  static const _treeKey = 'sound_pack_folder';
  static const _nameKey = 'sound_pack_folder_name';

  @override
  PickedFolder? build() {
    final prefs = ref.read(sharedPreferencesProvider);
    final tree = prefs.getString(_treeKey);
    if (tree == null || tree.isEmpty) return null;
    return PickedFolder(tree: tree, name: prefs.getString(_nameKey) ?? '');
  }

  Future<bool> pick() async {
    final folders = ref.read(soundPackFolderProvider);
    final picked = await folders.pick();
    if (picked == null) return false;
    final previous = state;
    if (previous != null && previous.tree != picked.tree) {
      await folders.release(previous.tree);
    }
    final prefs = ref.read(sharedPreferencesProvider);
    await prefs.setString(_treeKey, picked.tree);
    await prefs.setString(_nameKey, picked.name);
    state = picked;
    return true;
  }

  Future<void> clear() async {
    final previous = state;
    if (previous == null) return;
    await ref.read(soundPackFolderProvider).release(previous.tree);
    final prefs = ref.read(sharedPreferencesProvider);
    await prefs.remove(_treeKey);
    await prefs.remove(_nameKey);
    state = null;
  }
}

class SoundPacks {
  const SoundPacks(this.packs, {this.folderUnreadable = false});
  final List<SoundPack> packs;
  final bool folderUnreadable;
}

final soundPacksProvider = FutureProvider<SoundPacks>((ref) async {
  final packs = <SoundPack>[SoundPack.default_, SoundPack.majorly];
  final folder = ref.watch(soundPackFolderSettingProvider);
  if (folder == null) return SoundPacks(packs);
  try {
    final contents = await ref.read(soundPackFolderProvider).list(folder.tree);
    packs.addAll(contents.map(SoundPack.folder));
    return SoundPacks(packs);
  } on SoundPackFolderUnreadable {
    appLog.w('sound', 'The sound pack folder can no longer be read');
    return SoundPacks(packs, folderUnreadable: true);
  }
});

final selectedSoundPackProvider =
    NotifierProvider<SelectedSoundPackNotifier, String>(
      SelectedSoundPackNotifier.new,
    );

class SelectedSoundPackNotifier extends PersistedStringNotifier {
  @override
  String get prefsKey => 'sound_pack';
  @override
  String get defaultValue => 'default';
}

SoundPack currentSoundPack(Ref ref) {
  final id = ref.read(selectedSoundPackProvider);
  final packs =
      ref.read(soundPacksProvider).value?.packs ??
      const [SoundPack.default_, SoundPack.majorly];
  return packs.firstWhere((p) => p.id == id, orElse: () => SoundPack.default_);
}
