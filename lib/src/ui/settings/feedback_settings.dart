import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/announcer.dart';
import '../../app/settings/settings_providers.dart';
import '../../app/settings/sound_packs.dart';
import '../../app/settings/sound_player.dart';
import '../../app/settings/tts_providers.dart';
import '../../domain/tts_info.dart';
import '../../l10n/l10n.dart';
import '../common/ui.dart';
import 'settings_widgets.dart';

class SpeechSettingsScreen extends ConsumerWidget {
  const SpeechSettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider);
    final notifier = ref.read(settingsProvider.notifier);
    final l10n = context.l10n;
    return Scaffold(
      appBar: AppBar(title: Text(l10n.eventsSpeech)),
      body: ListView(
        children: [
          SectionHeader(l10n.speechSpeakEventsThrough),
          RadioGroup<SpeechOutput>(
            groupValue: settings.speechOutput,
            onChanged: (value) {
              if (value != null) notifier.setSpeechOutput(value);
            },
            child: Column(
              children: [
                RadioListTile<SpeechOutput>(
                  title: Text(l10n.speechScreenReader),
                  subtitle: Text(l10n.speechScreenReaderSub),
                  value: SpeechOutput.screenReader,
                ),
                RadioListTile<SpeechOutput>(
                  title: Text(l10n.speechTts),
                  value: SpeechOutput.tts,
                ),
                RadioListTile<SpeechOutput>(
                  title: Text(l10n.speechNothing),
                  value: SpeechOutput.none,
                ),
              ],
            ),
          ),
          if (settings.speechOutput == SpeechOutput.tts) ...[
            const Divider(),
            SectionHeader(l10n.speechTts),
            if (defaultTargetPlatform == TargetPlatform.android)
              SwitchListTile(
                title: Text(l10n.ttsAccessibilityStream),
                subtitle: Text(l10n.ttsAccessibilityStreamSub),
                value: settings.ttsUseAccessibilityStream,
                onChanged: notifier.setTtsUseAccessibilityStream,
              ),
            _TtsEnginePicker(settings: settings),
            _TtsLanguagePicker(settings: settings),
            _TtsVoicePicker(settings: settings),
            LevelSlider(
              label: l10n.ttsVolume,
              value: settings.ttsVolumePercent,
              max: 100,
              percent: true,
              onChanged: notifier.setTtsVolumePercent,
            ),
            LevelSlider(
              label: l10n.ttsRate,
              value: settings.ttsRatePercent,
              min: 10,
              max: 300,
              percent: true,
              onChanged: notifier.setTtsRatePercent,
            ),
            LevelSlider(
              label: l10n.ttsPitch,
              value: settings.ttsPitchPercent,
              min: 50,
              max: 200,
              percent: true,
              onChanged: notifier.setTtsPitchPercent,
            ),
            ListTile(
              leading: const Icon(Icons.play_arrow),
              title: Text(l10n.ttsTest),
              onTap: () =>
                  ref.read(announcerProvider).announce(l10n.ttsTestSentence),
            ),
          ],
        ],
      ),
    );
  }
}

class SoundSettingsScreen extends ConsumerWidget {
  const SoundSettingsScreen({super.key});

  Future<void> _pickFolder(BuildContext context, WidgetRef ref) async {
    final messenger = ScaffoldMessenger.of(context);
    final l10n = context.l10n;
    final setting = ref.read(soundPackFolderSettingProvider.notifier);
    if (!await setting.pick()) return;
    final name = ref.read(soundPackFolderSettingProvider)?.name ?? '';
    messenger.showMessage(l10n.soundPackFolderPicked(name));
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider);
    final notifier = ref.read(settingsProvider.notifier);
    final packsAsync = ref.watch(soundPacksProvider);
    final selected = ref.watch(selectedSoundPackProvider);
    final folder = ref.watch(soundPackFolderSettingProvider);
    final l10n = context.l10n;
    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.settingsSound),
        actions: [
          if (folder != null)
            IconButton(
              icon: const Icon(Icons.refresh),
              tooltip: l10n.soundRescan,
              onPressed: () => ref.invalidate(soundPacksProvider),
            ),
        ],
      ),
      body: ListView(
        children: [
          SwitchListTile(
            title: Text(l10n.soundPlayEvents),
            subtitle: Text(l10n.soundPlayEventsSub),
            value: settings.soundsEnabled,
            onChanged: notifier.setSoundsEnabled,
          ),
          LevelSlider(
            label: l10n.soundEventVolume,
            value: settings.eventVolumePercent,
            max: 300,
            step: 5,
            percent: true,
            onChanged: notifier.setEventVolumePercent,
            onChangeEnd: (_) => unawaited(
              ref.read(soundPlayerProvider).playAsset('channel_message.ogg'),
            ),
          ),
          const Divider(),
          SectionHeader(l10n.soundPack),
          packsAsync.when(
            loading: () => ListTile(title: Text(l10n.soundLoadingPacks)),
            error: (_, _) => ListTile(title: Text(l10n.soundPacksFailed)),
            data: (packs) => RadioGroup<String>(
              groupValue: packs.packs.any((p) => p.id == selected)
                  ? selected
                  : SoundPack.default_.id,
              onChanged: (value) {
                if (value != null) {
                  ref.read(selectedSoundPackProvider.notifier).set(value);
                }
              },
              child: Column(
                children: [
                  for (final pack in packs.packs)
                    RadioListTile<String>(
                      title: Text(
                        pack.id == SoundPack.default_.id
                            ? l10n.soundPackDefault
                            : pack.name,
                      ),
                      subtitle: pack.kind == SoundPackKind.folder
                          ? Text(l10n.soundCustomFolder)
                          : null,
                      value: pack.id,
                    ),
                ],
              ),
            ),
          ),
          ListTile(
            leading: const Icon(Icons.folder_open),
            title: Text(l10n.soundPackFolder),
            subtitle: Text(
              folder == null
                  ? l10n.soundPackFolderNone
                  : packsAsync.value?.folderUnreadable ?? false
                  ? l10n.soundPackFolderUnreadable
                  : l10n.soundPackFolderChosen(folder.name),
            ),
            onTap: () => _pickFolder(context, ref),
          ),
          if (folder != null)
            ListTile(
              leading: const Icon(Icons.folder_off),
              title: Text(l10n.soundPackFolderForget),
              onTap: () =>
                  ref.read(soundPackFolderSettingProvider.notifier).clear(),
            ),
        ],
      ),
    );
  }
}

