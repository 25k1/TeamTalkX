part of '../audio_worker.dart';

void _workerMain(SendPort rootPort) {
  final commands = ReceivePort();
  rootPort.send(commands.sendPort);
  final worker = _Worker(rootPort);
  commands.listen((msg) {
    if (msg is _ShutdownMsg) {
      worker.shutdown();
      commands.close();
    } else {
      worker.handle(msg);
    }
  });
}

class _Worker {
  _Worker(this.rootPort) {
    output = _OutputJob(this);
    network = _NetworkJob(this);
    receive = _ReceiveJob(this);
    capture = _CaptureJob(this);
    micTest = _MicTestJob(this);
    media = _MediaJob(this);
    recording = _RecordingJob(this);
  }

  final SendPort rootPort;

  final clock = Stopwatch()..start();

  late final _OutputJob output;
  late final _NetworkJob network;
  late final _ReceiveJob receive;
  late final _CaptureJob capture;
  late final _MicTestJob micTest;
  late final _MediaJob media;
  late final _RecordingJob recording;

  void log(LogLevel level, String message, [Object? error]) =>
      rootPort.send(_WorkerLogMsg(level, message, error?.toString()));

  void handle(Object? msg) {
    if (msg is _StartUdpMsg) {
      unawaited(network.start(msg));
    } else if (msg is _UserGainMsg) {
      network.gains[msg.userId] = (msg.voice, msg.media);
    } else if (msg is _MicTestMsg) {
      micTest.start(msg);
    } else if (msg is _StopMicTestMsg) {
      micTest.stop();
      rootPort.send(MicTestPhase.finished);
    } else if (msg is _StartMediaMsg) {
      media.start(msg);
    } else if (msg is _MediaControlMsg) {
      media.control(msg);
    } else if (msg is _CryptKeyMsg) {
      network.setCryptKey(msg.key);
    } else if (msg is _RxConfigMsg) {
      receive.codec = msg.codec;
    } else if (msg is _StartAudioMsg) {
      output.start(msg);
    } else if (msg is _OutputGainMsg) {
      output.native?.masterGain = msg.gain;
    } else if (msg is AudioOutput) {
      output.setOutput(msg);
    } else if (msg is VoiceQuality) {
      receive.setQuality(msg);
      capture.setProtection(msg.protection);
    } else if (msg is _MediaGainMsg) {
      receive.mediaGain = msg.gain;
    } else if (msg is _NormalizeMsg) {
      receive.setNormalize(enabled: msg.enabled);
    } else if (msg is _StatsRequestMsg) {
      rootPort.send(receive.stats());
    } else if (msg is _StartCaptureMsg) {
      capture.start(msg);
    } else if (msg is _StopCaptureMsg) {
      capture.stop();
    } else if (msg is _CaptureStateMsg) {
      capture.setState(msg);
    } else if (msg is _InjectCaptureMsg) {
      output.engine()?.pushCapture(msg.pcm);
    } else if (msg is _CaptureSettingsMsg) {
      capture.pipeline.configure(msg.settings);
    } else if (msg is _SileroModelMsg) {
      capture.pipeline.sileroModel = msg.model.materialize().asUint8List();
    } else if (msg is _ResetCaptureMsg) {
      capture.reset();
    } else if (msg is _RxPacketMsg) {
      receive.receive(msg);
    } else if (msg is _ResetTxMsg) {
      capture.tx.reset();
    } else if (msg is _ResetRxMsg) {
      receive.reset(msg.key);
    } else if (msg is _ResetRxAllMsg) {
      capture.tx.reset();
      receive.dispose();
    } else if (msg is _StartRecordingMsg) {
      recording.start(msg);
    } else if (msg is _StopRecordingMsg) {
      recording.stop(reply: true);
    }
  }

  void shutdown() {
    recording.finishNow();
    network.stopActivity();
    receive.stopPlayout();
    output.stopIdleTimer();
    media.stop(report: false);
    micTest.stop();
    network.close();
    capture.stop();
    receive.dispose();
    capture.tx.reset();
    output.dispose();
    unawaited(capture.pipeline.dispose());
  }
}

class _WorkerLogMsg {
  const _WorkerLogMsg(this.level, this.message, this.error);

  final LogLevel level;
  final String message;

  final String? error;
}

typedef _WorkerLog =
    void Function(LogLevel level, String message, [Object? error]);
