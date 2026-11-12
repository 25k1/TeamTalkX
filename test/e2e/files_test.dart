@Tags(['e2e'])
library;

import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:teamtalkx/src/domain/events.dart';
import 'package:teamtalkx/src/domain/models.dart';
import 'package:teamtalkx/src/protocol/protocol_client.dart';

import 'support/e2e_server.dart';

Future<TtFileTransfer> _finished(
  ProtocolClient client, {
  required bool inbound,
}) => nextEvent<FileTransferEvent>(
  client,
  (e) =>
      e.transfer.inbound == inbound &&
      e.transfer.status != TtFileTransferStatus.active,
).then((e) => e.transfer);

void main() {
  group('files', skip: e2eSkip, () {
    late Directory dir;

    setUp(() async {
      dir = await Directory.systemTemp.createTemp('teamtalkx-e2e-');
      addTearDown(() => dir.delete(recursive: true));
    });

    for (final transport in E2eTransport.values) {
      test(
        'upload, download and delete over ${transport.name}',
        skip: transport.skip,
        () async {
          final alice = await loginAs(E2eAccount.alice, transport: transport);
          final bob = await loginAs(E2eAccount.bob, transport: transport);
          await alice.joinChannel(E2eChannel.files);
          await bob.joinChannel(E2eChannel.files);

          final random = Random(42);
          final bytes = Uint8List.fromList(
            List.generate(200 * 1024 + 17, (_) => random.nextInt(256)),
          );
          final name = '${uniqueName('upload')}.bin';
          final source = File('${dir.path}/$name');
          await source.writeAsBytes(bytes);

          final uploaded = _finished(alice, inbound: false);
          final listed = nextEvent<FileNewEvent>(
            bob,
            (e) => e.file.fileName == name,
          );
          await alice.sendFile(E2eChannel.files, source.path);
          expect((await uploaded).status, TtFileTransferStatus.finished);
          final remote = (await listed).file;
          expect(remote.fileSize, bytes.length);
          expect(remote.username, E2eAccount.alice.username);

          final target = File('${dir.path}/downloaded.bin');
          final downloaded = _finished(bob, inbound: true);
          await bob.recvFile(
            E2eChannel.files,
            remote.fileId,
            target.path,
            remote.fileName,
            remote.fileSize,
          );
          expect((await downloaded).status, TtFileTransferStatus.finished);
          expect(await target.readAsBytes(), bytes);

          final removed = nextEvent<FileRemoveEvent>(
            bob,
            (e) => e.file.fileId == remote.fileId,
          );
          await alice.deleteFile(E2eChannel.files, name);
          await removed;
        },
      );
    }
  });
}
