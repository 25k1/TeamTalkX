@Tags(['e2e'])
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:teamtalkx/src/domain/events.dart';
import 'package:teamtalkx/src/domain/models.dart';
import 'package:teamtalkx/src/domain/tt_types.dart';
import 'package:teamtalkx/src/protocol/channel_wire.dart';
import 'package:teamtalkx/src/protocol/protocol_client.dart';

import 'support/e2e_server.dart';

Future<int> _createChannel(ProtocolClient admin, TtChannelConfig cfg) async {
  final created = nextEvent<ChannelNewEvent>(
    admin,
    (e) => e.channel.name == cfg.name,
  );
  await admin.saveChannel(cfg, parentId: E2eChannel.root);
  final id = (await created).channel.id;
  addTearDown(() async {
    if (admin.isConnected) await admin.removeChannel(id);
  });
  return id;
}

void main() {
  group('channels', skip: e2eSkip, () {
    test('reads the codec of every fixture channel', () async {
      final client = await loginAs(E2eAccount.admin);

      final stereo = client.channelConfig(E2eChannel.opusStereo)!.codec;
      expect(stereo.codec, AudioCodecType.opus);
      expect(stereo.opusChannels, 2);
      expect(stereo.opusApplication, TtAudioCodec.opusApplicationAudio);
      expect(stereo.opusBitrate, 64000);
      expect(stereo.opusFrameSizeMSec, 20);
      expect(stereo.opusTxIntervalMSec, 20);

      final speex = client.channelConfig(E2eChannel.speex)!.codec;
      expect(speex.codec, AudioCodecType.speex);
      expect(speex.speexBandmode, 1);
      expect(speex.speexQuality, 4);
      expect(speex.speexTxIntervalMSec, 40);

      final vbr = client.channelConfig(E2eChannel.speexVbr)!.codec;
      expect(vbr.codec, AudioCodecType.speexVbr);
      expect(vbr.speexVbrBandmode, 2);
      expect(vbr.speexVbrQuality, 6);
      expect(vbr.speexVbrDtx, isTrue);
      expect(vbr.speexVbrTxIntervalMSec, 40);

      expect(client.state.channels[E2eChannel.locked]!.hasPassword, isTrue);
      expect(client.channelConfig(E2eChannel.files)!.diskQuotaKB, 10240);
    });

    for (final codec in const [
      TtAudioCodec(opusChannels: 2, opusBitrate: 48000, opusDtx: false),
      TtAudioCodec(codec: AudioCodecType.speex, speexQuality: 7),
      TtAudioCodec(codec: AudioCodecType.speexVbr, speexVbrBandmode: 2),
    ]) {
      test('a new ${codec.codec.name} channel reads back unchanged', () async {
        final admin = await loginAs(E2eAccount.admin);
        final cfg = TtChannelConfig(
          name: uniqueName(codec.codec.name),
          topic: 'Round trip',
          password: 'pw',
          opPassword: 'oppw',
          maxUsers: 12,
          diskQuotaKB: 2048,
          permanent: true,
          noRecording: true,
          agcEnabled: true,
          gainLevel: 6000,
          codec: codec,
        );

        final id = await _createChannel(admin, cfg);

        expect(
          channelWireProperties(admin.channelConfig(id)!),
          channelWireProperties(cfg),
        );
      });
    }

    test('editing one property keeps all the others', () async {
      final admin = await loginAs(E2eAccount.admin);
      final cfg = TtChannelConfig(
        name: uniqueName('edit'),
        password: 'secret',
        opPassword: 'opsecret',
        maxUsers: 25,
        diskQuotaKB: 1024,
        permanent: true,
        classroom: true,
        codec: const TtAudioCodec(codec: AudioCodecType.speex),
      );
      final id = await _createChannel(admin, cfg);

      final updated = nextEvent<ChannelUpdateEvent>(
        admin,
        (e) => e.channel.id == id,
      );
      await admin.saveChannel(
        admin.channelConfig(id)!.copyWith(topic: 'New topic'),
        channelId: id,
      );
      await updated;

      expect(
        channelWireProperties(admin.channelConfig(id)!),
        channelWireProperties(cfg.copyWith(topic: 'New topic')),
      );
    });
  });
}
