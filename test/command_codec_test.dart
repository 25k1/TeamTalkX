import 'package:flutter_test/flutter_test.dart';
import 'package:teamtalkx/src/protocol/command.dart';

void main() {
  group('TtCommand.parse', () {
    test('verb only', () {
      final cmd = TtCommand.parse('pong');
      expect(cmd.verb, 'pong');
      expect(cmd.params, isEmpty);
    });

    test('mixed string, int and quoted-with-spaces', () {
      final cmd = TtCommand.parse(
        'login nickname="Bob B" username="" protocol="5.14" id=7',
      );
      expect(cmd.verb, 'login');
      expect(cmd.getString('nickname'), 'Bob B');
      expect(cmd.getString('username'), '');
      expect(cmd.getString('protocol'), '5.14');
      expect(cmd.getInt('id'), 7);
    });

    test('unescapes backslash and quote', () {
      final cmd = TtCommand.parse(r'msg content="say \"hi\" \\ end"');
      expect(cmd.getString('content'), r'say "hi" \ end');
    });

    test('int list and bool', () {
      final cmd = TtCommand.parse('addchannel operators=[1,2,3] protected=1');
      expect(cmd.getIntList('operators'), [1, 2, 3]);
      expect(cmd.getIntList('missing'), isEmpty);
      expect(cmd.getBool('protected'), isTrue);
      expect(cmd.getBool('missing'), isFalse);
    });
  });

  group('TtCommand.encode', () {
    test('escapes and types values', () {
      final line = TtCommand('login')
          .set('nickname', 'Bob "B"')
          .set('username', '')
          .set('protocol', teamTalkProtocolVersion)
          .set('id', 7)
          .encode();
      expect(
        line,
        'login nickname="Bob \\"B\\"" username="" protocol="5.14" id=7\r\n',
      );
    });

    test('bool and int list', () {
      final line = TtCommand(
        'addchannel',
      ).set('operators', [1, 2, 3]).set('protected', true).encode();
      expect(line, 'addchannel operators=[1,2,3] protected=1\r\n');
    });

    test('round trips through parse', () {
      final original = TtCommand(
        'joined',
      ).set('chanid', 5).set('topic', r'weird \ " chars').encode();
      final parsed = TtCommand.parse(original.trimRight());
      expect(parsed.verb, 'joined');
      expect(parsed.getInt('chanid'), 5);
      expect(parsed.getString('topic'), r'weird \ " chars');
    });

    test('escapes CR/LF so newlines cannot break the wire line', () {
      final line = TtCommand('message').set('content', 'typing\r\n1').encode();
      expect(
        line,
        r'message content="typing\r\n1"'
        '\r\n',
      );
      expect('\n'.allMatches(line).length, 1);

      final parsed = TtCommand.parse(line.trimRight());
      expect(parsed.getString('content'), 'typing\r\n1');
    });
  });
}
