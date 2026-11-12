part of '../audio_worker.dart';

class _OutputJob {
  _OutputJob(this._w);

  final _Worker _w;

  NativeAudioEngine? native;
  var _unavailable = false;
  bool playback = false;
  AudioOutput settings = const AudioOutput();

  final _idle = OutputIdle();
  Timer? _idleTimer;

  int? _startingUs;

  NativeAudioEngine? engine() {
    if (native != null || _unavailable) return native;
    try {
      native = NativeAudioEngine(sampleRate: 48000, playbackChannels: 2);
    } on ArgumentError catch (e) {
      _unavailable = true;
      _w.log(LogLevel.warning, 'Native audio engine unavailable', e);
    } on StateError catch (e) {
      _unavailable = true;
      _w.log(LogLevel.warning, 'Native audio engine unavailable', e);
    }
    return native;
  }

  void start(_StartAudioMsg msg) {
    final e = engine();
    var result = engineNoDevice;
    if (e != null) {
      e
        ..masterGain = msg.outputGain
        ..setOutput(voiceCall: settings.voiceCall, deviceId: settings.deviceId);
      result = e.startPlayback();
    }
    playback = result == 0;
    if (playback) {
      _idle.opened(_w.clock.elapsedMicroseconds);
      _idleTimer ??= Timer.periodic(
        const Duration(seconds: 1),
        (_) => _closeIdle(),
      );
    }
    _w.rootPort.send(_AudioStatusMsg(playback: playback, error: result));
  }

  void setOutput(AudioOutput output) {
    settings = output;
    native?.setOutput(voiceCall: output.voiceCall, deviceId: output.deviceId);
  }

  void wake(NativeAudioEngine e) {
    final nowUs = _w.clock.elapsedMicroseconds;
    if (!_idle.needsOpen(nowUs)) return;
    e.startPlaybackAsync();
    _idle.opened(nowUs);
    _startingUs = nowUs;
  }

  void checkStarted() {
    final sinceUs = _startingUs;
    final e = native;
    if (sinceUs == null || e == null) return;
    final elapsedUs = _w.clock.elapsedMicroseconds - sinceUs;
    final stats = e.stats();
    if (stats.playbackRunning) {
      _startingUs = null;
      _w.log(LogLevel.debug, 'Output started in ${elapsedUs ~/ 1000} ms');
    } else if (elapsedUs > 2 * Duration.microsecondsPerSecond) {
      _startingUs = null;
      _idle.closed();
      _w.log(
        LogLevel.warning,
        'Sound output could not open again (${stats.lastError})',
      );
    }
  }

  void _closeIdle() {
    final e = native;
    if (e == null || !playback) return;
    checkStarted();
    final busy =
        _startingUs != null ||
        _w.micTest.test != null ||
        _w.micTest.player != null ||
        _w.media.streamer != null ||
        _w.receive.streams.entries.any(
          (s) => s.value.buffer.pendingMs > 0 || e.speakerQueued(s.key) > 0,
        );
    if (!_idle.shouldClose(_w.clock.elapsedMicroseconds, busy: busy)) return;
    e.stopPlayback();
    _idle.closed();
    _w.log(LogLevel.debug, 'Output closed while idle');
  }

  void stopIdleTimer() => _idleTimer?.cancel();

  void dispose() {
    native
      ?..stopPlayback()
      ..dispose();
    native = null;
  }
}
