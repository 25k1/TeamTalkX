import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../diagnostics/log.dart';
import '../../domain/events.dart';
import '../../domain/failure.dart';
import '../../domain/server_entry.dart';
import '../../domain/sound_level.dart';
import '../../domain/teamtalk_client.dart';
import '../../l10n/failure_messages.dart';
import '../../protocol/tt_connection.dart';
import '../announcer.dart';
import '../app_info.dart';
import '../failures.dart';
import '../platform_services.dart';
import '../pure_teamtalk_client.dart';
import '../security/certificate_trust.dart';
import '../servers/bearware_login.dart';
import '../servers/server_list_providers.dart';
import '../settings/event_config.dart';
import '../settings/event_dispatcher.dart';
import '../settings/locale_providers.dart';
import '../settings/settings_providers.dart';
import 'notification_text.dart';
import 'reconnect_policy.dart';

final teamTalkClientProvider = Provider<TeamTalkClient>((ref) {
  final client = PureTeamTalkClient(
    appVersion: ref.read(appVersionProvider),
    trust: ref.read(certificateTrustProvider),
  );
  ref.onDispose(client.dispose);
  return client;
});

final serverStateTickProvider = StreamProvider<int>(
  (ref) => ref.watch(teamTalkClientProvider).state.changes,
);

sealed class ConnectionState {
  const ConnectionState();
}

final class Disconnected extends ConnectionState {
  const Disconnected({this.reason});

  final DisconnectReason? reason;
}

final class Connecting extends ConnectionState {
  const Connecting();
}

final class LoggingIn extends ConnectionState {
  const LoggingIn();
}

final class LoggedIn extends ConnectionState {
  const LoggedIn(this.myUserId);
  final int myUserId;
}

final class Reconnecting extends ConnectionState {
  const Reconnecting({
    required this.attempt,
    this.retryAt,
    this.waitingForNetwork = false,
    this.lastFailure,
  });

  final int attempt;

  final DateTime? retryAt;

  final bool waitingForNetwork;

  final TtFailure? lastFailure;
}

sealed class DisconnectReason {
  const DisconnectReason();
}

final class ConnectFailed extends DisconnectReason {
  const ConnectFailed(this.failure);
  final TtFailure failure;
}

final class CertificateNotTrusted extends DisconnectReason {
  const CertificateNotTrusted(this.failure, this.entry, {this.listIndex});
  final UntrustedCertificate failure;
  final ServerEntry entry;
  final int? listIndex;
}

final class KickedFromServer extends DisconnectReason {
  const KickedFromServer({this.by});

  final String? by;
}

class ConnectCancelled implements Exception {
  const ConnectCancelled();

  @override
  String toString() => 'ConnectCancelled';
}

final connectionProvider = NotifierProvider<SessionController, ConnectionState>(
  SessionController.new,
);

class SessionController extends Notifier<ConnectionState> {
  ServerEntry? _entry;
  int? _entryIndex;
  StreamSubscription<TtEvent>? _eventSub;
  StreamSubscription<bool>? _networkSub;
  Timer? _retryTimer;

  int _attempt = 0;

  int _loggedInAttempt = 0;

  int _failures = 0;
  bool _online = true;

  String _currentChannelPath = '';
  int _manualJoinTargetId = 0;
  String _manualJoinPassword = '';
  String _accountInitChannel = '';

  bool _establishing = false;
  bool _joining = false;

  bool get suppressAnnouncements => _establishing || _joining;

  ReconnectScheduler get _scheduler => ref.read(reconnectSchedulerProvider);

  @override
  ConnectionState build() {
    final client = ref.watch(teamTalkClientProvider);
    unawaited(_eventSub?.cancel());
    _eventSub = client.events.listen(_onEvent);
    final connectivity = ref.read(connectivityProvider);
    unawaited(_networkSub?.cancel());
    _networkSub = connectivity.changes.listen(_onNetwork);
    unawaited(connectivity.isOnline().then((online) => _online = online));
    ref.onDispose(() {
      unawaited(_eventSub?.cancel());
      unawaited(_networkSub?.cancel());
      _retryTimer?.cancel();
    });
    return const Disconnected();
  }

