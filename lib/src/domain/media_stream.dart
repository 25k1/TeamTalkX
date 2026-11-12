class MediaStreamState {
  const MediaStreamState({
    required this.fileName,
    this.position = Duration.zero,
    this.duration,
    this.paused = false,
    this.loop = false,
    this.volumePercent = 100,
    this.monitor = false,
  });

  final String fileName;
  final Duration position;

  final Duration? duration;
  final bool paused;
  final bool loop;

  final int volumePercent;

  final bool monitor;

  MediaStreamState copyWith({
    Duration? position,
    Duration? duration,
    bool? paused,
    bool? loop,
    int? volumePercent,
    bool? monitor,
  }) => MediaStreamState(
    fileName: fileName,
    position: position ?? this.position,
    duration: duration ?? this.duration,
    paused: paused ?? this.paused,
    loop: loop ?? this.loop,
    volumePercent: volumePercent ?? this.volumePercent,
    monitor: monitor ?? this.monitor,
  );
}
