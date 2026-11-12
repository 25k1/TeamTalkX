enum MediaKey {
  playPause,
  next,
  previous,
  fastForward,
  rewind,
  stop;

  static MediaKey? fromName(String? name) {
    for (final v in values) {
      if (v.name == name) return v;
    }
    return null;
  }
}

enum KeyPress {
  single,
  long;

  static KeyPress? fromName(String? name) {
    for (final v in values) {
      if (v.name == name) return v;
    }
    return null;
  }
}

enum KeyAction {
  toggleTransmission,

  holdToTalk,
  toggleVoiceActivation,
  toggleSpeakers,
  toggleMicrophone,
  nextChannel,
  previousChannel,
  joinSelectedChannel,
  speakTalking,
  speakChannel,
  toggleRecording;

  bool availableFor(KeyPress press) =>
      this != holdToTalk || press == KeyPress.long;

  static KeyAction? fromName(String? name) {
    for (final v in values) {
      if (v.name == name) return v;
    }
    return null;
  }
}

class KeyBindings {
  const KeyBindings([this._actions = const {}]);

  factory KeyBindings.decode(String? text) {
    final actions = <(MediaKey, KeyPress), KeyAction>{};
    for (final entry in (text ?? '').split(';')) {
      final parts = entry.split('=');
      if (parts.length != 2) continue;
      final keyParts = parts[0].split('.');
      if (keyParts.length != 2) continue;
      final key = MediaKey.fromName(keyParts[0]);
      final press = KeyPress.fromName(keyParts[1]);
      final action = KeyAction.fromName(parts[1]);
      if (key == null || press == null || action == null) continue;
      if (!action.availableFor(press)) continue;
      actions[(key, press)] = action;
    }
    return KeyBindings(actions);
  }

  final Map<(MediaKey, KeyPress), KeyAction> _actions;

  bool get isEmpty => _actions.isEmpty;

  KeyAction? actionFor(MediaKey key, KeyPress press) => _actions[(key, press)];

  Set<MediaKey> get mappedKeys => {for (final (k, _) in _actions.keys) k};

  KeyBindings withAction(MediaKey key, KeyPress press, KeyAction? action) {
    final next = Map.of(_actions);
    if (action == null || !action.availableFor(press)) {
      next.remove((key, press));
    } else {
      next[(key, press)] = action;
    }
    return KeyBindings(next);
  }

  String encode() => [
    for (final MapEntry(key: (key, press), value: action) in _actions.entries)
      '${key.name}.${press.name}=${action.name}',
  ].join(';');

  @override
  bool operator ==(Object other) =>
      other is KeyBindings && other.encode() == encode();

  @override
  int get hashCode => encode().hashCode;
}
