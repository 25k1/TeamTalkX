enum CallState {
  idle,
  ringing,
  active;

  static CallState fromName(String? name) =>
      values.firstWhere((v) => v.name == name, orElse: () => idle);
}
