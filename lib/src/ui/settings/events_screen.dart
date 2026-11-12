import 'dart:async';
import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart' show CustomSemanticsAction;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/settings/event_config.dart';
import '../../app/settings/haptic_player.dart';
import '../../app/settings/locale_providers.dart';
import '../../app/settings/sound_player.dart';
import '../../l10n/l10n.dart';
import '../common/insert_variable_button.dart';
import '../common/labels.dart';
import '../common/text_controllers.dart';
import '../common/ui.dart';
import 'feedback_settings.dart';
import 'settings_widgets.dart';

class EventsScreen extends ConsumerWidget {
  const EventsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final configs = ref.watch(eventConfigProvider);
    final l10n = context.l10n;
    return ListView(
      children: [
        ListTile(
          leading: const Icon(Icons.record_voice_over),
          title: Text(l10n.eventsSpeech),
          subtitle: Text(l10n.eventsSpeechSub),
          onTap: () => pushScreen(context, const SpeechSettingsScreen()),
        ),
        ListTile(
          leading: const Icon(Icons.music_note),
          title: Text(l10n.settingsSound),
          subtitle: Text(l10n.eventsSoundSub),
          onTap: () => pushScreen(context, const SoundSettingsScreen()),
        ),
        const Divider(),
        SectionHeader(l10n.settingsEvents),
        for (final event in AppEvent.values)
          Builder(
            builder: (context) {
              final config = configs[event]!;
              final active = [
                if (config.speechEnabled) l10n.eventsSpeech,
                if (config.soundEnabled) l10n.settingsSound,
                if (config.hapticEnabled) l10n.eventsHaptic,
                if (config.chatEnabled) l10n.eventsChat,
              ];
              final summary = config.enabled
                  ? (active.isEmpty ? l10n.eventsOn : active.join(', '))
                  : l10n.eventsDisabled;
              void open() => pushScreen(context, EventEditScreen(event: event));
              void toggle() => ref
                  .read(eventConfigProvider.notifier)
                  .setEnabled(event, !config.enabled);
              return MergeSemantics(
                child: GestureDetector(
                  onLongPress: open,
                  child: Semantics(
                    customSemanticsActions: {
                      CustomSemanticsAction(label: l10n.eventsOpenSettings):
                          open,
                    },
                    child: SwitchListTile(
                      title: Text(event.label(l10n)),
                      subtitle: Text(summary),
                      value: config.enabled,
                      onChanged: (_) => toggle(),
                    ),
                  ),
                ),
              );
            },
          ),
      ],
    );
  }
}

class EventEditScreen extends ConsumerStatefulWidget {
  const EventEditScreen({super.key, required this.event});

  final AppEvent event;

  @override
  ConsumerState<EventEditScreen> createState() => _EventEditScreenState();
}

