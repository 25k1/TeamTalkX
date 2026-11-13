import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../diagnostics/log.dart';
import '../../domain/media_keys.dart';
import '../../domain/models.dart';
import '../../l10n/failure_messages.dart';
import '../announcer.dart';
import '../channels/channel_tree_providers.dart';
import '../connection/connection_providers.dart';
import '../failures.dart';
import '../keys/press_detector.dart';
import '../platform_services.dart';
import '../recording/recording_controller.dart';
import '../settings/locale_providers.dart';
import '../settings/settings_providers.dart';
import 'voice_providers.dart';

final hardwareControlsProvider = Provider<void>((ref) {
  final controls = _HardwareControls(ref);
  ref.onDispose(controls.dispose);
  ref.listen(connectionProvider, (previous, next) {
    switch (next) {
      case LoggedIn():
        controls.start();
      case Disconnected() || Reconnecting():
        controls.stop();
      default:
        break;
    }
  }, fireImmediately: true);
  ref
    ..listen(
      keySettingsProvider.select((s) => s.pttKeyCode),
      (_, _) => controls.applyPttKey(),
    )
    ..listen(
      keySettingsProvider.select((s) => s.keyBindings),
      (_, _) => controls.applyKeyBindings(),
    );
});

class _HardwareControls {
  _HardwareControls(this._ref) {
    _presses = PressDetector(
      hasLongPress: (key) => _bindings.actionFor(key, KeyPress.long) != null,
      onPress: (key) => _run(_bindings.actionFor(key, KeyPress.single)),
      onHoldStart: (key) {
        final action = _bindings.actionFor(key, KeyPress.long);
        if (action == KeyAction.holdToTalk) {
          _voice.startTransmission();
        } else {
          _run(action);
        }
      },
      onHoldEnd: (key) {
        if (_bindings.actionFor(key, KeyPress.long) == KeyAction.holdToTalk) {
          _voice.stopTransmission();
        }
      },
    );
  }

  final Ref _ref;
  late final PressDetector _presses;
  final _subs = <StreamSubscription<Object?>>[];
  bool _started = false;

  int _selectedChannel = 0;

  KeyBindings get _bindings => _ref.read(keySettingsProvider).keyBindings;
  VoiceNotifier get _voice => _ref.read(voiceProvider.notifier);

  void start() {
    if (_started) return;
    _started = true;
    final hotkeys = _ref.read(hotkeysProvider);
    _subs
      ..add(hotkeys.pttDown.listen((_) => _voice.startTransmission()))
      ..add(hotkeys.pttUp.listen((_) => _voice.stopTransmission()))
      ..add(_ref.read(mediaKeysProvider).events.listen(_onKey));
    unawaited(hotkeys.setPttKey(_ref.read(keySettingsProvider).pttKeyCode));
    applyKeyBindings();
  }

  void stop() {
    if (!_started) return;
    _started = false;
    for (final sub in _subs) {
      unawaited(sub.cancel());
    }
    _subs.clear();
    _presses.reset();
    _selectedChannel = 0;
    unawaited(_ref.read(hotkeysProvider).setPttKey(0));
    unawaited(
      _ref.read(mediaKeysProvider).configure(session: false, mapped: const {}),
    );
  }

  void applyPttKey() {
    if (_started) {
      unawaited(
        _ref
            .read(hotkeysProvider)
            .setPttKey(_ref.read(keySettingsProvider).pttKeyCode),
      );
    }
  }

  void applyKeyBindings() {
    if (!_started) return;
    _presses.reset();
    final bindings = _bindings;
    unawaited(
      _ref
          .read(mediaKeysProvider)
          .configure(session: !bindings.isEmpty, mapped: bindings.mappedKeys),
    );
  }

  void _onKey(({MediaKey key, bool down}) event) {
    if (!_bindings.mappedKeys.contains(event.key)) return;
    if (event.down) {
      _presses.down(event.key);
    } else {
      _presses.up(event.key);
    }
  }

