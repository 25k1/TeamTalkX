import 'dart:math' as math;
import 'dart:typed_data';

import 'dsp/pcm_resampler.dart';

export '../domain/mic_test.dart';

class MicTestRecorder {
  MicTestRecorder({
    required this.live,
    required int sampleRate,
    required this.channels,
    this.outputChannel = -1,
    this.recordMs = 5000,
  }) : _resampler = StreamingResampler(sampleRate, 48000),
       _recordFrames = 48 * recordMs;

  final bool live;
  final int channels;

  final int outputChannel;
  final int recordMs;

  final StreamingResampler _resampler;
  final int _recordFrames;
  final _recorded = BytesBuilder(copy: false);
  int _recordedFrames = 0;

  bool get recordingDone => !live && _recordedFrames >= _recordFrames;

  Int16List? add(Uint8List pcm, double gain) {
    final bd = ByteData.sublistView(pcm);
    final frames = pcm.lengthInBytes ~/ 2 ~/ channels;
    final mono = Int16List(frames);
    for (var f = 0; f < frames; f++) {
      final int s;
      if (channels == 2 && outputChannel != 0 && outputChannel != 1) {
        s =
            (bd.getInt16(f * 4, Endian.little) +
                bd.getInt16(f * 4 + 2, Endian.little)) ~/
            2;
      } else {
        final ch = channels == 2 ? outputChannel : 0;
        s = bd.getInt16((f * channels + ch) * 2, Endian.little);
      }
      mono[f] = gain == 1 ? s : (s * gain).round().clamp(-32768, 32767);
    }
    final up = _resampler.process(mono);
    final stereo = Int16List(up.length * 2);
    for (var i = 0; i < up.length; i++) {
      stereo[i * 2] = up[i];
      stereo[i * 2 + 1] = up[i];
    }
    if (live) return stereo;
    if (_recordedFrames < _recordFrames) {
      final keep = math.min(up.length, _recordFrames - _recordedFrames);
      _recorded.add(
        Int16List.sublistView(
          stereo,
          0,
          keep * 2,
        ).buffer.asUint8List(stereo.offsetInBytes, keep * 4),
      );
      _recordedFrames += keep;
    }
    return null;
  }

  Int16List takeRecording() {
    final bytes = _recorded.takeBytes();
    return bytes.buffer.asInt16List(bytes.offsetInBytes, bytes.length ~/ 2);
  }
}