class _EventEditScreenState extends ConsumerState<EventEditScreen>
    with TextControllers {
  late final TextEditingController _template;
  late final TextEditingController _chatTemplate;

  AppEvent get _event => widget.event;
  EventConfigNotifier get _notifier => ref.read(eventConfigProvider.notifier);

  @override
  void initState() {
    super.initState();
    _template = textController(_notifier.speechTemplate(_event));
    _chatTemplate = textController(_notifier.chatTemplateOf(_event));
  }

  Map<String, String> get _variables => {
    for (final v in _event.variables) '{$v}': '',
  };

  Widget _templateEditor({
    required TextEditingController controller,
    required String label,
    required void Function(String) save,
    required VoidCallback reset,
  }) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: TextField(
          controller: controller,
          maxLines: null,
          decoration: InputDecoration(labelText: label),
          onChanged: save,
        ),
      ),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Wrap(
          spacing: 8,
          children: [
            if (_event.variables.isNotEmpty)
              InsertVariableButton(
                controller: controller,
                variables: _variables,
                onChanged: save,
              ),
            TextButton.icon(
              icon: const Icon(Icons.restore),
              label: Text(context.l10n.commonResetToDefault),
              onPressed: () {
                reset();
                setControllerText(
                  controller,
                  defaultEventTemplate(
                    _event,
                    ref.read(appLocalizationsProvider),
                  ),
                );
              },
            ),
          ],
        ),
      ),
    ],
  );

  Future<void> _pickSound() async {
    final file = await openFile(
      acceptedTypeGroups: [
        XTypeGroup(
          label: context.l10n.eventsAudioFiles,
          extensions: ['ogg', 'mp3', 'wav', 'm4a', 'aac', 'flac'],
        ),
      ],
    );
    if (file != null) _notifier.setSoundPath(_event, file.path);
  }

  void _testSound(EventConfig config) {
    final player = ref.read(soundPlayerProvider);
    final volume = config.soundVolumePercent;
    if (config.hasCustomSound) {
      unawaited(player.playFile(config.soundPath, volumePercent: volume));
    } else if (_event.defaultSound != null) {
      unawaited(
        player.playAsset(_event.defaultSound!.asset, volumePercent: volume),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final config = ref.watch(eventConfigProvider)[_event]!;
    final l10n = context.l10n;
    return Scaffold(
      appBar: AppBar(title: Text(_event.label(l10n))),
      body: ListView(
        children: [
          SwitchListTile(
            title: Text(l10n.eventEnabled),
            subtitle: Text(l10n.eventEnabledSub),
            value: config.enabled,
            onChanged: (v) => _notifier.setEnabled(_event, v),
          ),
          const Divider(),
          if (_event.supportsSpeech) ...[
            SwitchListTile(
              title: Text(l10n.eventsSpeech),
              subtitle: Text(l10n.eventSpeechSub),
              value: config.speechEnabled,
              onChanged: (v) => _notifier.setSpeechEnabled(_event, v),
            ),
            if (config.speechEnabled)
              _templateEditor(
                controller: _template,
                label: l10n.eventWhatToSpeak,
                save: (v) => _notifier.setTemplate(_event, v),
                reset: () => _notifier.resetTemplate(_event),
              ),
            if (config.speechEnabled)
              SwitchListTile(
                title: Text(l10n.eventInterrupts),
                subtitle: Text(l10n.eventInterruptsSub),
                value: config.interrupts,
                onChanged: (v) => _notifier.setInterrupts(_event, v),
              ),
            const Divider(),
          ],
          if (_event.supportsChat) ...[
            SwitchListTile(
              title: Text(l10n.eventShowInChat),
              subtitle: Text(l10n.eventShowInChatSub),
              value: config.chatEnabled,
              onChanged: (v) => _notifier.setChatEnabled(_event, v),
            ),
            if (config.chatEnabled)
              _templateEditor(
                controller: _chatTemplate,
                label: l10n.eventWhatToShow,
                save: (v) => _notifier.setChatTemplate(_event, v),
                reset: () => _notifier.resetChatTemplate(_event),
              ),
            const Divider(),
          ],
          SwitchListTile(
            title: Text(l10n.settingsSound),
            subtitle: Text(l10n.eventSoundSub),
            value: config.soundEnabled,
            onChanged: (v) => _notifier.setSoundEnabled(_event, v),
          ),
          if (config.soundEnabled) ...[
            ListTile(
              leading: const Icon(Icons.audiotrack),
              title: Text(
                config.hasCustomSound
                    ? config.soundPath.split(Platform.pathSeparator).last
                    : l10n.eventDefaultSound,
              ),
              subtitle: Text(l10n.eventChooseSound),
              onTap: _pickSound,
              trailing: IconButton(
                icon: const Icon(Icons.play_arrow),
                tooltip: l10n.eventPlay,
                onPressed: () => _testSound(config),
              ),
            ),
            LevelSlider(
              label: l10n.eventSoundVolume,
              value: config.soundVolumePercent,
              max: 200,
              step: 5,
              percent: true,
              onChanged: (v) => _notifier.setSoundVolume(_event, v),
              onChangeEnd: (_) =>
                  _testSound(ref.read(eventConfigProvider)[_event]!),
            ),
            if (config.hasCustomSound)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    icon: const Icon(Icons.restore),
                    label: Text(l10n.eventResetSound),
                    onPressed: () => _notifier.setSoundPath(_event, ''),
                  ),
                ),
              ),
          ],
          const Divider(),
          if (_event.supportsHaptic) ...[
            SwitchListTile(
              title: Text(l10n.eventHaptic),
              subtitle: Text(l10n.eventHapticSub),
              value: config.hapticEnabled,
              onChanged: (v) => _notifier.setHapticEnabled(_event, v),
            ),
            if (config.hapticEnabled)
              _HapticEditor(event: _event, pattern: config.haptic),
          ],
        ],
      ),
    );
  }
}