class _SelectionScreen extends StatelessWidget {
  const _SelectionScreen({
    required this.title,
    required this.options,
    required this.current,
  });

  final String title;

  final List<(String, String)> options;
  final String current;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: RadioGroup<String>(
        groupValue: options.any((o) => o.$1 == current) ? current : '',
        onChanged: (value) {
          if (value != null) Navigator.of(context).pop(value);
        },
        child: ListView.builder(
          itemCount: options.length,
          itemBuilder: (context, index) => RadioListTile<String>(
            title: Text(options[index].$2),
            value: options[index].$1,
          ),
        ),
      ),
    );
  }
}

class _PickerTile extends StatelessWidget {
  const _PickerTile({
    required this.title,
    required this.currentLabel,
    required this.options,
    required this.currentValue,
    required this.onSelected,
  });

  final String title;
  final String currentLabel;
  final List<(String, String)> options;
  final String currentValue;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      title: Text(title),
      subtitle: Text(currentLabel),
      onTap: () async {
        final selected = await pushScreenForResult<String>(
          context,
          _SelectionScreen(
            title: title,
            options: options,
            current: currentValue,
          ),
        );
        if (selected != null) onSelected(selected);
      },
    );
  }
}

class _TtsEnginePicker extends ConsumerWidget {
  const _TtsEnginePicker({required this.settings});

  final Settings settings;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final engines = ref.watch(ttsEnginesProvider).value ?? const [];
    if (engines.isEmpty) return const SizedBox.shrink();
    final current = engines
        .where((e) => e.name == settings.ttsEngine)
        .firstOrNull;
    return _PickerTile(
      title: context.l10n.ttsEngine,
      currentLabel: current?.label ?? context.l10n.ttsSystemDefault,
      currentValue: settings.ttsEngine,
      options: [
        ('', context.l10n.ttsSystemDefault),
        for (final engine in engines) (engine.name, engine.label),
      ],
      onSelected: (value) =>
          ref.read(settingsProvider.notifier).setTtsEngine(value),
    );
  }
}

class _TtsLanguagePicker extends ConsumerWidget {
  const _TtsLanguagePicker({required this.settings});

  final Settings settings;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final languages = ref.watch(ttsLanguagesProvider).value ?? const [];
    if (languages.isEmpty) return const SizedBox.shrink();
    final known = languages.contains(settings.ttsLanguage);
    return _PickerTile(
      title: context.l10n.languageSetting,
      currentLabel: known
          ? settings.ttsLanguage
          : context.l10n.ttsEngineDefault,
      currentValue: settings.ttsLanguage,
      options: [
        ('', context.l10n.ttsEngineDefault),
        for (final language in languages) (language, language),
      ],
      onSelected: (value) =>
          ref.read(settingsProvider.notifier).setTtsLanguage(value),
    );
  }
}

class _TtsVoicePicker extends ConsumerWidget {
  const _TtsVoicePicker({required this.settings});

  final Settings settings;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    var voices = ref.watch(ttsVoicesProvider).value ?? const <TtsVoiceInfo>[];
    if (settings.ttsLanguage.isNotEmpty) {
      voices = voices
          .where(
            (v) =>
                v.locale == settings.ttsLanguage ||
                v.locale.startsWith('${settings.ttsLanguage}-') ||
                settings.ttsLanguage.startsWith('${v.locale}-'),
          )
          .toList();
    }
    if (voices.isEmpty) return const SizedBox.shrink();
    final known = voices.any((v) => v.name == settings.ttsVoice);
    return _PickerTile(
      title: context.l10n.ttsVoice,
      currentLabel: known ? settings.ttsVoice : context.l10n.ttsDefaultVoice,
      currentValue: settings.ttsVoice,
      options: [
        ('', context.l10n.ttsDefaultVoice),
        for (final voice in voices) (voice.name, voice.name),
      ],
      onSelected: (value) =>
          ref.read(settingsProvider.notifier).setTtsVoice(value),
    );
  }
}
