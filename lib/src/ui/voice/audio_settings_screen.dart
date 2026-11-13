import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/settings/settings_providers.dart';
import '../../app/voice/audio_output.dart';
import '../../app/voice/voice_providers.dart';
import '../../domain/audio_output.dart';
import '../../domain/sound_level.dart';
import '../../domain/voice_quality.dart';
import '../../l10n/l10n.dart';
import '../a11y/accessible_menu.dart';
import '../common/labels.dart';
import '../common/ui.dart';
import '../settings/settings_widgets.dart';
import 'mic_test_screen.dart';
import 'voice_activation_screen.dart';

Map<int, String> _audioSources(AppLocalizations l10n) => {
  0: l10n.audioSourceDefault,
  1: l10n.audioSourceMicrophone,
  5: l10n.audioSourceCamcorder,
  6: l10n.audioSourceVoiceRecognition,
  7: l10n.audioSourceVoiceCommunication,
  9: l10n.audioSourceUnprocessed,
  10: l10n.audioSourceVoicePerformance,
};

const _sampleRates = <int, String>{
  8000: '8 kHz',
  16000: '16 kHz',
  24000: '24 kHz',
  44100: '44.1 kHz',
  48000: '48 kHz',
};

Map<int, String> _channelOptions(AppLocalizations l10n) => {
  1: l10n.audioMono,
  2: l10n.audioStereo,
};

class AudioSettingsScreen extends ConsumerWidget {
  const AudioSettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final microphoneSettings = ref.watch(microphoneSettingsProvider);
    final playbackSettings = ref.watch(playbackSettingsProvider);
    final agcActive = microphoneSettings.agcEnabled;
    final l10n = context.l10n;
    final sources = _audioSources(l10n);
    final channels = _channelOptions(l10n);

    Widget choiceTile<T>({
      required IconData icon,
      required String title,
      required String subtitle,
      required Map<T, String> options,
      required T selected,
      required void Function(T value) onPick,
    }) => ListTile(
      leading: Icon(icon),
      title: Text(title),
      subtitle: Text(subtitle),
      onTap: () async {
        final value = await showSingleChoiceMenu<T>(
          context,
          title: title,
          options: options,
          selected: selected,
        );
        if (value == null) return;
        onPick(value);
        ref.read(voiceProvider.notifier).restartCustomTransmission();
      },
    );

