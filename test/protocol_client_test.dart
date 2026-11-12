import 'package:flutter_test/flutter_test.dart';
import 'package:teamtalkx/src/domain/events.dart';
import 'package:teamtalkx/src/domain/server_state.dart';
import 'package:teamtalkx/src/protocol/command.dart';
import 'package:teamtalkx/src/protocol/protocol_client.dart';
import 'package:teamtalkx/src/protocol/wire_models.dart';

void main() {
  const dump = [
    'accepted userid=3717 userrights=3407871 usertype=2 username="carol"',
    'serverupdate servername="gozaltech.org" motd="Добро пожаловать" tcpport=10333',
    'addchannel channel="/" chanid=1 parentid=0 maxusers=1000 type=1',
    'addchannel channel="/Music request service/" chanid=2 parentid=1 '
        'name="Music request service" maxusers=1000 type=1',
    'addchannel channel="/Свободная зона/" chanid=3 parentid=1 '
        'name="Свободная зона" protected=1 type=1',
    'loggedin userid=3693 nickname="Carol" username="carol" statusmode=0',
    'loggedin userid=3706 nickname="Danstiv" username="Danstiv" statusmode=0',
    'adduser userid=3693 nickname="Carol" username="carol" chanid=3 statusmode=0',
    'addfile filename="test.apk" filesize=938 fileid=1 owner="carol" chanid=2',
  ];

  ServerState replay(Iterable<String> lines) {
    final state = ServerState();
    for (final line in lines) {
      final cmd = TtCommand.parse(line);
      for (final event in mapCommand(cmd, state)) {
        state.apply(event);
      }
    }
    return state;
  }

  test('login populates my identity', () {
    final state = replay(dump);
    expect(state.myUserId, 3717);
    expect(state.myUserRights, 3407871);
  });

  test('server info incl. Cyrillic MOTD', () {
    final state = replay(dump);
    expect(state.serverInfo.name, 'gozaltech.org');
    expect(state.serverInfo.motd, 'Добро пожаловать');
  });

  test('channel tree with names, parents and password flag', () {
    final state = replay(dump);
    expect(state.channels.length, 3);
    expect(state.channels[2]!.name, 'Music request service');
    expect(state.channels[2]!.parentId, 1);
    expect(state.channels[1]!.isRoot, isTrue);
    expect(state.channels[3]!.name, 'Свободная зона');
    expect(state.channels[3]!.hasPassword, isTrue);
  });

  test('users and channel membership', () {
    final state = replay(dump);
    expect(state.users.length, 2);
    expect(state.users[3693]!.nickname, 'Carol');
    expect(state.users[3693]!.channelId, 3);
    expect(state.usersInChannel(3).map((u) => u.id), [3693]);
  });

  test('files land in their channel', () {
    final state = replay(dump);
    expect(state.filesInChannel(2).single.fileName, 'test.apk');
    expect(state.filesInChannel(2).single.fileSize, 938);
  });

  test('a user leaving clears their channel but keeps them online', () {
    final state = replay([...dump, 'left userid=3693 chanid=3']);
    expect(state.users[3693]!.channelId, 0);
    expect(state.usersInChannel(3), isEmpty);
  });

  test('"joined" confirmation does not create a phantom id-0 user', () {
    final state = replay([
      ...dump,
      'joined chanid=3',
      'adduser userid=3717 nickname="carol" username="carol" chanid=3 statusmode=0',
    ]);
    expect(state.users.containsKey(0), isFalse);
    expect(state.users[3717]!.nickname, 'carol');
    expect(state.usersInChannel(3).map((u) => u.id), containsAll([3693, 3717]));
  });

  test('bare "left" without a userid is ignored', () {
    final state = replay([...dump, 'left chanid=3']);
    expect(state.users.containsKey(0), isFalse);
    expect(state.users[3693]!.channelId, 3);
  });

  test('serverupdate parses full server properties', () {
    final c = TtCommand.parse(
      'serverupdate servername="gozaltech.org" maxusers=1000 maxiplogins=0 '
      'logindelay=0 usertimeout=60 motd="hi" motdraw="hi %uptime%" '
      'maxloginattempts=10 autosave=1 tcpport=10333 udpport=10333 '
      'voicetxlimit=0 totaltxlimit=0 logevents=33554431 version="5.14"',
    );
    final p = serverPropsFromCommand(c);
    expect(p.serverName, 'gozaltech.org');
    expect(p.maxUsers, 1000);
    expect(p.maxLoginAttempts, 10);
    expect(p.userTimeout, 60);
    expect(p.motdRaw, 'hi %uptime%');
    expect(p.autoSave, isTrue);
    expect(p.tcpPort, 10333);
  });

  test('useraccount parses into a TtUserAccount', () {
    final c = TtCommand.parse(
      'useraccount username="carol" password="pw-test" usertype=2 '
      'userrights=259591 note="admin" opchannels="[8,12]" '
      'audiocodeclimit=0 cmdflood="[3,1000]"',
    );
    final a = accountFromCommand(c);
    expect(a.username, 'carol');
    expect(a.userType, 2);
    expect(a.userRights, 259591);
    expect(a.note, 'admin');
    expect(a.autoOperatorChannels, [8, 12]);
    expect(a.commandsLimit, 3);
    expect(a.commandsIntervalMSec, 1000);
  });

  test('useraccount maps to a UserAccountEvent', () {
    final events = mapCommand(
      TtCommand.parse('useraccount username="x" usertype=1'),
      ServerState(),
    );
    expect(events.single, isA<UserAccountEvent>());
  });

  test('updateuser without chanid keeps the user in their channel', () {
    final state = replay([
      ...dump,
      'updateuser userid=3693 nickname="Carol" statusmode=4096 statusmsg="brb"',
    ]);
    final carol = state.users[3693]!;
    expect(carol.channelId, 3);
    expect(carol.statusMode, 4096);
    expect(carol.statusMessage, 'brb');
    expect(carol.username, 'carol');
    expect(state.usersInChannel(3).map((u) => u.id), [3693]);
  });

  test('logout removes the user', () {
    final state = replay([...dump, 'loggedout userid=3706']);
    expect(state.users.containsKey(3706), isFalse);
    expect(state.users.length, 1);
  });

  test('a kick says whether it was from a channel or the server', () {
    final state = replay(dump);
    List<TtEvent> map(String line) => mapCommand(TtCommand.parse(line), state);

    final channelKick =
        map('kicked kickerid=3706 chanid=3').single as MyselfKickedEvent;
    expect(channelKick.fromServer, isFalse);
    expect(channelKick.channelId, 3);
    expect(channelKick.kicker?.nickname, 'Danstiv');

    final serverKick = map('kicked kickerid=3706').single as MyselfKickedEvent;
    expect(serverKick.fromServer, isTrue);
    expect(serverKick.channelId, isNull);
  });

  test('the server logging this client out ends the session', () {
    final state = replay(dump);

    expect(
      mapCommand(TtCommand.parse('loggedout'), state).single,
      isA<MyselfLoggedOutEvent>(),
    );
    expect(
      mapCommand(TtCommand.parse('loggedout userid=3706'), state).single,
      isA<UserLoggedOutEvent>(),
    );
  });
}
