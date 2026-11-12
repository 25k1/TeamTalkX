import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:teamtalkx/src/domain/models.dart';
import 'package:teamtalkx/src/protocol/file_transfer.dart';

Future<ServerSocket> _serveDownload(Uint8List content) async {
  final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
  server.listen((socket) {
    socket.done.ignore();
    socket.write('teamtalk userid=1 protocol="5.14"\r\n');
    socket
        .cast<List<int>>()
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen((line) {
          if (line.startsWith('recvfile')) {
            socket
              ..write('fileready\r\n')
              ..add(content);
          }
        }, onError: (Object _) {});
  });
  return server;
}

void main() {
  late Directory dir;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('teamtalkx-transfer-');
    addTearDown(() => dir.delete(recursive: true));
  });

  test('a finished download is complete on disk', () async {
    final random = Random(7);
    final content = Uint8List.fromList(
      List.generate(512 * 1024 + 3, (_) => random.nextInt(256)),
    );
    final server = await _serveDownload(content);
    addTearDown(server.close);
    final path = '${dir.path}/download.bin';

    final done = Completer<int>();
    final node = FileTransferNode(
      host: InternetAddress.loopbackIPv4.address,
      port: server.port,
      encrypted: false,
      transferId: 1,
      channelId: 1,
      localPath: path,
      remoteFileName: 'download.bin',
      fileSize: content.length,
      inbound: true,
      transferKey: 'key',
      onStatus: (t) {
        if (t.status == TtFileTransferStatus.active) return;
        done.complete(
          t.status == TtFileTransferStatus.finished
              ? File(path).lengthSync()
              : -1,
        );
      },
    );
    await node.start();

    expect(await done.future, content.length);
    expect(await File(path).readAsBytes(), content);
  });

  test('a download that cannot be written is reported as an error', () async {
    final server = await _serveDownload(Uint8List(1024));
    addTearDown(server.close);

    final status = Completer<TtFileTransferStatus>();
    final node = FileTransferNode(
      host: InternetAddress.loopbackIPv4.address,
      port: server.port,
      encrypted: false,
      transferId: 2,
      channelId: 1,
      localPath: dir.path,
      remoteFileName: 'x.bin',
      fileSize: 1024,
      inbound: true,
      transferKey: 'key',
      onStatus: (t) {
        if (t.status != TtFileTransferStatus.active && !status.isCompleted) {
          status.complete(t.status);
        }
      },
    );
    await node.start();

    expect(await status.future, TtFileTransferStatus.error);
  });

  test('a server whose certificate is not trusted is hung up on', () async {
    final context = SecurityContext()
      ..useCertificateChain('test/fixtures/tls/a.cert.pem')
      ..usePrivateKey('test/fixtures/tls/a.key.pem');
    final server = await SecureServerSocket.bind(
      InternetAddress.loopbackIPv4,
      0,
      context,
    );
    addTearDown(server.close);
    final hungUp = Completer<void>();
    server.listen((socket) {
      socket.done.ignore();
      socket.listen(
        (_) {},
        onError: (Object _) {},
        onDone: () {
          if (!hungUp.isCompleted) hungUp.complete();
        },
      );
    }, onError: (Object _) {});

    final status = Completer<TtFileTransferStatus>();
    final node = FileTransferNode(
      host: InternetAddress.loopbackIPv4.address,
      port: server.port,
      encrypted: true,
      transferId: 3,
      channelId: 1,
      localPath: '${dir.path}/untrusted.bin',
      remoteFileName: 'untrusted.bin',
      fileSize: 10,
      inbound: true,
      transferKey: 'key',
      onStatus: (t) {
        if (t.status != TtFileTransferStatus.active && !status.isCompleted) {
          status.complete(t.status);
        }
      },
    );
    await node.start();

    expect(await status.future, TtFileTransferStatus.error);
    await hungUp.future.timeout(const Duration(seconds: 5));
  });
}
