import 'dart:ffi';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

import 'native_library.dart';

typedef _CreateN = Pointer<Void> Function(Int32, Int32, Int32);
typedef _CreateD = Pointer<Void> Function(int, int, int);
typedef _CreateVbrN =
    Pointer<Void> Function(Int32, Int32, Float, Int32, Int32, Int32);
typedef _CreateVbrD = Pointer<Void> Function(int, int, double, int, int, int);
typedef _EncodeN =
    Int32 Function(Pointer<Void>, Pointer<Int16>, Pointer<Uint8>, Int32);
typedef _EncodeD =
    int Function(Pointer<Void>, Pointer<Int16>, Pointer<Uint8>, int);
typedef _DecCreateN = Pointer<Void> Function(Int32);
typedef _DecCreateD = Pointer<Void> Function(int);
typedef _DecodeN =
    Int32 Function(Pointer<Void>, Pointer<Uint8>, Int32, Pointer<Int16>);
typedef _DecodeD =
    int Function(Pointer<Void>, Pointer<Uint8>, int, Pointer<Int16>);
typedef _DestroyN = Void Function(Pointer<Void>);
typedef _DestroyD = void Function(Pointer<Void>);

int speexSampleRate(int bandMode) => switch (bandMode) {
  0 => 8000,
  1 => 16000,
  _ => 32000,
};

int speexFrameSamples(int bandMode) => speexSampleRate(bandMode) ~/ 50;

const int speexComplexity = 2;

class SpeexFrameEncoder {
  SpeexFrameEncoder({
    required this.bandMode,
    required int quality,
    DynamicLibrary? library,
  }) {
    final lib = _bind(library);
    _state = lib.lookupFunction<_CreateN, _CreateD>('tt_speex_encoder_create')(
      bandMode,
      speexComplexity,
      quality.clamp(0, 10),
    );
    _check();
  }

  SpeexFrameEncoder.vbr({
    required this.bandMode,
    required int vbrQuality,
    int bitrate = 0,
    int maxBitrate = 0,
    bool dtx = false,
    DynamicLibrary? library,
  }) {
    final lib = _bind(library);
    _state =
        lib.lookupFunction<_CreateVbrN, _CreateVbrD>(
          'tt_speex_encoder_create_vbr',
        )(
          bandMode,
          speexComplexity,
          vbrQuality.clamp(0, 10).toDouble(),
          bitrate,
          maxBitrate,
          dtx ? 1 : 0,
        );
    _check();
  }

  final int bandMode;
  late final _EncodeD _encode;
  late final _DestroyD _destroy;
  late final Pointer<Void> _state;
  late final Pointer<Int16> _pcm;
  late final Pointer<Uint8> _out;
  bool _disposed = false;

  static const _maxBytes = 1024;

  int get frameSamples => speexFrameSamples(bandMode);

  DynamicLibrary _bind(DynamicLibrary? library) {
    final lib = library ?? openNativeAudio();
    _encode = lib.lookupFunction<_EncodeN, _EncodeD>('tt_speex_encode');
    _destroy = lib.lookupFunction<_DestroyN, _DestroyD>(
      'tt_speex_encoder_destroy',
    );
    return lib;
  }

  void _check() {
    if (_state == nullptr) {
      throw StateError('Speex encoder creation failed (band $bandMode)');
    }
    _pcm = calloc<Int16>(speexFrameSamples(2));
    _out = calloc<Uint8>(_maxBytes);
  }

  Uint8List encode(Int16List frame) {
    if (_disposed) throw StateError('SpeexFrameEncoder disposed');
    if (frame.length != frameSamples) {
      throw ArgumentError.value(frame.length, 'frame', 'Not one frame');
    }
    _pcm.asTypedList(frameSamples).setAll(0, frame);
    final bytes = _encode(_state, _pcm, _out, _maxBytes);
    if (bytes <= 0) return Uint8List(0);
    return Uint8List.fromList(_out.asTypedList(bytes));
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _destroy(_state);
    calloc
      ..free(_pcm)
      ..free(_out);
  }
}

class SpeexFrameDecoder {
  SpeexFrameDecoder({required this.bandMode, DynamicLibrary? library}) {
    final lib = library ?? openNativeAudio();
    _decode = lib.lookupFunction<_DecodeN, _DecodeD>('tt_speex_decode');
    _destroy = lib.lookupFunction<_DestroyN, _DestroyD>(
      'tt_speex_decoder_destroy',
    );
    _state = lib.lookupFunction<_DecCreateN, _DecCreateD>(
      'tt_speex_decoder_create',
    )(bandMode);
    if (_state == nullptr) {
      throw StateError('Speex decoder creation failed (band $bandMode)');
    }
    _in = calloc<Uint8>(_maxBytes);
    _pcm = calloc<Int16>(frameSamples);
  }

  final int bandMode;
  late final _DecodeD _decode;
  late final _DestroyD _destroy;
  late final Pointer<Void> _state;
  late final Pointer<Uint8> _in;
  late final Pointer<Int16> _pcm;
  bool _disposed = false;

  static const _maxBytes = 1024;

  int get frameSamples => speexFrameSamples(bandMode);

  Int16List decode(Uint8List? frame) {
    if (_disposed) throw StateError('SpeexFrameDecoder disposed');
    final length = frame == null ? 0 : frame.length.clamp(0, _maxBytes);
    if (frame != null) _in.asTypedList(length).setAll(0, frame.take(length));
    final samples = _decode(
      _state,
      frame == null ? nullptr : _in,
      length,
      _pcm,
    );
    if (samples < 0) throw const FormatException('Corrupt Speex frame');
    return Int16List.fromList(_pcm.asTypedList(samples));
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _destroy(_state);
    calloc
      ..free(_in)
      ..free(_pcm);
  }
}
