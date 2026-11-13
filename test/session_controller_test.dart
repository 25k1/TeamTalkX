import 'dart:async';
import 'dart:math';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:teamtalkx/src/app/connection/connection_providers.dart';
import 'package:teamtalkx/src/app/connection/foreground_notification.dart';
import 'package:teamtalkx/src/app/connection/reconnect_policy.dart';
import 'package:teamtalkx/src/app/settings/settings_providers.dart';
import 'package:teamtalkx/src/domain/certificate.dart';
import 'package:teamtalkx/src/domain/events.dart';
import 'package:teamtalkx/src/domain/failure.dart';
import 'package:teamtalkx/src/domain/models.dart';
import 'package:teamtalkx/src/domain/server_entry.dart';
import 'package:teamtalkx/src/domain/server_state.dart';
import 'package:teamtalkx/src/domain/teamtalk_client.dart';
import 'package:teamtalkx/src/domain/voice_quality.dart';
import 'package:teamtalkx/src/protocol/tt_connection.dart';

import 'support/fake_platform.dart';

class _FakeClient implements TeamTalkClient {
  _FakeClient() {
    state.myUserId = 7;
  }

  final eventController = StreamController<TtEvent>.broadcast(sync: true);
  @override
  final ServerState state = ServerState();

  int connects = 0;
  int logins = 0;
  int disconnects = 0;
  final joins = <int>[];

  Completer<void>? connectGate;
  Completer<void>? loginGate;
  Completer<void>? joinGate;

  Exception? connectError;
  Exception? loginError;

  void emit(TtEvent event) => eventController.add(event);

  @override
  Stream<TtEvent> get events => eventController.stream;
  @override
  Future<void> connect(
    String host, {
    int tcpPort = 10333,
    int udpPort = 10333,
    bool encrypted = false,
    Duration timeout = const Duration(seconds: 20),
  }) async {
    connects++;
    await connectGate?.future;
    if (connectError case final e?) throw e;
  }

  @override
  Future<void> login({
    required String nickname,
    String username = '',
    String password = '',
    String clientName = '',
  }) async {
    logins++;
    await loginGate?.future;
    if (loginError case final e?) throw e;
  }

  @override
  void disconnect() => disconnects++;
  @override
  int get myUserId => 7;
  @override
  int get rootChannelId => 1;
  @override
  String get serverAccessToken => '';
  @override
  int channelIdFromPath(String path) => path == '/Room/' ? 5 : 0;
  @override
  String channelPath(int channelId) => channelId == 5 ? '/Room/' : '/';
  @override
  Future<void> joinChannel(int channelId, {String password = ''}) async {
    joins.add(channelId);
    await joinGate?.future;
  }

  @override
  Future<void> changeStatus(int statusMode, String statusMessage) async {}
  @override
  bool setMasterVolume(int volume) => true;
  @override
  void setMediaPlaybackVolume(int percent) {}
  @override
  void setPlaybackNormalization({required bool enabled}) {}

  @override
  void setVoiceQuality(VoiceQuality quality) {}
  @override
  void setAudioOutput({required bool voiceCall, int deviceId = 0}) {}
  @override
  bool setMicrophoneGain(int gain) => true;
  @override
  bool setVoiceActivationLevel(int level) => true;
  @override
  bool setVoiceTransmission({required bool enabled}) => true;
  @override
  bool setVoiceActivation({required bool enabled}) => true;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeTimer implements Timer {
  _FakeTimer(this.delay, this._callback);

  final Duration delay;
  final void Function() _callback;
  bool _active = true;

  void fire() {
    if (!_active) return;
    _active = false;
    _callback();
  }

  @override
  void cancel() => _active = false;
  @override
  bool get isActive => _active;
  @override
  int get tick => 0;
}

class _FakeScheduler extends ReconnectScheduler {
  _FakeScheduler() : super(random: Random(1));

  final timers = <_FakeTimer>[];
  final clock = DateTime(2026, 11, 9);

  _FakeTimer? get pending =>
      timers.where((t) => t.isActive).toList().lastOrNull;

  @override
  DateTime now() => clock;

