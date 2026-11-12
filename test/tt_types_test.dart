import 'package:flutter_test/flutter_test.dart';
import 'package:teamtalkx/src/domain/tt_types.dart';

void main() {
  test('audio codec values match the wire format', () {
    expect(AudioCodecType.values.map((c) => c.value), [0, 1, 2, 3]);
    expect(AudioCodecType.fromValue(3), AudioCodecType.opus);
    expect(AudioCodecType.fromValue(128), AudioCodecType.none);
  });

  test('server log events are distinct single bits in ascending order', () {
    final bits = ServerLogEvent.values.map((e) => e.value).toList();

    for (var i = 0; i < bits.length; i++) {
      expect(bits[i], 1 << i, reason: ServerLogEvent.values[i].name);
    }
  });

  test('combined flags are the union of their parts', () {
    expect(
      UserRights.transmitMediaFile,
      UserRights.transmitMediaFileAudio | UserRights.transmitMediaFileVideo,
    );
    expect(
      UserStates.mediaFile,
      UserStates.mediaFileAudio | UserStates.mediaFileVideo,
    );
  });
}
