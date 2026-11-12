import 'dart:io';

const thresholds = <String, double>{
  'app': 69,
  'audio': 79,
  'data': 88,
  'diagnostics': 80,
  'domain': 90,
  'l10n': 98,
  'platform': 17,
  'protocol': 82,
  'ui': 59,
};

final _generated = [RegExp(r'\.g\.dart$'), RegExp(r'^lib/src/l10n/generated/')];

typedef LayerCoverage = ({int lines, int hit});

Map<String, LayerCoverage> coverageByLayer(Iterable<String> lcov) {
  final result = <String, LayerCoverage>{};
  String? layer;
  for (final line in lcov) {
    if (line.startsWith('SF:')) {
      final path = line.substring(3).replaceAll(r'\', '/');
      final at = path.indexOf('lib/src/');
      final relative = at < 0 ? path : path.substring(at);
      layer = at < 0 || _generated.any((p) => p.hasMatch(relative))
          ? null
          : relative.split('/')[2];
    } else if (line.startsWith('DA:') && layer != null) {
      final hits = int.parse(line.substring(3).split(',')[1]);
      final old = result[layer] ?? (lines: 0, hit: 0);
      result[layer] = (lines: old.lines + 1, hit: old.hit + (hits > 0 ? 1 : 0));
    }
  }
  return result;
}

({String table, List<String> failures}) checkCoverage(
  Map<String, LayerCoverage> layers,
  Map<String, double> floors,
) {
  final failures = <String>[];
  final rows = <String>[];
  for (final name in {...floors.keys, ...layers.keys}.toList()..sort()) {
    final lines = layers[name]?.lines ?? 0;
    final percent = lines == 0 ? 0.0 : 100 * layers[name]!.hit / lines;
    final floor = floors[name];
    final String status;
    if (floor == null) {
      status = 'none';
      failures.add('$name has no threshold in tool/coverage.dart');
    } else if (lines == 0) {
      status = 'no data';
      failures.add('$name has no coverage data');
    } else if (percent < floor) {
      status = 'below ${floor.toStringAsFixed(0)} %';
      failures.add(
        '$name: ${percent.toStringAsFixed(1)} % is below '
        '${floor.toStringAsFixed(0)} %',
      );
    } else {
      status = '${floor.toStringAsFixed(0)} %';
    }
    rows.add('| $name | ${percent.toStringAsFixed(1)} % | $lines | $status |');
  }
  final table = [
    '| Layer | Coverage | Lines | Threshold |',
    '|---|---|---|---|',
    ...rows,
  ].join('\n');
  return (table: table, failures: failures);
}

void main(List<String> args) {
  var input = 'coverage/lcov.info';
  String? summaryPath;
  for (var i = 0; i < args.length; i++) {
    if (args[i] == '--summary' && i + 1 < args.length) {
      summaryPath = args[++i];
    } else {
      input = args[i];
    }
  }

  final report = checkCoverage(
    coverageByLayer(File(input).readAsLinesSync()),
    thresholds,
  );
  stdout.writeln(report.table);
  if (summaryPath != null) {
    File(summaryPath).writeAsStringSync(
      '### Coverage by layer\n\n${report.table}\n\n',
      mode: FileMode.append,
    );
  }
  if (report.failures.isNotEmpty) {
    stderr.writeln(report.failures.join('\n'));
    exitCode = 1;
  }
}