  void _run(KeyAction? action) {
    final voice = _ref.read(voiceProvider);
    switch (action) {
      case null:
        return;
      case KeyAction.toggleTransmission:
        _voice.toggleTransmission();
      case KeyAction.holdToTalk:
        return;
      case KeyAction.toggleVoiceActivation:
        _voice.setVoiceActivation(enabled: !voice.voxEnabled);
      case KeyAction.toggleSpeakers:
        _voice.toggleSpeakerMute();
      case KeyAction.toggleMicrophone:
        _voice.toggleMicrophoneMute();
      case KeyAction.nextChannel:
        _moveSelection(1);
      case KeyAction.previousChannel:
        _moveSelection(-1);
      case KeyAction.joinSelectedChannel:
        unawaited(_joinSelected());
      case KeyAction.speakTalking:
        _speakTalking();
      case KeyAction.speakChannel:
        _speakChannel();
      case KeyAction.toggleRecording:
        unawaited(_ref.read(recordingProvider.notifier).toggle());
    }
  }

  void _announce(String text) => _ref.read(announcerProvider).announce(text);

  String _channelName(TtChannel channel) => channel.isRoot
      ? _ref.read(appLocalizationsProvider).keysRootChannel
      : channel.name;

  void _moveSelection(int step) {
    final state = _ref.read(teamTalkClientProvider).state;
    final channels = channelsInTreeOrder(state, _ref.read(channelSortProvider));
    if (channels.isEmpty) return;
    var index = channels.indexWhere((c) => c.id == _selectedChannel);
    if (index < 0) {
      index = channels.indexWhere((c) => c.id == state.joinedChannelId);
    }
    index = index < 0
        ? (step > 0 ? 0 : channels.length - 1)
        : (index + step) % channels.length;
    final channel = channels[index];
    _selectedChannel = channel.id;
    final l10n = _ref.read(appLocalizationsProvider);
    _announce(
      l10n.keysChannelSelected(
        _channelName(channel),
        state.usersInChannel(channel.id).length,
      ),
    );
  }

  Future<void> _joinSelected() async {
    final l10n = _ref.read(appLocalizationsProvider);
    final state = _ref.read(teamTalkClientProvider).state;
    final channel = state.channels[_selectedChannel];
    if (channel == null) {
      _announce(l10n.keysNoChannelSelected);
      return;
    }
    if (channel.id == state.joinedChannelId) {
      _announce(l10n.keysAlreadyInChannel(_channelName(channel)));
      return;
    }
    if (channel.hasPassword) {
      _announce(l10n.keysChannelNeedsPassword(_channelName(channel)));
      return;
    }
    try {
      await _ref.read(connectionProvider.notifier).joinChannel(channel.id);
    } on Object catch (e, st) {
      appLog.w('keys', 'Joining channel ${channel.id} failed', e, st);
      _announce(l10n.failureMessage(failureFrom(e)));
    }
  }

  void _speakTalking() {
    final l10n = _ref.read(appLocalizationsProvider);
    final state = _ref.read(teamTalkClientProvider).state;
    final talking = [
      for (final u in state.usersInChannel(state.joinedChannelId))
        if (u.isTalking && u.id != state.myUserId) u.displayName,
    ];
    _announce(
      talking.isEmpty
          ? l10n.keysNobodyTalking
          : l10n.keysTalking(talking.join(', ')),
    );
  }

  void _speakChannel() {
    final l10n = _ref.read(appLocalizationsProvider);
    final state = _ref.read(teamTalkClientProvider).state;
    final channel = state.channels[state.joinedChannelId];
    if (channel == null) {
      _announce(l10n.keysNotInChannel);
      return;
    }
    _announce(
      l10n.keysCurrentChannel(
        _channelName(channel),
        state.usersInChannel(channel.id).length,
      ),
    );
  }

  void dispose() {
    if (!_started) return;
    _started = false;
    for (final sub in _subs) {
      unawaited(sub.cancel());
    }
    _subs.clear();
    _presses.reset(endHolds: false);
  }
}
