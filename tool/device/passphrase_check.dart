import 'package:flutter/material.dart';
import 'package:teamtalkx/src/data/passphrase_box.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(
    const MaterialApp(
      home: Scaffold(body: Center(child: Text('Passphrase check'))),
    ),
  );
  void log(String line) => debugPrint('TTX-BENCH $line');
  final watch = Stopwatch()..start();
  final box = await PassphraseBox.seal('{"servers": []}', 'correct horse');
  log('seal: ${watch.elapsedMilliseconds} ms');
  watch.reset();
  final text = await PassphraseBox.open(box, 'correct horse');
  log('open: ${watch.elapsedMilliseconds} ms, ${text.length} chars');
  watch.reset();
  try {
    await PassphraseBox.open(box, 'wrong');
    log('FAIL: a wrong passphrase opened it');
  } on WrongPassphrase {
    log('wrong passphrase refused: ${watch.elapsedMilliseconds} ms');
  }
  debugPrint('TTX-BENCH done');
}
