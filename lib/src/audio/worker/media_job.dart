part of '../audio_worker.dart';

class _MediaJob {
  _MediaJob(this._w);

  final _Worker _w;

  MediaStreamer? streamer;
  Timer? _timer;
  var _monitorGain = 1.0;
  var _statusUs = 0;
  static const _monitorKey = packetKindMediaFileAudio;

  void _report(MediaStreamer m) {
    _statusUs = _w.clock.elapsedMicroseconds;
    _w.rootPort.send(m.status);
  }

  void stop({bool report = true}) {
    _timer?.cancel();
    _timer = null;
    final m = streamer;
    streamer = null;
    if (m == null) return;
    if (report) {
      final s = m.status;
      _w.rootPort.send(
        MediaStreamStatus(
          position: s.position,
          duration: s.duration,
          paused: false,
          ended: true,
          error: s.error,
        ),
      );
    }
    m.dispose();
    _w.output.native?.removeSpeaker(_monitorKey);
  }

  void _tick() {
    final m = streamer;
    if (m == null) return;
    final now = _w.clock.elapsedMicroseconds;
    final tick = m.tick(now);
    _w.network.send(tick.packets, m.userId, packetKindMediaFileAudio);
    final pcm = tick.monitor;
    final e = _w.output.native;
    if (pcm != null && _w.output.playback && e != null) {
      _w.output.wake(e);
      e.writeSpeaker(_monitorKey, pcm, gain: _monitorGain);
    }
    if (m.ended) {
      if (m.status.error case final error?) {
        _w.log(LogLevel.warning, 'Media streaming stopped', error);
      }
      stop();
    } else if (now - _statusUs > 500000) {
      _report(m);
    }
  }

  void start(_StartMediaMsg msg) {
    stop(report: false);
    MediaSource? source;
    try {
      source = openMediaSource(msg.path);
      streamer = MediaStreamer(
        source: source,
        codec: msg.codec,
        streamId: msg.streamId,
        userId: msg.userId,
        channelId: msg.channelId,
        nowUs: _w.clock.elapsedMicroseconds,
        loop: msg.loop,
        gain: msg.gain,
        monitor: msg.monitor,
      );
    } on Exception catch (e) {
      source?.close();
      _w.rootPort.send(_MediaStartedMsg('$e'));
      return;
    } on Error catch (e) {
      source?.close();
      _w.rootPort.send(_MediaStartedMsg('$e'));
      return;
    }
    _monitorGain = msg.monitorGain;
    _w.rootPort.send(const _MediaStartedMsg(null));
    _timer = Timer.periodic(const Duration(milliseconds: 10), (_) => _tick());
    _tick();
  }

  void control(_MediaControlMsg msg) {
    if (msg.stop) {
      stop();
      return;
    }
    final m = streamer;
    if (m == null) return;
    final now = _w.clock.elapsedMicroseconds;
    if (msg.loop case final loop?) m.loop = loop;
    if (msg.gain case final gain?) m.gain = gain;
    if (msg.monitor case final monitor?) {
      m.monitor = monitor;
      if (!monitor) _w.output.native?.removeSpeaker(_monitorKey);
    }
    if (msg.monitorGain case final gain?) _monitorGain = gain;
    if (msg.seekTo case final to?) m.seek(to, now);
    if (msg.seekBy case final by?) m.seek(m.status.position + by, now);
    switch (msg.paused) {
      case true:
        m.pause();
        _w.output.native?.removeSpeaker(_monitorKey);
      case false:
        m.resume(now);
      case null:
        break;
    }
    _report(m);
  }
}
