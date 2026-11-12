import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:teamtalkx/src/audio/pure_voice_engine.dart';
import 'package:teamtalkx/src/domain/events.dart';
import 'package:teamtalkx/src/protocol/protocol_client.dart';

void main() {
  test('a server that never answers on UDP fails the start, '
      'and missing sound output is reported', () async {
    final silent = await RawDatagramSocket.bind(
      InternetAddress.loopbackIPv4,
      0,
    );
    addTearDown(silent.close);
    final proto = ProtocolClient();
    addTearDown(proto.dispose);
    final problems = <VoiceProblem>[];
    proto.events.listen((e) {
      if (e is VoiceProblemEvent) problems.add(e.problem);
    });
    final engine = PureVoiceEngine(proto);
    addTearDown(engine.stop);

    await expectLater(
      engine.start(host: '127.0.0.1', udpPort: silent.port),
      throwsA(isA<VoiceConnectionException>()),
    );
    await pumpEventQueue();

    expect(engine.playbackAvailable, isFalse);
    expect(problems, [VoiceProblem.playbackFailed]);
  }, timeout: const Timeout(Duration(seconds: 30)));
}
