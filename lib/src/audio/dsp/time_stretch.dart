import 'dart:ffi';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

import '../native_library.dart';

typedef _CreateN = Pointer<Void> Function(Int32, Int32);
typedef _CreateD = Pointer<Void> Function(int, int);
typedef _ProcessN =
    Int32 Function(
      Pointer<Void>,
      Pointer<Int16>,
      Int32,
      Float,
      Pointer<Int16>,
      Int32,
    );
typedef _ProcessD =
    int Function(
      Pointer<Void>,
      Pointer<Int16>,
      int,
      double,
      Pointer<Int16>,
      int,
    );
typedef _FlushN = Int32 Function(Pointer<Void>, Pointer<Int16>, Int32);
typedef _FlushD = int Function(Pointer<Void>, Pointer<Int16>, int);
typedef _DestroyN = Void Function(Pointer<Void>);
typedef _DestroyD = void Function(Pointer<Void>);

class TimeStretcher {
  TimeStretcher({
    this.sampleRate = 48000,
    this.channels = 2,
    DynamicLibrary? library,
  }) {
    final lib = library ?? openNativeAudio();
    _process = lib.lookupFunction<_ProcessN, _ProcessD>('tt_stretch_process');
    _flush = lib.lookupFunction<_FlushN, _FlushD>('tt_stretch_flush');
    _destroy = lib.lookupFunction<_DestroyN, _DestroyD>('tt_stretch_destroy');
    _state = lib.lookupFunction<_CreateN, _CreateD>('tt_stretch_create')(
      sampleRate,
      channels,
    );
    if (_state == nullptr) throw StateError('tt_stretch_create failed');
    _in = calloc<Int16>(_maxSamples);
    _out = calloc<Int16>(_maxSamples * 2);
  }

  final int sampleRate;
  final int channels;

  int get _maxSamples => sampleRate * channels;

  late final _ProcessD _process;
  late final _FlushD _flush;
  late final _DestroyD _destroy;
  late final Pointer<Void> _state;
  late final Pointer<Int16> _in;
  late final Pointer<Int16> _out;
  bool _disposed = false;

  Int16List process(Int16List pcm, double speed) {
    if (_disposed) throw StateError('TimeStretcher disposed');
    final samples = pcm.length.clamp(0, _maxSamples);
    _in.asTypedList(samples).setRange(0, samples, pcm);
    final frames = _process(
      _state,
      _in,
      samples ~/ channels,
      speed,
      _out,
      _maxSamples * 2 ~/ channels,
    );
    return Int16List.fromList(_out.asTypedList(frames * channels));
  }

  Int16List flush() {
    if (_disposed) return Int16List(0);
    final frames = _flush(_state, _out, _maxSamples * 2 ~/ channels);
    return Int16List.fromList(_out.asTypedList(frames * channels));
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _destroy(_state);
    calloc
      ..free(_in)
      ..free(_out);
  }
}
