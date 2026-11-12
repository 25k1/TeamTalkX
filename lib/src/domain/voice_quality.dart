enum VoiceEnhancement {
  off(0),
  standard(5),
  better(6),
  best(7);

  const VoiceEnhancement(this.opusComplexity);

  final int opusComplexity;

  static VoiceEnhancement fromName(String? name) => values.firstWhere(
    (e) => e.name == name,
    orElse: () => VoiceEnhancement.off,
  );
}

enum LossProtection {
  channel(fec: true, dredMs: 0),
  channelAndDred(fec: true, dredMs: 100),
  none(fec: false, dredMs: 0);

  const LossProtection({required this.fec, required this.dredMs});

  final bool fec;
  final int dredMs;

  int get expectedLossPercent => switch (this) {
    channel => 10,
    channelAndDred => 20,
    none => 0,
  };

  static LossProtection fromName(String? name) => values.firstWhere(
    (e) => e.name == name,
    orElse: () => LossProtection.channel,
  );
}

class VoiceQuality {
  const VoiceQuality({
    this.enhancement = VoiceEnhancement.off,
    this.bandwidthExtension = false,
    this.protection = LossProtection.channel,
  });

  final VoiceEnhancement enhancement;
  final bool bandwidthExtension;
  final LossProtection protection;

  @override
  bool operator ==(Object other) =>
      other is VoiceQuality &&
      other.enhancement == enhancement &&
      other.bandwidthExtension == bandwidthExtension &&
      other.protection == protection;

  @override
  int get hashCode => Object.hash(enhancement, bandwidthExtension, protection);
}
