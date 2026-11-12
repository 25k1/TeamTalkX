enum VoiceDetectorKind {
  silero(releaseHold: Duration.zero),

  rnnoise(releaseHold: Duration(seconds: 1));

  const VoiceDetectorKind({required this.releaseHold});

  final Duration releaseHold;
}

class CaptureSettings {
  const CaptureSettings({
    required this.sampleRate,
    required this.channels,
    this.outputChannel = -1,
    this.noiseSuppression = false,
    this.noiseSuppressionLevel = 0.7,
    this.voiceDetection = false,
    this.detector = VoiceDetectorKind.silero,
    this.voiceLevel = 10,
    this.agc = false,
    this.agcGainPercent = 50,
    this.gain = 1.0,
  });

  final int sampleRate;
  final int channels;

  final int outputChannel;

  final bool noiseSuppression;

  final double noiseSuppressionLevel;

  final bool voiceDetection;
  final VoiceDetectorKind detector;

  final int voiceLevel;

  final bool agc;
  final int agcGainPercent;
  final double gain;

  bool get needsDenoiser =>
      noiseSuppression ||
      (voiceDetection && detector == VoiceDetectorKind.rnnoise);
}
