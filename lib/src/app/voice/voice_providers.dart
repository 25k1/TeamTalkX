import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/capture_settings.dart';
import '../../domain/events.dart';
import '../../domain/teamtalk_client.dart';
import '../announcer.dart';
import '../connection/client_events.dart';
import '../connection/connection_providers.dart';
import '../settings/event_config.dart';
import '../settings/event_dispatcher.dart';
import '../settings/locale_providers.dart';
import '../settings/settings_providers.dart';

class VoiceState {
  const VoiceState({
    this.txEnabled = false,
    this.txLocked = false,
    this.voxEnabled = false,
    this.voxActive = false,
    this.micMuted = false,
  });

  final bool txEnabled;

  final bool txLocked;

  final bool voxEnabled;

  final bool voxActive;

  final bool micMuted;

  VoiceState copyWith({
    bool? txEnabled,
    bool? txLocked,
    bool? voxEnabled,
    bool? voxActive,
    bool? micMuted,
  }) => VoiceState(
    txEnabled: txEnabled ?? this.txEnabled,
    txLocked: txLocked ?? this.txLocked,
    voxEnabled: voxEnabled ?? this.voxEnabled,
    voxActive: voxActive ?? this.voxActive,
    micMuted: micMuted ?? this.micMuted,
  );
}

final speakerMutedProvider = NotifierProvider<SpeakerMutedNotifier, bool>(
  SpeakerMutedNotifier.new,
);

class SpeakerMutedNotifier extends Notifier<bool> {
  @override
  bool build() => false;

  void toggle() => state = !state;
}

CaptureSettings captureSettingsFor(
  MicrophoneSettings settings, {
  required bool voiceDetection,
}) {
  final channels = settings.customInputChannels;
  return CaptureSettings(
    sampleRate: settings.customInputSampleRate,
    channels: channels,
    outputChannel: channels == 2
        ? settings.customStereoChannel.outputChannel
        : -1,
    noiseSuppression: settings.noiseSuppressionEnabled,
    noiseSuppressionLevel: settings.noiseSuppressionLevel / 100.0,
    voiceDetection: voiceDetection,
    detector: switch (settings.vadEngine) {
      VadEngine.silero => VoiceDetectorKind.silero,
      VadEngine.rnnoise => VoiceDetectorKind.rnnoise,
    },
    voiceLevel: settings.voiceActivationLevel,
    agc: settings.agcEnabled,
    agcGainPercent: settings.customInputGainPercent,
    gain: settings.customInputGain,
  );
}

final voiceProvider = NotifierProvider<VoiceNotifier, VoiceState>(
  VoiceNotifier.new,
);

final noiseSuppressionApplyProvider = Provider<void>((ref) {
  ref.listen<MicrophoneSettings>(microphoneSettingsProvider, (prev, next) {
    if (prev == null) return;
    final changed =
        prev.noiseSuppressionEnabled != next.noiseSuppressionEnabled ||
        prev.noiseSuppressionLevel != next.noiseSuppressionLevel;
    if (changed) {
      ref.read(voiceProvider.notifier).restartCustomTransmission();
    }
  });
});

class VoiceNotifier extends Notifier<VoiceState> {
  bool _inputActive = false;
  StreamSubscription<bool>? _voiceSub;
  int _streamId = 0;

  bool _flushPreRoll = false;

  bool _resumeTxOnRejoin = false;

  bool _voxMonitorActive = false;

  bool _voxDetectsVoice = false;

  bool _voxReleaseScheduled = false;

  bool _voxStartedTx = false;

  bool _pttOwnsTx = false;

  DateTime? _voxTxSince;

  bool _micBlocked = false;

  void setMicBlocked({required bool blocked}) => _micBlocked = blocked;

  bool _refuseWhileBlocked() {
    if (!_micBlocked) return false;
    ref
        .read(announcerProvider)
        .announce(ref.read(appLocalizationsProvider).callMicUnavailable);
    return true;
  }

  CaptureSettings _captureSettingsFor(MicrophoneSettings settings) =>
      captureSettingsFor(settings, voiceDetection: state.voxEnabled);

  void _applyCaptureSettings() {
    if (!_inputActive) return;
    ref
        .read(teamTalkClientProvider)
        .configureCapture(
          _captureSettingsFor(ref.read(microphoneSettingsProvider)),
        );
  }

  static const _voxMinHold = Duration(milliseconds: 200);

