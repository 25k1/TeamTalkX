class TtsEngineInfo {
  const TtsEngineInfo({required this.name, required this.label});

  final String name;

  final String label;
}

class TtsVoiceInfo {
  const TtsVoiceInfo({required this.name, required this.locale});

  final String name;
  final String locale;
}