  TeamTalkClient get _client => ref.read(teamTalkClientProvider);

  ServerEntry? get currentEntry => _entry;

  String? get currentServerKey {
    final entry = _entry;
    return entry == null ? null : '${entry.host}:${entry.tcpPort}';
  }

  Future<void> joinChannel(int channelId, {String password = ''}) async {
    _joining = true;
    _manualJoinTargetId = channelId;
    _manualJoinPassword = password;
    try {
      await _client.joinChannel(channelId, password: password);
    } on Object {
      _manualJoinTargetId = 0;
      rethrow;
    } finally {
      _joining = false;
    }
  }

  Future<void> connect(ServerEntry entry, {int? listIndex}) async {
    final attempt = _newAttempt();
    _failures = 0;
    _client.disconnect();
    _entry = entry;
    _entryIndex = listIndex;
    _currentChannelPath = '';
    _manualJoinTargetId = 0;
    _accountInitChannel = '';
    state = const Connecting();
    try {
      await _establish(entry, attempt, reconnect: false);
    } on ConnectCancelled {
      if (_loggedInAttempt == attempt &&
          (state is Reconnecting || state is LoggedIn)) {
        return;
      }
      rethrow;
    } on Object catch (e) {
      _end(_failed(failureFrom(e), entry, listIndex));
      rethrow;
    }
  }

  DisconnectReason _failed(TtFailure failure, ServerEntry entry, int? index) =>
      failure is UntrustedCertificate
      ? CertificateNotTrusted(failure, entry, listIndex: index)
      : ConnectFailed(failure);

  Future<void> disconnect() async {
    appLog.i('connection', 'Disconnected by the user');
    _end(null);
  }

  int _newAttempt() {
    _retryTimer?.cancel();
    _retryTimer = null;
    _establishing = false;
    return ++_attempt;
  }

  void _end(DisconnectReason? reason) {
    _newAttempt();
    _failures = 0;
    _entry = null;
    _entryIndex = null;
    _establishing = false;
    _client.setVoiceTransmission(enabled: false);
    _client.setVoiceActivation(enabled: false);
    _client.disconnect();
    state = Disconnected(reason: reason);
    unawaited(ref.read(foregroundServiceProvider).stop());
  }

