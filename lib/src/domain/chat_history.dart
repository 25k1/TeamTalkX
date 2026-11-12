library;

enum StoredMessageKind { channel, broadcast, private }

class StoredMessage {
  const StoredMessage({
    this.id,
    required this.server,
    required this.conversation,
    required this.kind,
    required this.sender,
    required this.fromMe,
    required this.text,
    required this.time,
    this.read = false,
  });

  final int? id;
  final String server;
  final String conversation;
  final StoredMessageKind kind;
  final String sender;
  final bool fromMe;
  final String text;
  final DateTime time;
  final bool read;
}

class ChatServerSummary {
  const ChatServerSummary({
    required this.server,
    required this.name,
    required this.messages,
  });

  final String server;
  final String name;
  final int messages;
}

String channelConversation(String channelPath) => 'c:$channelPath';

String privateConversation({
  required String username,
  required String nickname,
}) => username.isNotEmpty ? 'u:$username' : 'n:$nickname';

String chatServerKey(String host, int port) => '${host.toLowerCase()}:$port';