    return Scaffold(
      appBar: AppBar(title: Text(l10n.controlsAudioSettings)),
      body: ListView(
        children: [
          const _OutputSection(),
          SectionHeader(l10n.audioInput),
          ListTile(
            leading: const Icon(Icons.mic),
            title: Text(l10n.micTestEntry),
            subtitle: Text(l10n.micTestEntrySub),
            onTap: () => pushScreen(context, const MicTestScreen()),
          ),
          choiceTile<int>(
            icon: Icons.mic_external_on,
            title: l10n.audioSource,
            subtitle:
                sources[microphoneSettings.customAudioSource] ??
                l10n.audioSourceOther(microphoneSettings.customAudioSource),
            options: sources,
            selected: microphoneSettings.customAudioSource,
            onPick: ref
                .read(microphoneSettingsProvider.notifier)
                .setCustomAudioSource,
          ),
          choiceTile<int>(
            icon: Icons.graphic_eq,
            title: l10n.audioSampleRate,
            subtitle:
                _sampleRates[microphoneSettings.customInputSampleRate] ??
                '${microphoneSettings.customInputSampleRate} Hz',
            options: _sampleRates,
            selected: microphoneSettings.customInputSampleRate,
            onPick: ref
                .read(microphoneSettingsProvider.notifier)
                .setCustomInputSampleRate,
          ),
          choiceTile<int>(
            icon: Icons.headphones,
            title: l10n.audioChannels,
            subtitle:
                channels[microphoneSettings.customInputChannels] ??
                '${microphoneSettings.customInputChannels}',
            options: channels,
            selected: microphoneSettings.customInputChannels,
            onPick: ref
                .read(microphoneSettingsProvider.notifier)
                .setCustomInputChannels,
          ),
          if (microphoneSettings.customInputChannels == 2)
            choiceTile<StereoChannel>(
              icon: Icons.hearing,
              title: l10n.audioStereoChannel,
              subtitle: microphoneSettings.customStereoChannel.label(l10n),
              options: {for (final c in StereoChannel.values) c: c.label(l10n)},
              selected: microphoneSettings.customStereoChannel,
              onPick: ref
                  .read(microphoneSettingsProvider.notifier)
                  .setCustomStereoChannel,
            ),
          SectionHeader(l10n.audioProcessing),
          ListTile(
            leading: const Icon(Icons.record_voice_over),
            title: Text(l10n.settingsVoiceActivation),
            subtitle: Text(l10n.settingsVoiceActivationSub),
            onTap: () => pushScreen(context, const VoiceActivationScreen()),
          ),
          SwitchListTile(
            secondary: const Icon(Icons.hearing_disabled),
            title: Text(l10n.audioNoiseSuppression),
            subtitle: Text(l10n.audioNoiseSuppressionSub),
            value: microphoneSettings.noiseSuppressionEnabled,
            onChanged: ref
                .read(microphoneSettingsProvider.notifier)
                .setNoiseSuppressionEnabled,
          ),
          if (microphoneSettings.noiseSuppressionEnabled)
            LevelSlider(
              label: l10n.audioSuppressionLevel,
              value: microphoneSettings.noiseSuppressionLevel,
              max: 100,
              percent: true,
              step: 5,
              onChanged: ref
                  .read(microphoneSettingsProvider.notifier)
                  .setNoiseSuppressionLevel,
            ),
          SwitchListTile(
            secondary: const Icon(Icons.equalizer),
            title: Text(l10n.audioAgc),
            subtitle: Text(l10n.audioAgcSub),
            value: microphoneSettings.agcEnabled,
            onChanged: ref
                .read(microphoneSettingsProvider.notifier)
                .setAgcEnabled,
          ),
          SectionHeader(l10n.audioLevels),
          LevelSlider(
            label: l10n.audioMasterVolume,
            value: playbackSettings.masterVolumePercent,
            max: volumePercentMax,
            percent: true,
            step: 5,
            onChanged: ref
                .read(playbackSettingsProvider.notifier)
                .setMasterVolumePercent,
          ),
          LevelSlider(
            label: l10n.audioMediaVolume,
            value: playbackSettings.mediaVolumePercent,
            max: volumePercentMax,
            percent: true,
            step: 5,
            onChanged: ref
                .read(playbackSettingsProvider.notifier)
                .setMediaVolumePercent,
          ),
          SwitchListTile(
            secondary: const Icon(Icons.tune),
            title: Text(l10n.audioNormalize),
            subtitle: Text(l10n.audioNormalizeSub),
            value: playbackSettings.normalizeSpeakers,
            onChanged: ref
                .read(playbackSettingsProvider.notifier)
                .setNormalizeSpeakers,
          ),
          SectionHeader(l10n.audioVoiceQuality),
          _VoiceQualityTile<VoiceEnhancement>(
            icon: Icons.auto_fix_high,
            title: l10n.audioEnhancement,
            options: {
              VoiceEnhancement.off: l10n.audioEnhancementOff,
              VoiceEnhancement.standard: l10n.audioEnhancementStandard,
              VoiceEnhancement.better: l10n.audioEnhancementBetter,
              VoiceEnhancement.best: l10n.audioEnhancementBest,
            },
            selected: playbackSettings.voiceQuality.enhancement,
            onPick: ref
                .read(playbackSettingsProvider.notifier)
                .setVoiceEnhancement,
          ),
          SwitchListTile(
            secondary: const Icon(Icons.graphic_eq),
            title: Text(l10n.audioBandwidthExtension),
            subtitle: Text(l10n.audioBandwidthExtensionSub),
            value: playbackSettings.voiceQuality.bandwidthExtension,
            onChanged: ref
                .read(playbackSettingsProvider.notifier)
                .setBandwidthExtension,
          ),
          _VoiceQualityTile<LossProtection>(
            icon: Icons.shield_outlined,
            title: l10n.audioLossProtection,
            options: {
              LossProtection.channel: l10n.audioLossProtectionChannel,
              LossProtection.channelAndDred: l10n.audioLossProtectionDred,
              LossProtection.none: l10n.audioLossProtectionNone,
            },
            selected: playbackSettings.voiceQuality.protection,
            onPick: ref
                .read(playbackSettingsProvider.notifier)
                .setLossProtection,
          ),
          LevelSlider(
            label: agcActive ? l10n.audioTargetMicLevel : l10n.audioMicGain,
            value: microphoneSettings.customInputGainPercent,
            max: 100,
            percent: true,
            step: 5,
            onChanged: ref
                .read(microphoneSettingsProvider.notifier)
                .setCustomInputGainPercent,
          ),
        ],
      ),
    );
  }
}

