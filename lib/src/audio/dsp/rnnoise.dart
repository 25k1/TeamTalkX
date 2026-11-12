import 'dart:ffi';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

import '../native_library.dart';

typedef _FrameSizeNative = Int32 Function();
typedef _FrameSizeDart = int Function();
typedef _CreateNative = Pointer<Void> Function();
typedef _CreateDart = Pointer<Void> Function();
typedef _ProcessNative =
    Float Function(Pointer<Void>, Pointer<Int16>, Pointer<Int16>, Float);
typedef _ProcessDart =
    double Function(Pointer<Void>, Pointer<Int16>, Pointer<Int16>, double);
typedef _HandleNative = Void Function(Pointer<Void>);
typedef _HandleDart = void Function(Pointer<Void>);

class RnnoiseDenoiser {
  RnnoiseDenoiser({DynamicLibrary? library}) {
    final lib = library ?? openNativeAudio();
    _process = lib.lookupFunction<_ProcessNative, _ProcessDart>(
      'tt_rnnoise_process',
    );
    _reset = lib.lookupFunction<_HandleNative, _HandleDart>('tt_rnnoise_reset');
    _destroy = lib.lookupFunction<_HandleNative, _HandleDart>(
      'tt_rnnoise_destroy',
    );
    final size = lib.lookupFunction<_FrameSizeNative, _FrameSizeDart>(
      'tt_rnnoise_frame_size',
    )();
    if (size != frameSize) {
      throw StateError('RNNoise frame size $size, expected $frameSize');
    }
    _state = lib.lookupFunction<_CreateNative, _CreateDart>(
      'tt_rnnoise_create',
    )();
    if (_state == nullptr) throw StateError('tt_rnnoise_create failed');
    _buffer = calloc<Int16>(frameSize);
  }

  static const frameSize = 480;

  late final _ProcessDart _process;
  late final _HandleDart _reset;
  late final _HandleDart _destroy;
  late final Pointer<Void> _state;
  late final Pointer<Int16> _buffer;
  bool _disposed = false;

  double process(Int16List frame, {double wet = 1}) {
    if (_disposed) throw StateError('RnnoiseDenoiser disposed');
    if (frame.length != frameSize) {
      throw ArgumentError.value(frame.length, 'frame', 'must be $frameSize');
    }
    final native = _buffer.asTypedList(frameSize)..setAll(0, frame);
    final probability = _process(_state, _buffer, _buffer, wet);
    frame.setAll(0, native);
    return probability;
  }

  void reset() {
    if (!_disposed) _reset(_state);
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _destroy(_state);
    calloc.free(_buffer);
  }
}
