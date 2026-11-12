import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:teamtalkx/src/data/passphrase_box.dart';

void main() {
  test('opens with the passphrase only', () async {
    final box = await PassphraseBox.seal('hunter2 ქართული', 'correct horse');
    expect(jsonEncode(box), isNot(contains('hunter2')));
    expect(box['iterations'], PassphraseBox.iterations);
    expect(await PassphraseBox.open(box, 'correct horse'), 'hunter2 ქართული');
    await expectLater(
      PassphraseBox.open(box, 'wrong'),
      throwsA(isA<WrongPassphrase>()),
    );
  });

  test('a tampered box is refused', () async {
    final box = await PassphraseBox.seal('x', 'p', iterations: 1000);
    final data = base64Decode(box['data']! as String)..[0] ^= 1;
    await expectLater(
      PassphraseBox.open({...box, 'data': base64Encode(data)}, 'p'),
      throwsA(isA<WrongPassphrase>()),
    );
    await expectLater(
      PassphraseBox.open({...box, 'kdf': 'rot13'}, 'p'),
      throwsA(isA<FormatException>()),
    );
  });
}
