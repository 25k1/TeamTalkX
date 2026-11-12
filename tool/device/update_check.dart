import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:teamtalkx/src/platform/app_updater.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(
    const MaterialApp(
      home: Scaffold(body: Center(child: Text('Update check'))),
    ),
  );
  void log(String line) => debugPrint('TTX-BENCH $line');
  final updater = AndroidAppUpdater();
  try {
    final device = await updater.device();
    log(
      'device: ${device.packageName}, ${device.abis}, '
      'debuggable ${device.debuggable}',
    );
    log(
      'metered: ${await updater.isMetered()}, '
      'can install: ${await updater.canInstall()}',
    );
    final cache = (await getApplicationCacheDirectory()).path;
    for (final name in ['same.apk', 'other.apk']) {
      final check = await updater.verify('$cache/updates/$name');
      log(
        '$name: valid ${check.valid}, ${check.packageName} '
        '${check.versionName}, same signer ${check.sameSigner}',
      );
    }
  } on Object catch (e, st) {
    log('FAIL: $e\n$st');
  }
  debugPrint('TTX-BENCH done');
}
