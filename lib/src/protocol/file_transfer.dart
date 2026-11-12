import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import '../diagnostics/log.dart';
import '../domain/certificate.dart';
import '../domain/failure.dart';
import '../domain/models.dart';
import 'command.dart';
import 'tls_trust.dart';

class FileTransferNode {
  FileTransferNode({
    required this.host,
    required this.port,
    required this.encrypted,
    required this.transferId,
    required this.channelId,
    required this.localPath,
    required this.remoteFileName,
    required this.fileSize,
    required this.inbound,
    required this.transferKey,
    required this.onStatus,
    this.trust = const AuthorityTrustOnly(),
  });

  final String host;
  final int port;
  final bool encrypted;
  final int transferId;
  final int channelId;
  final String localPath;
  final String remoteFileName;
  final int fileSize;
  final bool inbound;
  final String transferKey;
  final void Function(TtFileTransfer) onStatus;

  final CertificateTrust trust;

  Socket? _socket;
  final _lineBuf = <int>[];
  bool _binaryReceive = false;
  int _received = 0;

  RandomAccessFile? _file;

  Future<void> _writes = Future.value();
  bool _done = false;

  TtFileTransfer _info(TtFileTransferStatus status, int transferred) =>
      TtFileTransfer(
        status: status,
        transferId: transferId,
        channelId: channelId,
        localFilePath: localPath,
        remoteFileName: remoteFileName,
        fileSize: fileSize,
        transferred: transferred,
        inbound: inbound,
      );

  Future<void> start() async {
    try {
      if (inbound) _file = await File(localPath).open(mode: FileMode.write);
      final check = TlsTrustCheck(trust);
      _socket = encrypted
          ? await SecureSocket.connect(
              host,
              port,
              onBadCertificate: check.onBadCertificate,
              timeout: const Duration(seconds: 15),
            )
          : await Socket.connect(
              host,
              port,
              timeout: const Duration(seconds: 15),
            );
      if (_socket case final SecureSocket secure) {
        await check.verify(secure, host, port);
      }
      _socket?.listen(
        _onData,
        onError: (_) => _fail(),
        onDone: _onDone,
        cancelOnError: true,
      );
    } on IOException catch (e) {
      appLog.w('transfer', 'Transfer $transferId could not start', e);
      _fail();
    } on UntrustedCertificate {
      appLog.w(
        'transfer',
        "Transfer $transferId: the server's certificate isn't the trusted "
            'one',
      );
      _fail();
    }
  }

  void cancel() {
    if (_done) return;
    _done = true;
    _cleanup();
    onStatus(_info(TtFileTransferStatus.closed, _received));
  }

  void _onData(Uint8List data) {
    if (_done) return;
    if (_binaryReceive) {
      _writeFileBytes(data);
      return;
    }
    _lineBuf.addAll(data);
    while (!_binaryReceive) {
      final nl = _lineBuf.indexOf(0x0A);
      if (nl < 0) break;
      var end = nl;
      if (end > 0 && _lineBuf[end - 1] == 0x0D) end--;
      final line = utf8.decode(_lineBuf.sublist(0, end), allowMalformed: true);
      _lineBuf.removeRange(0, nl + 1);
      _handleLine(line);
    }
  }

  void _handleLine(String line) {
    if (line.isEmpty) return;
    final cmd = TtCommand.parse(line);
    switch (cmd.verb) {
      case 'teamtalk':
        if (inbound) {
          _send(
            TtCommand(
              'recvfile',
            ).set('transferid', transferId).set('filetxkey', transferKey),
          );
        } else {
          _send(
            TtCommand(
              'sendfile',
            ).set('transferid', transferId).set('filetxkey', transferKey),
          );
        }
      case 'filedeliver':
        onStatus(_info(TtFileTransferStatus.active, 0));
        unawaited(_streamFile());
      case 'fileready':
        onStatus(_info(TtFileTransferStatus.active, 0));
        _binaryReceive = true;
        _send(TtCommand('filedeliver'));
        if (_lineBuf.isNotEmpty) {
          final rest = Uint8List.fromList(_lineBuf);
          _lineBuf.clear();
          _writeFileBytes(rest);
        }
      case 'filecompleted':
        _finish();
      case 'error':
        _fail();
    }
  }

  void _writeFileBytes(Uint8List data) {
    if (_done) return;
    final remaining = fileSize - _received;
    final take = data.length > remaining ? remaining : data.length;
    if (take > 0) {
      final file = _file!;
      final chunk = take == data.length ? data : data.sublist(0, take);
      _writes = _writes.then((_) => file.writeFrom(chunk));
      _received += take;
    }
    onStatus(_info(TtFileTransferStatus.active, _received));
    if (_received >= fileSize) _finish();
  }

  Future<void> _streamFile() async {
    final socket = _socket;
    if (socket == null) return;
    try {
      final file = File(localPath).openRead();
      var sent = 0;
      await for (final chunk in file) {
        if (_done) return;
        socket.add(chunk);
        sent += chunk.length;
        onStatus(_info(TtFileTransferStatus.active, sent));
        await socket.flush();
      }
    } on IOException catch (e) {
      appLog.w('transfer', 'Upload $transferId failed', e);
      _fail();
    } on StateError catch (e) {
      appLog.d('transfer', 'Upload $transferId stopped: $e');
      _fail();
    }
  }

  void _finish() => unawaited(_complete());

  Future<void> _complete() async {
    if (_done) return;
    _done = true;
    _closeSocket();
    final written = await _closeFile();
    onStatus(
      written
          ? _info(TtFileTransferStatus.finished, inbound ? _received : fileSize)
          : _info(TtFileTransferStatus.error, _received),
    );
  }

  void _fail() {
    if (_done) return;
    _done = true;
    _cleanup();
    onStatus(_info(TtFileTransferStatus.error, _received));
  }

  void _onDone() {
    if (_done) return;
    if (inbound && _received >= fileSize) {
      _finish();
    } else {
      _fail();
    }
  }

  void _cleanup() {
    _closeSocket();
    unawaited(_closeFile());
  }

  void _closeSocket() {
    _socket?.destroy();
    _socket = null;
  }

  Future<bool> _closeFile() async {
    final file = _file;
    _file = null;
    if (file == null) return true;
    try {
      await _writes;
      return true;
    } on FileSystemException catch (e) {
      appLog.w('transfer', 'Transfer $transferId could not write the file', e);
      return false;
    } finally {
      try {
        await file.close();
      } on FileSystemException catch (e) {
        appLog.w(
          'transfer',
          'Transfer $transferId could not close the file',
          e,
        );
      }
    }
  }

  void _send(TtCommand cmd) => _socket?.add(cmd.encode().codeUnits);
}
