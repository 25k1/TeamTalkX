library;

import 'package:xml/xml.dart';

import '../domain/server_entry.dart';

String encodeTtFile(List<ServerEntry> entries) {
  final builder = XmlBuilder();
  builder.processing('xml', 'version="1.0" encoding="UTF-8"');
  builder.element(
    'teamtalk',
    attributes: {'version': '5.0'},
    nest: () {
      for (final entry in entries) {
        builder.element(
          'host',
          nest: () {
            builder.element('name', nest: entry.name);
            builder.element('address', nest: entry.host);
            builder.element('tcpport', nest: entry.tcpPort.toString());
            builder.element('udpport', nest: entry.udpPort.toString());
            builder.element('encrypted', nest: entry.encrypted.toString());
            builder.element(
              'auth',
              nest: () {
                builder.element('username', nest: entry.username);
                builder.element('password', nest: entry.password);
                builder.element('nickname', nest: entry.nickname);
                builder.element('statusmsg', nest: entry.statusMessage);
              },
            );
            builder.element(
              'join',
              nest: () {
                builder.element(
                  'join-last-channel',
                  nest: entry.rememberLastChannel.toString(),
                );
                builder.element('channel', nest: entry.channel);
                builder.element('password', nest: entry.channelPassword);
              },
            );
          },
        );
      }
    },
  );
  return builder.buildDocument().toXmlString(pretty: true);
}

List<ServerEntry> decodeTtFile(String xml) {
  final XmlDocument document;
  try {
    document = XmlDocument.parse(xml);
  } on XmlException {
    return const [];
  }
  final entries = <ServerEntry>[];
  for (final host in document.findAllElements('host')) {
    String text(XmlElement scope, String tag, [String fallback = '']) =>
        scope.findElements(tag).firstOrNull?.innerText ?? fallback;
    bool flag(XmlElement scope, String tag) =>
        text(scope, tag).toLowerCase() == 'true';

    final auth = host.findElements('auth').firstOrNull;
    final join = host.findElements('join').firstOrNull;
    final stats = host.findElements('stats').firstOrNull;
    entries.add(
      ServerEntry(
        name: text(host, 'name'),
        host: text(host, 'address'),
        tcpPort:
            int.tryParse(text(host, 'tcpport')) ?? ServerEntry.defaultTcpPort,
        udpPort:
            int.tryParse(text(host, 'udpport')) ?? ServerEntry.defaultUdpPort,
        encrypted: flag(host, 'encrypted'),
        username: auth == null ? '' : text(auth, 'username'),
        password: auth == null ? '' : text(auth, 'password'),
        nickname: auth == null ? '' : text(auth, 'nickname'),
        statusMessage: auth == null ? '' : text(auth, 'statusmsg'),
        channel: join == null ? '' : text(join, 'channel'),
        channelPassword: join == null ? '' : text(join, 'password'),
        rememberLastChannel: join != null && flag(join, 'join-last-channel'),
        listingType: switch (text(host, 'listing')) {
          'official' => ServerListingType.official,
          'public' => ServerListingType.public,
          'private' => ServerListingType.unofficial,
          _ => ServerListingType.local,
        },
        userCount: stats == null
            ? 0
            : int.tryParse(text(stats, 'user-count')) ?? 0,
        country: stats == null ? '' : text(stats, 'country'),
        motd: stats == null ? '' : text(stats, 'motd'),
      ),
    );
  }
  return entries;
}

ServerEntry? parseTtLink(String url) {
  final uri = Uri.tryParse(url);
  if (uri == null || uri.scheme != 'tt' || uri.host.isEmpty) return null;
  final params = uri.queryParameters;
  final tcpPort =
      int.tryParse(params['tcpport'] ?? '') ?? ServerEntry.defaultTcpPort;
  final encrypted = (params['encrypted'] ?? '').toLowerCase();
  return ServerEntry(
    name: '${uri.host}:$tcpPort',
    host: uri.host,
    tcpPort: tcpPort,
    udpPort:
        int.tryParse(params['udpport'] ?? '') ?? ServerEntry.defaultUdpPort,
    username: params['username'] ?? '',
    password: params['password'] ?? '',
    channel: params['channel'] ?? '',
    channelPassword: params['chanpasswd'] ?? '',
    encrypted: encrypted == 'true' || encrypted == '1',
  );
}
