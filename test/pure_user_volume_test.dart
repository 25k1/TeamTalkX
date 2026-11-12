import 'package:flutter_test/flutter_test.dart';
import 'package:teamtalkx/src/app/pure_teamtalk_client.dart';
import 'package:teamtalkx/src/domain/sound_level.dart';
import 'package:teamtalkx/src/protocol/packet.dart';

void main() {
  group('the volume scale (D132)', () {
    test('1000 is 100 %, the top is 300 %', () {
      expect(volumeFromPercent(100), volumeNormal);
      expect(volumeFromPercent(300), 3000);
      expect(volumeFromPercent(500), 3000, reason: 'capped');
      expect(volumeToPercent(1500), 150);
      expect(gainFromVolume(volumeNormal), 1.0);
      expect(gainFromVolume(3000), 3.0);
      expect(gainFromVolume(32000), 3.0, reason: 'capped');
    });
  });

  group('PureTeamTalkClient per-user audio', () {
    test('setUserVolume then getUserVolume round-trips', () {
      final client = PureTeamTalkClient();
      expect(client.getUserVolume(42), volumeNormal);
      expect(client.setUserVolume(42, 1500), isTrue);
      expect(client.getUserVolume(42), 1500);
      expect(client.getUserVolume(42, media: true), volumeNormal);
      expect(client.setUserVolume(42, 2000, media: true), isTrue);
      expect(client.getUserVolume(42, media: true), 2000);
    });

    test('isUserMuted / setUserMute round-trip independently per stream', () {
      final client = PureTeamTalkClient();
      expect(client.isUserMuted(7), isFalse);
      expect(client.setUserMute(7, muted: true), isTrue);
      expect(client.isUserMuted(7), isTrue);
      expect(client.isUserMuted(7, media: true), isFalse);
      client.setUserMute(7, muted: true, media: true);
      expect(client.isUserMuted(7, media: true), isTrue);
    });

    test('resolveUserGain returns 1.0 when nothing is set', () {
      final client = PureTeamTalkClient();
      expect(client.resolveUserGain(1, packetKindVoice), 1.0);
    });

    test('resolveUserGain is the percentage as a linear gain', () {
      final client = PureTeamTalkClient()
        ..setUserVolume(1, volumeFromPercent(50));
      expect(client.resolveUserGain(1, packetKindVoice), 0.5);
      client.setUserVolume(1, volumeFromPercent(250));
      expect(client.resolveUserGain(1, packetKindVoice), 2.5);
    });

    test('resolveUserGain returns 0.0 for muted voice stream', () {
      final client = PureTeamTalkClient()
        ..setUserVolume(1, volumeFromPercent(200), media: true)
        ..setUserMute(1, muted: true);
      expect(client.resolveUserGain(1, packetKindVoice), 0.0);
      expect(client.resolveUserGain(1, packetKindMediaFileAudio), 2.0);
    });

    test('resolveUserGain distinguishes voice vs media', () {
      final client = PureTeamTalkClient()
        ..setUserVolume(1, volumeFromPercent(150))
        ..setUserVolume(1, volumeFromPercent(80), media: true);
      expect(client.resolveUserGain(1, packetKindVoice), 1.5);
      expect(client.resolveUserGain(1, packetKindMediaFileAudio), 0.8);
      client
        ..setUserMute(1, muted: true)
        ..setUserMute(1, muted: true, media: true);
      expect(client.resolveUserGain(1, packetKindVoice), 0.0);
      expect(client.resolveUserGain(1, packetKindMediaFileAudio), 0.0);
    });

    test('resolveUserGain stops at 300 %', () {
      final client = PureTeamTalkClient()..setUserVolume(1, soundVolumeMax);
      expect(client.resolveUserGain(1, packetKindVoice), 3.0);
    });
  });
}
