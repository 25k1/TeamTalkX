import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/call_state.dart';
import '../../platform/audio_routing.dart';
import '../connection/connection_providers.dart';
import '../platform_services.dart';
import '../settings/settings_providers.dart';
import '../settings/sound_player.dart';
import 'call_handler.dart';

final audioOutputsProvider = StreamProvider<List<AudioOutputDevice>>((
  ref,
) async* {
  final routing = ref.watch(audioRoutingProvider);
  yield await routing.outputs();
  await for (final _ in routing.outputsChanged) {
    yield await routing.outputs();
  }
});

bool outputPickable(AudioOutputKind kind, {required bool voiceCall}) =>
    voiceCall || kind != AudioOutputKind.earpiece;

AudioOutputDevice? chosenOutput(
  List<AudioOutputDevice> outputs,
  AudioOutputKind? route, {
  required bool voiceCall,
}) {
  if (route == null || !outputPickable(route, voiceCall: voiceCall)) {
    return null;
  }
  for (final d in outputs) {
    if (d.kind == route) return d;
  }
  return null;
}

final audioOutputControllerProvider = Provider<void>((ref) {
  final settings = ref.watch(
    settingsProvider.select((s) => (s.voiceCallMode, s.outputRoute)),
  );
  final outputs = ref.watch(audioOutputsProvider).value ?? const [];
  final connected = ref.watch(
    connectionProvider.select((c) => c is LoggedIn || c is Reconnecting),
  );
  final inCall = ref.watch(callHandlerProvider) == CallState.active;
  final (voiceCall, route) = settings;
  final device = chosenOutput(outputs, route, voiceCall: voiceCall);
  final deviceId = device?.id ?? 0;

  ref
      .read(teamTalkClientProvider)
      .setAudioOutput(voiceCall: voiceCall, deviceId: voiceCall ? 0 : deviceId);
  ref
      .read(soundPlayerProvider)
      .setOutput(
        voiceCall: voiceCall && connected,
        deviceId: voiceCall ? 0 : deviceId,
      );
  final routing = ref.read(audioRoutingProvider);
  unawaited(
    routing.setCommunication(
      on: voiceCall && connected && !inCall,
      deviceId: deviceId,
    ),
  );
});
