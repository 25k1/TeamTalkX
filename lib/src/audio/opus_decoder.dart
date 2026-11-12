import 'dart:ffi';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

import 'native_library.dart';

typedef _CreateNative = Pointer<Void> Function(Int32, Int32);
typedef _CreateDart = Pointer<Void> Function(int, int);

typedef _QualityNative = Int32 Function(Pointer<Void>, Int32, Int32);
typedef _QualityDart = int Function(Pointer<Void>, int, int);

typedef _DecodeNative =
    Int32 Function(
      Pointer<Void>,
      Pointer<Uint8>,
      Int32,
      Pointer<Int16>,
      Int32,
      Int32,
    );
typedef _DecodeDart =
    int Function(Pointer<Void>, Pointer<Uint8>, int, Pointer<Int16>, int, int);

typedef _RecoverNative =
    Int32 Function(
      Pointer<Void>,
      Pointer<Uint8>,
      Int32,
      Int32,
      Pointer<Int16>,
      Int32,
      Pointer<Int32>,
    );
typedef _RecoverDart =
    int Function(
      Pointer<Void>,
      Pointer<Uint8>,
      int,
      int,
      Pointer<Int16>,
      int,
      Pointer<Int32>,
    );

typedef _DestroyNative = Void Function(Pointer<Void>);
typedef _DestroyDart = void Function(Pointer<Void>);

DynamicLibrary openOpus([String? libraryPath]) => openNativeAudio(libraryPath);

enum OpusRecovery { concealed, fec, dred }

class OpusFrameDecoder {
  OpusFrameDecoder({
    required this.sampleRate,
    required this.channels,
    DynamicLibrary? library,
  }) {
    final lib = library ?? openOpus();
    _decode = lib.lookupFunction<_DecodeNative, _DecodeDart>('tt_opus_decode');
    _recover = lib.lookupFunction<_RecoverNative, _RecoverDart>(
      'tt_opus_recover',
    );
    _quality = lib.lookupFunction<_QualityNative, _QualityDart>(
      'tt_opus_decoder_set_quality',
    );
    _destroy = lib.lookupFunction<_DestroyNative, _DestroyDart>(
      'tt_opus_decoder_destroy',
    );
    final create = lib.lookupFunction<_CreateNative, _CreateDart>(
      'tt_opus_decoder_create',
    );
    _state = create(sampleRate, channels);
    if (_state == nullptr) {
      throw StateError('tt_opus_decoder_create failed');
    }
  }

  final int sampleRate;
  final int channels;

  late final Pointer<Void> _state;
  late final _DecodeDart _decode;
  late final _RecoverDart _recover;
  late final _QualityDart _quality;
  late final _DestroyDart _destroy;

  Pointer<Uint8>? _inBuf;
  int _inBufLen = 0;
  Pointer<Int16>? _pcmBuf;
  int _pcmBufLen = 0;
  final Pointer<Int32> _method = calloc<Int32>();
  Int16List _out = Int16List(0);

  OpusRecovery lastRecovery = OpusRecovery.concealed;

  void setQuality({required int complexity, bool bandwidthExtension = false}) {
    _quality(_state, complexity, bandwidthExtension ? 1 : 0);
  }

  Int16List decode(Uint8List frame, {int maxSamplesPerChannel = 5760}) {
    if (frame.isEmpty) return Int16List(0);
    final data = _ensureInBuf(frame.length);
    final pcm = _ensurePcmBuf(maxSamplesPerChannel);
    data.asTypedList(frame.length).setAll(0, frame);
    final samples = _decode(
      _state,
      data,
      frame.length,
      pcm,
      maxSamplesPerChannel,
      0,
    );
    if (samples < 0) return Int16List(0);
    return _copyOut(samples * channels);
  }

  Int16List decodeLost({int samplesPerChannel = 960}) =>
      recover(null, offset: 0, samplesPerChannel: samplesPerChannel);

  Int16List recover(
    Uint8List? next, {
    required int offset,
    required int samplesPerChannel,
  }) {
    final pcm = _ensurePcmBuf(samplesPerChannel);
    final length = next?.length ?? 0;
    final data = length == 0 ? nullptr : _ensureInBuf(length);
    if (next != null && length > 0) data.asTypedList(length).setAll(0, next);
    final samples = _recover(
      _state,
      data,
      length,
      offset,
      pcm,
      samplesPerChannel,
      _method,
    );
    lastRecovery = OpusRecovery.values[_method.value.clamp(0, 2)];
    if (samples < 0) return Int16List(0);
    return _copyOut(samples * channels);
  }

  Int16List _copyOut(int count) {
    if (_out.length < count) _out = Int16List(count);
    _out.setRange(0, count, _pcmBuf!.asTypedList(count));
    return Int16List.sublistView(_out, 0, count);
  }

  Pointer<Uint8> _ensureInBuf(int len) {
    if (_inBuf == null || _inBufLen < len) {
      final old = _inBuf;
      _inBuf = calloc<Uint8>(len);
      _inBufLen = len;
      if (old != null) calloc.free(old);
    }
    return _inBuf!;
  }

  Pointer<Int16> _ensurePcmBuf(int maxSamplesPerChannel) {
    final len = maxSamplesPerChannel * channels;
    if (_pcmBuf == null || _pcmBufLen < len) {
      final old = _pcmBuf;
      _pcmBuf = calloc<Int16>(len);
      _pcmBufLen = len;
      if (old != null) calloc.free(old);
    }
    return _pcmBuf!;
  }

  void dispose() {
    final inBuf = _inBuf;
    final pcmBuf = _pcmBuf;
    _inBuf = null;
    _pcmBuf = null;
    if (inBuf != null) calloc.free(inBuf);
    if (pcmBuf != null) calloc.free(pcmBuf);
    calloc.free(_method);
    _destroy(_state);
  }
}
