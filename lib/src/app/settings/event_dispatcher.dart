import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../announcer.dart';
import '../chat/chat_providers.dart';
import 'event_config.dart';
import 'haptic_player.dart';
import 'settings_providers.dart';
import 'sound_player.dart';

final eventDispatcherProvider = Provider<EventDispatcher>(EventDispatcher.new);

class EventDispatcher {
  EventDispatcher(this._ref);

  final Ref _ref;

  void fire(
    AppEvent event, {
    Map<String, String> vars = const {},
    bool speak = true,
  }) {
    final config = _ref.read(eventConfigProvider)[event]!;
    if (!config.enabled) return;
    final eventSoundSettings = _ref.read(eventSoundSettingsProvider);

    if (speak && event.supportsSpeech && config.speechEnabled) {
      final template = _ref
          .read(eventConfigProvider.notifier)
          .speechTemplate(event);
      _ref
          .read(announcerProvider)
          .announce(_substitute(template, vars), interrupt: config.interrupts);
    }
    if (speak && config.soundEnabled && eventSoundSettings.soundsEnabled) {
      final player = _ref.read(soundPlayerProvider);
      final volume = config.soundVolumePercent;
      if (config.hasCustomSound) {
        unawaited(player.playFile(config.soundPath, volumePercent: volume));
      } else if (event.defaultSound != null) {
        unawaited(
          player.playEventSound(event.defaultSound!, volumePercent: volume),
        );
      }
    }
    if (config.chatEnabled && event.supportsChat) {
      final template = _ref
          .read(eventConfigProvider.notifier)
          .chatTemplateOf(event);
      final line = _substitute(template, vars).trim();
      if (line.isNotEmpty) _ref.read(chatProvider.notifier).addLog(line);
    }
    haptic(event);
  }

  void haptic(AppEvent event) {
    final config = _ref.read(eventConfigProvider)[event]!;
    if (event.supportsHaptic &&
        config.hapticEnabled &&
        config.haptic.isNotEmpty) {
      _ref.read(hapticPlayerProvider).play(config.haptic);
    }
  }

  String _substitute(String template, Map<String, String> vars) {
    var out = template;
    vars.forEach((key, value) {
      out = out.replaceAll('{$key}', value);
    });
    return out;
  }
}
