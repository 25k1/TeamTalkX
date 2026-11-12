library;

const _redacted = '<redacted>';

final _secretPair = RegExp(
  r'\b(password|oppassword|passwd|filetxkey|cryptkey|accesstoken|token|'
  r'secret|dsn)=("(?:[^"\\]|\\.)*"|[^\s&",\]]+)',
  caseSensitive: false,
);

final _secretJson = RegExp(
  r'"(password|oppassword|token|accesstoken|secret)"\s*:\s*"(?:[^"\\]|\\.)*"',
  caseSensitive: false,
);

final _content = RegExp(r'\bcontent=("(?:[^"\\]|\\.)*"|\S+)');

String redact(String text) {
  if (text.isEmpty) return text;
  return text
      .replaceAllMapped(_secretPair, (m) => '${m[1]}=$_redacted')
      .replaceAllMapped(_secretJson, (m) => '"${m[1]}": "$_redacted"')
      .replaceAllMapped(_content, (_) => 'content=$_redacted');
}
