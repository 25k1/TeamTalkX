import 'dart:io';

import 'package:flutter/material.dart';
import 'package:teamtalkx/src/app/security/certificate_trust.dart';
import 'package:teamtalkx/src/data/app_database.dart';
import 'package:teamtalkx/src/data/certificate_pin_store.dart';
import 'package:teamtalkx/src/domain/certificate.dart';
import 'package:teamtalkx/src/domain/failure.dart';
import 'package:teamtalkx/src/protocol/protocol_client.dart';

const _host = '127.0.0.1';
const _port = 10443;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(
    const MaterialApp(
      home: Scaffold(body: Center(child: Text('TLS trust check'))),
    ),
  );
  void log(String line) => debugPrint('TTX-BENCH $line');
  final db = AppDatabase.open();
  final store = CertificatePinStore(db);
  final trust = PinnedCertificateTrust(store);
  try {
    log('plain connect to 10333');
    final plain = ProtocolClient();
    await plain.connect(host: _host, tcpPort: 10333);
    await plain.dispose();
    log('plain connect works');
    final watch = Stopwatch()..start();
    try {
      final raw = await SecureSocket.connect(
        _host,
        _port,
        onBadCertificate: (_) => true,
        timeout: const Duration(seconds: 10),
      );
      log(
        'raw TLS handshake: ${watch.elapsedMilliseconds} ms, '
        '${raw.peerCertificate?.subject}',
      );
      raw.destroy();
    } on Object catch (e) {
      log('raw TLS failed after ${watch.elapsedMilliseconds} ms: $e');
    }
    await store.forget(certificateEndpoint(_host, _port));
    log('database open');
    Future<void> connect() async {
      final client = ProtocolClient(trust: trust);
      try {
        await client.connect(host: _host, tcpPort: _port, encrypted: true);
      } finally {
        await client.dispose();
      }
    }

    try {
      await connect();
      log('FAIL: connected without asking');
    } on UntrustedCertificate catch (e) {
      log('first connect: ${e.reason.runtimeType}, ${e.certificate.sha256}');
      await trust.accept(_host, _port, e.certificate);
    }
    final pin = await store.find(certificateEndpoint(_host, _port));
    log('saved pin: ${pin?.sha256}');
    await connect();
    log('second connect: trusted');
    await store.forget(certificateEndpoint(_host, _port));
    log('forgotten: ${await store.find(certificateEndpoint(_host, _port))}');
  } on Object catch (e, st) {
    log('FAIL: $e\n$st');
  } finally {
    await db.close();
  }
  debugPrint('TTX-BENCH done');
}
