import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'opus_encoder.dart';

const int recordingSampleRate = 48000;
const int recordingChannels = 2;

abstract interface class RecordingWriter {
  void write(Int16List pcm);

  void sync();

  void close();
}

Uint8List wavHeader(
  int dataBytes, {
  int sampleRate = recordingSampleRate,
  int channels = recordingChannels,
}) {
  final b = ByteData(44);
  void tag(int at, String s) {
    for (var i = 0; i < 4; i++) {
      b.setUint8(at + i, s.codeUnitAt(i));
    }
  }

  tag(0, 'RIFF');
  b.setUint32(4, 36 + dataBytes, Endian.little);
  tag(8, 'WAVE');
  tag(12, 'fmt ');
  b
    ..setUint32(16, 16, Endian.little)
    ..setUint16(20, 1, Endian.little)
    ..setUint16(22, channels, Endian.little)
    ..setUint32(24, sampleRate, Endian.little)
    ..setUint32(28, sampleRate * channels * 2, Endian.little)
    ..setUint16(32, channels * 2, Endian.little)
    ..setUint16(34, 16, Endian.little);
  tag(36, 'data');
  b.setUint32(40, dataBytes, Endian.little);
  return b.buffer.asUint8List();
}

class WavWriter implements RecordingWriter {
  WavWriter(String path) : _file = File(path).openSync(mode: FileMode.write) {
    _file.writeFromSync(wavHeader(0));
  }

  static const _maxDataBytes = 0xFFFFFFFF - 36;

  final RandomAccessFile _file;
  int _dataBytes = 0;
  bool _closed = false;

  bool get full => _dataBytes >= _maxDataBytes - 4;

  @override
  void write(Int16List pcm) {
    if (_closed || full) return;
    var bytes = _littleEndian(pcm);
    final room = _maxDataBytes - _dataBytes;
    if (bytes.length > room) {
      bytes = Uint8List.sublistView(bytes, 0, room - room % 4);
    }
    _file.writeFromSync(bytes);
    _dataBytes += bytes.length;
  }

  @override
  void sync() {
    if (_closed) return;
    final end = _file.positionSync();
    _file
      ..setPositionSync(0)
      ..writeFromSync(wavHeader(_dataBytes))
      ..setPositionSync(end);
  }

  @override
  void close() {
    if (_closed) return;
    sync();
    _closed = true;
    _file.closeSync();
  }
}

Uint8List _littleEndian(Int16List pcm) {
  if (Endian.host == Endian.little) {
    return pcm.buffer.asUint8List(pcm.offsetInBytes, pcm.lengthInBytes);
  }
  final b = ByteData(pcm.length * 2);
  for (var i = 0; i < pcm.length; i++) {
    b.setInt16(i * 2, pcm[i], Endian.little);
  }
  return b.buffer.asUint8List();
}

final Uint32List _crcTable = () {
  final table = Uint32List(256);
  for (var i = 0; i < 256; i++) {
    var r = i << 24;
    for (var j = 0; j < 8; j++) {
      r = (r & 0x80000000) != 0 ? ((r << 1) ^ 0x04c11db7) : (r << 1);
    }
    table[i] = r & 0xFFFFFFFF;
  }
  return table;
}();

int oggCrc(Uint8List data) {
  var crc = 0;
  for (final byte in data) {
    crc = ((crc << 8) & 0xFFFFFFFF) ^ _crcTable[((crc >> 24) & 0xFF) ^ byte];
  }
  return crc;
}

Uint8List oggPage({
  required List<Uint8List> packets,
  required int granule,
  required int serial,
  required int sequence,
  bool first = false,
  bool last = false,
}) {
  final lacing = <int>[];
  for (final p in packets) {
    var n = p.length;
    while (n >= 255) {
      lacing.add(255);
      n -= 255;
    }
    lacing.add(n);
  }
  if (lacing.length > 255) {
    throw ArgumentError('Too many segments for one page: ${lacing.length}');
  }
  final bodyLength = packets.fold<int>(0, (n, p) => n + p.length);
  final page = Uint8List(27 + lacing.length + bodyLength);
  final b = ByteData.sublistView(page);
  page.setAll(0, 'OggS'.codeUnits);
  b
    ..setUint8(4, 0)
    ..setUint8(5, (first ? 0x02 : 0) | (last ? 0x04 : 0))
    ..setInt64(6, granule, Endian.little)
    ..setUint32(14, serial, Endian.little)
    ..setUint32(18, sequence, Endian.little)
    ..setUint32(22, 0, Endian.little)
    ..setUint8(26, lacing.length);
  page.setAll(27, lacing);
  var at = 27 + lacing.length;
  for (final p in packets) {
    page.setAll(at, p);
    at += p.length;
  }
  b.setUint32(22, oggCrc(page), Endian.little);
  return page;
}

