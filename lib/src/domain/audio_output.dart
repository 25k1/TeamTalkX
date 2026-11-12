enum AudioOutputKind {
  speaker,
  earpiece,
  wired,
  usb,
  bluetooth,
  hearingAid;

  static AudioOutputKind? fromName(String? name) {
    for (final k in values) {
      if (k.name == name) return k;
    }
    return null;
  }
}

class AudioOutputDevice {
  const AudioOutputDevice({
    required this.id,
    required this.kind,
    required this.name,
  });

  final int id;
  final AudioOutputKind kind;

  final String name;
}
