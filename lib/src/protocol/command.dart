library;

const teamTalkProtocolVersion = '5.14';

class TtCommand {
  TtCommand(this.verb, [Map<String, Object?>? params])
    : params = params ?? <String, Object?>{};

  final String verb;

  final Map<String, Object?> params;

  String? getString(String key) {
    final v = params[key];
    return v is String ? v : v?.toString();
  }

  int? getInt(String key) {
    final v = params[key];
    if (v is int) return v;
    if (v is String) return int.tryParse(v);
    return null;
  }

  bool getBool(String key) {
    final v = params[key];
    if (v is bool) return v;
    return (getInt(key) ?? 0) != 0;
  }

  List<int> getIntList(String key) {
    final v = params[key];
    if (v is List<int>) return v;
    if (v is String && v.isNotEmpty) {
      var s = v.trim();
      if (s.startsWith('[')) s = s.substring(1);
      if (s.endsWith(']')) s = s.substring(0, s.length - 1);
      if (s.isEmpty) return const [];
      return s.split(',').map((e) => int.parse(e.trim())).toList();
    }
    return const [];
  }

  TtCommand set(String key, Object? value) {
    params[key] = value;
    return this;
  }

  String encode() {
    final out = StringBuffer(verb);
    params.forEach((key, value) {
      out.write(' $key=');
      switch (value) {
        case final String v:
          out.write('"${_escape(v)}"');
        case final bool v:
          out.write(v ? 1 : 0);
        case final List<int> v:
          out.write('[${v.join(',')}]');
        case null:
          out.write('""');
        default:
          out.write(value);
      }
    });
    out.write('\r\n');
    return out.toString();
  }

  static TtCommand parse(String line) {
    var i = 0;
    final n = line.length;

    while (i < n && line[i] != ' ') {
      i++;
    }
    final verb = line.substring(0, i);
    final params = <String, Object?>{};

    while (i < n) {
      while (i < n && line[i] == ' ') {
        i++;
      }
      if (i >= n) break;

      final keyStart = i;
      while (i < n && line[i] != '=') {
        i++;
      }
      if (i >= n) break;
      final key = line.substring(keyStart, i);
      i++;

      if (i < n && line[i] == '"') {
        i++;
        final buf = StringBuffer();
        while (i < n) {
          final c = line[i];
          if (c == '\\' && i + 1 < n) {
            final next = line[i + 1];
            buf.write(switch (next) {
              'r' => '\r',
              'n' => '\n',
              _ => next,
            });
            i += 2;
          } else if (c == '"') {
            i++;
            break;
          } else {
            buf.write(c);
            i++;
          }
        }
        params[key] = buf.toString();
      } else {
        final valStart = i;
        while (i < n && line[i] != ' ') {
          i++;
        }
        params[key] = line.substring(valStart, i);
      }
    }

    return TtCommand(verb, params);
  }

  static String _escape(String value) => value
      .replaceAll('\\', r'\\')
      .replaceAll('"', r'\"')
      .replaceAll('\r', r'\r')
      .replaceAll('\n', r'\n');

  @override
  String toString() => 'TtCommand($verb, $params)';
}
