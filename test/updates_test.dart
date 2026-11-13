import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pointycastle/digests/sha256.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:teamtalkx/src/app/app_info.dart';
import 'package:teamtalkx/src/app/settings/settings_providers.dart';
import 'package:teamtalkx/src/app/updates/update_controller.dart';
import 'package:teamtalkx/src/domain/app_update.dart';
import 'package:teamtalkx/src/platform/app_updater.dart';

import 'support/fake_platform.dart';

final _apk = utf8.encode('pretend this is an APK');
final _apkSha = [
  for (final b in SHA256Digest().process(_apk))
    b.toRadixString(16).padLeft(2, '0'),
].join();

Map<String, Object?> _release(
  String tag, {
  bool prerelease = false,
  bool draft = false,
}) {
  final version = tag.substring(1);
  return {
    'tag_name': tag,
    'prerelease': prerelease,
    'draft': draft,
    'body': '### Changes\n- Better voice',
    'html_url': 'https://github.com/25k1/TeamTalkX/releases/tag/$tag',
    'assets': [
      for (final abi in ['arm64-v8a', 'armeabi-v7a', 'universal'])
        {
          'name': 'TeamTalkX-$version-$abi.apk',
          'browser_download_url': 'https://dl/$version/$abi',
          'size': _apk.length,
        },
      {
        'name': 'SHA256SUMS.txt',
        'browser_download_url': 'https://dl/$version/sums',
        'size': 100,
      },
    ],
  };
}

class _Network implements UpdateNetwork {
  _Network(this.releases);

  List<Map<String, Object?>> releases;
  String? sumsOverride;
  final requests = <String>[];

  @override
  Future<String> getText(String url) async {
    requests.add(url);
    if (url == releasesApi) return jsonEncode(releases);
    final version = url.split('/')[3];
    return sumsOverride ??
        '$_apkSha  TeamTalkX-$version-arm64-v8a.apk\n'
            'deadbeef  TeamTalkX-$version-universal.apk\n';
  }

  @override
  Future<void> download(
    String url,
    File target, {
    required void Function(int received, int total) onProgress,
    required Future<void> cancel,
  }) async {
    requests.add(url);
    await target.writeAsBytes(_apk);
    onProgress(_apk.length, _apk.length);
  }
}

