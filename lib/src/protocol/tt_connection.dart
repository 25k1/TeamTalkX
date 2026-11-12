import 'dart:async';
import 'dart:io';

import '../diagnostics/log.dart';
import '../domain/certificate.dart';
import '../domain/failure.dart';
import 'command.dart';
import 'line_framer.dart';
import 'tls_trust.dart';

const _serverBegin = 'begin';
const _serverEnd = 'end';
const _serverError = 'error';
const _serverPong = 'pong';

const defaultCommandTimeout = Duration(seconds: 15);

const listCommandTimeout = Duration(seconds: 60);

class ConnectionCancelled implements Exception {
  const ConnectionCancelled();

  @override
  String toString() => 'ConnectionCancelled';
}

class TtCommandError implements Exception {
  TtCommandError(this.number, this.message);
  final int number;
  final String message;
  @override
  String toString() => 'TtCommandError($number): $message';
}

class TtConnection {
  TtConnection({this.trust = const AuthorityTrustOnly()});

  final CertificateTrust trust;

  Socket? _socket;

  void Function()? _cancelConnect;

  int _generation = 0;
  LineFramer _framer = LineFramer();
  final _commands = StreamController<TtCommand>.broadcast();
  final _pending = <int, _PendingCommand>{};
  int _cmdIdCounter = 0;
  Timer? _keepAlive;
  bool _active = false;
  TtCommandError? _blockError;

  void Function()? onClosed;

  Stream<TtCommand> get commands => _commands.stream;

  bool get isConnected => _socket != null;

  InternetAddress? get remoteAddress => _socket?.remoteAddress;

  Future<void> connect(
    String host,
    int tcpPort, {
    bool encrypted = false,
    Duration timeout = const Duration(seconds: 10),
    Duration keepAliveInterval = const Duration(seconds: 30),
    Duration keepAliveTimeout = defaultCommandTimeout,
  }) async {
    if (_socket != null) {
      throw StateError('Already connected: close() the connection first');
    }
    _cancelConnect?.call();
    final generation = ++_generation;
    final check = TlsTrustCheck(trust);
    final task = encrypted
        ? await SecureSocket.startConnect(
            host,
            tcpPort,
            onBadCertificate: check.onBadCertificate,
          )
        : await Socket.startConnect(host, tcpPort);
    if (generation != _generation) {
      task.cancel();
      throw const ConnectionCancelled();
    }
    final cancelled = Completer<Socket>();
    void cancel() {
      task.cancel();
      if (!cancelled.isCompleted) {
        cancelled.completeError(const ConnectionCancelled());
      }
    }

    _cancelConnect = cancel;
    unawaited(
      task.socket.then((late) {
        if (generation != _generation) late.destroy();
      }, onError: (Object _) {}),
    );
    final Socket socket;
    try {
      socket = await Future.any([
        task.socket,
        cancelled.future,
      ]).timeout(timeout);
    } on TimeoutException {
      task.cancel();
      rethrow;
    } on SocketException {
      if (generation != _generation) throw const ConnectionCancelled();
      rethrow;
    } finally {
      if (identical(_cancelConnect, cancel)) _cancelConnect = null;
    }
    if (generation != _generation) {
      socket.destroy();
      throw const ConnectionCancelled();
    }
    if (socket is SecureSocket) {
      await check.verify(socket, host, tcpPort);
      if (generation != _generation) {
        socket.destroy();
        throw const ConnectionCancelled();
      }
    }
    _framer = LineFramer();
    _socket = socket;
    _active = true;
    socket.listen(
      _onData,
      onError: (Object e) => _shutdown(),
      onDone: _shutdown,
      cancelOnError: true,
    );
    _keepAlive = Timer.periodic(keepAliveInterval, (_) {
      if (isConnected) unawaited(_ping(keepAliveTimeout));
    });
  }

  Future<void> _ping(Duration timeout) async {
    try {
      await sendCommand(TtCommand('ping'), timeout: timeout);
    } on ConnectionTimedOut {
      appLog.w('connection', 'The server stopped answering; closing');
      _shutdown();
    } on NotConnected catch (_) {}
  }

  void _onData(List<int> bytes) {
    for (final line in _framer.addBytes(bytes)) {
      if (line.isEmpty) continue;
      final cmd = TtCommand.parse(line);
      if (cmd.verb == _serverPong) {
        _pending.remove(cmd.getInt('id'))?.complete();
        continue;
      }
      _commands.add(cmd);
    }
  }

  void resolveReply(TtCommand cmd) {
    switch (cmd.verb) {
      case _serverBegin:
        _blockError = null;
      case _serverError:
        final err = TtCommandError(
          cmd.getInt('number') ?? -1,
          cmd.getString('message') ?? 'Command failed',
        );
        final id = cmd.getInt('id');
        if (id != null) {
          _pending.remove(id)?.fail(err);
        } else {
          _blockError = err;
        }
      case _serverEnd:
        final pending = _pending.remove(cmd.getInt('id'));
        final err = _blockError;
        _blockError = null;
        if (pending == null) break;
        if (err != null) {
          pending.fail(err);
        } else {
          pending.complete();
        }
    }
  }

  Future<void> sendCommand(
    TtCommand command, {
    Duration timeout = defaultCommandTimeout,
  }) {
    final socket = _socket;
    if (socket == null) {
      return Future.error(const NotConnected());
    }
    final id = ++_cmdIdCounter;
    command.set('id', id);
    final pending = _PendingCommand(
      Timer(
        timeout,
        () => _pending.remove(id)?.fail(const ConnectionTimedOut()),
      ),
    );
    _pending[id] = pending;
    socket.write(command.encode());
    return pending.future;
  }

  Future<void> close() async {
    final socket = _socket;
    if (socket != null) {
      try {
        socket.write(TtCommand('quit').encode());
        await socket.flush();
      } on IOException catch (_) {
      } on StateError catch (_) {}
    }
    _shutdown();
  }

  Future<void> dispose() async {
    _shutdown();
    if (!_commands.isClosed) await _commands.close();
  }

  void _shutdown() {
    _generation++;
    _cancelConnect?.call();
    _cancelConnect = null;
    final wasActive = _active;
    _active = false;
    _keepAlive?.cancel();
    _keepAlive = null;
    _socket?.destroy();
    _socket = null;
    final pending = [..._pending.values];
    _pending.clear();
    for (final command in pending) {
      command.fail(const NotConnected());
    }
    if (wasActive) onClosed?.call();
  }
}

class _PendingCommand {
  _PendingCommand(this._timer);

  final Timer _timer;
  final _completer = Completer<void>();

  Future<void> get future => _completer.future;

  void complete() {
    _timer.cancel();
    if (!_completer.isCompleted) _completer.complete();
  }

  void fail(Object error) {
    _timer.cancel();
    if (!_completer.isCompleted) _completer.completeError(error);
  }
}
