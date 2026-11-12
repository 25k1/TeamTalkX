import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teamtalkx/src/app/third_party_licenses.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('each native library is registered with its license text', () async {
    LicenseRegistry.reset();
    registerThirdPartyLicenses();

    final entries = await LicenseRegistry.licenses.toList();
    final byPackage = {
      for (final e in entries)
        for (final p in e.packages)
          p: e.paragraphs.map((p) => p.text).join('\n'),
    };

    expect(
      byPackage.keys,
      containsAll(<String>[
        'Opus',
        'Speex',
        'RNNoise',
        'Oboe',
        'Sonic',
        'Silero VAD',
        'AndroidX',
        'Kotlin standard library',
      ]),
    );
    expect(byPackage['Opus'], contains('Xiph.Org'));
    expect(byPackage['Speex'], contains('Jean-Marc Valin'));
    expect(byPackage['RNNoise'], contains('Jean-Marc Valin'));
    expect(byPackage['Oboe'], contains('The Android Open Source Project'));
    expect(byPackage['Oboe'], contains('Apache License'));
    expect(byPackage['Sonic'], contains('Bill Cox'));
    expect(byPackage['Silero VAD'], contains('Silero Team'));
    expect(byPackage.keys, isNot(contains('ONNX Runtime')));
  });
}
