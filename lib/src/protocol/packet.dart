import 'dart:typed_data';

const int packetKindHello = 1;
const int packetKindKeepAlive = 2;
const int packetKindVoice = 3;
const int packetKindVoiceCrypt = 4;
const int packetKindMediaFileAudio = 7;
const int packetKindMediaFileAudioCrypt = 8;

const int _maskKind = 0x7F;
const int _maskDestUserSet = 0x80;

const int packetProtocol = 1;

const int _fieldTypeProtocol = 1;

const int _channelHeaderSize = 8;
const int _userHeaderSize = 10;

void _packUint12Pair(Uint8List b, int off, int v1, int v2) {
  b[off] = v1 & 0xFF;
  b[off + 1] = ((v1 >> 8) & 0xF) | ((v2 & 0xF) << 4);
  b[off + 2] = (v2 >> 4) & 0xFF;
}

(int, int) _unpackUint12Pair(Uint8List b, int off) {
  final v1 = b[off] | ((b[off + 1] & 0xF) << 8);
  final v2 = (b[off + 1] >> 4) | (b[off + 2] << 4);
  return (v1, v2);
}

void _setUint32LE(Uint8List b, int off, int v) {
  b[off] = v & 0xFF;
  b[off + 1] = (v >> 8) & 0xFF;
  b[off + 2] = (v >> 16) & 0xFF;
  b[off + 3] = (v >> 24) & 0xFF;
}

int _getUint32LE(Uint8List b, int off) =>
    b[off] | (b[off + 1] << 8) | (b[off + 2] << 16) | (b[off + 3] << 24);

int _writeFieldPrefix(Uint8List b, int off, int fieldType, int fieldSize) {
  b[off] = fieldSize & 0xFF;
  b[off + 1] = ((fieldSize >> 8) & 0xF) | ((fieldType & 0xF) << 4);
  return off + 2;
}

class PacketHeader {
  const PacketHeader({
    required this.kind,
    required this.srcUserId,
    required this.destChannelId,
    required this.time,
    required this.destUserId,
    required this.headerSize,
  });

  final int kind;
  final int srcUserId;
  final int destChannelId;
  final int time;
  final int destUserId;
  final int headerSize;
}

PacketHeader parseHeader(Uint8List b) {
  final kind = b[0] & _maskKind;
  final hasDestUser = (b[0] & _maskDestUserSet) != 0;
  final (src, chan) = _unpackUint12Pair(b, 1);
  final time = _getUint32LE(b, 4);
  var destUser = 0;
  if (hasDestUser) {
    destUser = b[8] | ((b[9] & 0xF) << 8);
  }
  return PacketHeader(
    kind: kind,
    srcUserId: src,
    destChannelId: chan,
    time: time,
    destUserId: destUser,
    headerSize: hasDestUser ? _userHeaderSize : _channelHeaderSize,
  );
}

Uint8List _channelHeader(int kind, int srcUserId, int destChannelId, int time) {
  final b = Uint8List(_channelHeaderSize);
  b[0] = kind & _maskKind;
  _packUint12Pair(b, 1, srcUserId, destChannelId);
  _setUint32LE(b, 4, time);
  return b;
}

Uint8List helloPacket(int srcUserId, int time) {
  final b = Uint8List(_channelHeaderSize + 3);
  b.setRange(
    0,
    _channelHeaderSize,
    _channelHeader(packetKindHello, srcUserId, 0, time),
  );
  final off = _writeFieldPrefix(b, _channelHeaderSize, _fieldTypeProtocol, 1);
  b[off] = packetProtocol;
  return b;
}

Uint8List keepAlivePacket(int srcUserId, int time) =>
    _channelHeader(packetKindKeepAlive, srcUserId, 0, time);

int packetTimestamp() => DateTime.now().millisecondsSinceEpoch & 0xFFFFFFFF;

const int _audioStreamIdPktNum = 1;
const int _audioStreamIdPktNumFragCnt = 2;
const int _audioStreamIdPktNumFragNo = 3;
const int _audioEncData = 4;
const int _audioEncFrameSizes = 5;

int _getUint16LE(Uint8List b, int off) => b[off] | (b[off + 1] << 8);

class PacketField {
  const PacketField(this.type, this.data);
  final int type;
  final Uint8List data;
}

List<PacketField> readFields(Uint8List b, int off) {
  final fields = <PacketField>[];
  while (off + 2 <= b.length) {
    final size = b[off] | ((b[off + 1] & 0xF) << 8);
    final type = b[off + 1] >> 4;
    off += 2;
    if (off + size > b.length) break;
    fields.add(PacketField(type, Uint8List.sublistView(b, off, off + size)));
    off += size;
  }
  return fields;
}

