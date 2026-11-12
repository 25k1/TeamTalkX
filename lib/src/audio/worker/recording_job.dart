part of '../audio_worker.dart';

class _RecordingJob {
  _RecordingJob(this._w);

  final _Worker _w;

  Recorder? recorder;
  Timer? _timer;

  void _finish(Recorder r, {required bool reply}) {
    if (r.finish(_w.clock.elapsedMicroseconds)) {
      if (reply) _w.rootPort.send(const _RecordingReplyMsg(null));
      return;
    }
    Timer.run(() => _finish(r, reply: reply));
  }

  void stop({required bool reply}) {
    _timer?.cancel();
    _timer = null;
    final r = recorder;
    recorder = null;
    if (r == null) {
      if (reply) _w.rootPort.send(const _RecordingReplyMsg(null));
      return;
    }
    _finish(r, reply: reply);
  }

  void finishNow() {
    _timer?.cancel();
    if (recorder case final r?) {
      recorder = null;
      while (!r.finish(_w.clock.elapsedMicroseconds)) {}
    }
  }

  void start(_StartRecordingMsg msg) {
    final previous = recorder;
    recorder = null;
    _timer?.cancel();
    if (previous != null) {
      while (!previous.finish(_w.clock.elapsedMicroseconds)) {}
    }
    final sep = Platform.pathSeparator;
    final r = Recorder(
      mode: msg.mode,
      startUs: _w.clock.elapsedMicroseconds,
      open: (userId) {
        final path =
            '${msg.directory}$sep${recordingFileName(userId, msg.format)}';
        return switch (msg.format) {
          RecordingFormat.wav => WavWriter(path),
          RecordingFormat.oggOpus => OggOpusWriter.withOpus(path),
        };
      },
      onWriterFailed: (userId, error) => _w.log(
        LogLevel.error,
        'Recording file for user $userId failed',
        error,
      ),
    );
    if (msg.mode == RecordingMode.mixed && r.users.isEmpty) {
      _w.rootPort.send(
        const _RecordingReplyMsg('The recording file could not be opened'),
      );
      return;
    }
    recorder = r;
    _timer = Timer.periodic(
      const Duration(milliseconds: 100),
      (_) => r.tick(_w.clock.elapsedMicroseconds),
    );
    _w.rootPort.send(const _RecordingReplyMsg(null));
  }
}
