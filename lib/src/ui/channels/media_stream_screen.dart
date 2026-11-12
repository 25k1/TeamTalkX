import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/voice/media_stream_providers.dart';
import '../../domain/media_stream.dart';
import '../../l10n/l10n.dart';
import '../settings/settings_widgets.dart';

class MediaStreamScreen extends ConsumerWidget {
  const MediaStreamScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final stream = ref.watch(mediaStreamProvider);
    ref.listen<MediaStreamState?>(mediaStreamProvider, (previous, next) {
      if (next == null && Navigator.of(context).canPop()) {
        Navigator.of(context).pop();
      }
    });
    if (stream == null) {
      return Scaffold(appBar: AppBar(title: Text(l10n.mediaStreamTitle)));
    }
    final notifier = ref.read(mediaStreamProvider.notifier);
    return Scaffold(
      appBar: AppBar(title: Text(l10n.mediaStreamTitle)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(stream.fileName, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          Text(notifier.positionText(stream)),
          const SizedBox(height: 16),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              OutlinedButton.icon(
                onPressed: () => notifier.seekBy(-MediaStreamNotifier.seekStep),
                icon: const Icon(Icons.replay_10),
                label: Text(l10n.mediaStreamBack),
              ),
              FilledButton.icon(
                onPressed: notifier.togglePause,
                icon: Icon(stream.paused ? Icons.play_arrow : Icons.pause),
                label: Text(
                  stream.paused
                      ? l10n.mediaStreamResume
                      : l10n.mediaStreamPause,
                ),
              ),
              OutlinedButton.icon(
                onPressed: () => notifier.seekBy(MediaStreamNotifier.seekStep),
                icon: const Icon(Icons.forward_10),
                label: Text(l10n.mediaStreamForward),
              ),
            ],
          ),
          const SizedBox(height: 8),
          SwitchListTile(
            title: Text(l10n.mediaStreamLoop),
            value: stream.loop,
            onChanged: (loop) => notifier.setLoop(loop: loop),
          ),
          LevelSlider(
            label: l10n.mediaStreamVolume,
            value: stream.volumePercent,
            max: 200,
            step: 5,
            percent: true,
            onChanged: notifier.setVolume,
          ),
          SwitchListTile(
            title: Text(l10n.mediaStreamMonitor),
            subtitle: Text(l10n.mediaStreamMonitorSub),
            value: stream.monitor,
            onChanged: (monitor) => notifier.setMonitor(monitor: monitor),
          ),
          const SizedBox(height: 16),
          FilledButton.tonalIcon(
            onPressed: notifier.stop,
            icon: const Icon(Icons.stop),
            label: Text(l10n.mediaStreamStop),
          ),
        ],
      ),
    );
  }
}
