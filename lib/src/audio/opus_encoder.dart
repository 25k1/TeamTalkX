import 'dart:ffi';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

import 'opus_decoder.dart' show openOpus;

typedef _WrapCreateNative = Pointer<Void> Function(Int32, Int32, Int32, Int32);
typedef _WrapCreateDart = Pointer<Void> Function(int, int, int, int);

typedef _WrapConfigureNative =
    Int32 Function(Pointer<Void>, Int32, Int32, Int32, Int32, Int32);
typedef _WrapConfigureDart =
    int Function(Pointer<Void>, int, int, int, int, int);

typedef _EncodeNative =
    Int32 Function(Pointer<Void>, Pointer<Int16>, Int32, Pointer<Uint8>, Int32);
typedef _EncodeDart =
    int Function(Pointer<Void>, Pointer<Int16>, int, Pointer<Uint8>, int);

typedef _LossNative = Int32 Function(Pointer<Void>, Int32, Int32);
typedef _LossDart = int Function(Pointer<Void>, int, int);

typedef _DestroyNative = Void Function(Pointer<Void>);
typedef _DestroyDart = void Function(Pointer<Void>);

const int opusApplicationVoip = 2048;
const int opusApplicationAudio = 2049;

int opusFrameSamples(int sampleRate, int msec) {
  if (msec < 5) return sampleRate * 25 ~/ 10000;
  if (msec < 10) return sampleRate * 50 ~/ 10000;
  if (msec < 20) return sampleRate * 100 ~/ 10000;
  if (msec < 40) return sampleRate * 200 ~/ 10000;
  if (msec < 60) return sampleRate * 400 ~/ 10000;
  if (msec < 80) return sampleRate * 600 ~/ 10000;
  if (msec < 100) return sampleRate * 800 ~/ 10000;
  if (msec < 120) return sampleRate * 1000 ~/ 10000;
  return sampleRate * 1200 ~/ 10000;
}

class OpusFrameEncoder {
  OpusFrameEncoder({
    required this.sampleRate,
    required this.channels,
    int bitrate = 32000,
    int application = opusApplicationVoip,
    int complexity = 10,
    bool fec = false,
    bool dtx = false,
    bool vbr = true,
    bool vbrConstraint = false,
    int lossPercent = 0,
    int dredMs = 0,
    DynamicLibrary? library,
  }) {
    final lib = library ?? openOpus();
    _encode = lib.lookupFunction<_EncodeNative, _EncodeDart>('tt_opus_encode');
    _destroy = lib.lookupFunction<_DestroyNative, _DestroyDart>(
      'tt_opus_encoder_destroy',
    );
    final create = lib.lookupFunction<_WrapCreateNative, _WrapCreateDart>(
      'tt_opus_encoder_create',
    );
    _state = create(sampleRate, channels, application, bitrate);
    if (_state == nullptr) {
      throw StateError('tt_opus_encoder_create failed');
    }
    final configure = lib
        .lookupFunction<_WrapConfigureNative, _WrapConfigureDart>(
          'tt_opus_encoder_configure',
        );
    configure(
      _state,
      complexity,
      fec ? 1 : 0,
      dtx ? 1 : 0,
      vbr ? 1 : 0,
      vbrConstraint ? 1 : 0,
    );
    lib.lookupFunction<_LossNative, _LossDart>('tt_opus_encoder_set_loss')(
      _state,
      lossPercent,
      dredMs,
    );
  }

  final int sampleRate;
  final int channels;

  late final Pointer<Void> _state;
  late final _EncodeDart _encode;
  late final _DestroyDart _destroy;

  Pointer<Int16>? _inBuf;
  int _inBufLen = 0;
  Pointer<Uint8>? _outBuf;
  int _outBufLen = 0;
  Uint8List _out = Uint8List(0);

  Uint8List encode(Int16List frame, {int maxBytes = 4000}) {
    final samplesPerChannel = frame.length ~/ channels;
    final input = _ensureInBuf(frame.length);
    final output = _ensureOutBuf(maxBytes);
    input.asTypedList(frame.length).setAll(0, frame);
    final n = _encode(_state, input, samplesPerChannel, output, maxBytes);
    if (n < 0) return Uint8List(0);
    _out.setRange(0, n, output.asTypedList(n));
    return Uint8List.sublistView(_out, 0, n);
  }

  Pointer<Int16> _ensureInBuf(int len) {
    if (_inBuf == null || _inBufLen < len) {
      final old = _inBuf;
      _inBuf = calloc<Int16>(len);
      _inBufLen = len;
      if (old != null) calloc.free(old);
    }
    return _inBuf!;
  }

  Pointer<Uint8> _ensureOutBuf(int len) {
    if (_outBuf == null || _outBufLen < len) {
      final old = _outBuf;
      _outBuf = calloc<Uint8>(len);
      _outBufLen = len;
      if (old != null) calloc.free(old);
    }
    if (_out.length < len) _out = Uint8List(len);
    return _outBuf!;
  }

  void dispose() {
    final inBuf = _inBuf;
    final outBuf = _outBuf;
    _inBuf = null;
    _outBuf = null;
    if (inBuf != null) calloc.free(inBuf);
    if (outBuf != null) calloc.free(outBuf);
    _destroy(_state);
  }
}
