import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:teamtalkx/src/domain/failure.dart';
import 'package:teamtalkx/src/protocol/command.dart';
import 'package:teamtalkx/src/protocol/tt_connection.dart';

Future<ServerSocket> _server(
  void Function(Socket s, String line) onLine,
) async {
  final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
  server.listen((socket) {
    socket.done.ignore();
    socket.write('teamtalk userid=1 protocol="5.14"\r\n');
    socket
        .cast<List<int>>()
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen((line) => onLine(socket, line), onError: (Object _) {});
  });
  addTearDown(server.close);
  return server;
}

Future<TtConnection> _connect(
  ServerSocket server, {
  Duration keepAliveInterval = const Duration(seconds: 30),
  Duration keepAliveTimeout = defaultCommandTimeout,
}) async {
  final conn = TtConnection();
  addTearDown(conn.dispose);
  await conn.connect(
    InternetAddress.loopbackIPv4.address,
    server.port,
    keepAliveInterval: keepAliveInterval,
    keepAliveTimeout: keepAliveTimeout,
  );
  return conn;
}

void main() {
  test('an unanswered command times out', () async {
    final server = await _server((_, _) {});
    final conn = await _connect(server);

    await expectLater(
      conn.sendCommand(
        TtCommand('join'),
        timeout: const Duration(milliseconds: 100),
      ),
      throwsA(isA<ConnectionTimedOut>()),
    );
    expect(conn.isConnected, isTrue);
  });

  test('an answer that arrives after the timeout is ignored', () async {
    final answered = Completer<void>();
    final server = await _server((socket, line) {
      final id = TtCommand.parse(line).getInt('id');
      Timer(const Duration(milliseconds: 200), () {
        socket.write('begin id=$id\r\nend id=$id\r\n');
        answered.complete();
      });
    });
    final conn = await _connect(server);
    final reply = conn.sendCommand(
      TtCommand('join'),
      timeout: const Duration(milliseconds: 50),
    );

    await expectLater(reply, throwsA(isA<ConnectionTimedOut>()));
    await answered.future;
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(conn.isConnected, isTrue);
  });

  test('a server that stops answering pings is treated as lost', () async {
    final server = await _server((_, _) {});
    final closed = Completer<void>();
    final conn = await _connect(
      server,
      keepAliveInterval: const Duration(milliseconds: 50),
      keepAliveTimeout: const Duration(milliseconds: 100),
    );
    conn.onClosed = closed.complete;

    await closed.future.timeout(const Duration(seconds: 5));
    expect(conn.isConnected, isFalse);
  });

  test('closing during a TLS handshake cancels the connect', () async {
    final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(server.close);
    final accepted = Completer<void>();
    final sockets = <Socket>[];
    server.listen((s) {
      sockets.add(s);
      if (!accepted.isCompleted) accepted.complete();
    });
    addTearDown(() {
      for (final s in sockets) {
        s.destroy();
      }
    });

    final conn = TtConnection();
    addTearDown(conn.dispose);
    final connecting = expectLater(
      conn
          .connect(
            InternetAddress.loopbackIPv4.address,
            server.port,
            encrypted: true,
          )
          .timeout(const Duration(seconds: 2)),
      throwsA(isA<ConnectionCancelled>()),
    );
    await accepted.future;
    await conn.close();

    await connecting;
    expect(conn.isConnected, isFalse);
  });

  test('a newer connect supersedes one still in progress', () async {
    final hang = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(hang.close);
    final hung = <Socket>[];
    hang.listen(hung.add);
    addTearDown(() {
      for (final s in hung) {
        s.destroy();
      }
    });
    final good = await _server((_, _) {});

    final conn = TtConnection();
    addTearDown(conn.dispose);
    final first = expectLater(
      conn.connect(
        InternetAddress.loopbackIPv4.address,
        hang.port,
        encrypted: true,
      ),
      throwsA(isA<ConnectionCancelled>()),
    );
    await Future<void>.delayed(const Duration(milliseconds: 50));
    await conn.connect(InternetAddress.loopbackIPv4.address, good.port);

    await first;
    expect(conn.isConnected, isTrue);
  });
}
