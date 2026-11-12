import 'package:flutter_test/flutter_test.dart';
import 'package:teamtalkx/src/data/tt_format.dart';
import 'package:teamtalkx/src/domain/server_entry.dart';

const _androidClientXml = '''
<?xml version='1.0' encoding='UTF-8' standalone='yes' ?>
<teamtalk version="5.0">
  <host>
    <name>My Server</name>
    <address>voice.example.com</address>
    <tcpport>10333</tcpport>
    <udpport>10444</udpport>
    <encrypted>true</encrypted>
    <auth>
      <username>beka</username>
      <password>secret</password>
      <nickname>ბექა</nickname>
      <statusmsg>hi</statusmsg>
    </auth>
    <join>
      <join-last-channel>true</join-last-channel>
      <channel>/Lobby/</channel>
      <password>chanpw</password>
    </join>
  </host>
  <host>
    <name>Second</name>
    <address>other.example.com</address>
    <tcpport>10333</tcpport>
    <udpport>10333</udpport>
    <encrypted>false</encrypted>
  </host>
</teamtalk>
''';

void main() {
  group('.tt XML', () {
    test('parses Android-client formatted XML', () {
      final entries = decodeTtFile(_androidClientXml);
      expect(entries, hasLength(2));
      final first = entries[0];
      expect(first.name, 'My Server');
      expect(first.host, 'voice.example.com');
      expect(first.tcpPort, 10333);
      expect(first.udpPort, 10444);
      expect(first.encrypted, isTrue);
      expect(first.username, 'beka');
      expect(first.password, 'secret');
      expect(first.nickname, 'ბექა');
      expect(first.statusMessage, 'hi');
      expect(first.channel, '/Lobby/');
      expect(first.channelPassword, 'chanpw');
      expect(first.rememberLastChannel, isTrue);
      expect(entries[1].encrypted, isFalse);
      expect(entries[1].username, '');
    });

    test('round-trips through toTtXml/fromTtXml', () {
      final original = decodeTtFile(_androidClientXml);
      final roundTripped = decodeTtFile(encodeTtFile(original));
      expect(roundTripped, hasLength(original.length));
      for (var i = 0; i < original.length; i++) {
        expect(roundTripped[i].toJson(), original[i].toJson());
      }
    });

    test('returns empty list on malformed XML', () {
      expect(decodeTtFile('not xml'), isEmpty);
      expect(decodeTtFile('<teamtalk/>'), isEmpty);
    });
  });

  group('bearware.dk public list XML', () {
    const publicListXml = '''
<?xml version="1.0" encoding="UTF-8" ?><teamtalk version="5.0"><host><id>205</id><joincode>abcdefgh</joincode><listing>official</listing><name>TeamTalk 5 Official Server (EU)</name><address>tt5eu.bearware.dk</address><tcpport>10335</tcpport><udpport>10335</udpport><encrypted>false</encrypted><auth><username>guest</username><password>guest</password></auth><join><channel>/</channel><password></password></join><stats><user-count>8</user-count><country>DE</country><servername>TeamTalk 5 Server (EU)</servername><motd>Welcome!</motd><active>true</active></stats></host><host><listing>private</listing><name>Community</name><address>c.example.com</address><tcpport>10333</tcpport><udpport>10333</udpport><encrypted>false</encrypted></host></teamtalk>
''';

    test('parses listing type and stats', () {
      final entries = decodeTtFile(publicListXml);
      expect(entries, hasLength(2));
      expect(entries[0].listingType, ServerListingType.official);
      expect(entries[0].userCount, 8);
      expect(entries[0].country, 'DE');
      expect(entries[0].motd, 'Welcome!');
      expect(entries[0].username, 'guest');
      expect(entries[0].channel, '/');
      expect(entries[1].listingType, ServerListingType.unofficial);
      expect(entries[1].userCount, 0);
    });
  });

  group('tt:// URLs', () {
    test('parses full URL like ServerListActivity does', () {
      final entry = parseTtLink(
        'tt://voice.example.com?tcpport=10444&udpport=10555'
        '&username=guest&password=pw&channel=/Lobby/&chanpasswd=cpw'
        '&encrypted=1',
      );
      expect(entry, isNotNull);
      expect(entry!.host, 'voice.example.com');
      expect(entry.tcpPort, 10444);
      expect(entry.udpPort, 10555);
      expect(entry.username, 'guest');
      expect(entry.password, 'pw');
      expect(entry.channel, '/Lobby/');
      expect(entry.channelPassword, 'cpw');
      expect(entry.encrypted, isTrue);
      expect(entry.name, 'voice.example.com:10444');
    });

    test('defaults ports and treats missing params as empty', () {
      final entry = parseTtLink('tt://h.example.com');
      expect(entry!.tcpPort, ServerEntry.defaultTcpPort);
      expect(entry.udpPort, ServerEntry.defaultUdpPort);
      expect(entry.encrypted, isFalse);
      expect(entry.username, '');
    });

    test('rejects other schemes and empty hosts', () {
      expect(parseTtLink('http://x.example.com'), isNull);
      expect(parseTtLink('tt://'), isNull);
    });
  });

  group('JSON persistence', () {
    test('encode/decode round trip', () {
      final entries = decodeTtFile(_androidClientXml);
      final decoded = ServerEntry.decodeList(ServerEntry.encodeList(entries));
      expect(decoded, hasLength(entries.length));
      expect(decoded[0].toJson(), entries[0].toJson());
    });

    test('decode tolerates garbage', () {
      expect(ServerEntry.decodeList('{"not":"a list"}'), isEmpty);
    });
  });
}
