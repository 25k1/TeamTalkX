import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import '../domain/certificate.dart';
import '../domain/events.dart';
import '../domain/failure.dart';
import '../domain/models.dart';
import '../domain/server_state.dart';
import 'channel_wire.dart';
import 'command.dart';
import 'file_transfer.dart';
import 'long_text.dart';
import 'tt_connection.dart';
import 'voice_crypt.dart';
import 'wire_models.dart';

class ProtocolClient {
  ProtocolClient({CertificateTrust trust = const AuthorityTrustOnly()})
    : _trust = trust,
      _conn = TtConnection(trust: trust);

  final CertificateTrust _trust;
  final TtConnection _conn;
  final ServerState state = ServerState();
  final StreamController<TtEvent> _events =
      StreamController<TtEvent>.broadcast();
  StreamSubscription<TtCommand>? _sub;
  bool _loggedOut = false;

  Stream<TtEvent> get events => _events.stream;
  bool get isConnected => _conn.isConnected;

  InternetAddress? get serverAddress => _conn.remoteAddress;

  int udpPort = 0;

  TtServerProperties? serverProperties;

  int myUserType = 0;

  final Map<int, List<int>> channelCodecs = {};

  final _cryptKeys = ChannelCryptKeys();

  Uint8List? voiceCryptKey(int channelId) =>
      _encrypted ? _cryptKeys[channelId] : null;

  final Map<int, TtChannelConfig> _channelConfigs = {};

  TtChannelConfig? channelConfig(int channelId) => _channelConfigs[channelId];

  String _host = '';
  int _tcpPort = 0;
  bool _encrypted = false;

  final Map<int, FileTransferNode> _transfers = {};
  final Map<int, TtFileTransfer> _transferInfo = {};

  final Map<int, _PendingTransfer> _pendingTransfers = {};

  Completer<TtServerStats>? _stats;

  final TextReassembler _texts = TextReassembler();

  int? _replyCmdId;

  final Random _random = Random.secure();

  Future<void> connect({
    required String host,
    required int tcpPort,
    bool encrypted = false,
  }) async {
    state.clear();
    channelCodecs.clear();
    _cryptKeys.clear();
    _channelConfigs.clear();
    _pendingTransfers.clear();
    _texts.clear();
    _replyCmdId = null;
    _loggedOut = false;
    _host = host;
    _tcpPort = tcpPort;
    _encrypted = encrypted;

    final welcome = _conn.commands.firstWhere(
      (c) => c.verb == 'teamtalk',
      orElse: () => TtCommand('__closed__'),
    );
    _conn.onClosed = _onConnectionDone;
    await _conn.connect(host, tcpPort, encrypted: encrypted);
    await _sub?.cancel();
    _sub = _conn.commands.listen(_onCommand);
    _emit(const ConSuccessEvent());

    final w = await welcome.timeout(const Duration(seconds: 10));
    if (w.verb == '__closed__') {
      throw const ServerClosedConnection();
    }
  }

  Future<void> login({
    required String nickname,
    required String username,
    required String password,
    String clientName = 'TeamTalkDart',
    String version = '5.14.0.0',
  }) async {
    final loggedIn = events.firstWhere(
      (e) => e is MyselfLoggedInEvent,
      orElse: () => const MyselfLoggedOutEvent(),
    );
    await _conn.sendCommand(
      TtCommand('login')
          .set('nickname', nickname)
          .set('username', username)
          .set('password', password)
          .set('clientname', clientName)
          .set('protocol', teamTalkProtocolVersion)
          .set('version', version),
    );
    final r = await loggedIn.timeout(const Duration(seconds: 10));
    if (r is! MyselfLoggedInEvent) {
      throw const NotConnected();
    }
  }

