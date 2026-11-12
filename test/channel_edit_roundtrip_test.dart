import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:teamtalkx/src/app/pure_teamtalk_client.dart';
import 'package:teamtalkx/src/domain/events.dart';
import 'package:teamtalkx/src/domain/tt_types.dart';
import 'package:teamtalkx/src/protocol/command.dart';

void main() {
  late ServerSocket server;
  late List<TtCommand> received;

  setUp(() async {
    received = [];
    server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((socket) {
      socket.done.ignore();
      socket.write(
        'teamtalk userid=1 protocol="5.14"\r\n'
        'addchannel channel="/" chanid=1 parentid=0 maxusers=1000 type=1 '
        'diskquota=0 audiocfg=[0,8000] '
        'audiocodec=[3,48000,1,2048,10,1,1,32000,1,0,1920,1]\r\n'
        'addchannel channel="/Room/" chanid=2 parentid=1 name="Room" '
        'password="secret" oppassword="opsecret" protected=1 topic="Hi" '
        'diskquota=10485760 maxusers=25 type=33 userdata=7 '
        'audiocodec=[1,1,6,2,0] audiocfg=[1,6000]\r\n',
      );
      socket
          .cast<List<int>>()
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen((line) {
            final cmd = TtCommand.parse(line);
            received.add(cmd);
            final id = cmd.getInt('id');
            socket.write('begin id=$id\r\nend id=$id\r\n');
          }, onError: (Object _) {});
    });
  });

  tearDown(() => server.close());

  Future<PureTeamTalkClient> connectedClient() async {
    final client = PureTeamTalkClient();
    addTearDown(client.logout);
    final room = client.events.firstWhere(
      (e) => e is ChannelNewEvent && e.channel.id == 2,
    );
    await client.connect('127.0.0.1', tcpPort: server.port);
    await room;
    return client;
  }

  test('the edit form starts from the full channel configuration', () async {
    final client = await connectedClient();

    final cfg = client.getChannelConfig(2);

    expect(cfg.name, 'Room');
    expect(cfg.topic, 'Hi');
    expect(cfg.password, 'secret');
    expect(cfg.opPassword, 'opsecret');
    expect(cfg.diskQuotaKB, 10240);
    expect(cfg.maxUsers, 25);
    expect(cfg.permanent, isTrue);
    expect(cfg.noRecording, isTrue);
    expect(cfg.gainLevel, 6000);
    expect(cfg.codec.codec, AudioCodecType.speex);
    expect(cfg.codec.speexQuality, 6);
    expect(cfg.codec.speexTxIntervalMSec, 40);
  });

  test('saving an edited topic sends only the topic', () async {
    final client = await connectedClient();
    final edited = client.getChannelConfig(2).copyWith(topic: 'New topic');

    await client.saveChannel(edited, channelId: 2);

    final cmd = received.singleWhere((c) => c.verb == 'updatechannel');
    expect(cmd.getInt('chanid'), 2);
    expect(cmd.getString('topic'), 'New topic');
    expect(cmd.params.keys.toSet(), {
      'chanid',
      'topic',
      'id',
    }, reason: 'password, type, quota, codec and user data must be left alone');
  });
}
