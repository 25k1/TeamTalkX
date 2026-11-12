import 'dart:ffi';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

import '../native_library.dart';

typedef _ChunkSizeNative = Int32 Function();
typedef _ChunkSizeDart = int Function();
typedef _CreateNative = Pointer<Void> Function(Pointer<Uint8>, Int32);
typedef _CreateDart = Pointer<Void> Function(Pointer<Uint8>, int);
typedef _ProcessNative = Float Function(Pointer<Void>, Pointer<Float>);
typedef _ProcessDart = double Function(Pointer<Void>, Pointer<Float>);
typedef _FeedNative =
    Int32 Function(Pointer<Void>, Pointer<Int16>, Int32, Pointer<Float>, Int32);
typedef _FeedDart =
    int Function(Pointer<Void>, Pointer<Int16>, int, Pointer<Float>, int);
typedef _StateNative =
    Void Function(Pointer<Void>, Pointer<Float>, Pointer<Float>);
typedef _StateDart =
    void Function(Pointer<Void>, Pointer<Float>, Pointer<Float>);
typedef _HandleNative = Void Function(Pointer<Void>);
typedef _HandleDart = void Function(Pointer<Void>);

class SileroVad {
  SileroVad(Uint8List weights, {DynamicLibrary? library}) {
    final lib = library ?? openNativeAudio();
    _process = lib.lookupFunction<_ProcessNative, _ProcessDart>(
      'tt_silero_process',
    );
    _feed = lib.lookupFunction<_FeedNative, _FeedDart>('tt_silero_feed');
    _stateOf = lib.lookupFunction<_StateNative, _StateDart>('tt_silero_state');
    _reset = lib.lookupFunction<_HandleNative, _HandleDart>('tt_silero_reset');
    _destroy = lib.lookupFunction<_HandleNative, _HandleDart>(
      'tt_silero_destroy',
    );
    final size = lib.lookupFunction<_ChunkSizeNative, _ChunkSizeDart>(
      'tt_silero_chunk_size',
    )();
    if (size != chunkSize) {
      throw StateError('Silero chunk size $size, expected $chunkSize');
    }
    final create = lib.lookupFunction<_CreateNative, _CreateDart>(
      'tt_silero_create',
    );
    final bytes = calloc<Uint8>(weights.length);
    try {
      bytes.asTypedList(weights.length).setAll(0, weights);
      _vad = create(bytes, weights.length);
    } finally {
      calloc.free(bytes);
    }
    if (_vad == nullptr) {
      throw ArgumentError('Not Silero v6.2 weights, or out of memory');
    }
    _chunk = calloc<Float>(chunkSize);
  }

  static const chunkSize = 512;

  static const stateSize = 128;

  late final _ProcessDart _process;
  late final _FeedDart _feed;
  late final _StateDart _stateOf;
  late final _HandleDart _reset;
  late final _HandleDart _destroy;
  late final Pointer<Void> _vad;
  late final Pointer<Float> _chunk;
  Pointer<Int16> _pcm = nullptr;
  int _pcmCapacity = 0;
  Pointer<Float> _probs = nullptr;
  int _probsCapacity = 0;
  bool _disposed = false;

  static final _none = Float32List(0);

  Float32List feed(Int16List pcm) {
    _checkOpen();
    if (pcm.isEmpty) return _none;
    if (pcm.length > _pcmCapacity) {
      if (_pcm != nullptr) calloc.free(_pcm);
      _pcmCapacity = pcm.length;
      _pcm = calloc<Int16>(_pcmCapacity);
    }
    final most = pcm.length ~/ chunkSize + 1;
    if (most > _probsCapacity) {
      if (_probs != nullptr) calloc.free(_probs);
      _probsCapacity = most;
      _probs = calloc<Float>(_probsCapacity);
    }
    _pcm.asTypedList(pcm.length).setAll(0, pcm);
    final n = _feed(_vad, _pcm, pcm.length, _probs, _probsCapacity);
    if (n == 0) return _none;
    return Float32List.fromList(_probs.asTypedList(n));
  }

  double process(Float32List chunk) {
    _checkOpen();
    if (chunk.length != chunkSize) {
      throw ArgumentError.value(chunk.length, 'chunk', 'must be $chunkSize');
    }
    _chunk.asTypedList(chunkSize).setAll(0, chunk);
    return _process(_vad, _chunk);
  }

  ({Float32List h, Float32List c}) get state {
    _checkOpen();
    final h = calloc<Float>(stateSize);
    final c = calloc<Float>(stateSize);
    try {
      _stateOf(_vad, h, c);
      return (
        h: Float32List.fromList(h.asTypedList(stateSize)),
        c: Float32List.fromList(c.asTypedList(stateSize)),
      );
    } finally {
      calloc
        ..free(h)
        ..free(c);
    }
  }

  void reset() {
    if (!_disposed) _reset(_vad);
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _destroy(_vad);
    calloc.free(_chunk);
    if (_pcm != nullptr) calloc.free(_pcm);
    if (_probs != nullptr) calloc.free(_probs);
  }

  void _checkOpen() {
    if (_disposed) throw StateError('SileroVad disposed');
  }
}