  @override
  VoiceState build() {
    final client = ref.read(teamTalkClientProvider);
    ref.listenClientEvents((event) {
      switch (event) {
        case VoiceActivationEvent(:final active):
          state = state.copyWith(voxActive: active);
        case UserJoinedEvent(:final user) when user.id == client.state.myUserId:
          if (_resumeTxOnRejoin) {
            _resumeTxOnRejoin = false;
            startTransmission();
          } else {
            final tx = client.isVoiceTransmitting;
            if (tx != state.txEnabled) state = state.copyWith(txEnabled: tx);
          }
        case ConLostEvent():
          _resumeTxOnRejoin = state.txEnabled;
          _stopCustomInput();
          _voxMonitorActive = false;
          _resetVox();
          state = VoiceState(micMuted: state.micMuted);
        case MyselfLoggedOutEvent():
          _resumeTxOnRejoin = false;
          _stopCustomInput();
          _voxMonitorActive = false;
          _resetVox();
          state = const VoiceState();
        default:
          break;
      }
    });
    ref.listen<MicrophoneSettings>(
      microphoneSettingsProvider,
      (_, _) => _applyCaptureSettings(),
    );
    listenSelf((previous, next) {
      if (!_inputActive) return;
      if (previous?.txEnabled != next.txEnabled ||
          previous?.voxActive != next.voxActive ||
          previous?.micMuted != next.micMuted) {
        _syncTransmit();
      }
    });
    ref.onDispose(() {
      _stopCustomInput(client: client);
      _voxMonitorActive = false;
    });
    return const VoiceState();
  }

  void startTransmission() {
    if (state.txEnabled) return;
    if (_refuseWhileBlocked()) return;
    final wasVoxActive = state.voxActive;
    _pttOwnsTx = true;
    _voxStartedTx = false;
    _voxTxSince = null;
    _voxReleaseScheduled = false;
    _voxDetectsVoice = false;
    _startCustomInput(ref.read(microphoneSettingsProvider));
    state = state.copyWith(txEnabled: true, voxActive: false);
    if (wasVoxActive) {
      _notifyVox(active: false);
    }
    _txFeedback(on: true);
  }

  void stopTransmission() {
    if (!state.txEnabled) return;
    final wasVoxActive = state.voxActive;
    _pttOwnsTx = false;
    if (_inputActive) {
      if (_voxMonitorActive) {
        state = state.copyWith(txEnabled: false, txLocked: false);
        _resetVox();
        if (wasVoxActive) {
          state = state.copyWith(voxActive: false);
          _notifyVox(active: false);
        }
        _txFeedback(on: false);
        return;
      }
      _stopCustomInput();
    } else {
      ref.read(teamTalkClientProvider).setVoiceTransmission(enabled: false);
    }
    state = state.copyWith(txEnabled: false, txLocked: false, voxActive: false);
    _resetVox();
    if (wasVoxActive) {
      _notifyVox(active: false);
    }
    _txFeedback(on: false);
  }

  void _startCustomInput(MicrophoneSettings settings) {
    if (_inputActive) return;
    _inputActive = true;
    final client = ref.read(teamTalkClientProvider);
    _streamId = client.beginAudioInput();
    _flushPreRoll = false;
    client.configureCapture(_captureSettingsFor(settings));
    _voiceSub = client.captureVoice.listen(_onCaptureVoice);
    client.startCapture(
      audioSource: settings.customAudioSource,
      sampleRate: settings.customInputSampleRate,
      channels: settings.customInputChannels,
    );
    _syncTransmit();
  }

  void _syncTransmit() {
    final flush = state.txEnabled && _flushPreRoll;
    if (flush) _flushPreRoll = false;
    ref
        .read(teamTalkClientProvider)
        .setCaptureTransmit(
          _streamId,
          transmit: state.txEnabled && !state.micMuted,
          flushPreRoll: flush,
          voiceActive: state.voxActive,
        );
  }

  void _onCaptureVoice(bool voice) {
    if (!state.voxEnabled || _pttOwnsTx) return;
    _handleVoxEdge(active: voice);
  }

  void _stopCustomInput({TeamTalkClient? client}) {
    if (!_inputActive) return;
    _inputActive = false;
    unawaited(_voiceSub?.cancel());
    _voiceSub = null;
    _flushPreRoll = false;
    final TeamTalkClient tt = client ?? ref.read(teamTalkClientProvider);
    tt
      ..stopCapture()
      ..endAudioInput()
      ..resetCapture();
  }

  void _handleVoxEdge({required bool active}) {
    if (active) {
      _voxDetectsVoice = true;
      if (!_voxMonitorActive) return;
      _voxTxSince ??= DateTime.now();
      if (state.voxActive) return;
      state = state.copyWith(voxActive: true);
      _notifyVox(active: true);
      if (!state.txEnabled) {
        _voxStartedTx = true;
        _flushPreRoll = true;
        state = state.copyWith(txEnabled: true);
      }
      return;
    }

    _voxDetectsVoice = false;
    if (!_voxMonitorActive) return;
    if (!state.voxActive) return;
    if (_voxReleaseScheduled) return;
    _voxReleaseScheduled = true;

    final now = DateTime.now();
    final trigger = _voxTxSince ?? now;
    final minHoldDeadline = trigger.add(_voxMinHold);
    final releaseHold = captureSettingsFor(
      ref.read(microphoneSettingsProvider),
      voiceDetection: true,
    ).detector.releaseHold;
    final releaseHoldDeadline = now.add(releaseHold);
    final when = minHoldDeadline.isAfter(releaseHoldDeadline)
        ? minHoldDeadline
        : releaseHoldDeadline;
    final delay = when.difference(now);
    Future.delayed(delay.isNegative ? Duration.zero : delay, _doVoxRelease);
  }