  Future<void> _establish(
    ServerEntry entry,
    int attempt, {
    required bool reconnect,
  }) async {
    void ensureCurrent() {
      if (attempt != _attempt) throw const ConnectCancelled();
    }

    final client = _client;
    _establishing = true;
    appLog.i(
      'connection',
      '${reconnect ? 'Reconnecting' : 'Connecting'} to '
          '${entry.host}:${entry.tcpPort} (UDP ${entry.udpPort}'
          '${entry.encrypted ? ', encrypted' : ''})',
    );
    try {
      await client.connect(
        entry.host,
        tcpPort: entry.tcpPort,
        udpPort: entry.udpPort,
        encrypted: entry.encrypted,
      );
      ensureCurrent();
      if (!reconnect) state = const LoggingIn();
      var username = entry.username;
      if (isWebLogin(username)) {
        final account = ref.read(bearwareAccountProvider);
        if (!account.isLinked) throw const WebLoginRequired();
        username = await resolveWebLoginUsername(
          account,
          client.serverAccessToken,
        );
        ensureCurrent();
      }
      final settings = ref.read(settingsProvider);
      await client.login(
        nickname: entry.nickname.isNotEmpty
            ? entry.nickname
            : settings.nickname,
        username: username,
        password: entry.password,
      );
      ensureCurrent();
      client
        ..setMasterVolume(volumeFromPercent(settings.masterVolumePercent))
        ..setMediaPlaybackVolume(settings.mediaVolumePercent)
        ..setPlaybackNormalization(enabled: settings.normalizeSpeakers)
        ..setVoiceQuality(settings.voiceQuality)
        ..setMicrophoneGain(refGain(settings.microphoneGainPercent.toDouble()))
        ..setVoiceActivationLevel(settings.voiceActivationLevel);
      client
          .changeStatus(
            settings.gender.statusBits | settings.status.statusBits,
            settings.statusMessage,
          )
          .ignore();
      state = LoggedIn(client.myUserId);
      _loggedInAttempt = attempt;
      unawaited(ref.read(serverListProvider.notifier).markConnected(entry));
      appLog.i('connection', 'Logged in as user ${client.myUserId}');
      final l10n = ref.read(appLocalizationsProvider);
      if (reconnect) {
        ref.read(announcerProvider).announce(l10n.connectionReconnected);
      }
      await ref
          .read(foregroundServiceProvider)
          .start(
            serverName: entry.displayName,
            channelName: '',
            text: notificationText(l10n),
            keepAwake: ref.read(settingsProvider).keepAwakeWhileConnected,
          );
      ensureCurrent();
      await _autoJoin(entry, reconnect: reconnect);
    } on ConnectCancelled {
      rethrow;
    } on ConnectionCancelled {
      throw const ConnectCancelled();
    } on Object catch (e, st) {
      if (attempt != _attempt) throw const ConnectCancelled();
      appLog.w(
        'connection',
        '${reconnect ? 'Reconnect' : 'Connect'} to '
            '${entry.host}:${entry.tcpPort} failed',
        e,
        st,
      );
      client.disconnect();
      rethrow;
    } finally {
      if (attempt == _attempt) _establishing = false;
    }
  }

  void _onEvent(TtEvent event) {
    switch (event) {
      case ConLostEvent() || MyselfLoggedOutEvent():
        if (state is LoggedIn) _connectionLost();
      case MyselfKickedEvent(
        :final kicker,
        :final fromServer,
        :final channelId,
      ):
        _onKicked(
          kicker?.displayName,
          fromServer: fromServer,
          channelId: channelId,
        );
      case MyselfLoggedInEvent(:final initChannel):
        _accountInitChannel = initChannel;
      case UserJoinedEvent(:final user):
        if (user.id == _client.state.myUserId) {
          _currentChannelPath = _client.channelPath(user.channelId);
          if (user.channelId == _manualJoinTargetId) {
            _manualJoinTargetId = 0;
            _rememberChannel(_currentChannelPath, _manualJoinPassword);
          }
        }
      default:
        break;
    }
  }

  void _onKicked(String? by, {required bool fromServer, int? channelId}) {
    final l10n = ref.read(appLocalizationsProvider);
    appLog.i(
      'connection',
      'Kicked from the ${fromServer ? 'server' : 'channel'} by '
          '${by ?? 'the server'}',
    );
    final client = _client;
    final kicker = by ?? l10n.kickerServer;
    if (fromServer) {
      ref
          .read(eventDispatcherProvider)
          .fire(
            AppEvent.kickedFromServer,
            vars: {
              'kicker': kicker,
              'servername': client.state.serverInfo.name,
            },
          );
      _end(KickedFromServer(by: by));
    } else {
      final channel = client.state.channels[channelId];
      ref
          .read(eventDispatcherProvider)
          .fire(
            AppEvent.kickedFromChannel,
            vars: {
              'kicker': kicker,
              'channel': channel == null
                  ? l10n.kickedChannelUnknown
                  : (channel.isRoot ? '/' : channel.name),
            },
          );
      _currentChannelPath = '';
    }
  }

  void _connectionLost() {
    appLog.w('connection', 'Connection to $currentServerKey lost');
    ref
        .read(eventDispatcherProvider)
        .fire(
          AppEvent.connectionLost,
          vars: {'servername': _client.state.serverInfo.name},
        );
    _client.setVoiceTransmission(enabled: false);
    _client.disconnect();
    _failures = 0;
    _scheduleRetry(const NotConnected());
  }

