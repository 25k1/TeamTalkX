import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:teamtalkx/src/audio/media_source.dart';
import 'package:teamtalkx/src/audio/sound_effects.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(
    const MaterialApp(
      home: Scaffold(body: Center(child: Text('Sound check'))),
    ),
  );
  final manifest = await AssetManifest.loadFromAssetBundle(rootBundle);
  final assets = manifest
      .listAssets()
      .where(
        (a) =>
            a.startsWith('assets/sounds/') ||
            a.startsWith('assets/soundpacks/'),
      )
      .toList();
  final cache = Directory(
    '${(await getApplicationCacheDirectory()).path}/sound-check',
  )..createSync(recursive: true);
  final paths = <String>[];
  var failed = 0;
  final watch = Stopwatch()..start();
  for (final asset in assets) {
    final data = await rootBundle.load(asset);
    final file = File('${cache.path}/${asset.replaceAll('/', '_')}')
      ..writeAsBytesSync(
        data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
      );
    try {
      final source = openMediaSource(file.path);
      final pcm = decodeForMixer(source);
      source.close();
      if (pcm.isEmpty) throw const FormatException('no audio');
      paths.add(file.path);
    } on Exception catch (e) {
      failed++;
      debugPrint('TTX-BENCH FAILED $asset: $e');
    }
  }
  debugPrint(
    'TTX-BENCH decoded ${paths.length} of ${assets.length} event sounds '
    '($failed failed) in ${watch.elapsedMilliseconds} ms',
  );
  final effects = await SoundEffects.spawn();
  for (final path in paths.take(3)) {
    effects.play(path, gain: 0.3);
    await Future<void>.delayed(const Duration(milliseconds: 700));
  }
  effects
    ..play(paths.first, gain: 0.3)
    ..play(paths.last, gain: 0.3);
  await Future<void>.delayed(const Duration(seconds: 2));
  effects.dispose();
  cache.deleteSync(recursive: true);
  debugPrint('TTX-BENCH played 5 sounds');
  debugPrint('TTX-BENCH done');
}
