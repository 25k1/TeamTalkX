import 'package:flutter/services.dart';

import 'native_channel.dart';

class PickedFolder {
  const PickedFolder({required this.tree, required this.name});

  final String tree;
  final String name;
}

class PackSoundFile {
  const PackSoundFile({
    required this.name,
    required this.uri,
    required this.modified,
  });

  final String name;
  final String uri;

  final int modified;
}

class PackFolderContents {
  const PackFolderContents({required this.name, required this.sounds});
  final String name;
  final List<PackSoundFile> sounds;
}

class SoundPackFolderUnreadable implements Exception {
  const SoundPackFolderUnreadable();
}

abstract interface class SoundPackFolder {
  Future<PickedFolder?> pick();

  Future<void> release(String tree);

  Future<List<PackFolderContents>> list(String tree);

  Future<Uint8List> read(String uri);
}

class AndroidSoundPackFolder implements SoundPackFolder {
  final _channel = NativeChannel('sound_pack_folder');

  @override
  Future<PickedFolder?> pick() async {
    final result = await _channel.invoke<Map<Object?, Object?>>('pick');
    if (result == null) return null;
    return PickedFolder(
      tree: result['tree'] as String? ?? '',
      name: result['name'] as String? ?? '',
    );
  }

  @override
  Future<void> release(String tree) =>
      _channel.invokeQuiet<void>('release', {'tree': tree});

  @override
  Future<List<PackFolderContents>> list(String tree) async {
    final result = await _guard(
      () => _channel.invokeList<Map<Object?, Object?>>('list', {'tree': tree}),
    );
    return [
      for (final pack in result ?? const <Map<Object?, Object?>>[])
        PackFolderContents(
          name: pack['name'] as String? ?? '',
          sounds: [
            for (final s
                in (pack['sounds'] as List? ?? const [])
                    .cast<Map<Object?, Object?>>())
              PackSoundFile(
                name: s['name'] as String? ?? '',
                uri: s['uri'] as String? ?? '',
                modified: (s['modified'] as num?)?.toInt() ?? 0,
              ),
          ],
        ),
    ];
  }

  @override
  Future<Uint8List> read(String uri) async {
    final bytes = await _guard(
      () => _channel.invoke<Uint8List>('read', {'uri': uri}),
    );
    if (bytes == null) throw const SoundPackFolderUnreadable();
    return bytes;
  }

  Future<T> _guard<T>(Future<T> Function() call) async {
    try {
      return await call();
    } on PlatformException {
      throw const SoundPackFolderUnreadable();
    }
  }
}
