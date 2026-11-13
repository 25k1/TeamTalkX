import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/connection/connection_providers.dart';
import '../../app/settings/settings_providers.dart';
import '../../app/voice/voice_providers.dart';
import '../../l10n/l10n.dart';
import '../a11y/accessible_menu.dart';
import '../settings/settings_widgets.dart';

class VoiceActivationScreen extends ConsumerWidget {
  const VoiceActivationScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final microphoneSettings = ref.watch(microphoneSettingsProvider);
    final l10n = context.l10n;
    return Scaffold(
      appBar: AppBar(title: Text(l10n.settingsVoiceActivation)),
      body: ListView(
        children: [
          ListTile(
            leading: const Icon(Icons.record_voice_over),
            title: Text(l10n.audioVoiceDetection),
            subtitle: Text(microphoneSettings.vadEngine.label),
            onTap: () async {
              final value = await showSingleChoiceMenu<VadEngine>(
                context,
                title: l10n.audioVoiceDetection,
                options: {for (final e in VadEngine.values) e: e.label},
                selected: microphoneSettings.vadEngine,
              );
              if (value == null) return;
              ref.read(microphoneSettingsProvider.notifier).setVadEngine(value);
              ref.read(voiceProvider.notifier).restartCustomTransmission();
            },
          ),
          LevelSlider(
            label: l10n.audioVoxLevel,
            value: microphoneSettings.voiceActivationLevel,
            max: 20,
            onChanged: (value) {
              ref
                  .read(microphoneSettingsProvider.notifier)
                  .setVoiceActivationLevel(value);
              ref.read(teamTalkClientProvider).setVoiceActivationLevel(value);
            },
          ),
        ],
      ),
    );
  }
}
