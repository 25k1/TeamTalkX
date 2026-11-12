import 'dart:convert';

enum ServerListingType { local, official, public, unofficial }

class ServerEntry {
  const ServerEntry({
    this.name = '',
    this.host = '',
    this.tcpPort = defaultTcpPort,
    this.udpPort = defaultUdpPort,
    this.encrypted = false,
    this.username = '',
    this.password = '',
    this.nickname = '',
    this.statusMessage = '',
    this.channel = '',
    this.channelPassword = '',
    this.rememberLastChannel = false,
    this.favorite = false,
    this.connectOnStartup = false,
    this.lastConnected,
    this.listingType = ServerListingType.local,
    this.userCount = 0,
    this.country = '',
    this.motd = '',
  });

  static const defaultTcpPort = 10333;
  static const defaultUdpPort = 10333;

  final String name;
  final String host;
  final int tcpPort;
  final int udpPort;
  final bool encrypted;
  final String username;
  final String password;
  final String nickname;
  final String statusMessage;

  final String channel;
  final String channelPassword;
  final bool rememberLastChannel;

  final bool favorite;

  final bool connectOnStartup;

  final DateTime? lastConnected;

  final ServerListingType listingType;
  final int userCount;
  final String country;
  final String motd;

  String get displayName => name.isNotEmpty ? name : '$host:$tcpPort';

  ServerEntry copyWith({
    String? name,
    String? host,
    int? tcpPort,
    int? udpPort,
    bool? encrypted,
    String? username,
    String? password,
    String? nickname,
    String? statusMessage,
    String? channel,
    String? channelPassword,
    bool? rememberLastChannel,
    bool? favorite,
    bool? connectOnStartup,
    DateTime? lastConnected,
  }) => ServerEntry(
    name: name ?? this.name,
    host: host ?? this.host,
    tcpPort: tcpPort ?? this.tcpPort,
    udpPort: udpPort ?? this.udpPort,
    encrypted: encrypted ?? this.encrypted,
    username: username ?? this.username,
    password: password ?? this.password,
    nickname: nickname ?? this.nickname,
    statusMessage: statusMessage ?? this.statusMessage,
    channel: channel ?? this.channel,
    channelPassword: channelPassword ?? this.channelPassword,
    rememberLastChannel: rememberLastChannel ?? this.rememberLastChannel,
    favorite: favorite ?? this.favorite,
    connectOnStartup: connectOnStartup ?? this.connectOnStartup,
    lastConnected: lastConnected ?? this.lastConnected,
    listingType: listingType,
    userCount: userCount,
    country: country,
    motd: motd,
  );

  Map<String, dynamic> toJson() => {
    'name': name,
    'host': host,
    'tcpPort': tcpPort,
    'udpPort': udpPort,
    'encrypted': encrypted,
    'username': username,
    'password': password,
    'nickname': nickname,
    'statusMessage': statusMessage,
    'channel': channel,
    'channelPassword': channelPassword,
    'rememberLastChannel': rememberLastChannel,
    if (favorite) 'favorite': true,
    if (connectOnStartup) 'connectOnStartup': true,
    if (lastConnected case final t?)
      'lastConnected': t.toUtc().toIso8601String(),
  };

  factory ServerEntry.fromJson(Map<String, dynamic> json) => ServerEntry(
    name: json['name'] as String? ?? '',
    host: json['host'] as String? ?? '',
    tcpPort: json['tcpPort'] as int? ?? defaultTcpPort,
    udpPort: json['udpPort'] as int? ?? defaultUdpPort,
    encrypted: json['encrypted'] as bool? ?? false,
    username: json['username'] as String? ?? '',
    password: json['password'] as String? ?? '',
    nickname: json['nickname'] as String? ?? '',
    statusMessage: json['statusMessage'] as String? ?? '',
    channel: json['channel'] as String? ?? '',
    channelPassword: json['channelPassword'] as String? ?? '',
    rememberLastChannel: json['rememberLastChannel'] as bool? ?? false,
    favorite: json['favorite'] as bool? ?? false,
    connectOnStartup: json['connectOnStartup'] as bool? ?? false,
    lastConnected: DateTime.tryParse(json['lastConnected'] as String? ?? ''),
  );

  static String encodeList(List<ServerEntry> entries) =>
      jsonEncode([for (final e in entries) e.toJson()]);

  static List<ServerEntry> decodeList(String json) {
    final decoded = jsonDecode(json);
    if (decoded is! List) return const [];
    return [
      for (final item in decoded)
        if (item is Map<String, dynamic>) ServerEntry.fromJson(item),
    ];
  }
}
