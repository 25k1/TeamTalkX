import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/audio_output.dart';
import '../../domain/call_state.dart';
import '../announcer.dart';
import '../connection/connection_providers.dart';
import '../settings/locale_providers.dart';
import 'audio_output.dart';
import 'call_handler.dart';
import 'voice_providers.dart';

bool isHeadset(AudioOutputKind kind) => switch (kind) {
  AudioOutputKind.wired ||
  AudioOutputKind.usb ||
  AudioOutputKind.bluetooth ||
  AudioOutputKind.hearingAid => true,
  AudioOutputKind.speaker || AudioOutputKind.earpiece => false,
};

final headsetWatchProvider = Provider<void>((ref) {
  Set<String>? previous;
  ref.listen(audioOutputsProvider, (_, next) {
    final outputs = next.value;
    if (outputs == null) return;
    final headsets = {
      for (final d in outputs)
        if (isHeadset(d.kind)) '${d.kind.name}/${d.name}',
    };
    final before = previous;
    previous = headsets;
    if (before == null || before.difference(headsets).isEmpty) return;
    if (ref.read(connectionProvider) is! LoggedIn) return;
    if (ref.read(callHandlerProvider) != CallState.idle) return;

    final voice = ref.read(voiceProvider);
    final notifier = ref.read(voiceProvider.notifier);
    final stopped = voice.txEnabled || voice.voxEnabled;
    if (voice.voxEnabled) notifier.setVoiceActivation(enabled: false);
    if (ref.read(voiceProvider).txEnabled) notifier.stopTransmission();
    final l10n = ref.read(appLocalizationsProvider);
    ref
        .read(announcerProvider)
        .announce(
          stopped ? l10n.headsetDisconnectedTxOff : l10n.headsetDisconnected,
        );
  }, fireImmediately: true);
});
