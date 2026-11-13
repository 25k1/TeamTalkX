import 'dart:async';

import 'package:flutter/semantics.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../platform/native_tts.dart';
import 'platform_services.dart';
import 'settings/settings_providers.dart';

final announcerProvider = Provider<Announcer>((ref) {
  final announcer = Announcer(ref, ref.read(ttsProvider));
  ref.onDispose(announcer.dispose);
  return announcer;
});

final ttsConfiguratorProvider = Provider<void>((ref) {
  final speechSettings = ref.watch(speechSettingsProvider);
  if (speechSettings.speechOutput != SpeechOutput.tts) return;
  unawaited(
    Future(() async {
      final tts = ref.read(ttsProvider);
      await tts.init(engine: speechSettings.ttsEngine);
      await tts.configure(
        language: speechSettings.ttsLanguage,
        voice: speechSettings.ttsVoice,
        rate: speechSettings.ttsRatePercent / 100,
        pitch: speechSettings.ttsPitchPercent / 100,
        volume: speechSettings.ttsVolumePercent / 100,
        accessibilityStream: speechSettings.ttsUseAccessibilityStream,
      );
    }),
  );
});

class Announcer {
  Announcer(this._ref, this._tts);

  final Ref _ref;
  final Tts _tts;

  void announce(String message, {bool interrupt = false}) {
    if (message.trim().isEmpty) return;
    final speechSettings = _ref.read(speechSettingsProvider);
    switch (speechSettings.speechOutput) {
      case SpeechOutput.screenReader:
        final dispatcher = WidgetsBinding.instance.platformDispatcher;
        final view = dispatcher.implicitView ?? dispatcher.views.firstOrNull;
        if (view != null) {
          unawaited(
            SemanticsService.sendAnnouncement(
              view,
              message,
              TextDirection.ltr,
              assertiveness: interrupt
                  ? Assertiveness.assertive
                  : Assertiveness.polite,
            ),
          );
        }
      case SpeechOutput.tts:
        unawaited(_tts.speak(message, interrupt: interrupt));
      case SpeechOutput.none:
        break;
    }
  }

  void announceShown(String message) {
    if (_ref.read(speechSettingsProvider).speechOutput == SpeechOutput.tts) {
      announce(message);
    }
  }

  void dispose() {
    unawaited(_tts.stop());
  }
}
