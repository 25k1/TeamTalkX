import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/voice/audio_output.dart';
import '../../app/voice/mic_test.dart';
import '../../domain/mic_test.dart';
import '../../l10n/l10n.dart';
import '../common/ui.dart';

class MicTestScreen extends ConsumerWidget {
  const MicTestScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final phase = ref.watch(micTestProvider);
    final notifier = ref.read(micTestProvider.notifier);
    final headphones = headphonesConnected(
      ref.watch(audioOutputsProvider).value ?? const [],
    );
    final running = phase != null && phase != MicTestPhase.finished;

    Future<void> start({required bool live}) async {
      final messenger = ScaffoldMessenger.of(context);
      final refusal = await notifier.start(live: live);
      if (refusal == null) return;
      messenger.showMessage(switch (refusal) {
        MicTestRefusal.transmitting => l10n.micTestStopTransmitting,
        MicTestRefusal.noPermission => l10n.micTestNoPermission,
      });
    }

    return Scaffold(
      appBar: AppBar(title: Text(l10n.micTestTitle)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(l10n.micTestIntro),
          const SizedBox(height: 16),
          if (running)
            FilledButton.icon(
              onPressed: notifier.stop,
              icon: const Icon(Icons.stop),
              label: Text(l10n.micTestStop),
            )
          else ...[
            if (headphones)
              FilledButton.icon(
                onPressed: () => start(live: true),
                icon: const Icon(Icons.headphones),
                label: Text(l10n.micTestListenLive),
              )
            else
              Text(l10n.micTestLiveNeedsHeadphones),
            const SizedBox(height: 8),
            FilledButton.tonalIcon(
              onPressed: () => start(live: false),
              icon: const Icon(Icons.fiber_manual_record),
              label: Text(l10n.micTestRecord),
            ),
          ],
        ],
      ),
    );
  }
}
