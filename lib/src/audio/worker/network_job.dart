part of '../audio_worker.dart';

class _NetworkJob {
  _NetworkJob(this._w) {
    _activityTimer = Timer.periodic(const Duration(milliseconds: 100), (_) {
      final now = DateTime.now();
      _lastHeard.removeWhere((key, last) {
        if (now.difference(last) < const Duration(milliseconds: 500)) {
          return false;
        }
        _w.rootPort.send(_ActivityMsg(key.$1, key.$2, active: false));
        return true;
      });
    });
  }

  final _Worker _w;

  UdpConnection? _udp;
  StreamSubscription<VoicePacket>? _udpSub;
  final gains = <int, (double, double)>{};
  Uint8List? _cryptKey;
  var _encryptFailureLogged = false;

  final _lastHeard = <(int, int), DateTime>{};
  late final Timer _activityTimer;

  void heard(int userId, int kind) {
    final key = (userId, kind);
    if (_lastHeard[key] == null) {
      _w.rootPort.send(_ActivityMsg(userId, kind, active: true));
    }
    _lastHeard[key] = DateTime.now();
  }

  void send(List<Uint8List> packets, int userId, int kind) {
    if (packets.isEmpty) return;
    final key = _cryptKey;
    if (key != null) {
      try {
        for (var i = 0; i < packets.length; i++) {
          packets[i] = encryptVoicePacket(packets[i], key);
        }
      } on ArgumentError catch (e) {
        if (!_encryptFailureLogged) {
          _encryptFailureLogged = true;
          _w.log(LogLevel.error, 'Audio could not be encrypted', e);
        }
        return;
      }
    }
    final connection = _udp;
    if (connection != null && connection.isConnected) {
      packets.forEach(connection.sendPacket);
      heard(userId, kind);
    } else {
      _w.rootPort.send(TxPackets(packets));
    }
  }

  void setCryptKey(Uint8List? key) {
    _cryptKey = key;
    _udp
      ?..cryptKey = key
      ..undecryptable = 0;
  }

  void _onPacket(VoicePacket v) {
    if (v.encodedAudio.isEmpty) return;
    heard(v.srcUserId, v.kind);
    final gain = gains[v.srcUserId];
    _w.receive.receive(
      _RxPacketMsg(
        (v.srcUserId << 8) | v.kind,
        v.streamId,
        v.encodedAudio,
        v.packetNumber,
        v.kind == packetKindMediaFileAudio ? (gain?.$2 ?? 1) : (gain?.$1 ?? 1),
        v.frameSizes,
        _w.receive.codec.fpp,
      ),
    );
  }

  Future<void> start(_StartUdpMsg msg) async {
    await _udpSub?.cancel();
    await _udp?.close();
    final address = InternetAddress.tryParse(msg.address);
    if (address == null) {
      _w.rootPort.send(_UdpStatusMsg('Not an address: ${msg.address}'));
      return;
    }
    final connection = _udp = UdpConnection()
      ..cryptKey = _cryptKey
      ..onUndecryptable = () => _w.log(
        LogLevel.warning,
        'Encrypted voice that does not decrypt with the channel key',
      );
    _udpSub = connection.voice.listen(_onPacket);
    try {
      await connection.connect(
        address: address,
        udpPort: msg.port,
        userId: msg.userId,
      );
      _w.rootPort.send(const _UdpStatusMsg(null));
    } on TimeoutException {
      _w.rootPort.send(
        _UdpStatusMsg('The server did not answer on UDP port ${msg.port}'),
      );
    } on SocketException catch (e) {
      _w.rootPort.send(_UdpStatusMsg('UDP failed: ${e.message}'));
    }
  }

  void stopActivity() => _activityTimer.cancel();

  void close() {
    unawaited(_udpSub?.cancel());
    unawaited(_udp?.close());
    _udp = null;
  }
}
