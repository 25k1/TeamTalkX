import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/failure.dart';
import '../../domain/media_stream.dart';
import '../announcer.dart';
import '../connection/connection_providers.dart';
import '../failures.dart';
import '../settings/locale_providers.dart';
import '../settings/settings_providers.dart';

String formatStreamPosition(Duration d) {
  final h = d.inHours;
  final m = d.inMinutes % 60;
  final s = (d.inSeconds % 60).toString().padLeft(2, '0');
  return h > 0 ? '$h:${m.toString().padLeft(2, '0')}:$s' : '$m:$s';
}

final mediaStreamProvider =
    NotifierProvider<MediaStreamNotifier, MediaStreamState?>(
      MediaStreamNotifier.new,
    );

class MediaStreamNotifier extends Notifier<MediaStreamState?> {
  static const seekStep = Duration(seconds: 10);

  @override
  MediaStreamState? build() {
    final client = ref.watch(teamTalkClientProvider);
    final sub = client.mediaStreamChanges.listen((s) => state = s);
    ref.onDispose(sub.cancel);
    return client.mediaStream;
  }

  void _announce(String text) => ref.read(announcerProvider).announce(text);

  Future<TtFailure?> start(String path, String fileName) async {
    final settings = ref.read(settingsProvider);
    try {
      await ref
          .read(teamTalkClientProvider)
          .startStreamingMediaFile(
            path,
            fileName: fileName,
            volumePercent: settings.mediaStreamVolumePercent,
            monitor: settings.mediaStreamMonitor,
          );
    } on Object catch (e) {
      return failureFrom(e);
    }
    _announce(ref.read(appLocalizationsProvider).streamingFile(fileName));
    return null;
  }

  void togglePause() {
    final s = state;
    if (s == null) return;
    ref.read(teamTalkClientProvider).setMediaStreamPaused(paused: !s.paused);
    final l10n = ref.read(appLocalizationsProvider);
    _announce(s.paused ? l10n.mediaStreamResumed : l10n.mediaStreamPaused);
  }

  void seekBy(Duration offset) {
    final s = state;
    if (s == null) return;
    ref.read(teamTalkClientProvider).seekMediaStreamBy(offset);
    var target = s.position + offset;
    if (target < Duration.zero) target = Duration.zero;
    final duration = s.duration;
    if (duration != null && target > duration) target = duration;
    _announce(_position(target, duration));
  }

  String positionText(MediaStreamState s) => _position(s.position, s.duration);

  String _position(Duration position, Duration? duration) {
    final at = formatStreamPosition(position);
    if (duration == null) return at;
    return ref
        .read(appLocalizationsProvider)
        .mediaStreamPosition(at, formatStreamPosition(duration));
  }

  void setLoop({required bool loop}) {
    ref.read(teamTalkClientProvider).setMediaStreamLoop(loop: loop);
    final l10n = ref.read(appLocalizationsProvider);
    _announce(loop ? l10n.mediaStreamLoopOn : l10n.mediaStreamLoopOff);
  }

  void setVolume(int percent) {
    ref.read(teamTalkClientProvider).setMediaStreamVolume(percent);
    ref.read(settingsProvider.notifier).setMediaStreamVolumePercent(percent);
  }

  void setMonitor({required bool monitor}) {
    ref.read(teamTalkClientProvider).setMediaStreamMonitor(monitor: monitor);
    ref.read(settingsProvider.notifier).setMediaStreamMonitor(monitor);
  }

  void stop() {
    if (state == null) return;
    ref.read(teamTalkClientProvider).stopStreamingMediaFile();
    _announce(ref.read(appLocalizationsProvider).streamingStopped);
  }
}
