import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import '../../audio/sound_effects.dart';
import '../../diagnostics/log.dart';
import '../platform_services.dart';
import 'settings_providers.dart';
import 'sound_packs.dart';

final soundPlayerProvider = Provider<SoundPlayer>((ref) {
  final player = SoundPlayer(ref);
  ref.onDispose(player.dispose);
  return player;
});

class SoundPlayer {
  SoundPlayer(this._ref);

  final Ref _ref;
  Future<SoundEffects>? _effects;
  Directory? _assetCache;
  Directory? _folderCache;
  ({bool voiceCall, int deviceId}) _output = (voiceCall: false, deviceId: 0);

  bool suppressed = false;

  final _playing = StreamController<bool>.broadcast();

  Stream<bool> get playing => _playing.stream;

  void setOutput({required bool voiceCall, int deviceId = 0}) {
    _output = (voiceCall: voiceCall, deviceId: deviceId);
    unawaited(
      _effects?.then(
        (e) => e.setOutput(voiceCall: voiceCall, deviceId: deviceId),
      ),
    );
  }

  Future<void> play(SoundEvent event) async {
    if (!_ref.read(settingsProvider).soundEnabled(event)) return;
    await playEventSound(event);
  }

  Future<void> playEventSound(SoundEvent event, {int volumePercent = 100}) {
    final fallback = AssetSound('sounds/${event.asset}');
    return _play(
      currentSoundPack(_ref).sourceFor(event) ?? fallback,
      volumePercent,
      fallback: fallback,
    );
  }

  Future<void> playAsset(String asset, {int volumePercent = 100}) =>
      _play(AssetSound('sounds/$asset'), volumePercent);

  Future<void> playFile(String path, {int volumePercent = 100}) =>
      _play(FileSound(path), volumePercent);

  Future<void> _play(
    SoundSource source,
    int volumePercent, {
    SoundSource? fallback,
  }) async {
    if (suppressed) return;
    String path;
    try {
      path = await _pathFor(source);
    } on Object catch (e) {
      if (fallback == null) {
        appLog.d('sound', 'No $source: $e');
        return;
      }
      try {
        path = await _pathFor(fallback);
      } on Object catch (e2) {
        appLog.w('sound', 'No $fallback either', e2);
        return;
      }
    }
    final volume = _ref.read(settingsProvider).eventVolumePercent;
    final effects = await (_effects ??= SoundEffects.spawn().then((e) {
      e
        ..setOutput(voiceCall: _output.voiceCall, deviceId: _output.deviceId)
        ..busy.listen(_playing.add);
      return e;
    }));
    effects.play(path, gain: volume / 100 * volumePercent / 100);
  }

  Future<String> _pathFor(SoundSource source) async {
    switch (source) {
      case FileSound(:final path):
        if (!File(path).existsSync()) {
          throw FileSystemException('Missing sound file', path);
        }
        return path;
      case FolderSound(:final file):
        final dir = _folderCache ??= Directory(
          '${(await getApplicationCacheDirectory()).path}/pack-sounds',
        );
        final ext = file.name.split('.').last;
        final cached = File(
          '${dir.path}/${_hash(file.uri)}_${file.modified}.$ext',
        );
        if (!cached.existsSync()) {
          final bytes = await _ref.read(soundPackFolderProvider).read(file.uri);
          await dir.create(recursive: true);
          await cached.writeAsBytes(bytes, flush: true);
        }
        return cached.path;
      case AssetSound(:final asset):
        final dir = _assetCache ??= Directory(
          '${(await getApplicationCacheDirectory()).path}/event-sounds',
        );
        final file = File('${dir.path}/${asset.replaceAll('/', '_')}');
        if (!file.existsSync()) {
          final data = await rootBundle.load('assets/$asset');
          await dir.create(recursive: true);
          await file.writeAsBytes(
            data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
            flush: true,
          );
        }
        return file.path;
    }
  }

  static String _hash(String text) {
    var hash = 0x811c9dc5;
    for (final unit in text.codeUnits) {
      hash = ((hash ^ unit) * 0x01000193) & 0xffffffff;
    }
    return hash.toRadixString(16).padLeft(8, '0');
  }

  void dispose() {
    final effects = _effects;
    _effects = null;
    unawaited(_playing.close());
    unawaited(effects?.then((e) => e.dispose()));
  }
}