  void _scheduleRetry(TtFailure lastFailure) {
    final attempt = _newAttempt();
    if (!_online) {
      appLog.i('connection', 'No network; reconnecting when it returns');
      state = Reconnecting(
        attempt: _failures + 1,
        waitingForNetwork: true,
        lastFailure: lastFailure,
      );
      return;
    }
    final delay = reconnectDelay(_failures, _scheduler.random);
    state = Reconnecting(
      attempt: _failures + 1,
      retryAt: _scheduler.now().add(delay),
      lastFailure: lastFailure,
    );
    _retryTimer = _scheduler.start(delay, () => unawaited(_retry(attempt)));
  }

  Future<void> _retry(int scheduled) async {
    final entry = _entry;
    if (scheduled != _attempt || entry == null) return;
    final attempt = _newAttempt();
    final previous = state;
    state = Reconnecting(
      attempt: _failures + 1,
      lastFailure: previous is Reconnecting ? previous.lastFailure : null,
    );
    try {
      await _establish(entry, attempt, reconnect: true);
      _failures = 0;
    } on ConnectCancelled {
      return;
    } on Object catch (e) {
      final failure = failureFrom(e);
      if (endsReconnecting(failure)) {
        final l10n = ref.read(appLocalizationsProvider);
        ref
            .read(announcerProvider)
            .announce(
              l10n.failureReport(
                l10n.actionConnect,
                l10n.failureMessage(failure),
              ),
            );
        _end(_failed(failure, entry, _entryIndex));
        return;
      }
      _failures++;
      _scheduleRetry(failure);
    }
  }

  void _onNetwork(bool online) {
    _online = online;
    final current = state;
    if (current is! Reconnecting) return;
    final waiting = current.retryAt != null || current.waitingForNetwork;
    if (!waiting) return;
    if (online) {
      appLog.i('connection', 'The network is back; reconnecting now');
      _failures = 0;
      unawaited(_retry(_attempt));
    } else {
      _scheduleRetry(current.lastFailure ?? const NotConnected());
    }
  }

  void _rememberChannel(String path, String password) {
    final entry = _entry;
    final index = _entryIndex;
    if (entry == null || index == null || !entry.rememberLastChannel) return;
    if (path.isEmpty ||
        (path == entry.channel && password == entry.channelPassword)) {
      return;
    }
    _entry = entry.copyWith(channel: path, channelPassword: password);
    unawaited(
      ref
          .read(serverListProvider.notifier)
          .updateChannel(index, entry, path: path, password: password),
    );
  }

  Future<void> _autoJoin(ServerEntry entry, {required bool reconnect}) async {
    final client = _client;
    try {
      if (reconnect) {
        if (_currentChannelPath.isEmpty) return;
        final channelId = client.channelIdFromPath(_currentChannelPath);
        if (channelId <= 0) return;
        final samePassword =
            _currentChannelPath == entry.channel && entry.channel.isNotEmpty;
        await client.joinChannel(
          channelId,
          password: samePassword ? entry.channelPassword : '',
        );
        return;
      }
      if (entry.channel.isNotEmpty) {
        final channelId = client.channelIdFromPath(entry.channel);
        if (channelId > 0) {
          await client.joinChannel(channelId, password: entry.channelPassword);
        }
        return;
      }
      if (_accountInitChannel.isNotEmpty) {
        final channelId = client.channelIdFromPath(_accountInitChannel);
        if (channelId > 0) {
          await client.joinChannel(channelId);
          return;
        }
      }
      if (ref.read(settingsProvider).autoJoinRootChannel) {
        final rootId = client.rootChannelId;
        if (rootId > 0) await client.joinChannel(rootId);
      }
    } on Object catch (e, st) {
      appLog.w('connection', 'Automatic channel join failed', e, st);
      ref
          .read(announcerProvider)
          .announce(
            ref.read(appLocalizationsProvider).connectionCouldNotJoinChannel,
          );
    }
  }
}
