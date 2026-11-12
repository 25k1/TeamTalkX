import 'package:flutter_test/flutter_test.dart';
import 'package:teamtalkx/src/domain/models.dart';
import 'package:teamtalkx/src/domain/tt_types.dart';
import 'package:teamtalkx/src/protocol/channel_wire.dart';
import 'package:teamtalkx/src/protocol/command.dart';

void main() {
  group('audio codec wire format', () {
    test('Opus round-trips through the wire list', () {
      const codec = TtAudioCodec(
        opusSampleRate: 48000,
        opusChannels: 2,
        opusApplication: TtAudioCodec.opusApplicationAudio,
        opusComplexity: 7,
        opusFec: false,
        opusDtx: false,
        opusBitrate: 64000,
        opusVbr: false,
        opusVbrConstraint: true,
        opusFrameSizeMSec: 20,
        opusTxIntervalMSec: 60,
      );

      final wire = audioCodecToWire(codec);

      expect(wire, [3, 48000, 2, 2049, 7, 0, 0, 64000, 0, 1, 960, 3]);
      expect(audioCodecToWire(audioCodecFromWire(wire)), wire);
      final back = audioCodecFromWire(wire);
      expect(back.opusFrameSizeMSec, 20);
      expect(back.opusTxIntervalMSec, 60);
    });

    test('Opus "auto" frame size uses one frame per transmit interval', () {
      const codec = TtAudioCodec(opusFrameSizeMSec: 0, opusTxIntervalMSec: 40);

      final wire = audioCodecToWire(codec);

      expect(wire.sublist(10), [1920, 1]);
    });

    test('a 2.5 ms Opus frame survives a round-trip', () {
      final wire = [3, 48000, 1, 2048, 10, 1, 1, 32000, 1, 0, 120, 8];

      final codec = audioCodecFromWire(wire);

      expect(codec.opusFrameSizeMSec, 2);
      expect(codec.opusTxIntervalMSec, 20);
      expect(audioCodecToWire(codec), wire);
    });

    test('Speex rounds the transmit interval up to whole 20 ms frames', () {
      const codec = TtAudioCodec(
        codec: AudioCodecType.speex,
        speexBandmode: 2,
        speexQuality: 8,
        speexTxIntervalMSec: 50,
      );

      expect(audioCodecToWire(codec), [1, 2, 8, 3, 0]);
      final back = audioCodecFromWire([1, 2, 8, 3, 0]);
      expect(back.codec, AudioCodecType.speex);
      expect(back.speexBandmode, 2);
      expect(back.speexQuality, 8);
      expect(back.speexTxIntervalMSec, 60);
    });

    test('Speex VBR uses the server field order', () {
      const codec = TtAudioCodec(
        codec: AudioCodecType.speexVbr,
        speexVbrBandmode: 1,
        speexVbrQuality: 6,
        speexVbrMaxBitRate: 24000,
        speexVbrDtx: false,
        speexVbrTxIntervalMSec: 40,
      );

      final wire = audioCodecToWire(codec);

      expect(wire, [2, 1, 6, 0, 24000, 0, 2, 0]);
      expect(audioCodecToWire(audioCodecFromWire(wire)), wire);
    });

    test('an unknown codec decodes as no codec', () {
      expect(audioCodecFromWire([9, 1, 2]).codec, AudioCodecType.none);
      expect(audioCodecFromWire(const []).codec, AudioCodecType.none);
    });
  });

  group('channel config from server commands', () {
    const addLine =
        'addchannel channel="/Room/" chanid=2 parentid=1 name="Room" '
        'password="secret" oppassword="opsecret" protected=1 topic="Hi" '
        'diskquota=10485760 maxusers=25 type=97 userdata=0 '
        'audiocodec=[3,48000,1,2048,10,1,1,32000,1,0,1920,1] audiocfg=[1,6000]';

    test('addchannel fills every editable property', () {
      final cfg = channelConfigFromCommand(TtCommand.parse(addLine));

      expect(cfg.name, 'Room');
      expect(cfg.topic, 'Hi');
      expect(cfg.password, 'secret');
      expect(cfg.opPassword, 'opsecret');
      expect(cfg.diskQuotaKB, 10240);
      expect(cfg.maxUsers, 25);
      expect(cfg.permanent, isTrue);
      expect(cfg.noRecording, isTrue);
      expect(cfg.hidden, isTrue);
      expect(cfg.classroom, isFalse);
      expect(cfg.soloTransmit, isFalse);
      expect(cfg.channelTypeMask, 97);
      expect(cfg.agcEnabled, isTrue);
      expect(cfg.gainLevel, 6000);
      expect(cfg.codec.codec, AudioCodecType.opus);
      expect(cfg.codec.opusFrameSizeMSec, 40);
      expect(cfg.codec.opusTxIntervalMSec, 40);
    });

    test('updatechannel without passwords keeps the known ones', () {
      final base = channelConfigFromCommand(TtCommand.parse(addLine));

      final cfg = channelConfigFromCommand(
        TtCommand.parse(
          'updatechannel chanid=2 name="Room" protected=1 topic="Bye" '
          'diskquota=10485760 maxusers=25 type=1 userdata=0 audiocfg=[0,8000]',
        ),
        base: base,
      );

      expect(cfg.topic, 'Bye');
      expect(cfg.password, 'secret');
      expect(cfg.opPassword, 'opsecret');
      expect(cfg.channelTypeMask, 1);
      expect(cfg.agcEnabled, isFalse);
      expect(cfg.codec.opusFrameSizeMSec, 40, reason: 'codec not resent');
    });
  });

  group('channel commands', () {
    final current = channelConfigFromCommand(
      TtCommand.parse(
        'addchannel chanid=2 parentid=1 name="Room" password="secret" '
        'oppassword="op" topic="Hi" diskquota=1048576 maxusers=10 type=1 '
        'audiocodec=[3,48000,1,2048,10,1,1,32000,1,0,1920,1] audiocfg=[1,8000]',
      ),
    );

    test('an update sends only what changed', () {
      final cmd = updateChannelCommand(
        2,
        current.copyWith(topic: 'New topic'),
        current: current,
      );

      expect(cmd.encode(), 'updatechannel chanid=2 topic="New topic"\r\n');
    });

    test('an update with no changes touches nothing', () {
      final cmd = updateChannelCommand(2, current, current: current);

      expect(cmd.params.keys, ['chanid']);
    });

    test('a changed codec or flag is sent', () {
      final cmd = updateChannelCommand(
        2,
        current.copyWith(
          permanent: false,
          codec: current.codec.copyWith(opusBitrate: 48000),
        ),
        current: current,
      );

      expect(cmd.params.keys, ['chanid', 'audiocodec', 'type']);
      expect(cmd.getInt('type'), 0);
    });

    test('an update for an unknown channel sends every property', () {
      final cmd = updateChannelCommand(2, current);

      expect(cmd.params.keys, [
        'chanid',
        'name',
        'password',
        'topic',
        'diskquota',
        'oppassword',
        'maxusers',
        'audiocodec',
        'audiocfg',
        'type',
      ]);
    });

    test('makechannel carries the full configuration', () {
      final cmd = makeChannelCommand(current, parentId: 1);

      expect(cmd.verb, 'makechannel');
      expect(cmd.getInt('parentid'), 1);
      expect(cmd.getString('password'), 'secret');
      expect(cmd.getInt('diskquota'), 1048576);
      expect(cmd.getInt('type'), 1);
      expect(cmd.getIntList('audiocodec'), audioCodecToWire(current.codec));
      expect(cmd.getInt('userdata'), 0);
    });
  });
}
