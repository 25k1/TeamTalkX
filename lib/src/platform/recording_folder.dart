import 'package:flutter/services.dart';

import 'native_channel.dart';
import 'sound_pack_folder.dart' show PickedFolder;

export 'sound_pack_folder.dart' show PickedFolder;

class RecordingFolderUnwritable implements Exception {
  const RecordingFolderUnwritable();
}

abstract interface class RecordingFolder {
  Future<PickedFolder?> pick();

  Future<void> release(String tree);

  Future<String> save(String tree, String path, String name);
}

class AndroidRecordingFolder implements RecordingFolder {
  final _channel = NativeChannel('sound_pack_folder');

  @override
  Future<PickedFolder?> pick() async {
    final result = await _channel.invoke<Map<Object?, Object?>>('pick', {
      'write': true,
    });
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
  Future<String> save(String tree, String path, String name) async {
    try {
      final saved = await _channel.invoke<String>('save', {
        'tree': tree,
        'path': path,
        'name': name,
      });
      return saved ?? name;
    } on PlatformException {
      throw const RecordingFolderUnwritable();
    }
  }
}
