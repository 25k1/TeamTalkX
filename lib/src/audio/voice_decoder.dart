import 'dart:typed_data';

import '../domain/voice_quality.dart';
import 'dsp/pcm_resampler.dart';
import 'opus_decoder.dart';
import 'speex_codec.dart';

abstract interface class VoiceFrameDecoder {
  Int16List decode(Uint8List frame);

  Int16List conceal(int samplesPerChannel);

  Int16List recover(Uint8List? next, int offset, int samplesPerChannel);

  bool get lastRecovered;

  void setQuality(VoiceQuality quality);

  void dispose();
}

class OpusVoiceDecoder implements VoiceFrameDecoder {
  final _decoder = OpusFrameDecoder(sampleRate: 48000, channels: 2);

  @override
  Int16List decode(Uint8List frame) =>
      Int16List.fromList(_decoder.decode(frame));

  @override
  Int16List conceal(int samplesPerChannel) => Int16List.fromList(
    _decoder.decodeLost(samplesPerChannel: samplesPerChannel),
  );

  @override
  Int16List recover(Uint8List? next, int offset, int samplesPerChannel) =>
      Int16List.fromList(
        _decoder.recover(
          next,
          offset: offset,
          samplesPerChannel: samplesPerChannel,
        ),
      );

  @override
  bool get lastRecovered => _decoder.lastRecovery != OpusRecovery.concealed;

  @override
  void setQuality(VoiceQuality quality) => _decoder.setQuality(
    complexity: quality.enhancement.opusComplexity,
    bandwidthExtension: quality.bandwidthExtension,
  );

  @override
  void dispose() => _decoder.dispose();
}

class SpeexVoiceDecoder implements VoiceFrameDecoder {
  SpeexVoiceDecoder(int bandMode)
    : _decoder = SpeexFrameDecoder(bandMode: bandMode),
      _resampler = StreamingResampler(speexSampleRate(bandMode), 48000);

  final SpeexFrameDecoder _decoder;
  final StreamingResampler _resampler;

  @override
  Int16List decode(Uint8List frame) => _stereo(_decoder.decode(frame));

  @override
  Int16List conceal(int samplesPerChannel) {
    final frames = ((samplesPerChannel + 959) ~/ 960).clamp(1, 12);
    final parts = [for (var i = 0; i < frames; i++) _decoder.decode(null)];
    final mono = Int16List(parts.fold(0, (n, p) => n + p.length));
    var off = 0;
    for (final p in parts) {
      mono.setAll(off, p);
      off += p.length;
    }
    return _stereo(mono);
  }

  @override
  Int16List recover(Uint8List? next, int offset, int samplesPerChannel) =>
      conceal(samplesPerChannel);

  @override
  bool get lastRecovered => false;

  @override
  void setQuality(VoiceQuality quality) {}

  Int16List _stereo(Int16List mono) {
    final up = _resampler.process(mono);
    final out = Int16List(up.length * 2);
    for (var i = 0; i < up.length; i++) {
      out[i * 2] = up[i];
      out[i * 2 + 1] = up[i];
    }
    return out;
  }

  @override
  void dispose() => _decoder.dispose();
}
