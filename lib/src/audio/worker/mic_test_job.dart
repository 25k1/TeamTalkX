part of '../audio_worker.dart';

class _MicTestJob {
  _MicTestJob(this._w);

  final _Worker _w;

  MicTestRecorder? test;
  SoundEffectsMixer? player;
  Timer? _timer;
  static const _key = 0x7F;

  void start(_MicTestMsg msg) {
    stop();
    final settings = _w.capture.pipeline.settings;
    if (settings == null) {
      _w.log(LogLevel.warning, 'Microphone test without capture settings');
      _w.rootPort.send(MicTestPhase.finished);
      return;
    }
    test = MicTestRecorder(
      live: msg.live,
      sampleRate: settings.sampleRate,
      channels: settings.channels,
      outputChannel: settings.outputChannel,
      recordMs: msg.recordMs,
    );
    _w.rootPort.send(
      msg.live ? MicTestPhase.listening : MicTestPhase.recording,
    );
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
    test = null;
    player?.stopAll();
    player = null;
    _w.output.native?.removeSpeaker(_key);
  }

  void frames(List<CaptureFrame> frames) {
    final test = this.test;
    final e = _w.output.native;
    if (test == null) return;
    for (final frame in frames) {
      final pcm = test.add(frame.pcm, frame.gain);
      if (pcm != null && e != null) {
        if (_w.output.playback) _w.output.wake(e);
        e.writeSpeaker(_key, pcm);
      }
    }
    if (!test.recordingDone) return;
    this.test = null;
    _w.rootPort.send(MicTestPhase.playing);
    if (e == null || !_w.output.playback) {
      _w.rootPort.send(MicTestPhase.finished);
      return;
    }
    _w.output.wake(e);
    final player = this.player = SoundEffectsMixer(NativeSpeakerSink(e))
      ..play(test.takeRecording());
    _timer = Timer.periodic(const Duration(milliseconds: 10), (_) {
      player.tick();
      if (player.idle) {
        _timer?.cancel();
        _timer = null;
        this.player = null;
        _w.rootPort.send(MicTestPhase.finished);
      }
    });
  }
}