  Future<void> connectAndLogin({
    required String host,
    required int tcpPort,
    bool encrypted = false,
    required String nickname,
    required String username,
    required String password,
    String clientName = 'TeamTalkDart',
    String version = '5.14.0.0',
  }) async {
    await connect(host: host, tcpPort: tcpPort, encrypted: encrypted);
    await login(
      nickname: nickname,
      username: username,
      password: password,
      clientName: clientName,
      version: version,
    );
  }

  void _onCommand(TtCommand c) {
    _cryptKeys.onCommand(c);
    switch (c.verb) {
      case 'serverupdate':
        udpPort = c.getInt('udpport') ?? udpPort;
        serverProperties = serverPropsFromCommand(c);
      case 'accepted':
        myUserType = c.getInt('usertype') ?? myUserType;
      case 'addchannel':
      case 'updatechannel':
        final id = c.getInt('chanid') ?? 0;
        final codec = c.getIntList('audiocodec');
        if (codec.isNotEmpty) channelCodecs[id] = codec;
        _channelConfigs[id] = channelConfigFromCommand(
          c,
          base: c.verb == 'updatechannel' ? _channelConfigs[id] : null,
        );
      case 'removechannel':
        final id = c.getInt('chanid');
        channelCodecs.remove(id);
        _channelConfigs.remove(id);
      case 'begin':
        _replyCmdId = c.getInt('id');
      case 'fileaccepted':
        _onFileAccepted(c.getInt('transferid') ?? 0);
      case 'stats':
        _stats?.complete(serverStatsFromCommand(c));
        _stats = null;
    }
    for (var event in mapCommand(c, state)) {
      if (event is UserTextMessageEvent) {
        final whole = _texts.add(event.message);
        if (whole == null) continue;
        event = UserTextMessageEvent(whole);
      }
      state.apply(event);
      _emit(event);
    }
    _conn.resolveReply(c);
    if (c.verb == 'end') _replyCmdId = null;
  }

  void _onConnectionDone() {
    if (!_loggedOut) _emit(const ConLostEvent());
  }

  void _emit(TtEvent event) {
    if (!_events.isClosed) _events.add(event);
  }

  void applyLocalEvent(TtEvent event) {
    state.apply(event);
    _emit(event);
  }

  Future<void> joinChannel(int channelId, {String password = ''}) =>
      _conn.sendCommand(
        TtCommand('join').set('chanid', channelId).set('password', password),
      );

  Future<void> leaveChannel() => _conn.sendCommand(TtCommand('leave'));

  Future<void> sendChannelMessage(int channelId, String text) =>
      _sendText(text, (c) => c.set('type', 2).set('chanid', channelId));

  Future<void> sendUserMessage(int userId, String text) =>
      _sendText(text, (c) => c.set('type', 1).set('destuserid', userId));

  Future<void> sendBroadcastMessage(String text) =>
      _sendText(text, (c) => c.set('type', 3));

  Future<void> sendCustomMessage(int userId, String text) =>
      _sendText(text, (c) => c.set('type', 4).set('destuserid', userId));

  Future<void> _sendText(
    String text,
    TtCommand Function(TtCommand) address,
  ) async {
    final parts = splitText(text);
    for (final (i, part) in parts.indexed) {
      final command = address(TtCommand('message')).set('content', part);
      if (i < parts.length - 1) command.set('more', 1);
      await _conn.sendCommand(command);
    }
  }

  Future<void> changeNickname(String nickname) =>
      _conn.sendCommand(TtCommand('changenick').set('nickname', nickname));

  Future<void> changeStatus(int statusMode, String statusMessage) =>
      _conn.sendCommand(
        TtCommand(
          'changestatus',
        ).set('statusmode', statusMode).set('statusmsg', statusMessage),
      );

  Future<void> subscribe(int userId, int subscriptions) => _conn.sendCommand(
    TtCommand('subscribe').set('userid', userId).set('sublocal', subscriptions),
  );

  Future<void> unsubscribe(int userId, int subscriptions) => _conn.sendCommand(
    TtCommand(
      'unsubscribe',
    ).set('userid', userId).set('sublocal', subscriptions),
  );