List<int> _readUint12Array(Uint8List d) {
  final out = <int>[];
  var i = 0;
  while (i + 3 <= d.length) {
    out.add(d[i] | ((d[i + 1] & 0xF) << 8));
    out.add((d[i + 1] >> 4) | (d[i + 2] << 4));
    i += 3;
  }
  if (i + 2 == d.length) {
    out.add(d[i] | ((d[i + 1] & 0xF) << 8));
    i += 2;
  }
  return out;
}

Uint8List _writeUint12Array(List<int> values) {
  final out = Uint8List(
    (values.length ~/ 2) * 3 + (values.length.isOdd ? 2 : 0),
  );
  var i = 0;
  var o = 0;
  while (i + 1 < values.length) {
    final v0 = values[i] & 0xFFF;
    final v1 = values[i + 1] & 0xFFF;
    out[o] = v0 & 0xFF;
    out[o + 1] = ((v0 >> 8) & 0xF) | ((v1 & 0xF) << 4);
    out[o + 2] = (v1 >> 4) & 0xFF;
    i += 2;
    o += 3;
  }
  if (i < values.length) {
    final v = values[i] & 0xFFF;
    out[o] = v & 0xFF;
    out[o + 1] = (v >> 8) & 0xF;
  }
  return out;
}

Uint8List voicePacket({
  required int srcUserId,
  required int channelId,
  required int streamId,
  required int packetNumber,
  required int time,
  required Uint8List encodedAudio,
  List<int>? frameSizes,
  int kind = packetKindVoice,
}) {
  const streamFieldSize = 3;
  final sizes = (frameSizes != null && frameSizes.length > 1)
      ? _writeUint12Array(frameSizes)
      : null;
  final sizesFieldSize = sizes == null ? 0 : 2 + sizes.length;
  final total =
      _channelHeaderSize +
      2 +
      encodedAudio.length +
      sizesFieldSize +
      2 +
      streamFieldSize;
  final b = Uint8List(total);
  b.setRange(
    0,
    _channelHeaderSize,
    _channelHeader(kind, srcUserId, channelId, time),
  );
  var off = _channelHeaderSize;
  off = _writeFieldPrefix(b, off, _audioEncData, encodedAudio.length);
  b.setRange(off, off + encodedAudio.length, encodedAudio);
  off += encodedAudio.length;
  if (sizes != null) {
    off = _writeFieldPrefix(b, off, _audioEncFrameSizes, sizes.length);
    b.setRange(off, off + sizes.length, sizes);
    off += sizes.length;
  }
  off = _writeFieldPrefix(b, off, _audioStreamIdPktNum, streamFieldSize);
  b[off] = streamId & 0xFF;
  b[off + 1] = packetNumber & 0xFF;
  b[off + 2] = (packetNumber >> 8) & 0xFF;
  return b;
}

class VoicePacket {
  const VoicePacket({
    required this.kind,
    required this.srcUserId,
    required this.channelId,
    required this.streamId,
    required this.packetNumber,
    required this.encodedAudio,
    required this.frameSizes,
    this.fragmentNo,
    this.fragmentCount,
  });

  final int kind;
  final int srcUserId;
  final int channelId;
  final int streamId;
  final int packetNumber;
  final Uint8List encodedAudio;

  final List<int> frameSizes;

  final int? fragmentNo;
  final int? fragmentCount;

  bool get isFragment => fragmentNo != null;
}

const int maxVoicePayload = 1250;

VoicePacket? parseVoicePacket(Uint8List b) {
  final h = parseHeader(b);
  if (h.kind != packetKindVoice && h.kind != packetKindMediaFileAudio) {
    return null;
  }
  var streamId = 0;
  var packetNo = 0;
  int? fragmentNo;
  int? fragmentCount;
  var enc = Uint8List(0);
  var frameSizes = const <int>[];
  for (final f in readFields(b, h.headerSize)) {
    switch (f.type) {
      case _audioStreamIdPktNum:
        if (f.data.length >= 3) {
          streamId = f.data[0];
          packetNo = _getUint16LE(f.data, 1);
        }
      case _audioStreamIdPktNumFragCnt:
        if (f.data.length >= 4) {
          streamId = f.data[0];
          packetNo = _getUint16LE(f.data, 1);
          fragmentNo = 0;
          fragmentCount = f.data[3];
        }
      case _audioStreamIdPktNumFragNo:
        if (f.data.length >= 4) {
          streamId = f.data[0];
          packetNo = _getUint16LE(f.data, 1);
          fragmentNo = f.data[3];
        }
      case _audioEncData:
        enc = f.data;
      case _audioEncFrameSizes:
        frameSizes = _readUint12Array(f.data);
    }
  }
  return VoicePacket(
    kind: h.kind,
    srcUserId: h.srcUserId,
    channelId: h.destChannelId,
    streamId: streamId,
    packetNumber: packetNo,
    encodedAudio: enc,
    frameSizes: frameSizes,
    fragmentNo: fragmentNo,
    fragmentCount: fragmentCount,
  );
}

