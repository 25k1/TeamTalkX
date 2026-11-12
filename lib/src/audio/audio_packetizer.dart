import 'dart:typed_data';

import '../domain/tt_types.dart' show AudioCodecType;
import '../domain/voice_quality.dart';
import '../protocol/packet.dart';
import 'codec_config.dart';
import 'opus_encoder.dart';
import 'pcm_accumulator.dart';
import 'speex_codec.dart';

class VoiceFrameEncoder {
  VoiceFrameEncoder(this.encode, this.dispose);

  factory VoiceFrameEncoder.forConfig(
    TxCodecConfig config,
    int channels, {
    LossProtection? protection,
  }) {
    switch (config.codec) {
      case AudioCodecType.speex:
        final e = SpeexFrameEncoder(
          bandMode: config.speexBandMode,
          quality: config.speexQuality,
        );
        return VoiceFrameEncoder(e.encode, e.dispose);
      case AudioCodecType.speexVbr:
        final e = SpeexFrameEncoder.vbr(
          bandMode: config.speexBandMode,
          vbrQuality: config.speexQuality,
          bitrate: config.bitrate,
          maxBitrate: config.maxBitrate,
          dtx: config.dtx,
        );
        return VoiceFrameEncoder(e.encode, e.dispose);
      case AudioCodecType.opus || AudioCodecType.none:
        final fec = config.fec && (protection?.fec ?? true);
        final dredMs = protection?.dredMs ?? 0;
        final e = OpusFrameEncoder(
          sampleRate: config.sampleRate,
          channels: channels,
          bitrate: config.bitrate,
          complexity: config.complexity,
          fec: fec,
          lossPercent: protection != null && (fec || dredMs > 0)
              ? protection.expectedLossPercent
              : 0,
          dredMs: dredMs,
          dtx: config.dtx,
          vbr: config.vbr,
          vbrConstraint: config.vbrConstraint,
        );
        return VoiceFrameEncoder(e.encode, e.dispose);
    }
  }

  final Uint8List Function(Int16List frame) encode;
  final void Function() dispose;
}

class AudioPacketizer {
  AudioPacketizer({
    required this.config,
    required this.channels,
    this.kind = packetKindVoice,
    LossProtection? protection,
  }) : _encoder = VoiceFrameEncoder.forConfig(
         config,
         channels,
         protection: protection,
       );

  final TxCodecConfig config;
  final int channels;

  final int kind;

  final VoiceFrameEncoder _encoder;
  final _pcm = PcmAccumulator();
  final _frames = <Uint8List>[];
  final _sizes = <int>[];
  int _streamId = -1;
  int _packetNo = 0;

  int get frameSamples => config.isSpeex
      ? speexFrameSamples(config.speexBandMode)
      : opusFrameSamples(config.sampleRate, config.frameMs);

  bool get _withSizes =>
      config.fpp > 1 &&
      (config.codec == AudioCodecType.speexVbr ||
          (!config.isSpeex && (config.vbr || config.dtx)));

  List<Uint8List> add(
    Int16List pcm, {
    required int streamId,
    required int userId,
    required int channelId,
  }) {
    if (streamId != _streamId) {
      _streamId = streamId;
      _packetNo = 0;
      _pcm.clear();
      _frames.clear();
      _sizes.clear();
    }
    _pcm.addAll(pcm);
    final out = <Uint8List>[];
    final frameLen = frameSamples * channels;
    final fpp = config.fpp < 1 ? 1 : config.fpp;
    while (_pcm.length >= frameLen) {
      final encoded = _encoder.encode(_pcm.peek(frameLen));
      _pcm.consume(frameLen);
      if (encoded.isEmpty) {
        _frames.clear();
        _sizes.clear();
        continue;
      }
      _frames.add(Uint8List.fromList(encoded));
      _sizes.add(encoded.length);
      if (_frames.length < fpp) continue;
      out.addAll(_packet(userId, channelId));
    }
    return out;
  }

  List<Uint8List> flush({required int userId, required int channelId}) {
    final frameLen = frameSamples * channels;
    final fpp = config.fpp < 1 ? 1 : config.fpp;
    if (_pcm.length == 0 && _frames.isEmpty) return const [];
    final pad = (fpp - _frames.length) * frameLen - _pcm.length;
    return add(
      Int16List(pad),
      streamId: _streamId,
      userId: userId,
      channelId: channelId,
    );
  }

  List<Uint8List> _packet(int userId, int channelId) {
    final packets = fragmentVoicePacket(
      kind: kind,
      srcUserId: userId,
      channelId: channelId,
      streamId: _streamId,
      packetNumber: _packetNo++ & 0xFFFF,
      time: packetTimestamp(),
      encodedAudio: _concat(_frames),
      frameSizes: _withSizes ? List<int>.of(_sizes) : null,
    );
    _frames.clear();
    _sizes.clear();
    return packets;
  }

  void dispose() => _encoder.dispose();
}

Uint8List _concat(List<Uint8List> frames) {
  if (frames.length == 1) return frames.first;
  final out = Uint8List(frames.fold(0, (n, f) => n + f.length));
  var off = 0;
  for (final f in frames) {
    out.setAll(off, f);
    off += f.length;
  }
  return out;
}