  Future<void> listUserAccounts({int index = 0, int count = 1000}) =>
      _conn.sendCommand(
        TtCommand('listaccounts').set('index', index).set('count', count),
        timeout: listCommandTimeout,
      );

  Future<void> createUserAccount(TtUserAccount a) => _conn.sendCommand(
    TtCommand('newaccount')
        .set('username', a.username)
        .set('password', a.password)
        .set('usertype', a.userType)
        .set('userrights', a.userRights)
        .set('userdata', 0)
        .set('note', a.note)
        .set('initchan', a.initChannel)
        .set('opchannels', a.autoOperatorChannels)
        .set('audiocodeclimit', a.audioCodecBpsLimit)
        .set('cmdflood', [a.commandsLimit, a.commandsIntervalMSec]),
  );

  Future<void> deleteUserAccount(String username) =>
      _conn.sendCommand(TtCommand('delaccount').set('username', username));

  Future<void> listBans({int channelId = 0, int index = 0, int count = 1000}) {
    final cmd = TtCommand('listbans').set('index', index).set('count', count);
    if (channelId > 0) cmd.set('chanid', channelId);
    return _conn.sendCommand(cmd, timeout: listCommandTimeout);
  }

  Future<void> banUser(int userId, {int channelId = 0, int banTypes = 0x02}) =>
      _conn.sendCommand(
        TtCommand(
          'ban',
        ).set('userid', userId).set('chanid', channelId).set('type', banTypes),
      );

  Future<void> addBan({
    String ipAddress = '',
    String username = '',
    String channelPath = '',
    required int banTypes,
  }) => _conn.sendCommand(
    TtCommand('ban')
        .set('ipaddr', ipAddress)
        .set('username', username)
        .set('channel', channelPath)
        .set('type', banTypes),
  );

  Future<void> unbanUser(TtBannedUser ban) => _conn.sendCommand(
    TtCommand('unban')
        .set('ipaddr', ban.ipAddress)
        .set('username', ban.username)
        .set('channel', ban.channelPath)
        .set('type', ban.banTypes),
  );

  Future<void> kickUser(int userId, {int channelId = 0}) => _conn.sendCommand(
    TtCommand('kick').set('chanid', channelId).set('userid', userId),
  );

  Future<void> moveUser(int userId, int channelId) => _conn.sendCommand(
    TtCommand('moveuser').set('userid', userId).set('chanid', channelId),
  );

  Future<void> channelOperator(
    int userId,
    int channelId, {
    required bool makeOperator,
    String password = '',
  }) {
    final command = TtCommand('op')
        .set('chanid', channelId)
        .set('userid', userId)
        .set('opstatus', makeOperator);
    if (password.isNotEmpty) command.set('oppassword', password);
    return _conn.sendCommand(command);
  }

  Future<void> setTransmitUsers(
    int channelId, {
    required Set<int> voice,
    required Set<int> mediaFiles,
  }) => _conn.sendCommand(
    TtCommand('updatechannel')
        .set('chanid', channelId)
        .set('voiceusers', voice.toList()..sort())
        .set('mediafileusers', mediaFiles.toList()..sort()),
  );

  Future<TtServerStats> queryServerStats() async {
    final stats = _stats = Completer<TtServerStats>();
    await _conn.sendCommand(TtCommand('querystats'));
    return stats.future.timeout(defaultCommandTimeout);
  }

  Future<void> removeChannel(int channelId) =>
      _conn.sendCommand(TtCommand('removechannel').set('chanid', channelId));

  Future<void> saveChannel(
    TtChannelConfig cfg, {
    int? parentId,
    int? channelId,
  }) => _conn.sendCommand(
    channelId != null
        ? updateChannelCommand(
            channelId,
            cfg,
            current: _channelConfigs[channelId],
          )
        : makeChannelCommand(cfg, parentId: parentId ?? 0),
  );

