import 'package:flutter_test/flutter_test.dart';

import '../tool/coverage.dart';

void main() {
  final lcov = [
    r'SF:D:\work\lib\src\audio\a.dart',
    'DA:1,3',
    'DA:2,0',
    'end_of_record',
    'SF:/home/ci/lib/src/audio/dsp/b.dart',
    'DA:1,1',
    'DA:2,1',
    'end_of_record',
    'SF:lib/src/data/app_database.g.dart',
    'DA:1,0',
    'end_of_record',
    'SF:lib/src/l10n/generated/app_localizations.dart',
    'DA:1,0',
    'end_of_record',
    'SF:lib/main.dart',
    'DA:1,0',
    'end_of_record',
    'SF:lib/src/ui/c.dart',
    'DA:1,0',
    'DA:2,1',
    'end_of_record',
  ];

  test('lines are counted per layer, without generated code', () {
    expect(coverageByLayer(lcov), {
      'audio': (lines: 4, hit: 3),
      'ui': (lines: 2, hit: 1),
    });
  });

  test('a layer below its threshold fails', () {
    final report = checkCoverage(coverageByLayer(lcov), {
      'audio': 75,
      'ui': 51,
    });
    expect(report.failures, ['ui: 50.0 % is below 51 %']);
    expect(report.table, contains('| audio | 75.0 % | 4 | 75 % |'));
  });

  test('a layer without a threshold, or without data, fails', () {
    final report = checkCoverage(coverageByLayer(lcov), {
      'audio': 0,
      'data': 0,
    });
    expect(report.failures, [
      'data has no coverage data',
      'ui has no threshold in tool/coverage.dart',
    ]);
  });
}
