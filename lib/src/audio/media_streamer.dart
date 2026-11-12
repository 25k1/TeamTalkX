import 'dart:math' as math;
import 'dart:typed_data';

import '../protocol/packet.dart';
import 'audio_packetizer.dart';
import 'codec_config.dart';
import 'dsp/pcm_resampler.dart';
import 'media_source.dart';

class MediaStreamStatus {
  const MediaStreamStatus({
    required this.position,
    required this.duration,
    required this.paused,
    required this.ended,
    this.error,
  });

  final Duration position;
  final Duration? duration;
  final bool paused;

  final bool ended;

  final String? error;
}

class MediaTick {
  const MediaTick(this.packets, this.monitor);

  final List<Uint8List> packets;

  final Int16List? monitor;
}

class MediaStreamer {
  MediaStreamer({
    required this.source,
    required this.codec,
    required this.streamId,
    required this.userId,
    required this.channelId,
    required int nowUs,
    this.loop = false,
    this.gain = 1,
    this.monitor = false,
    AudioPacketizer? packetizer,
  }) : _packetizer =
           packetizer ??
           AudioPacketizer(
             config: codec,
             channels: codec.channels,
             kind: packetKindMediaFileAudio,
           ),
       _anchorUs = nowUs;

  static const leadMs = 100;

  final MediaSource source;
  final AudioPacketizer _packetizer;
  final TxCodecConfig codec;
  final int streamId;
  final int userId;
  final int channelId;
  bool loop;
  double gain;
  bool monitor;

  bool _paused = false;
  bool _ended = false;
  String? _error;
  Duration _position = Duration.zero;

  int _anchorUs;
  int _sentUs = 0;

  List<StreamingResampler> _toCodec = const [];
  List<StreamingResampler> _toMonitor = const [];
  int _resamplerRate = 0;

  MediaStreamStatus get status => MediaStreamStatus(
    position: _position,
    duration: source.duration,
    paused: _paused,
    ended: _ended,
    error: _error,
  );

  bool get ended => _ended;

  MediaTick tick(int nowUs) {
    if (_paused || _ended) return const MediaTick([], null);
    final packets = <Uint8List>[];
    final monitorParts = <Int16List>[];
    final dueUs = nowUs - _anchorUs + leadMs * 1000;
    var restarts = 0;
    while (_sentUs < dueUs) {
      final rate = math.max(1, source.sampleRate);
      final channels = math.max(1, source.channels);
      final frames = ((dueUs - _sentUs) * rate / 1000000).ceil().clamp(1, rate);
      final Int16List? chunk;
      try {
        chunk = source.read(frames * channels);
      } on Exception catch (e) {
        _error = '$e';
        _finish(packets);
        break;
      }
      if (chunk == null || chunk.isEmpty) {
        if (loop && restarts++ == 0) {
          source.seek(Duration.zero);
          _position = Duration.zero;
          continue;
        }
        _finish(packets);
        break;
      }
      restarts = 0;
      final readRate = math.max(1, source.sampleRate);
      final readChannels = math.max(1, source.channels);
      final readFrames = chunk.length ~/ readChannels;
      final us = readFrames * 1000000 ~/ readRate;
      _sentUs += us;
      _position += Duration(microseconds: us);
      _prepareResamplers(readRate);
      packets.addAll(
        _packetizer.add(
          _convert(chunk, readChannels, codec.channels, _toCodec),
          streamId: streamId,
          userId: userId,
          channelId: channelId,
        ),
      );
      if (monitor) {
        monitorParts.add(_convert(chunk, readChannels, 2, _toMonitor));
      }
    }
    return MediaTick(
      packets,
      monitorParts.isEmpty ? null : _join(monitorParts),
    );
  }

  void _finish(List<Uint8List> packets) {
    _ended = true;
    packets.addAll(_packetizer.flush(userId: userId, channelId: channelId));
  }

  void pause() => _paused = true;

  void resume(int nowUs) {
    if (!_paused) return;
    _paused = false;
    _reanchor(nowUs);
  }

  void seek(Duration position, int nowUs) {
    final duration = source.duration;
    var target = position < Duration.zero ? Duration.zero : position;
    if (duration != null && target > duration) target = duration;
    source.seek(target);
    _position = target;
    _reanchor(nowUs);
    for (final r in [..._toCodec, ..._toMonitor]) {
      r.reset();
    }
  }

  void _reanchor(int nowUs) {
    _anchorUs = nowUs;
    _sentUs = 0;
  }

  void _prepareResamplers(int rate) {
    if (rate == _resamplerRate) return;
    _resamplerRate = rate;
    _toCodec = [
      for (var c = 0; c < codec.channels; c++)
        StreamingResampler(rate, codec.sampleRate),
    ];
    _toMonitor = [for (var c = 0; c < 2; c++) StreamingResampler(rate, 48000)];
  }

  Int16List _convert(
    Int16List pcm,
    int inChannels,
    int outChannels,
    List<StreamingResampler> resamplers,
  ) {
    final frames = pcm.length ~/ inChannels;
    final parts = <Int16List>[];
    for (var out = 0; out < outChannels; out++) {
      final mono = Int16List(frames);
      for (var f = 0; f < frames; f++) {
        final int sample;
        if (outChannels == 1 && inChannels > 1) {
          var sum = 0;
          for (var c = 0; c < inChannels; c++) {
            sum += pcm[f * inChannels + c];
          }
          sample = sum ~/ inChannels;
        } else {
          sample = pcm[f * inChannels + math.min(out, inChannels - 1)];
        }
        mono[f] = gain == 1
            ? sample
            : (sample * gain).round().clamp(-32768, 32767);
      }
      parts.add(resamplers[out].process(mono));
    }
    if (outChannels == 1) return parts.single;
    final length = math.min(parts[0].length, parts[1].length);
    final out = Int16List(length * 2);
    for (var i = 0; i < length; i++) {
      out[i * 2] = parts[0][i];
      out[i * 2 + 1] = parts[1][i];
    }
    return out;
  }

  void dispose() {
    source.close();
    _packetizer.dispose();
  }
}

Int16List _join(List<Int16List> parts) {
  if (parts.length == 1) return parts.single;
  final out = Int16List(parts.fold(0, (n, p) => n + p.length));
  var off = 0;
  for (final p in parts) {
    out.setAll(off, p);
    off += p.length;
  }
  return out;
}