void main() {
  group('versions and releases', () {
    test('versions order, betas before their release', () {
      final v = AppVersion.tryParse;
      expect(v('v1.6.0')! > v('1.5.9')!, isTrue);
      expect(v('1.6.0')! > v('1.6.0-beta.3')!, isTrue);
      expect(v('1.6.0-beta.3')! > v('1.6.0-beta.2')!, isTrue);
      expect(v('1.10.0')! > v('1.9.9')!, isTrue);
      expect(v('nightly'), isNull);
      expect('${v('v2.0.1-beta.4')}', '2.0.1-beta.4');
    });

    test('the newest update, betas only when wanted', () {
      final releases = parseReleases(
        jsonEncode([
          _release('v1.7.0-beta.1', prerelease: true),
          _release('v1.6.0'),
          _release('v1.8.0', draft: true),
          {'tag_name': 'not-a-version', 'assets': <Object>[]},
          _release('v1.4.0'),
        ]),
      );
      expect(releases, hasLength(3));
      final current = AppVersion.tryParse('1.5.0')!;
      expect(
        '${newestUpdate(releases, current, betas: false)!.version}',
        '1.6.0',
      );
      expect(
        '${newestUpdate(releases, current, betas: true)!.version}',
        '1.7.0-beta.1',
      );
      expect(
        newestUpdate(releases, AppVersion.tryParse('1.6.0')!, betas: false),
        isNull,
      );
    });

    test("the APK for the phone's processor, else the universal one", () {
      final release = parseReleases(jsonEncode([_release('v1.6.0')])).single;
      expect(
        release.apkFor(['x86_64', 'arm64-v8a'])!.name,
        'TeamTalkX-1.6.0-arm64-v8a.apk',
      );
      expect(
        release.apkFor(['riscv64'])!.name,
        'TeamTalkX-1.6.0-universal.apk',
      );
      expect(
        checksumFor(
          'abc  TeamTalkX-1.6.0-arm64-v8a.apk\n',
          'TeamTalkX-1.6.0-arm64-v8a.apk',
        ),
        'abc',
      );
    });
  });

  group('UpdateController', () {
    late FakePlatform platform;
    late _Network network;
    late ProviderContainer c;
    late Directory cache;

    Future<void> start({
      Map<String, Object> prefs = const {},
      List<Map<String, Object?>>? releases,
    }) async {
      SharedPreferences.setMockInitialValues({
        'speech_output': 'tts',
        ...prefs,
      });
      platform = FakePlatform();
      network = _Network(releases ?? [_release('v1.6.0')]);
      cache = await Directory.systemTemp.createTemp('ttx-update');
      c = ProviderContainer(
        overrides: [
          ...platform.overrides,
          sharedPreferencesProvider.overrideWithValue(
            await SharedPreferences.getInstance(),
          ),
          appVersionProvider.overrideWithValue('1.5.0'),
          updateNetworkProvider.overrideWithValue(network),
          updateCacheProvider.overrideWithValue(() async => cache),
        ],
      );
      c.listen(updateControllerProvider, (_, _) {});
      addTearDown(() async {
        c.dispose();
        await platform.dispose();
        await cache.delete(recursive: true);
      });
    }

    UpdateController controller() => c.read(updateControllerProvider.notifier);

    test('the dev app and debug builds never look by themselves', () async {
      await start();
      await controller().checkAtStartup();
      expect(network.requests, isEmpty);
    });

    test('the app looks once a day and announces a new version once', () async {
      await start();
      platform.updater.deviceInfo = const UpdateDevice(
        packageName: updatablePackage,
        abis: ['arm64-v8a'],
        debuggable: false,
      );
      await controller().checkAtStartup();
      expect(c.read(updateControllerProvider), isA<UpdateAvailable>());
      expect(platform.tts.spoken, ['TeamTalkX 1.6.0 is available']);

      network.requests.clear();
      await controller().checkAtStartup();
      expect(network.requests, isEmpty, reason: 'within a day');

      await controller().check(announce: true);
      expect(platform.tts.spoken, hasLength(1), reason: 'announced once');
    });

    test('downloads the right APK, checks it, and installs it', () async {
      await start();
      await controller().check();
      final release =
          (c.read(updateControllerProvider) as UpdateAvailable).release;
      await controller().download(release);
      final ready = c.read(updateControllerProvider) as UpdateReady;
      expect(ready.path, endsWith('TeamTalkX-1.6.0-arm64-v8a.apk'));
      expect(network.requests, contains('https://dl/1.6.0/arm64-v8a'));
      expect(platform.tts.spoken.last, contains('ready to install'));

      platform.updater.installAllowed = false;
      expect(await controller().install(), isFalse);
      expect(platform.updater.settingsOpened, 1);
      platform.updater.installAllowed = true;
      expect(await controller().install(), isTrue);
      expect(platform.updater.installed, [ready.path]);
    });

    test('a wrong checksum or another key is refused', () async {
      await start();
      await controller().check();
      final release =
          (c.read(updateControllerProvider) as UpdateAvailable).release;

      network.sumsOverride = 'beef  TeamTalkX-1.6.0-arm64-v8a.apk\n';
      await controller().download(release);
      expect(
        (c.read(updateControllerProvider) as UpdateFailed).reason,
        UpdateProblem.checksum,
      );

      network.sumsOverride = null;
      platform.updater.check = const ApkCheck(valid: true);
      await controller().download(release);
      expect(
        (c.read(updateControllerProvider) as UpdateFailed).reason,
        UpdateProblem.signature,
      );
    });

    test('betas are offered only when wanted', () async {
      await start(releases: [_release('v1.7.0-beta.1', prerelease: true)]);
      await controller().check();
      expect(c.read(updateControllerProvider), isA<UpdateUpToDate>());
      controller().setBetas(true);
      await controller().check();
      expect(
        (c.read(updateControllerProvider) as UpdateAvailable)
            .release
            .version
            .isBeta,
        isTrue,
      );
    });
  });
}