  @override
  Timer start(Duration delay, void Function() callback) {
    final timer = _FakeTimer(delay, callback);
    timers.add(timer);
    return timer;
  }
}

TtUser _user(int id, {int channelId = 0, String nickname = ''}) => TtUser(
  id: id,
  username: '',
  nickname: nickname,
  statusMessage: '',
  channelId: channelId,
  userState: 0,
  userType: 1,
  clientName: '',
);

const _entry = ServerEntry(name: 'Test', host: 'tt.example', channel: '');

UntrustedCertificate _untrusted(UntrustedCertificateReason reason) =>
    UntrustedCertificate(
      host: 'tt.example',
      port: 10333,
      certificate: CertificateInfo(
        sha256: 'ab',
        subject: '/CN=tt',
        issuer: '/CN=tt',
        notBefore: DateTime.utc(2026),
        notAfter: DateTime.utc(2027),
        authorityTrusted: false,
      ),
      reason: reason,
    );

Future<void> _settle() => Future<void>.delayed(Duration.zero);

void main() {
  late _FakeClient client;
  late _FakeScheduler scheduler;
  late FakePlatform platform;
  late ProviderContainer c;

  SessionController session() => c.read(connectionProvider.notifier);
  ConnectionState state() => c.read(connectionProvider);

  setUp(() async {
    SharedPreferences.setMockInitialValues({
      'speech_output': 'tts',
      'app_language': 'english',
      'auto_join_root_channel': false,
    });
    final prefs = await SharedPreferences.getInstance();
    client = _FakeClient();
    scheduler = _FakeScheduler();
    platform = FakePlatform();
    c = ProviderContainer(
      overrides: [
        ...platform.overrides,
        sharedPreferencesProvider.overrideWithValue(prefs),
        teamTalkClientProvider.overrideWithValue(client),
        reconnectSchedulerProvider.overrideWithValue(scheduler),
      ],
    );
    addTearDown(() async {
      c.dispose();
      await platform.dispose();
    });
    c.listen(connectionProvider, (_, _) {});
    await _settle();
  });

  Future<void> connected() async {
    await session().connect(_entry);
    expect(state(), isA<LoggedIn>());
  }

  Future<_FakeTimer> lose() async {
    client.emit(const ConLostEvent());
    await _settle();
    expect(state(), isA<Reconnecting>());
    return scheduler.pending!;
  }

  group('abandoned attempts', () {
    test('disconnecting while connecting abandons the attempt', () async {
      client.loginGate = Completer<void>();
      final connecting = expectLater(
        session().connect(_entry),
        throwsA(isA<ConnectCancelled>()),
      );
      await _settle();
      expect(state(), isA<LoggingIn>());

      await session().disconnect();
      client.loginGate!.complete();
      await connecting;

      expect(state(), isA<Disconnected>());
      expect(
        platform.foregroundService.calls,
        isNot(contains(startsWith('start'))),
      );
    });

    test('a stale attempt that fails leaves the new session alone', () async {
      client.connectGate = Completer<void>();
      final first = expectLater(
        session().connect(_entry),
        throwsA(isA<ConnectCancelled>()),
      );
      await _settle();
      final gate = client.connectGate!;
      client.connectGate = null;

      await session().connect(_entry);
      final disconnectsAfterSecond = client.disconnects;

      client.connectError = const ServerUnreachable();
      gate.complete();
      await first;

      expect(state(), isA<LoggedIn>());
      expect(client.disconnects, disconnectsAfterSecond);
    });
  });

  group('reconnecting', () {
    test('a connection lost while joining still counts as connected', () async {
      client.joinGate = Completer<void>();
      final connecting = session().connect(
        const ServerEntry(host: 'tt.example', channel: '/Room/'),
      );
      await _settle();
      expect(state(), isA<LoggedIn>());

      client.emit(const ConLostEvent());
      client.joinGate!.complete();

      await connecting;
      expect(state(), isA<Reconnecting>());
    });

    test('a lost connection reconnects and rejoins the channel', () async {
      await connected();
      client.emit(UserJoinedEvent(_user(7, channelId: 5)));

      final retry = await lose();
      expect((state() as Reconnecting).attempt, 1);
      expect(retry.delay.inMilliseconds, inInclusiveRange(1600, 2400));
      expect(platform.tts.spoken.where((t) => t.startsWith('Connection')), [
        'Connection lost. Reconnecting',
      ], reason: 'once, as the connection-lost event');
      expect(platform.tts.interrupted, ['Connection lost. Reconnecting']);
      expect(platform.sounds.played, contains('serverLost'));

      retry.fire();
      await _settle();

      expect(state(), isA<LoggedIn>());
      expect(client.joins, [5]);
      expect(platform.tts.spoken.last, 'Reconnected');
      expect(platform.foregroundService.calls, isNot(contains('stop')));
    });

    test('failed attempts back off up to a minute', () async {
      await connected();
      var retry = await lose();
      client.connectError = const ServerUnreachable();

      final delays = <Duration>[];
      for (var i = 0; i < 8; i++) {
        retry.fire();
        await _settle();
        retry = scheduler.pending!;
        delays.add(retry.delay);
      }

      expect((state() as Reconnecting).attempt, 9);
      expect(delays.first, greaterThan(const Duration(milliseconds: 3000)));
      expect(delays.last, lessThanOrEqualTo(reconnectMaxDelay));
      expect(delays.last, greaterThan(const Duration(seconds: 45)));
    });

    test('waits for the network and retries as soon as it returns', () async {
      await connected();
      platform.connectivity.set(online: false);
      client.emit(const ConLostEvent());
      await _settle();

      final waiting = state() as Reconnecting;
      expect(waiting.waitingForNetwork, isTrue);
      expect(scheduler.pending, isNull);

      platform.connectivity.set(online: true);
      await _settle();
      expect(state(), isA<LoggedIn>());
    });

    test('the network returning skips the remaining wait', () async {
      await connected();
      final retry = await lose();
      final connects = client.connects;

      platform.connectivity.set(online: true);
      await _settle();

      expect(client.connects, connects + 1);
      expect(state(), isA<LoggedIn>());
      retry.fire();
      await _settle();
      expect(client.connects, connects + 1);
    });

    test('a refused login ends reconnecting', () async {
      await connected();
      final retry = await lose();
      client.loginError = TtCommandError(2002, 'Invalid account');

      retry.fire();
      await _settle();

      final ended = state() as Disconnected;
      expect((ended.reason! as ConnectFailed).failure, isA<ServerRejected>());
      expect(scheduler.pending, isNull);
      expect(platform.foregroundService.calls.last, 'stop');
    });

    test('disconnecting while waiting cancels the retry', () async {
      await connected();
      final retry = await lose();
      final connects = client.connects;

      await session().disconnect();
      retry.fire();
      await _settle();

      expect(state(), isA<Disconnected>());
      expect(client.connects, connects);
    });
  });

  group('wake lock', () {
    test('by default the connection lets the phone sleep', () async {
      await connected();
      expect(platform.foregroundService.calls, contains('start Test'));
    });

    test('turned on, the foreground service keeps the phone awake', () async {
      c
          .read(connectionSettingsProvider.notifier)
          .setKeepAwakeWhileConnected(true);
      await connected();
      expect(platform.foregroundService.calls, contains('start Test awake'));
    });

    test('changing it while connected updates the service', () async {
      c.listen(foregroundNotificationProvider, (_, _) {});
      await connected();
      await _settle();
      c
          .read(connectionSettingsProvider.notifier)
          .setKeepAwakeWhileConnected(true);
      await _settle();
      expect(platform.foregroundService.calls.last, endsWith(' awake'));
      c
          .read(connectionSettingsProvider.notifier)
          .setKeepAwakeWhileConnected(false);
      await _settle();
      expect(platform.foregroundService.calls.last, isNot(endsWith(' awake')));
    });

    test('the notification speaks the app language', () async {
      c.listen(foregroundNotificationProvider, (_, _) {});
      await connected();
      await _settle();
      expect(
        platform.foregroundService.text?.stopTransmitting,
        'Stop transmitting',
      );
      c
          .read(appearanceSettingsProvider.notifier)
          .setLanguage(AppLanguage.russian);
      await _settle();
      final text = platform.foregroundService.text!;
      expect(text.channel, 'Подключение');
      expect(text.transmit, 'Передавать');
      expect(text.stopRecording, 'Остановить запись');
    });
  });

  group('certificates', () {
    test(
      'a certificate to decide on ends the connect with the entry',
      () async {
        client.connectError = _untrusted(const NewCertificate());
        await expectLater(
          session().connect(_entry, listIndex: 3),
          throwsA(isA<UntrustedCertificate>()),
        );
        final reason =
            (state() as Disconnected).reason! as CertificateNotTrusted;
        expect(reason.entry, _entry);
        expect(reason.listIndex, 3);
        expect(reason.failure.reason, isA<NewCertificate>());
        expect(client.logins, 0, reason: 'nothing sent to the server');
      },
    );

    test('a changed certificate on reconnect waits for the user', () async {
      await connected();
      final retry = await lose();
      client.connectError = _untrusted(
        ChangedCertificate(
          CertificatePin(
            endpoint: 'tt.example:10333',
            sha256: 'cd',
            subject: '',
            issuer: '',
            notAfter: DateTime.utc(2027),
            savedAt: DateTime.utc(2026),
          ),
        ),
      );

      retry.fire();
      await _settle();

      final reason = (state() as Disconnected).reason! as CertificateNotTrusted;
      expect(reason.entry, _entry);
      expect(scheduler.pending, isNull, reason: 'no more attempts');
      expect(
        platform.tts.spoken.last,
        contains("The server's certificate has changed."),
      );
    });
  });

  group('kicks', () {
    test('a server kick ends the session without reconnecting', () async {
      await connected();
      final kicker = _user(2, nickname: 'Op');

      client.emit(MyselfKickedEvent(kicker));
      client.emit(const MyselfLoggedOutEvent());
      await _settle();

      final ended = state() as Disconnected;
      expect((ended.reason! as KickedFromServer).by, 'Op');
      expect(scheduler.pending, isNull);
      expect(platform.tts.spoken.last, 'Kicked from the server by Op');
      expect(platform.foregroundService.calls.last, 'stop');
    });

    test('a channel kick keeps the session and is not rejoined', () async {
      await connected();
      client.emit(UserJoinedEvent(_user(7, channelId: 5)));
      client.emit(MyselfKickedEvent(_user(2, nickname: 'Op'), channelId: 5));
      await _settle();

      expect(state(), isA<LoggedIn>());
      expect(platform.tts.spoken.last, 'Kicked from the channel by Op');
      expect(platform.tts.interrupted, ['Kicked from the channel by Op']);

      (await lose()).fire();
      await _settle();
      expect(state(), isA<LoggedIn>());
      expect(client.joins, isEmpty);
    });
  });

  group('reconnect policy', () {
    test('delays double from 2 s to 60 s with ±20 % jitter', () {
      final random = Random(3);
      for (var failures = 0; failures < 12; failures++) {
        final base = min(2000 * pow(2, failures), 60000);
        final delay = reconnectDelay(failures, random).inMilliseconds;
        expect(delay, greaterThanOrEqualTo(min(base * 0.8, 60000).floor()));
        expect(delay, lessThanOrEqualTo(min(base * 1.2, 60000).ceil()));
      }
    });

    test('only refusals of the login itself end reconnecting', () {
      expect(
        endsReconnecting(const ServerRejected(ServerError.invalidAccount)),
        isTrue,
      );
      expect(
        endsReconnecting(const ServerRejected(ServerError.bannedFromServer)),
        isTrue,
      );
      expect(endsReconnecting(const WebLoginRequired()), isTrue);
      expect(
        endsReconnecting(_untrusted(const NewCertificate())),
        isTrue,
        reason: 'waits for the user',
      );
      expect(
        endsReconnecting(
          const ServerRejected(ServerError.tooManyLoginsFromAddress),
        ),
        isFalse,
      );
      expect(endsReconnecting(const ServerUnreachable()), isFalse);
      expect(endsReconnecting(const ConnectionTimedOut()), isFalse);
    });
  });
}
