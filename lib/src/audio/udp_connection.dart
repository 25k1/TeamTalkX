import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import '../protocol/packet.dart';
import '../protocol/voice_crypt.dart';

class UdpConnection {
  UdpConnection();

  RawDatagramSocket? _socket;
  InternetAddress? _serverAddr;
  int _serverPort = 0;
  int _userId = 0;
  Timer? _keepAlive;

  final _voice = StreamController<VoicePacket>.broadcast();
  final _fragments = VoiceFragmentAssembler();
  Completer<void>? _helloAck;

  Uint8List? cryptKey;

  int undecryptable = 0;

  void Function()? onUndecryptable;

  Stream<VoicePacket> get voice => _voice.stream;
  bool get isConnected => _socket != null;

  Future<void> connect({
    required InternetAddress address,
    required int udpPort,
    required int userId,
    Duration helloTimeout = const Duration(seconds: 5),
    Duration keepAliveInterval = const Duration(seconds: 1),
  }) async {
    _userId = userId;
    _serverPort = udpPort;
    _serverAddr = address;
    _socket = await RawDatagramSocket.bind(
      address.type == InternetAddressType.IPv6
          ? InternetAddress.anyIPv6
          : InternetAddress.anyIPv4,
      0,
    );
    _socket!.listen(_onEvent);

    final ack = _helloAck = Completer<void>();
    _sendHello();
    final retry = Timer.periodic(const Duration(milliseconds: 500), (_) {
      if (!ack.isCompleted) _sendHello();
    });
    try {
      await ack.future.timeout(helloTimeout);
    } finally {
      retry.cancel();
    }

    _keepAlive = Timer.periodic(keepAliveInterval, (_) => _sendKeepAlive());
  }

  void _onEvent(RawSocketEvent event) {
    if (event != RawSocketEvent.read) return;
    final dg = _socket?.receive();
    if (dg == null || dg.data.isEmpty) return;
    final data = Uint8List.fromList(dg.data);
    final kind = data[0] & 0x7F;
    switch (kind) {
      case packetKindHello:
        if (_helloAck?.isCompleted == false) _helloAck!.complete();
      case packetKindVoice:
      case packetKindMediaFileAudio:
        _onAudio(data);
      case packetKindVoiceCrypt:
      case packetKindMediaFileAudioCrypt:
        final key = cryptKey;
        final plain = key == null ? null : decryptVoicePacket(data, key);
        if (plain == null) {
          if (undecryptable++ == 0) onUndecryptable?.call();
          return;
        }
        _onAudio(plain);
    }
  }

  void _onAudio(Uint8List data) {
    final parsed = parseVoicePacket(data);
    final packet = parsed == null ? null : _fragments.add(parsed);
    if (packet != null && !_voice.isClosed) _voice.add(packet);
  }

  void sendPacket(Uint8List data) {
    final addr = _serverAddr;
    if (_socket == null || addr == null) return;
    _socket!.send(data, addr, _serverPort);
  }

  void _sendHello() => _socket?.send(
    helloPacket(_userId, packetTimestamp()),
    _serverAddr!,
    _serverPort,
  );

  void _sendKeepAlive() => _socket?.send(
    keepAlivePacket(_userId, packetTimestamp()),
    _serverAddr!,
    _serverPort,
  );

  Future<void> close() async {
    _keepAlive?.cancel();
    _keepAlive = null;
    _socket?.close();
    _socket = null;
    if (!_voice.isClosed) await _voice.close();
  }
}
