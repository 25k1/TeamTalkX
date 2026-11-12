import 'dart:typed_data';

import 'package:pointycastle/api.dart' show KeyParameter, ParametersWithIV;
import 'package:pointycastle/block/aes.dart';
import 'package:pointycastle/block/modes/cbc.dart';

import 'command.dart';
import 'packet.dart';

const int voiceCryptKeyLength = 32;

const int _fieldTypeCryptData = 1;
const int _block = 16;

const int _maxCipherLength = 0xFFF;

Uint8List? parseVoiceCryptKey(String hex) {
  if (hex.length != voiceCryptKeyLength * 2) return null;
  final key = Uint8List(voiceCryptKeyLength);
  for (var i = 0; i < voiceCryptKeyLength; i++) {
    final byte = int.tryParse(hex.substring(i * 2, i * 2 + 2), radix: 16);
    if (byte == null) return null;
    key[i] = byte;
  }
  return key;
}

class ChannelCryptKeys {
  final _keys = <int, Uint8List>{};

  Uint8List? operator [](int channelId) => _keys[channelId];

  void onCommand(TtCommand c) {
    switch (c.verb) {
      case 'addchannel' || 'updatechannel' || 'joined':
        final key = parseVoiceCryptKey(c.getString('cryptkey') ?? '');
        if (key != null) _keys[c.getInt('chanid') ?? 0] = key;
      case 'removechannel':
        _keys.remove(c.getInt('chanid'));
    }
  }

  void clear() => _keys.clear();
}

bool isCryptVoiceKind(int kind) =>
    kind == packetKindVoiceCrypt || kind == packetKindMediaFileAudioCrypt;

Uint8List encryptVoicePacket(Uint8List plain, Uint8List key) {
  final h = parseHeader(plain);
  if (h.kind != packetKindVoice && h.kind != packetKindMediaFileAudio) {
    throw ArgumentError.value(h.kind, 'kind', 'Not an audio packet');
  }
  final fields = Uint8List.sublistView(plain, h.headerSize);
  final check = crc32(fields) & 0xFFFF;
  final padding = _block - (fields.length + 2) % _block;
  final data = Uint8List(fields.length + 2 + padding)
    ..setAll(0, fields)
    ..[fields.length] = check & 0xFF
    ..[fields.length + 1] = check >> 8
    ..fillRange(fields.length + 2, fields.length + 2 + padding, padding);
  final cipher = _cbc(key, data, encrypt: true);
  if (cipher.length > _maxCipherLength) {
    throw ArgumentError('Audio packet too large to encrypt');
  }
  final out = Uint8List(h.headerSize + 2 + cipher.length)
    ..setRange(0, h.headerSize, plain);
  out[0] = (plain[0] & 0x80) | (h.kind + 1);
  out[h.headerSize] = cipher.length & 0xFF;
  out[h.headerSize + 1] =
      ((cipher.length >> 8) & 0xF) | (_fieldTypeCryptData << 4);
  out.setAll(h.headerSize + 2, cipher);
  return out;
}

Uint8List? decryptVoicePacket(Uint8List packet, Uint8List key) {
  if (packet.isEmpty || key.length != voiceCryptKeyLength) return null;
  final h = parseHeader(packet);
  if (!isCryptVoiceKind(h.kind) || packet.length < h.headerSize) return null;
  Uint8List? cipher;
  for (final f in readFields(packet, h.headerSize)) {
    if (f.type == _fieldTypeCryptData) cipher = f.data;
  }
  if (cipher == null || cipher.isEmpty || cipher.length % _block != 0) {
    return null;
  }
  final data = _cbc(key, cipher, encrypt: false);
  final padding = data.last;
  if (padding < 1 || padding > _block || padding > data.length) return null;
  for (var i = data.length - padding; i < data.length; i++) {
    if (data[i] != padding) return null;
  }
  final length = data.length - padding;
  if (length < 2) return null;
  final fields = Uint8List.sublistView(data, 0, length - 2);
  final check = data[length - 2] | (data[length - 1] << 8);
  if (crc32(fields) & 0xFFFF != check) return null;

  final out = Uint8List(h.headerSize + fields.length)
    ..setRange(0, h.headerSize, packet)
    ..setAll(h.headerSize, fields);
  out[0] = (packet[0] & 0x80) | (h.kind - 1);
  return out;
}

Uint8List _cbc(Uint8List key, Uint8List data, {required bool encrypt}) {
  final cbc = CBCBlockCipher(AESEngine())
    ..init(encrypt, ParametersWithIV(KeyParameter(key), Uint8List(_block)));
  final out = Uint8List(data.length);
  for (var off = 0; off < data.length; off += _block) {
    cbc.processBlock(data, off, out, off);
  }
  return out;
}

final Uint32List _crcTable = () {
  final table = Uint32List(256);
  for (var n = 0; n < 256; n++) {
    var c = n;
    for (var k = 0; k < 8; k++) {
      c = (c & 1) != 0 ? 0xEDB88320 ^ (c >> 1) : c >> 1;
    }
    table[n] = c;
  }
  return table;
}();

int crc32(List<int> data) {
  var c = 0xFFFFFFFF;
  for (final b in data) {
    c = _crcTable[(c ^ b) & 0xFF] ^ (c >> 8);
  }
  return c ^ 0xFFFFFFFF;
}