  void _doVoxRelease() {
    _voxReleaseScheduled = false;
    if (!_voxMonitorActive) return;
    if (_voxDetectsVoice) return;
    if (!_voxStartedTx) return;
    if (!state.txEnabled) return;
    _voxStartedTx = false;
    _voxTxSince = null;
    state = state.copyWith(voxActive: false, txEnabled: false);
    _notifyVox(active: false);
  }

  void _resetVox() {
    _voxStartedTx = false;
    _pttOwnsTx = false;
    _voxTxSince = null;
    _voxDetectsVoice = false;
    _voxReleaseScheduled = false;
    ref.read(teamTalkClientProvider).resetCapture();
  }

  void restartCustomTransmission() {
    if (!_inputActive) return;
    _stopCustomInput();
    _startCustomInput(ref.read(microphoneSettingsProvider));
  }

  void toggleTransmission() =>
      state.txEnabled ? stopTransmission() : startTransmission();

  void lockTransmission() {
    if (!state.txEnabled || state.txLocked) return;
    final wasVoxActive = state.voxActive;
    _pttOwnsTx = true;
    _voxStartedTx = false;
    _voxTxSince = null;
    state = state.copyWith(txLocked: true, voxActive: false);
    if (wasVoxActive) {
      _notifyVox(active: false);
    }
    if (ref.read(eventFeedbackSettingsProvider).vibrationEnabled) {
      unawaited(HapticFeedback.heavyImpact());
      Future.delayed(
        const Duration(milliseconds: 130),
        HapticFeedback.heavyImpact,
      );
    }
    ref
        .read(announcerProvider)
        .announce(
          ref.read(appLocalizationsProvider).controlsTransmissionLocked,
        );
  }

  void _txFeedback({required bool on}) {
    ref
        .read(eventDispatcherProvider)
        .fire(on ? AppEvent.voiceTransmitOn : AppEvent.voiceTransmitOff);
  }

  void _notifyVox({required bool active}) => ref
      .read(teamTalkClientProvider)
      .applyLocalEvent(VoiceActivationEvent(active: active));

  void toggleSpeakerMute() {
    ref.read(speakerMutedProvider.notifier).toggle();
    ref
        .read(announcerProvider)
        .announce(
          ref.read(speakerMutedProvider)
              ? ref.read(appLocalizationsProvider).mainServerMuted
              : ref.read(appLocalizationsProvider).mainServerUnmuted,
        );
  }

  void toggleMicrophoneMute() {
    state = state.copyWith(micMuted: !state.micMuted);
    final l10n = ref.read(appLocalizationsProvider);
    ref
        .read(announcerProvider)
        .announce(state.micMuted ? l10n.micMuted : l10n.micUnmuted);
  }

  void setVoiceActivation({required bool enabled}) {
    if (enabled && _refuseWhileBlocked()) return;
    final client = ref.read(teamTalkClientProvider);
    final microphoneSettings = ref.read(microphoneSettingsProvider);
    client.setVoiceActivation(enabled: enabled);
    if (enabled) {
      client.setVoiceActivationLevel(microphoneSettings.voiceActivationLevel);
      if (!state.txEnabled) {
        _voxMonitorActive = true;
        _voxStartedTx = false;
        _voxTxSince = null;
        ref.read(teamTalkClientProvider).resetCapture();
        _startCustomInput(microphoneSettings);
      }
    } else {
      final wasVoxActive = state.voxActive;
      if (_voxMonitorActive) {
        if (_voxStartedTx && state.txEnabled) {
          _voxStartedTx = false;
          state = state.copyWith(txEnabled: false, voxActive: false);
          _notifyVox(active: false);
        } else if (wasVoxActive) {
          state = state.copyWith(voxActive: false);
          _notifyVox(active: false);
        }
        _voxMonitorActive = false;
        _voxTxSince = null;
        _voxReleaseScheduled = false;
        _voxDetectsVoice = false;
        ref.read(teamTalkClientProvider).resetCapture();
        if (!_pttOwnsTx) _stopCustomInput();
      } else if (wasVoxActive) {
        state = state.copyWith(voxActive: false);
        _notifyVox(active: false);
      }
    }
    state = state.copyWith(voxEnabled: enabled, voxActive: false);
    _applyCaptureSettings();
    ref
        .read(eventDispatcherProvider)
        .fire(
          enabled
              ? AppEvent.voiceActivationEnabled
              : AppEvent.voiceActivationDisabled,
        );
  }
}
