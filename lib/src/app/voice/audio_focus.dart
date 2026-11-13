import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/events.dart';
import '../../domain/server_state.dart';
import '../../domain/tt_types.dart';
import '../../platform/interruptions.dart';
import '../connection/client_events.dart';
import '../connection/connection_providers.dart';
import '../platform_services.dart';
import '../settings/settings_providers.dart';
import '../settings/sound_player.dart';
import 'call_handler.dart';
import 'output_interruption.dart';

const duckHang = Duration(milliseconds: 1500);

const otherAppHang = Duration(seconds: 1);

bool someoneAudible(ServerState state) => state.users.values.any(
  (u) =>
      u.id != state.myUserId &&
      (u.userState & (UserStates.voice | UserStates.mediaFileAudio)) != 0,
);

final audioFocusControllerProvider = Provider<void>((ref) {
  final controller = _AudioFocusController(ref);
  ref.onDispose(controller.dispose);
  ref.listen(connectionProvider, (_, next) {
    switch (next) {
      case LoggedIn():
        controller.start();
      case Disconnected() || Reconnecting():
        controller.stop();
      default:
        break;
    }
  }, fireImmediately: true);
  ref.listen(interruptionSettingsProvider, (previous, next) {
    if (previous?.focusLossPolicy != next.focusLossPolicy ||
        previous?.duckOthersForVoice != next.duckOthersForVoice ||
        previous?.duckOthersForEvents != next.duckOthersForEvents ||
        previous?.keepVolumeUnderTalkBack != next.keepVolumeUnderTalkBack) {
      controller.update();
    }
  });
  ref.listen(callHandlerProvider, (_, _) => controller.update());
  ref.listenClientEvents((event) {
    if (event is UserStateChangeEvent || event is UserLeftEvent) {
      controller.update();
    }
  });
});

class _AudioFocusController {
  _AudioFocusController(this._ref)
    : _interruptions = _ref.read(interruptionsProvider);

  final Ref _ref;
  final Interruptions _interruptions;
  final _subs = <StreamSubscription<Object?>>[];
  bool _started = false;

  bool _otherPlaying = false;
  bool _eventsPlaying = false;

  bool _ducking = false;

  bool _askedToDuck = false;

  bool _yielded = false;
  Timer? _releaseTimer;
  Timer? _otherStoppedTimer;

  OutputInterruptionNotifier get _output =>
      _ref.read(outputInterruptionProvider.notifier);

  void start() {
    if (_started) return;
    _started = true;
    _subs
      ..add(_interruptions.otherAppPlaying.listen(_onOtherPlaying))
      ..add(_interruptions.focusChanges.listen(_onFocus))
      ..add(
        _ref.read(soundPlayerProvider).playing.listen((playing) {
          _eventsPlaying = playing;
          update();
        }),
      );
    scheduleMicrotask(update);
  }

  void stop() {
    if (!_started) return;
    _started = false;
    _cancelSubs();
    _releaseTimer?.cancel();
    _otherStoppedTimer?.cancel();
    if (_ducking) unawaited(_interruptions.stopDuckingOthers());
    _ducking = false;
    _askedToDuck = false;
    _yielded = false;
    _otherPlaying = false;
    _eventsPlaying = false;
    _output
      ..set(InterruptionSource.otherApp, null)
      ..set(InterruptionSource.focus, null);
  }

  void _onOtherPlaying(bool playing) {
    if (playing) {
      _otherStoppedTimer?.cancel();
      _otherStoppedTimer = null;
      _otherPlaying = true;
      update();
    } else {
      _otherStoppedTimer ??= Timer(otherAppHang, () {
        _otherStoppedTimer = null;
        _otherPlaying = false;
        update();
      });
    }
  }

  void _onFocus(FocusChange change) {
    switch (change) {
      case FocusChange.ducked:
        _askedToDuck = true;
      case FocusChange.regained:
        _askedToDuck = false;
      case FocusChange.lost:
        _releaseTimer?.cancel();
        _releaseTimer = null;
        _ducking = false;
        _askedToDuck = false;
        _yielded = true;
    }
    update();
  }

  void update() {
    if (!_started) return;
    final interruptions = _ref.read(interruptionSettingsProvider);
    final playback = _ref.read(playbackSettingsProvider);
    final state = _ref.read(teamTalkClientProvider).state;
    final inCall = _ref.read(callHandlerProvider) != CallState.idle;
    final wantDuck =
        !inCall &&
        ((interruptions.duckOthersForVoice && someoneAudible(state)) ||
            (interruptions.duckOthersForEvents && _eventsPlaying));

    if (!wantDuck) _yielded = false;
    if (wantDuck && !_yielded) {
      _releaseTimer?.cancel();
      _releaseTimer = null;
      if (!_ducking) {
        _ducking = true;
        unawaited(_interruptions.duckOthers(voiceCall: playback.voiceCallMode));
      }
    } else if (_ducking) {
      _releaseTimer ??= Timer(duckHang, () {
        _releaseTimer = null;
        _ducking = false;
        _askedToDuck = false;
        unawaited(_interruptions.stopDuckingOthers());
        update();
      });
    }

    _output
      ..set(
        InterruptionSource.focus,
        _ducking && _askedToDuck && !interruptions.keepVolumeUnderTalkBack
            ? OutputEffect.duck
            : null,
      )
      ..set(
        InterruptionSource.otherApp,
        _ducking || !_otherPlaying
            ? null
            : switch (interruptions.focusLossPolicy) {
                FocusLossPolicy.ignore => null,
                FocusLossPolicy.duck => OutputEffect.duck,
                FocusLossPolicy.mute => OutputEffect.mute,
              },
      );
  }

  void _cancelSubs() {
    for (final sub in _subs) {
      unawaited(sub.cancel());
    }
    _subs.clear();
  }

  void dispose() {
    _started = false;
    _cancelSubs();
    _releaseTimer?.cancel();
    _otherStoppedTimer?.cancel();
    if (_ducking) unawaited(_interruptions.stopDuckingOthers());
  }
}
