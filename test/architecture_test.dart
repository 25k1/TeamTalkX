import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

const _allowed = <String, Set<String>>{
  'domain': {'domain'},
  'diagnostics': {'diagnostics'},
  'protocol': {'protocol', 'domain', 'diagnostics'},
  'audio': {'audio', 'protocol', 'domain', 'diagnostics'},
  'data': {'data', 'domain', 'platform', 'diagnostics'},
  'platform': {'platform', 'domain', 'diagnostics'},
  'app': {
    'app',
    'domain',
    'protocol',
    'audio',
    'data',
    'platform',
    'diagnostics',
    'l10n',
  },
  'ui': {'ui', 'app', 'domain', 'diagnostics', 'l10n'},
  'l10n': {'l10n', 'domain'},
};

bool _forbiddenInDomain(String uri) =>
    uri.startsWith('package:') ||
    const {'dart:io', 'dart:ui', 'dart:ffi', 'dart:isolate'}.contains(uri);

final _directive = RegExp(r"^(?:import|export)\s+'([^']+)'", multiLine: true);

String _layerOf(String path) => path.split('/')[2];

Set<String> _violations() {
  final found = <String>{};
  final files = Directory('lib/src')
      .listSync(recursive: true)
      .whereType<File>()
      .where((f) => f.path.endsWith('.dart'));
  for (final file in files) {
    final from = file.path.replaceAll(r'\', '/');
    final layer = _layerOf(from);
    final allowed = _allowed[layer];
    expect(allowed, isNotNull, reason: '$from is in no known layer');
    for (final match in _directive.allMatches(file.readAsStringSync())) {
      final uri = match.group(1)!;
      final String? target;
      if (uri.startsWith('package:teamtalkx/')) {
        target = 'lib/${uri.substring('package:teamtalkx/'.length)}';
      } else if (uri.contains(':')) {
        if (layer == 'domain' && _forbiddenInDomain(uri)) {
          found.add('$from -> $uri');
        }
        target = null;
      } else {
        target = Uri.file(
          from,
        ).resolve(uri).path.replaceFirst(RegExp('^/'), '');
      }
      if (target != null && !allowed!.contains(_layerOf(target))) {
        found.add('$from -> $target');
      }
    }
  }
  return found;
}

void main() {
  test('imports follow the layer dependency rule', () {
    expect(
      _violations(),
      isEmpty,
      reason:
          'Imports break the layer rule (docs/ARCHITECTURE.md, section 2). '
          'Move the code to the right layer.',
    );
  });
}