class _OutputSection extends ConsumerWidget {
  const _OutputSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final playbackSettings = ref.watch(playbackSettingsProvider);
    final voiceCall = playbackSettings.voiceCallMode;
    final outputs = ref.watch(audioOutputsProvider).value ?? const [];
    final kinds = <AudioOutputKind, AudioOutputDevice>{
      for (final d in outputs.reversed)
        if (outputPickable(d.kind, voiceCall: voiceCall)) d.kind: d,
    };
    final ordered = [
      for (final d in outputs)
        if (kinds[d.kind] == d) d,
    ];
    final route = playbackSettings.outputRoute;
    final missing =
        route != null &&
        outputPickable(route, voiceCall: voiceCall) &&
        !kinds.containsKey(route);

    String label(AudioOutputKind kind, String name) {
      final base = switch (kind) {
        AudioOutputKind.speaker => l10n.audioOutputSpeaker,
        AudioOutputKind.earpiece => l10n.audioOutputEarpiece,
        AudioOutputKind.wired => l10n.audioOutputWired,
        AudioOutputKind.usb => l10n.audioOutputUsb,
        AudioOutputKind.bluetooth => l10n.audioOutputBluetooth,
        AudioOutputKind.hearingAid => l10n.audioOutputHearingAid,
      };
      final named =
          name.isNotEmpty &&
          kind != AudioOutputKind.speaker &&
          kind != AudioOutputKind.earpiece;
      return named ? '$base: $name' : base;
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionHeader(l10n.audioOutputSection),
        SwitchListTile(
          secondary: const Icon(Icons.call),
          title: Text(l10n.audioVoiceCallMode),
          subtitle: Text(l10n.audioVoiceCallModeSub),
          value: voiceCall,
          onChanged: ref
              .read(playbackSettingsProvider.notifier)
              .setVoiceCallMode,
        ),
        RadioGroup<AudioOutputKind?>(
          groupValue:
              route != null && outputPickable(route, voiceCall: voiceCall)
              ? route
              : null,
          onChanged: ref.read(playbackSettingsProvider.notifier).setOutputRoute,
          child: Column(
            children: [
              RadioListTile<AudioOutputKind?>(
                title: Text(l10n.audioOutputAutomatic),
                value: null,
              ),
              for (final d in ordered)
                RadioListTile<AudioOutputKind?>(
                  title: Text(label(d.kind, d.name)),
                  value: d.kind,
                ),
              if (missing)
                RadioListTile<AudioOutputKind?>(
                  title: Text(l10n.audioOutputNotConnected(label(route, ''))),
                  value: route,
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _VoiceQualityTile<T> extends StatelessWidget {
  const _VoiceQualityTile({
    required this.icon,
    required this.title,
    required this.options,
    required this.selected,
    required this.onPick,
    super.key,
  });

  final IconData icon;
  final String title;
  final Map<T, String> options;
  final T selected;
  final void Function(T value) onPick;

  @override
  Widget build(BuildContext context) => ListTile(
    leading: Icon(icon),
    title: Text(title),
    subtitle: Text(options[selected] ?? ''),
    onTap: () async {
      final value = await showSingleChoiceMenu<T>(
        context,
        title: title,
        options: options,
        selected: selected,
      );
      if (value != null) onPick(value);
    },
  );
}
