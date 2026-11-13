import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/settings/settings_providers.dart';
import '../../l10n/l10n.dart';
import '../a11y/dialogs.dart';
import 'settings_widgets.dart';

class CallsSettingsScreen extends ConsumerWidget {
  const CallsSettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final interruptionSettings = ref.watch(interruptionSettingsProvider);
    final ducksOthers =
        interruptionSettings.duckOthersForVoice ||
        interruptionSettings.duckOthersForEvents;
    return Scaffold(
      appBar: AppBar(title: Text(l10n.settingsCalls)),
      body: ListView(
        children: [
          SectionHeader(l10n.callsSection),
          ListTile(title: Text(l10n.callsIntro)),
          SwitchListTile(
            secondary: const Icon(Icons.do_not_disturb_on),
            title: Text(l10n.callsAway),
            subtitle: Text(l10n.callsAwaySub),
            value: interruptionSettings.awayDuringCalls,
            onChanged: ref
                .read(interruptionSettingsProvider.notifier)
                .setAwayDuringCalls,
          ),
          if (interruptionSettings.awayDuringCalls)
            ListTile(
              leading: const Icon(Icons.short_text),
              title: Text(l10n.callsStatusMessage),
              subtitle: Text(
                interruptionSettings.callStatusMessage.isEmpty
                    ? l10n.callsStatusMessageKeep
                    : interruptionSettings.callStatusMessage,
              ),
              onTap: () async {
                final text = await promptText(
                  context,
                  title: l10n.callsStatusMessage,
                  label: l10n.callsStatusMessageLabel,
                  initialValue: interruptionSettings.callStatusMessage,
                  capitalization: TextCapitalization.sentences,
                  submitLabel: l10n.commonSave,
                );
                if (text != null) {
                  ref
                      .read(interruptionSettingsProvider.notifier)
                      .setCallStatusMessage(text);
                }
              },
            ),
          SectionHeader(l10n.otherAppsSection),
          ListTile(
            title: Text(l10n.focusPolicyTitle),
            subtitle: Text(l10n.focusPolicyNote),
          ),
          RadioGroup<FocusLossPolicy>(
            groupValue: interruptionSettings.focusLossPolicy,
            onChanged: (value) {
              if (value != null) {
                ref
                    .read(interruptionSettingsProvider.notifier)
                    .setFocusLossPolicy(value);
              }
            },
            child: Column(
              children: [
                for (final (policy, label) in [
                  (FocusLossPolicy.ignore, l10n.focusPolicyIgnore),
                  (FocusLossPolicy.duck, l10n.focusPolicyDuck),
                  (FocusLossPolicy.mute, l10n.focusPolicyMute),
                ])
                  RadioListTile<FocusLossPolicy>(
                    title: Text(label),
                    value: policy,
                  ),
              ],
            ),
          ),
          SwitchListTile(
            secondary: const Icon(Icons.record_voice_over),
            title: Text(l10n.duckOthersVoice),
            subtitle: Text(l10n.duckOthersSub),
            value: interruptionSettings.duckOthersForVoice,
            onChanged: ref
                .read(interruptionSettingsProvider.notifier)
                .setDuckOthersForVoice,
          ),
          SwitchListTile(
            secondary: const Icon(Icons.notifications_active),
            title: Text(l10n.duckOthersEvents),
            subtitle: Text(l10n.duckOthersSub),
            value: interruptionSettings.duckOthersForEvents,
            onChanged: ref
                .read(interruptionSettingsProvider.notifier)
                .setDuckOthersForEvents,
          ),
          if (ducksOthers)
            SwitchListTile(
              secondary: const Icon(Icons.accessibility_new),
              title: Text(l10n.keepVolumeTalkBack),
              subtitle: Text(l10n.keepVolumeTalkBackSub),
              value: interruptionSettings.keepVolumeUnderTalkBack,
              onChanged: ref
                  .read(interruptionSettingsProvider.notifier)
                  .setKeepVolumeUnderTalkBack,
            ),
        ],
      ),
    );
  }
}
