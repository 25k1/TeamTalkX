import 'dart:math' as math;

import '../domain/tt_types.dart' show AudioCodecType;
import 'speex_codec.dart';

class TxCodecConfig {
  const TxCodecConfig({
    required this.sampleRate,
    required this.channels,
    required this.bitrate,
    this.codec = AudioCodecType.opus,
    this.speexBandMode = 0,
    this.speexQuality = 0,
    this.maxBitrate = 0,
    this.complexity = 10,
    this.fec = false,
    this.dtx = false,
    this.vbr = true,
    this.vbrConstraint = false,
    this.frameMs = 20,
    this.fpp = 1,
  });

  final AudioCodecType codec;

  final int speexBandMode;

  final int speexQuality;

  final int maxBitrate;

  bool get isSpeex =>
      codec == AudioCodecType.speex || codec == AudioCodecType.speexVbr;

  final int sampleRate;
  final int channels;

  final int bitrate;
  final int complexity;
  final bool fec;

  final bool dtx;
  final bool vbr;
  final bool vbrConstraint;

  final int frameMs;

  final int fpp;

  @override
  bool operator ==(Object other) =>
      other is TxCodecConfig &&
      other.codec == codec &&
      other.speexBandMode == speexBandMode &&
      other.speexQuality == speexQuality &&
      other.maxBitrate == maxBitrate &&
      other.sampleRate == sampleRate &&
      other.channels == channels &&
      other.bitrate == bitrate &&
      other.complexity == complexity &&
      other.fec == fec &&
      other.dtx == dtx &&
      other.vbr == vbr &&
      other.vbrConstraint == vbrConstraint &&
      other.frameMs == frameMs &&
      other.fpp == fpp;

  @override
  int get hashCode => Object.hash(
    codec,
    speexBandMode,
    speexQuality,
    maxBitrate,
    sampleRate,
    channels,
    bitrate,
    complexity,
    fec,
    dtx,
    vbr,
    vbrConstraint,
    frameMs,
    fpp,
  );
}

TxCodecConfig txCodecConfigFromWire(
  List<int>? codec, {
  required int fallbackRate,
  required int outChannels,
}) {
  int at(int i, int def) =>
      (codec != null && codec.length > i) ? codec[i] : def;
  final type = at(0, AudioCodecType.opus.value);
  if (type == AudioCodecType.speex.value ||
      type == AudioCodecType.speexVbr.value) {
    final vbr = type == AudioCodecType.speexVbr.value;
    final band = at(1, 1).clamp(0, 2);
    return TxCodecConfig(
      codec: vbr ? AudioCodecType.speexVbr : AudioCodecType.speex,
      speexBandMode: band,
      speexQuality: at(2, vbr ? 5 : 4).clamp(0, 10),
      sampleRate: speexSampleRate(band),
      channels: 1,
      bitrate: vbr ? math.max(0, at(3, 0)) : 0,
      maxBitrate: vbr ? math.max(0, at(4, 0)) : 0,
      dtx: vbr && at(5, 0) != 0,
      vbr: vbr,
      fpp: at(vbr ? 6 : 3, 1).clamp(1, 12),
    );
  }
  final rate = _validOpusRates.contains(at(1, fallbackRate))
      ? at(1, fallbackRate)
      : 48000;
  final bitrate = at(7, 32000) > 0 ? at(7, 32000) : 32000;
  final complexity = at(4, 10).clamp(0, 10);
  final frameSamples = at(10, rate ~/ 50);
  final frameMs = frameSamples > 0 ? (frameSamples * 1000) ~/ rate : 20;
  final fpp = at(11, 1).clamp(1, 12);
  return TxCodecConfig(
    sampleRate: rate,
    channels: outChannels,
    bitrate: bitrate,
    complexity: complexity,
    fec: at(5, 0) != 0,
    dtx: at(6, 0) != 0,
    vbr: at(8, 1) != 0,
    vbrConstraint: at(9, 0) != 0,
    frameMs: frameMs < 1 ? 20 : frameMs,
    fpp: fpp,
  );
}

const _validOpusRates = {8000, 12000, 16000, 24000, 48000};
