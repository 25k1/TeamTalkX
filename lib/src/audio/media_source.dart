import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

import 'native_library.dart';

abstract interface class MediaSource {
  int get sampleRate;
  int get channels;

  Duration? get duration;

  Int16List? read(int maxSamples);

  void seek(Duration position);

  void close();
}

MediaSource openMediaSource(String path, {DynamicLibrary? library}) {
  DynamicLibrary? lib = library;
  if (lib == null) {
    try {
      lib = openNativeAudio();
    } on ArgumentError {
      lib = null;
    }
  }
  if (lib != null && lib.providesSymbol('tt_media_open')) {
    return NativeMediaSource(path, lib);
  }
  return WavMediaSource(path);
}

typedef _OpenN = Pointer<Void> Function(Pointer<Utf8>);
typedef _IntN = Int32 Function(Pointer<Void>);
typedef _IntD = int Function(Pointer<Void>);
typedef _DurationN = Int64 Function(Pointer<Void>);
typedef _ReadN = Int32 Function(Pointer<Void>, Pointer<Int16>, Int32);
typedef _ReadD = int Function(Pointer<Void>, Pointer<Int16>, int);
typedef _SeekN = Int32 Function(Pointer<Void>, Int64);
typedef _SeekD = int Function(Pointer<Void>, int);
typedef _CloseN = Void Function(Pointer<Void>);
typedef _CloseD = void Function(Pointer<Void>);

class NativeMediaSource implements MediaSource {
  NativeMediaSource(String path, DynamicLibrary lib) {
    _rate = lib.lookupFunction<_IntN, _IntD>('tt_media_sample_rate');
    _channels = lib.lookupFunction<_IntN, _IntD>('tt_media_channels');
    _read = lib.lookupFunction<_ReadN, _ReadD>('tt_media_read');
    _seek = lib.lookupFunction<_SeekN, _SeekD>('tt_media_seek');
    _close = lib.lookupFunction<_CloseN, _CloseD>('tt_media_close');
    final open = lib.lookupFunction<_OpenN, _OpenN>('tt_media_open');
    final nativePath = path.toNativeUtf8();
    try {
      _media = open(nativePath);
    } finally {
      calloc.free(nativePath);
    }
    if (_media == nullptr) {
      throw FormatException('No playable audio in the file', path);
    }
    final us = lib.lookupFunction<_DurationN, _IntD>('tt_media_duration_us')(
      _media,
    );
    duration = us < 0 ? null : Duration(microseconds: us);
  }

  late final _IntD _rate;
  late final _IntD _channels;
  late final _ReadD _read;
  late final _SeekD _seek;
  late final _CloseD _close;
  late final Pointer<Void> _media;
  Pointer<Int16>? _buffer;
  int _bufferLen = 0;
  bool _closed = false;

  @override
  late final Duration? duration;

  @override
  int get sampleRate => _closed ? 0 : _rate(_media);

  @override
  int get channels => _closed ? 0 : _channels(_media);

  @override
  Int16List? read(int maxSamples) {
    if (_closed) return null;
    if (_bufferLen < maxSamples) {
      final old = _buffer;
      _buffer = calloc<Int16>(maxSamples);
      _bufferLen = maxSamples;
      if (old != null) calloc.free(old);
    }
    final n = _read(_media, _buffer!, maxSamples);
    if (n < 0) throw const FormatException('The audio could not be decoded');
    if (n == 0) return null;
    return Int16List.fromList(_buffer!.asTypedList(n));
  }

  @override
  void seek(Duration position) {
    if (!_closed) _seek(_media, position.inMicroseconds);
  }

  @override
  void close() {
    if (_closed) return;
    _closed = true;
    _close(_media);
    final buffer = _buffer;
    if (buffer != null) calloc.free(buffer);
  }
}

class WavMediaSource implements MediaSource {
  WavMediaSource(String path) : _file = File(path).openSync() {
    try {
      _parseHeader();
    } on Object {
      _file.closeSync();
      rethrow;
    }
  }

  final RandomAccessFile _file;
  late final int _dataStart;
  late final int _dataEnd;
  late final int _rate;
  late final int _channels;
  bool _closed = false;

  void _parseHeader() {
    final head = _file.readSync(64 * 1024);
    final bd = ByteData.sublistView(head);
    String tag(int off) => String.fromCharCodes(head.sublist(off, off + 4));
    if (head.length < 12 || tag(0) != 'RIFF' || tag(8) != 'WAVE') {
      throw const FormatException('Not a WAV file');
    }
    var off = 12;
    int? format, bits, rate, channels, dataStart, dataLength;
    while (off + 8 <= head.length) {
      final size = bd.getUint32(off + 4, Endian.little);
      switch (tag(off)) {
        case 'fmt ' when off + 24 <= head.length:
          format = bd.getUint16(off + 8, Endian.little);
          channels = bd.getUint16(off + 10, Endian.little);
          rate = bd.getUint32(off + 12, Endian.little);
          bits = bd.getUint16(off + 22, Endian.little);
        case 'data':
          dataStart = off + 8;
          dataLength = size;
      }
      if (dataStart != null) break;
      off += 8 + size + (size.isOdd ? 1 : 0);
    }
    if (format != 1 || bits != 16) {
      throw FormatException('Only 16-bit PCM WAV (format $format, $bits bit)');
    }
    if (dataStart == null || channels == null || channels < 1) {
      throw const FormatException('WAV file without audio');
    }
    if (rate == null || rate < 1) {
      throw const FormatException('WAV file without a sample rate');
    }
    final fileLength = _file.lengthSync();
    _dataStart = dataStart;
    _dataEnd = (dataStart + dataLength!).clamp(dataStart, fileLength);
    _rate = rate;
    _channels = channels;
    _file.setPositionSync(_dataStart);
  }

  int get _frameBytes => _channels * 2;

  @override
  int get sampleRate => _rate;

  @override
  int get channels => _channels;

  @override
  Duration get duration => Duration(
    microseconds: (_dataEnd - _dataStart) ~/ _frameBytes * 1000000 ~/ _rate,
  );

  @override
  Int16List? read(int maxSamples) {
    if (_closed) return null;
    final position = _file.positionSync();
    final frames = maxSamples ~/ _channels;
    final bytes = (frames * _frameBytes).clamp(0, _dataEnd - position);
    if (bytes <= 0) return null;
    final data = _file.readSync(bytes - bytes % _frameBytes);
    if (data.isEmpty) return null;
    final out = Int16List(data.length ~/ 2);
    final bd = ByteData.sublistView(data);
    for (var i = 0; i < out.length; i++) {
      out[i] = bd.getInt16(i * 2, Endian.little);
    }
    return out;
  }

  @override
  void seek(Duration position) {
    if (_closed) return;
    final frame = position.inMicroseconds * _rate ~/ 1000000;
    _file.setPositionSync(
      (_dataStart + frame.clamp(0, 1 << 40) * _frameBytes).clamp(
        _dataStart,
        _dataEnd,
      ),
    );
  }

  @override
  void close() {
    if (_closed) return;
    _closed = true;
    _file.closeSync();
  }
}
