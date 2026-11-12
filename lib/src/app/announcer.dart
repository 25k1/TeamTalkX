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
  final settings = ref.watch(settingsProvider);
  if (settings.speechOutput != SpeechOutput.tts) return;
  unawaited(
    Future(() async {
      final tts = ref.read(ttsProvider);
      await tts.init(engine: settings.ttsEngine);
      await tts.configure(
        language: settings.ttsLanguage,
        voice: settings.ttsVoice,
        rate: settings.ttsRatePercent / 100,
        pitch: settings.ttsPitchPercent / 100,
        volume: settings.ttsVolumePercent / 100,
        accessibilityStream: settings.ttsUseAccessibilityStream,
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
    final settings = _ref.read(settingsProvider);
    switch (settings.speechOutput) {
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
    if (_ref.read(settingsProvider).speechOutput == SpeechOutput.tts) {
      announce(message);
    }
  }

  void dispose() {
    unawaited(_tts.stop());
  }
}