  Future<void> deleteFile(int channelId, String fileName) => _conn.sendCommand(
    TtCommand('deletefile').set('chanid', channelId).set('filename', fileName),
  );

  Future<void> sendFile(int channelId, String localPath) async {
    final fileName = localPath.split(RegExp(r'[\\/]')).last;
    final fileSize = await File(localPath).length();
    final key = _transferKey();
    await _registerTransfer(
      TtCommand('regsendfile')
          .set('filename', fileName)
          .set('filesize', fileSize)
          .set('chanid', channelId)
          .set('filetxkey', key),
      _PendingTransfer(
        inbound: false,
        channelId: channelId,
        localPath: localPath,
        remoteFileName: fileName,
        fileSize: fileSize,
        transferKey: key,
      ),
    );
  }

  Future<void> recvFile(
    int channelId,
    int fileId,
    String localPath,
    String fileName,
    int fileSize,
  ) async {
    final key = _transferKey();
    await _registerTransfer(
      TtCommand('regrecvfile')
          .set('filename', fileName)
          .set('chanid', channelId)
          .set('filetxkey', key),
      _PendingTransfer(
        inbound: true,
        channelId: channelId,
        localPath: localPath,
        remoteFileName: fileName,
        fileSize: fileSize,
        transferKey: key,
      ),
    );
  }

  Future<void> _registerTransfer(
    TtCommand cmd,
    _PendingTransfer pending,
  ) async {
    final reply = _conn.sendCommand(cmd);
    final id = cmd.getInt('id');
    if (id != null) _pendingTransfers[id] = pending;
    try {
      await reply;
    } finally {
      if (id != null) _pendingTransfers.remove(id);
    }
  }

  void _onFileAccepted(int transferId) {
    final cmdId = _replyCmdId;
    if (transferId == 0 || cmdId == null) return;
    final p = _pendingTransfers.remove(cmdId);
    if (p == null) return;
    final node = FileTransferNode(
      host: _host,
      port: _tcpPort,
      encrypted: _encrypted,
      transferId: transferId,
      channelId: p.channelId,
      localPath: p.localPath,
      remoteFileName: p.remoteFileName,
      fileSize: p.fileSize,
      inbound: p.inbound,
      transferKey: p.transferKey,
      trust: _trust,
      onStatus: (t) {
        _transferInfo[t.transferId] = t;
        _emit(FileTransferEvent(t));
        if (t.status == TtFileTransferStatus.finished ||
            t.status == TtFileTransferStatus.error ||
            t.status == TtFileTransferStatus.closed) {
          _transfers.remove(t.transferId);
        }
      },
    );
    _transfers[transferId] = node;
    unawaited(node.start());
  }

  TtFileTransfer? fileTransferInfo(int transferId) => _transferInfo[transferId];

  bool cancelFileTransfer(int transferId) {
    final node = _transfers.remove(transferId);
    if (node == null) return false;
    node.cancel();
    return true;
  }

  String _transferKey() {
    final bytes = List<int>.generate(16, (_) => _random.nextInt(256));
    return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }

  Future<void> updateServer(TtServerProperties p) => _conn.sendCommand(
    TtCommand('updateserver')
        .set('servername', p.serverName)
        .set('motdraw', p.motdRaw)
        .set('maxusers', p.maxUsers)
        .set('maxloginattempts', p.maxLoginAttempts)
        .set('maxiplogins', p.maxLoginsPerIpAddress)
        .set('logindelay', p.loginDelayMSec)
        .set('autosave', p.autoSave)
        .set('tcpport', p.tcpPort)
        .set('udpport', p.udpPort)
        .set('usertimeout', p.userTimeout)
        .set('voicetxlimit', p.maxVoiceTxPerSecond)
        .set('videotxlimit', p.maxVideoTxPerSecond)
        .set('mediafiletxlimit', p.maxMediaFileTxPerSecond)
        .set('desktoptxlimit', p.maxDesktopTxPerSecond)
        .set('totaltxlimit', p.maxTotalTxPerSecond)
        .set('logevents', p.serverLogEvents),
  );