List<Uint8List>? splitAudioFrames(
  Uint8List encoded,
  List<int> frameSizes, {
  int framesPerPacket = 1,
}) {
  if (encoded.isEmpty) return const [];
  if (frameSizes.isNotEmpty) {
    var total = 0;
    for (final size in frameSizes) {
      total += size;
    }
    if (total != encoded.length) return null;
    final frames = <Uint8List>[];
    var off = 0;
    for (final size in frameSizes) {
      frames.add(Uint8List.sublistView(encoded, off, off + size));
      off += size;
    }
    return frames;
  }
  if (framesPerPacket <= 1) return [encoded];
  if (encoded.length % framesPerPacket != 0) return null;
  final size = encoded.length ~/ framesPerPacket;
  return [
    for (var i = 0; i < framesPerPacket; i++)
      Uint8List.sublistView(encoded, i * size, (i + 1) * size),
  ];
}

List<Uint8List> fragmentVoicePacket({
  required int srcUserId,
  required int channelId,
  required int streamId,
  required int packetNumber,
  required int time,
  required Uint8List encodedAudio,
  List<int>? frameSizes,
  int kind = packetKindVoice,
  int maxChunk = maxVoicePayload,
}) {
  if (encodedAudio.length <= maxChunk) {
    return [
      voicePacket(
        srcUserId: srcUserId,
        channelId: channelId,
        streamId: streamId,
        packetNumber: packetNumber,
        time: time,
        encodedAudio: encodedAudio,
        frameSizes: frameSizes,
        kind: kind,
      ),
    ];
  }
  final count = (encodedAudio.length + maxChunk - 1) ~/ maxChunk;
  if (count >= 0xFF) {
    throw ArgumentError.value(encodedAudio.length, 'encodedAudio');
  }
  return [
    for (var i = 0; i < count; i++)
      _audioPacket(
        kind: kind,
        srcUserId: srcUserId,
        channelId: channelId,
        time: time,
        streamField: Uint8List.fromList([
          streamId & 0xFF,
          packetNumber & 0xFF,
          (packetNumber >> 8) & 0xFF,
          if (i == 0) count else i,
        ]),
        streamFieldType: i == 0
            ? _audioStreamIdPktNumFragCnt
            : _audioStreamIdPktNumFragNo,
        encodedAudio: Uint8List.sublistView(
          encodedAudio,
          i * maxChunk,
          i == count - 1 ? encodedAudio.length : (i + 1) * maxChunk,
        ),
        frameSizes: i == 0 ? frameSizes : null,
      ),
  ];
}

Uint8List _audioPacket({
  required int kind,
  required int srcUserId,
  required int channelId,
  required int time,
  required Uint8List streamField,
  required int streamFieldType,
  required Uint8List encodedAudio,
  List<int>? frameSizes,
}) {
  final sizes = (frameSizes != null && frameSizes.length > 1)
      ? _writeUint12Array(frameSizes)
      : null;
  final b = BytesBuilder(copy: false)
    ..add(_channelHeader(kind, srcUserId, channelId, time));
  void field(int type, Uint8List data) {
    final prefix = Uint8List(2);
    _writeFieldPrefix(prefix, 0, type, data.length);
    b
      ..add(prefix)
      ..add(data);
  }

  field(_audioEncData, encodedAudio);
  if (sizes != null) field(_audioEncFrameSizes, sizes);
  field(streamFieldType, streamField);
  return b.toBytes();
}

class VoiceFragmentAssembler {
  VoiceFragmentAssembler({this.maxPending = 16});

  final int maxPending;
  final _sets = <(int, int, int, int), Map<int, VoicePacket>>{};

  VoicePacket? add(VoicePacket packet) {
    if (!packet.isFragment) return packet;
    final key = (
      packet.srcUserId,
      packet.kind,
      packet.streamId,
      packet.packetNumber,
    );
    final set = _sets.remove(key) ?? <int, VoicePacket>{};
    set[packet.fragmentNo!] = packet;
    _sets[key] = set;
    while (_sets.length > maxPending) {
      _sets.remove(_sets.keys.first);
    }
    final first = set[0];
    final count = first?.fragmentCount;
    if (first == null || count == null || set.length < count) return null;
    _sets.remove(key);
    final joined = BytesBuilder(copy: false);
    for (var i = 0; i < count; i++) {
      final fragment = set[i];
      if (fragment == null) return null;
      joined.add(fragment.encodedAudio);
    }
    final encoded = joined.toBytes();
    if (first.frameSizes.isNotEmpty &&
        first.frameSizes.fold<int>(0, (a, b) => a + b) != encoded.length) {
      return null;
    }
    return VoicePacket(
      kind: first.kind,
      srcUserId: first.srcUserId,
      channelId: first.channelId,
      streamId: first.streamId,
      packetNumber: first.packetNumber,
      encodedAudio: encoded,
      frameSizes: first.frameSizes,
    );
  }

  void clear() => _sets.clear();
}
