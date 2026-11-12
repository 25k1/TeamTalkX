import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:teamtalkx/src/domain/events.dart';
import 'package:teamtalkx/src/domain/models.dart';
import 'package:teamtalkx/src/protocol/command.dart';
import 'package:teamtalkx/src/protocol/protocol_client.dart';

class _FakeServer {
  _FakeServer(this._socket, this.onCommand) {
    _socket.listen(_accept);
  }

  static Future<_FakeServer> start(
    String Function(TtCommand cmd) onCommand,
  ) async => _FakeServer(
    await ServerSocket.bind(InternetAddress.loopbackIPv4, 0),
    onCommand,
  );

  final ServerSocket _socket;

  final String Function(TtCommand cmd) onCommand;

  final registrations = <TtCommand>[];
  final transferHellos = StreamController<TtCommand>.broadcast();
  final _clients = <Socket>[];

  int get port => _socket.port;

  void _accept(Socket socket) {
    final control = _clients.isEmpty;
    _clients.add(socket);
    socket.done.ignore();
    socket.write('teamtalk userid=1 protocol="5.14"\r\n');
    socket
        .cast<List<int>>()
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen((line) {
          final cmd = TtCommand.parse(line);
          if (!control) {
            transferHellos.add(cmd);
            return;
          }
          if (cmd.verb.startsWith('reg')) registrations.add(cmd);
          final id = cmd.getInt('id');
          socket.write('begin id=$id\r\n${onCommand(cmd)}end id=$id\r\n');
        }, onError: (Object _) {});
  }

  Future<void> close() async {
    for (final c in _clients) {
      c.destroy();
    }
    await transferHellos.close();
    await _socket.close();
  }
}

void main() {
  late Directory dir;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('tt_transfer_test');
  });

  tearDown(() => dir.delete(recursive: true));

  Future<String> localFile(String name) async {
    final file = File('${dir.path}/$name');
    await file.writeAsString('content of $name');
    return file.path;
  }

  Future<ProtocolClient> connect(_FakeServer server) async {
    final proto = ProtocolClient();
    addTearDown(() async {
      await proto.disconnect();
      await proto.dispose();
    });
    await proto.connect(host: '127.0.0.1', tcpPort: server.port);
    return proto;
  }

  test('a failed registration does not capture the next transfer', () async {
    var regs = 0;
    final server = await _FakeServer.start((cmd) {
      if (!cmd.verb.startsWith('reg')) return '';
      regs++;
      return regs == 1
          ? 'error number=3007 message="File already exists"\r\n'
          : 'fileaccepted transferid=9\r\n';
    });
    addTearDown(server.close);
    final proto = await connect(server);
    final hello = server.transferHellos.stream.first;

    await expectLater(
      proto.sendFile(1, await localFile('rejected.txt')),
      throwsA(anything),
    );
    await proto.sendFile(1, await localFile('accepted.txt'));

    final sent = await hello.timeout(const Duration(seconds: 5));
    final accepted = server.registrations[1];
    expect(accepted.getString('filename'), 'accepted.txt');
    expect(sent.verb, 'sendfile');
    expect(sent.getInt('transferid'), 9);
    expect(
      sent.getString('filetxkey'),
      accepted.getString('filetxkey'),
      reason:
          'the transfer must use the accepted registration, not the '
          'rejected one',
    );
  });

  test('each fileaccepted goes to the command that registered it', () async {
    final server = await _FakeServer.start((cmd) {
      if (!cmd.verb.startsWith('reg')) return '';
      return 'fileaccepted transferid=${100 + cmd.getInt('id')!}\r\n';
    });
    addTearDown(server.close);
    final proto = await connect(server);
    final hellos = server.transferHellos.stream.take(2).toList();

    await Future.wait([
      proto.sendFile(1, await localFile('up.txt')),
      proto.recvFile(1, 5, '${dir.path}/down.txt', 'down.txt', 10),
    ]);

    final byTransfer = {
      for (final h in await hellos.timeout(const Duration(seconds: 5)))
        h.getInt('transferid'): h,
    };
    for (final reg in server.registrations) {
      final hello = byTransfer[100 + reg.getInt('id')!]!;
      expect(hello.verb, reg.verb == 'regsendfile' ? 'sendfile' : 'recvfile');
      expect(hello.getString('filetxkey'), reg.getString('filetxkey'));
    }
  });

  test('disconnecting during a transfer closes it cleanly', () async {
    final server = await _FakeServer.start(
      (cmd) =>
          cmd.verb.startsWith('reg') ? 'fileaccepted transferid=3\r\n' : '',
    );
    addTearDown(server.close);
    final proto = await connect(server);
    final hello = server.transferHellos.stream.first;
    final closed = proto.events.firstWhere(
      (e) =>
          e is FileTransferEvent &&
          e.transfer.status == TtFileTransferStatus.closed,
    );

    await proto.sendFile(1, await localFile('big.txt'));
    await hello.timeout(const Duration(seconds: 5));
    await proto.disconnect();

    await closed.timeout(const Duration(seconds: 5));
    expect(proto.cancelFileTransfer(3), isFalse);
  });

  test('transfer keys are 128-bit hex and unique', () async {
    final server = await _FakeServer.start((_) => '');
    addTearDown(server.close);
    final proto = await connect(server);

    for (var i = 0; i < 20; i++) {
      await proto.sendFile(1, await localFile('f$i.txt'));
    }

    final keys = server.registrations.map((r) => r.getString('filetxkey'));
    expect(keys.toSet(), hasLength(20));
    expect(keys, everyElement(matches(RegExp(r'^[0-9a-f]{32}$'))));
  });
}