class _HapticEditor extends ConsumerWidget {
  const _HapticEditor({required this.event, required this.pattern});

  final AppEvent event;
  final List<HapticStep> pattern;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notifier = ref.read(eventConfigProvider.notifier);
    void save(List<HapticStep> next) => notifier.setHaptic(event, next);

    return Column(
      children: [
        for (var i = 0; i < pattern.length; i++)
          _HapticStepRow(
            index: i,
            step: pattern[i],
            onStrength: (s) {
              final next = [...pattern];
              next[i] = HapticStep(s, pattern[i].gapMs);
              save(next);
            },
            onGap: (ms) {
              final next = [...pattern];
              next[i] = HapticStep(pattern[i].strength, ms);
              save(next);
            },
            onRemove: () => save([...pattern]..removeAt(i)),
          ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Wrap(
            spacing: 8,
            children: [
              TextButton.icon(
                icon: const Icon(Icons.add),
                label: Text(context.l10n.eventAddVibration),
                onPressed: () => save([
                  ...pattern,
                  const HapticStep(HapticStrength.medium, 80),
                ]),
              ),
              TextButton.icon(
                icon: const Icon(Icons.play_arrow),
                label: Text(context.l10n.eventTest),
                onPressed: () => ref.read(hapticPlayerProvider).play(pattern),
              ),
              TextButton.icon(
                icon: const Icon(Icons.restore),
                label: Text(context.l10n.commonResetToDefault),
                onPressed: () =>
                    save(event.defaultHaptic ?? const <HapticStep>[]),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _HapticStepRow extends StatelessWidget {
  const _HapticStepRow({
    required this.index,
    required this.step,
    required this.onStrength,
    required this.onGap,
    required this.onRemove,
  });

  final int index;
  final HapticStep step;
  final ValueChanged<HapticStrength> onStrength;
  final ValueChanged<int> onGap;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 4, 4),
      child: Row(
        children: [
          Text('${index + 1}.'),
          const SizedBox(width: 12),
          DropdownButton<HapticStrength>(
            value: step.strength,
            items: [
              for (final s in HapticStrength.values)
                DropdownMenuItem(value: s, child: Text(s.label(context.l10n))),
            ],
            onChanged: (s) {
              if (s != null) onStrength(s);
            },
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Semantics(
              label: context.l10n.eventStepPause(index + 1),
              child: TextFormField(
                initialValue: '${step.gapMs}',
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  labelText: context.l10n.eventPauseMs,
                ),
                onChanged: (value) => onGap(int.tryParse(value.trim()) ?? 0),
              ),
            ),
          ),
          Semantics(
            label: context.l10n.eventRemoveStep(index + 1),
            child: IconButton(
              icon: const Icon(Icons.remove_circle_outline),
              tooltip: context.l10n.commonRemove,
              onPressed: onRemove,
            ),
          ),
        ],
      ),
    );
  }
}
