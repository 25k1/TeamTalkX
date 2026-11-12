import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:teamtalkx/src/platform/native_export.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(
    const MaterialApp(
      home: Scaffold(body: Center(child: Text('Storage check'))),
    ),
  );
  void log(String line) => debugPrint('TTX-BENCH $line');
  final downloads = AndroidDownloads();
  try {
    log('export saved to ${await downloads.saveText('s4-check.txt', 'x')}');
    log('export exists: ${await downloads.exists('s4-check.txt')}');

    final cache = await getApplicationCacheDirectory();
    Future<PublishedFile> publish() async {
      final file = File('${cache.path}/s4-download.txt');
      await file.writeAsString('downloaded');
      final saved = await downloads.publish(file.path, 's4-download.txt');
      log('published ${saved.path}, cache copy left: ${await file.exists()}');
      return saved;
    }

    final first = await publish();
    log('download exists: ${await downloads.exists('s4-download.txt')}');
    final second = await publish();
    log('same name again: ${second.path} (${second.uri != first.uri})');

    await downloads.remove('s4-check.txt');
    await downloads.remove('s4-download.txt');
    await downloads.remove(second.path.split('/').last);
    log(
      'after removing: export ${await downloads.exists('s4-check.txt')}, '
      'download ${await downloads.exists('s4-download.txt')}',
    );
  } on Object catch (e, st) {
    log('FAIL: $e\n$st');
  }
  debugPrint('TTX-BENCH done');
}
