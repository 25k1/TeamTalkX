import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/call_state.dart';
import '../../domain/models.dart';
import '../announcer.dart';
import '../connection/connection_providers.dart';
import '../platform_services.dart';
import '../settings/locale_providers.dart';
import '../settings/settings_providers.dart';
import '../settings/sound_player.dart';
import 'output_interruption.dart';
import 'voice_providers.dart';

final callHandlerProvider = NotifierProvider<CallHandler, CallState>(
  CallHandler.new,
);

class CallHandler extends Notifier<CallState> {
  StreamSubscription<CallState>? _sub;

  bool _txWasOn = false;
  bool _voxWasOn = false;

  (int, String)? _statusBefore;
  (int, String)? _callStatus;

  @override
  CallState build() {
    ref.listen(connectionProvider, (_, next) {
      switch (next) {
        case LoggedIn():
          _start();
        case Disconnected() || Reconnecting():
          _stop();
        default:
          break;
      }
    }, fireImmediately: true);
    final interruptions = ref.read(interruptionsProvider);
    ref.onDispose(() {
      if (_sub == null) return;
      unawaited(_sub?.cancel());
      _sub = null;
      unawaited(interruptions.stop());
    });
    return CallState.idle;
  }

  void _start() {
    if (_sub != null) return;
    final interruptions = ref.read(interruptionsProvider);
    _sub = interruptions.callState.listen(_apply);
    unawaited(interruptions.start());
  }

  void _stop() {
    if (_sub == null) return;
    unawaited(_sub?.cancel());
    _sub = null;
    unawaited(ref.read(interruptionsProvider).stop());
    _statusBefore = null;
    _callStatus = null;
    _txWasOn = false;
    _voxWasOn = false;
    _release();
    state = CallState.idle;
  }

  void _apply(CallState next) {
    final previous = state;
    if (next == previous) return;
    state = next;
    final l10n = ref.read(appLocalizationsProvider);
    final output = ref.read(outputInterruptionProvider.notifier);
    switch (next) {
      case CallState.ringing:
        if (previous == CallState.idle) _suspendVoice();
        output.set(InterruptionSource.call, OutputEffect.duck);
        _blockMic(blocked: false);
        if (previous == CallState.idle) {
          ref.read(announcerProvider).announce(l10n.callIncoming);
        }
      case CallState.active:
        if (previous == CallState.idle) _suspendVoice();
        output.set(InterruptionSource.call, OutputEffect.mute);
        _blockMic(blocked: true);
        _setCallStatus();
      case CallState.idle:
        final txWasOn = _txWasOn;
        _restore();
        ref
            .read(announcerProvider)
            .announce(txWasOn ? l10n.callEndedTxOff : l10n.callEnded);
    }
  }

  void _suspendVoice() {
    final voice = ref.read(voiceProvider);
    final notifier = ref.read(voiceProvider.notifier);
    _txWasOn = voice.txEnabled && !voice.voxActive;
    _voxWasOn = voice.voxEnabled;
    if (voice.voxEnabled) notifier.setVoiceActivation(enabled: false);
    if (ref.read(voiceProvider).txEnabled) notifier.stopTransmission();
  }

  void _blockMic({required bool blocked}) {
    ref.read(voiceProvider.notifier).setMicBlocked(blocked: blocked);
    ref.read(soundPlayerProvider).suppressed = blocked;
  }

  void _release() {
    ref
        .read(outputInterruptionProvider.notifier)
        .set(InterruptionSource.call, null);
    _blockMic(blocked: false);
  }

  void _restore() {
    _release();
    _restoreStatus();
    if (_voxWasOn && !ref.read(voiceProvider).voxEnabled) {
      ref.read(voiceProvider.notifier).setVoiceActivation(enabled: true);
    }
    _txWasOn = false;
    _voxWasOn = false;
  }

  void _setCallStatus() {
    final settings = ref.read(settingsProvider);
    if (!settings.awayDuringCalls || _statusBefore != null) return;
    final client = ref.read(teamTalkClientProvider);
    final me = client.state.users[client.state.myUserId];
    if (me == null) return;
    final mode = (me.statusMode & ~TtStatusMode.modeMask) | TtStatusMode.away;
    final message = settings.callStatusMessage.isEmpty
        ? me.statusMessage
        : settings.callStatusMessage;
    _statusBefore = (me.statusMode, me.statusMessage);
    _callStatus = (mode, message);
    if (mode == me.statusMode && message == me.statusMessage) return;
    client.changeStatus(mode, message).ignore();
  }

  void _restoreStatus() {
    final before = _statusBefore;
    final during = _callStatus;
    _statusBefore = null;
    _callStatus = null;
    if (before == null || during == null) return;
    final client = ref.read(teamTalkClientProvider);
    final me = client.state.users[client.state.myUserId];
    if (me == null) return;
    if ((me.statusMode, me.statusMessage) != during) return;
    if (before == during) return;
    client.changeStatus(before.$1, before.$2).ignore();
  }
}
