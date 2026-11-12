part of '../audio_worker.dart';

class _CaptureErrorMsg {
  const _CaptureErrorMsg(this.error);
  final int error;
}

class _ActivityMsg {
  const _ActivityMsg(this.userId, this.kind, {required this.active});
  final int userId;
  final int kind;
  final bool active;
}

class _StartMediaMsg {
  const _StartMediaMsg({
    required this.path,
    required this.codec,
    required this.streamId,
    required this.userId,
    required this.channelId,
    required this.loop,
    required this.gain,
    required this.monitor,
    required this.monitorGain,
  });

  final String path;
  final TxCodecConfig codec;
  final int streamId;
  final int userId;
  final int channelId;
  final bool loop;
  final double gain;
  final bool monitor;
  final double monitorGain;
}

class _MediaStartedMsg {
  const _MediaStartedMsg(this.error);
  final String? error;
}

class _MediaControlMsg {
  const _MediaControlMsg({
    this.paused,
    this.seekTo,
    this.seekBy,
    this.loop,
    this.gain,
    this.monitor,
    this.monitorGain,
    this.stop = false,
  });

  final bool? paused;
  final Duration? seekTo;
  final Duration? seekBy;
  final bool? loop;
  final double? gain;
  final bool? monitor;
  final double? monitorGain;
  final bool stop;
}

class _MicTestMsg {
  const _MicTestMsg({required this.live, required this.recordMs});
  final bool live;
  final int recordMs;
}

class _StopMicTestMsg {
  const _StopMicTestMsg();
}

class _StartUdpMsg {
  const _StartUdpMsg(this.address, this.port, this.userId);

  final String address;
  final int port;
  final int userId;
}

class _UdpStatusMsg {
  const _UdpStatusMsg(this.error);
  final String? error;
}

class _UserGainMsg {
  const _UserGainMsg(this.userId, this.voice, this.media);
  final int userId;
  final double voice;
  final double media;
}

class _CryptKeyMsg {
  const _CryptKeyMsg(this.key);
  final Uint8List? key;
}

class _RxConfigMsg {
  const _RxConfigMsg(this.codec);
  final TxCodecConfig codec;
}

class _CaptureVoiceMsg {
  const _CaptureVoiceMsg(this.voice);
  final bool voice;
}

class _CaptureSettingsMsg {
  const _CaptureSettingsMsg(this.settings);
  final CaptureSettings settings;
}

class _SileroModelMsg {
  const _SileroModelMsg(this.model);
  final TransferableTypedData model;
}

class _StartAudioMsg {
  const _StartAudioMsg({required this.outputGain});
  final double outputGain;
}

class _AudioStatusMsg {
  const _AudioStatusMsg({required this.playback, required this.error});
  final bool playback;
  final int error;
}

class _StatsRequestMsg {
  const _StatsRequestMsg();
}

class _StatsReplyMsg {
  const _StatsReplyMsg(this.stats, this.playout);
  final EngineStats? stats;
  final List<PlayoutStats> playout;
}

class _OutputGainMsg {
  const _OutputGainMsg(this.gain);
  final double gain;
}

class _MediaGainMsg {
  const _MediaGainMsg(this.gain);
  final double gain;
}

class _NormalizeMsg {
  const _NormalizeMsg({required this.enabled});
  final bool enabled;
}

class _StartCaptureMsg {
  const _StartCaptureMsg({
    required this.audioSource,
    required this.sampleRate,
    required this.channels,
  });
  final int audioSource;
  final int sampleRate;
  final int channels;
}

class _StopCaptureMsg {
  const _StopCaptureMsg();
}

class _CaptureStateMsg {
  const _CaptureStateMsg({
    required this.streamId,
    required this.userId,
    required this.channelId,
    required this.transmit,
    required this.flushPreRoll,
    required this.voiceActive,
    required this.config,
  });

  final int streamId;
  final int userId;
  final int channelId;
  final bool transmit;
  final bool flushPreRoll;
  final bool voiceActive;
  final TxCodecConfig config;
}

class _InjectCaptureMsg {
  const _InjectCaptureMsg(this.pcm);
  final Int16List pcm;
}

class _ResetCaptureMsg {
  const _ResetCaptureMsg();
}

class _RxPacketMsg {
  const _RxPacketMsg(
    this.key,
    this.streamId,
    this.encoded,
    this.packetNo,
    this.gain,
    this.frameSizes,
    this.framesPerPacket,
  );
  final int key;
  final int streamId;
  final Uint8List encoded;
  final int packetNo;
  final List<int> frameSizes;

  final int framesPerPacket;

  final double gain;
}

class _ResetTxMsg {
  const _ResetTxMsg();
}

class _ResetRxMsg {
  const _ResetRxMsg(this.key);
  final int key;
}

class _ResetRxAllMsg {
  const _ResetRxAllMsg();
}

class _ShutdownMsg {
  const _ShutdownMsg();
}

class _StartRecordingMsg {
  const _StartRecordingMsg(this.directory, this.mode, this.format);
  final String directory;
  final RecordingMode mode;
  final RecordingFormat format;
}

class _StopRecordingMsg {
  const _StopRecordingMsg();
}

class _RecordingReplyMsg {
  const _RecordingReplyMsg(this.error);
  final String? error;
}