  Future<void> disconnect() async {
    _loggedOut = true;
    final open = [..._transfers.values];
    _transfers.clear();
    for (final node in open) {
      node.cancel();
    }
    _pendingTransfers.clear();
    await _conn.close();
    await _sub?.cancel();
    _emit(const MyselfLoggedOutEvent());
  }

  Future<void> dispose() async {
    await _sub?.cancel();
    await _conn.dispose();
    if (!_events.isClosed) await _events.close();
    state.dispose();
  }
}

class _PendingTransfer {
  _PendingTransfer({
    required this.inbound,
    required this.channelId,
    required this.localPath,
    required this.remoteFileName,
    required this.fileSize,
    required this.transferKey,
  });
  final bool inbound;
  final int channelId;
  final String localPath;
  final String remoteFileName;
  final int fileSize;
  final String transferKey;
}

List<TtEvent> mapCommand(TtCommand c, ServerState state) {
  switch (c.verb) {
    case 'accepted':
      return [
        MyselfLoggedInEvent(
          c.getInt('userid') ?? 0,
          userRights: c.getInt('userrights') ?? 0,
          initChannel: c.getString('initchan') ?? '',
        ),
      ];
    case 'serverupdate':
      return [ServerUpdateEvent(serverInfoFromCommand(c))];
    case 'addchannel':
      return [ChannelNewEvent(channelFromCommand(c))];
    case 'updatechannel':
      return [ChannelUpdateEvent(channelFromCommand(c))];
    case 'removechannel':
      final id = c.getInt('chanid') ?? 0;
      return [ChannelRemoveEvent(state.channels[id] ?? channelFromCommand(c))];
    case 'loggedin':
      return [UserLoggedInEvent(userFromCommand(c, channelId: 0))];
    case 'loggedout':
      final id = c.getInt('userid') ?? 0;
      if (id == 0 || id == state.myUserId) {
        return const [MyselfLoggedOutEvent()];
      }
      return [UserLoggedOutEvent(state.users[id] ?? userFromCommand(c))];
    case 'adduser':
      return [UserJoinedEvent(userFromCommand(c))];
    case 'joined':
      return const [];
    case 'updateuser':
      final existing = state.users[c.getInt('userid') ?? 0];
      return [
        UserUpdateEvent(
          existing != null
              ? userMergedFromCommand(existing, c)
              : userFromCommand(c),
        ),
      ];
    case 'removeuser':
    case 'left':
      final id = c.getInt('userid') ?? 0;
      if (id == 0) return const [];
      final channelId = c.getInt('chanid') ?? 0;
      final existing = state.users[id];
      final user = existing != null
          ? existing.copyWith(channelId: 0)
          : userFromCommand(c, channelId: 0);
      return [UserLeftEvent(channelId, user)];
    case 'useraccount':
      return [UserAccountEvent(accountFromCommand(c))];
    case 'userbanned':
      return [BannedUserEvent(banFromCommand(c))];
    case 'addfile':
      return [FileNewEvent(fileFromCommand(c))];
    case 'removefile':
      final chanId = c.getInt('chanid') ?? 0;
      final name = c.getString('filename') ?? '';
      final existing = state
          .filesInChannel(chanId)
          .where((f) => f.fileName == name)
          .firstOrNull;
      return [FileRemoveEvent(existing ?? fileFromCommand(c))];
    case 'messagedeliver':
      return [UserTextMessageEvent(textMessageFromCommand(c))];
    case 'kicked':
      final channelId = c.getInt('chanid');
      return [
        MyselfKickedEvent(
          state.users[c.getInt('kickerid') ?? 0],
          channelId: channelId != null && channelId > 0 ? channelId : null,
        ),
      ];
    default:
      return const [];
  }
}
