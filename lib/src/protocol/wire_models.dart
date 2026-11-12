import '../domain/models.dart';
import 'command.dart';

TtServerInfo serverInfoFromCommand(TtCommand c) => TtServerInfo(
  name: c.getString('servername') ?? '',
  motd: c.getString('motd') ?? '',
);

TtServerProperties serverPropsFromCommand(TtCommand c) {
  return TtServerProperties(
    serverName: c.getString('servername') ?? '',
    motd: c.getString('motd') ?? '',
    motdRaw: c.getString('motdraw') ?? '',
    maxUsers: c.getInt('maxusers') ?? 0,
    maxLoginAttempts: c.getInt('maxloginattempts') ?? 0,
    maxLoginsPerIpAddress: c.getInt('maxiplogins') ?? 0,
    loginDelayMSec: c.getInt('logindelay') ?? 0,
    maxVoiceTxPerSecond: c.getInt('voicetxlimit') ?? 0,
    maxVideoTxPerSecond: c.getInt('videotxlimit') ?? 0,
    maxMediaFileTxPerSecond: c.getInt('mediafiletxlimit') ?? 0,
    maxDesktopTxPerSecond: c.getInt('desktoptxlimit') ?? 0,
    maxTotalTxPerSecond: c.getInt('totaltxlimit') ?? 0,
    autoSave: c.getBool('autosave'),
    tcpPort: c.getInt('tcpport') ?? 0,
    udpPort: c.getInt('udpport') ?? 0,
    userTimeout: c.getInt('usertimeout') ?? 0,
    serverVersion: c.getString('version') ?? '',
    protocolVersion: c.getString('protocol') ?? '',
    serverLogEvents: c.getInt('logevents') ?? 0,
  );
}

TtBannedUser banFromCommand(TtCommand c) => TtBannedUser(
  ipAddress: c.getString('ipaddr') ?? '',
  channelPath: c.getString('channel') ?? '',
  banTime: c.getString('bantime') ?? '',
  nickname: c.getString('nickname') ?? '',
  username: c.getString('username') ?? '',
  banTypes: c.getInt('type') ?? 0,
);

TtUserAccount accountFromCommand(TtCommand c) {
  final flood = c.getIntList('cmdflood');
  return TtUserAccount(
    username: c.getString('username') ?? '',
    password: c.getString('password') ?? '',
    userType: c.getInt('usertype') ?? 1,
    userRights: c.getInt('userrights') ?? 0,
    note: c.getString('note') ?? '',
    initChannel: c.getString('initchan') ?? '',
    autoOperatorChannels: c.getIntList('opchannels'),
    audioCodecBpsLimit: c.getInt('audiocodeclimit') ?? 0,
    commandsLimit: flood.isNotEmpty ? flood[0] : 0,
    commandsIntervalMSec: flood.length > 1 ? flood[1] : 0,
  );
}

TtChannel channelFromCommand(TtCommand c) => TtChannel(
  id: c.getInt('chanid') ?? 0,
  parentId: c.getInt('parentid') ?? 0,
  name: c.getString('name') ?? '',
  topic: c.getString('topic') ?? '',
  hasPassword: c.getBool('protected'),
  maxUsers: c.getInt('maxusers') ?? 0,
  channelType: c.getInt('type') ?? 0,
  operators: c.getIntList('operators').toSet(),
  voiceUsers: c.getIntList('voiceusers').toSet(),
  mediaFileUsers: c.getIntList('mediafileusers').toSet(),
);

TtUser userFromCommand(TtCommand c, {int? channelId}) => TtUser(
  id: c.getInt('userid') ?? 0,
  username: c.getString('username') ?? '',
  nickname: c.getString('nickname') ?? '',
  statusMessage: c.getString('statusmsg') ?? '',
  channelId: channelId ?? c.getInt('chanid') ?? 0,
  userState: 0,
  userType: c.getInt('usertype') ?? 0,
  clientName: c.getString('clientname') ?? '',
  statusMode: c.getInt('statusmode') ?? 0,
  localSubscriptions: c.getInt('sublocal') ?? 0,
);

TtUser userMergedFromCommand(TtUser existing, TtCommand c) => existing.copyWith(
  username: c.getString('username'),
  nickname: c.getString('nickname'),
  statusMessage: c.getString('statusmsg'),
  channelId: c.getInt('chanid'),
  userType: c.getInt('usertype'),
  clientName: c.getString('clientname'),
  statusMode: c.getInt('statusmode'),
  localSubscriptions: c.getInt('sublocal'),
);

TtRemoteFile fileFromCommand(TtCommand c) => TtRemoteFile(
  channelId: c.getInt('chanid') ?? 0,
  fileId: c.getInt('fileid') ?? 0,
  fileName: c.getString('filename') ?? '',
  fileSize: c.getInt('filesize') ?? 0,
  username: c.getString('owner') ?? '',
  uploadTime: c.getString('uploadtime') ?? '',
);

TtTextMessage textMessageFromCommand(TtCommand c) => TtTextMessage(
  type: TtMsgType.fromValue(c.getInt('type') ?? 0),
  fromUserId: c.getInt('srcuserid') ?? 0,
  fromUsername: c.getString('username') ?? '',
  toUserId: c.getInt('destuserid') ?? 0,
  channelId: c.getInt('chanid') ?? 0,
  text: c.getString('content') ?? '',
  more: (c.getInt('more') ?? 0) != 0,
);

TtServerStats serverStatsFromCommand(TtCommand c) => TtServerStats(
  totalTx: c.getInt('totaltx') ?? 0,
  totalRx: c.getInt('totalrx') ?? 0,
  voiceTx: c.getInt('voicetx') ?? 0,
  voiceRx: c.getInt('voicerx') ?? 0,
  mediaFileTx: c.getInt('mediafiletx') ?? 0,
  mediaFileRx: c.getInt('mediafilerx') ?? 0,
  filesTx: c.getInt('filestx') ?? 0,
  filesRx: c.getInt('filesrx') ?? 0,
  usersServed: c.getInt('usersserved') ?? 0,
  usersSpoke: c.getInt('userspeak') ?? 0,
  uptime: Duration(milliseconds: c.getInt('uptime') ?? 0),
);