Uint8List opusHead({required int channels, required int preSkip}) {
  final b = ByteData(19);
  final bytes = b.buffer.asUint8List()..setAll(0, 'OpusHead'.codeUnits);
  b
    ..setUint8(8, 1)
    ..setUint8(9, channels)
    ..setUint16(10, preSkip, Endian.little)
    ..setUint32(12, recordingSampleRate, Endian.little)
    ..setInt16(16, 0, Endian.little)
    ..setUint8(18, 0);
  return bytes;
}

Uint8List opusTags({required String vendor, List<String> comments = const []}) {
  final out = BytesBuilder();
  void u32(int v) => out.add(
    (ByteData(4)..setUint32(0, v, Endian.little)).buffer.asUint8List(),
  );
  out.add('OpusTags'.codeUnits);
  final v = utf8.encode(vendor);
  u32(v.length);
  out.add(v);
  u32(comments.length);
  for (final c in comments) {
    final bytes = utf8.encode(c);
    u32(bytes.length);
    out.add(bytes);
  }
  return out.toBytes();
}

typedef OpusFrameEncode = Uint8List Function(Int16List frame);

class OggOpusWriter implements RecordingWriter {
  OggOpusWriter(
    String path, {
    required this._encode,
    this._onClose,
    this.preSkip = defaultPreSkip,
    int? serial,
    String vendor = 'TeamTalkX',
  }) : _file = File(path).openSync(mode: FileMode.write),
       _serial = serial ?? DateTime.now().microsecondsSinceEpoch & 0x7FFFFFFF {
    _writePage(
      [opusHead(channels: recordingChannels, preSkip: preSkip)],
      0,
      first: true,
    );
    _writePage([opusTags(vendor: vendor)], 0);
  }

  static const defaultPreSkip = 312;

  static const frameSamples = 960;
  static const _packetsPerPage = 50;

  factory OggOpusWriter.withOpus(String path) {
    final encoder = OpusFrameEncoder(
      sampleRate: recordingSampleRate,
      channels: recordingChannels,
      bitrate: 64000,
      application: opusApplicationAudio,
    );
    return OggOpusWriter(
      path,
      encode: (frame) => Uint8List.fromList(encoder.encode(frame)),
      onClose: encoder.dispose,
    );
  }

  final int preSkip;
  final RandomAccessFile _file;
  final OpusFrameEncode _encode;
  final void Function()? _onClose;
  final int _serial;
  int _sequence = 0;

  final _frame = Int16List(frameSamples * recordingChannels);
  int _frameFill = 0;
  final _packets = <Uint8List>[];
  int _segments = 0;

  int _encodedSamples = 0;
  int _inputSamples = 0;
  bool _closed = false;

  bool _closing = false;

  void _writePage(
    List<Uint8List> packets,
    int granule, {
    bool first = false,
    bool last = false,
  }) {
    _file.writeFromSync(
      oggPage(
        packets: packets,
        granule: granule,
        serial: _serial,
        sequence: _sequence++,
        first: first,
        last: last,
      ),
    );
  }

  void _encodeFrame() {
    final packet = _encode(_frame);
    _packets.add(packet);
    _segments += packet.length ~/ 255 + 1;
    _encodedSamples += frameSamples;
    _frameFill = 0;
    if (!_closing && (_packets.length >= _packetsPerPage || _segments > 200)) {
      _flushPage();
    }
  }

  void _flushPage({bool last = false, int? granule}) {
    if (_packets.isEmpty && !last) return;
    _writePage(List.of(_packets), granule ?? _encodedSamples, last: last);
    _packets.clear();
    _segments = 0;
  }

  void _add(Int16List pcm) {
    var at = 0;
    while (at < pcm.length) {
      final n = math.min(pcm.length - at, _frame.length - _frameFill);
      _frame.setRange(_frameFill, _frameFill + n, pcm, at);
      _frameFill += n;
      at += n;
      if (_frameFill == _frame.length) _encodeFrame();
    }
  }

  @override
  void write(Int16List pcm) {
    if (_closed) return;
    _inputSamples += pcm.length ~/ recordingChannels;
    _add(pcm);
  }

  @override
  void sync() {
    if (_closed || _packets.length < _packetsPerPage ~/ 2) return;
    _flushPage();
  }

  @override
  void close() {
    if (_closed) return;
    _closing = true;
    _add(Int16List(preSkip * recordingChannels));
    if (_frameFill > 0) {
      _frame.fillRange(_frameFill, _frame.length, 0);
      _encodeFrame();
    }
    _flushPage(last: true, granule: preSkip + _inputSamples);
    _closed = true;
    _file.closeSync();
    _onClose?.call();
  }

  int get encodedSamples => _encodedSamples;
}
