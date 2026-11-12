import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pointycastle/digests/sha256.dart';

import '../../diagnostics/log.dart';
import '../../domain/app_update.dart';
import '../../platform/app_updater.dart';
import '../announcer.dart';
import '../app_info.dart';
import '../platform_services.dart';
import '../settings/locale_providers.dart';
import '../settings/settings_providers.dart';

const releasesApi =
    'https://api.github.com/repos/25k1/TeamTalkX/releases?per_page=30';

const updatablePackage = 'org.gozaltech.teamtalkx';

const autoCheckInterval = Duration(hours: 24);

abstract interface class UpdateNetwork {
  Future<String> getText(String url);

  Future<void> download(
    String url,
    File target, {
    required void Function(int received, int total) onProgress,
    required Future<void> cancel,
  });
}

class _HttpUpdateNetwork implements UpdateNetwork {
  HttpClient _client() => HttpClient()
    ..connectionTimeout = const Duration(seconds: 15)
    ..userAgent = 'TeamTalkX';

  @override
  Future<String> getText(String url) async {
    final client = _client();
    try {
      final request = await client.getUrl(Uri.parse(url));
      request.headers.set('Accept', 'application/vnd.github+json');
      final response = await request.close();
      if (response.statusCode != HttpStatus.ok) {
        throw HttpException('GitHub answered ${response.statusCode}');
      }
      return await response.transform(const SystemEncoding().decoder).join();
    } finally {
      client.close();
    }
  }

  @override
  Future<void> download(
    String url,
    File target, {
    required void Function(int received, int total) onProgress,
    required Future<void> cancel,
  }) async {
    final client = _client();
    unawaited(cancel.then((_) => client.close(force: true)));
    try {
      final response = await (await client.getUrl(Uri.parse(url))).close();
      if (response.statusCode != HttpStatus.ok) {
        throw HttpException('Download answered ${response.statusCode}');
      }
      final total = response.contentLength;
      final sink = target.openWrite();
      var received = 0;
      try {
        await for (final chunk in response) {
          sink.add(chunk);
          received += chunk.length;
          onProgress(received, total);
        }
      } finally {
        await sink.close();
      }
    } finally {
      client.close();
    }
  }
}

final updateNetworkProvider = Provider<UpdateNetwork>(
  (ref) => _HttpUpdateNetwork(),
);

final updateCacheProvider = Provider<Future<Directory> Function()>(
  (ref) => getApplicationCacheDirectory,
);

sealed class UpdateState {
  const UpdateState();
}

final class UpdateIdle extends UpdateState {
  const UpdateIdle();
}

final class UpdateChecking extends UpdateState {
  const UpdateChecking();
}

final class UpdateUpToDate extends UpdateState {
  const UpdateUpToDate();
}

final class UpdateAvailable extends UpdateState {
  const UpdateAvailable(this.release);
  final AppRelease release;
}

final class UpdateDownloading extends UpdateState {
  const UpdateDownloading(this.release, this.received, this.total);
  final AppRelease release;
  final int received;

  final int total;

  double? get fraction => total > 0 ? received / total : null;
}

final class UpdateReady extends UpdateState {
  const UpdateReady(this.release, this.path);
  final AppRelease release;
  final String path;
}

final class UpdateFailed extends UpdateState {
  const UpdateFailed(this.reason, {this.release});
  final UpdateProblem reason;
  final AppRelease? release;
}

enum UpdateProblem { check, download, noApk, checksum, signature, install }

final updateControllerProvider =
    NotifierProvider<UpdateController, UpdateState>(UpdateController.new);

class UpdateController extends Notifier<UpdateState> {
  static const _lastCheckKey = 'update_last_check';
  static const _announcedKey = 'update_announced';
  static const betasKey = 'update_betas';

  Completer<void>? _cancel;
  int _announcedQuarter = 0;

  AppUpdater get _updater => ref.read(appUpdaterProvider);

  @override
  UpdateState build() {
    final sub = _updater.statuses.listen(_onInstallStatus);
    ref.onDispose(sub.cancel);
    return const UpdateIdle();
  }

  bool get betas =>
      ref.read(sharedPreferencesProvider).getBool(betasKey) ?? false;

  void setBetas(bool value) {
    unawaited(ref.read(sharedPreferencesProvider).setBool(betasKey, value));
    ref.notifyListeners();
  }

  DateTime? get lastCheck {
    final ms = ref.read(sharedPreferencesProvider).getInt(_lastCheckKey);
    return ms == null ? null : DateTime.fromMillisecondsSinceEpoch(ms);
  }

  Future<void> checkAtStartup({DateTime? now}) async {
    final device = await _updater.device();
    if (device.packageName != updatablePackage || device.debuggable) return;
    final last = lastCheck;
    final at = now ?? DateTime.now();
    if (last != null && at.difference(last) < autoCheckInterval) return;
    await check(announce: true);
  }

  Future<void> check({bool announce = false}) async {
    if (state is UpdateDownloading) return;
    state = const UpdateChecking();
    final prefs = ref.read(sharedPreferencesProvider);
    try {
      final releases = parseReleases(
        await ref.read(updateNetworkProvider).getText(releasesApi),
      );
      unawaited(
        prefs.setInt(_lastCheckKey, DateTime.now().millisecondsSinceEpoch),
      );
      final current = AppVersion.tryParse(ref.read(appVersionProvider));
      final newest = current == null
          ? null
          : newestUpdate(releases, current, betas: betas);
      if (newest == null) {
        state = const UpdateUpToDate();
        return;
      }
      state = UpdateAvailable(newest);
      final version = '${newest.version}';
      if (announce && prefs.getString(_announcedKey) != version) {
        unawaited(prefs.setString(_announcedKey, version));
        ref
            .read(announcerProvider)
            .announce(
              ref.read(appLocalizationsProvider).updateAvailable(version),
            );
      }
    } on Object catch (e, st) {
      appLog.w('updates', 'Checking for updates failed', e, st);
      state = const UpdateFailed(UpdateProblem.check);
    }
  }

  Future<void> download(AppRelease release) async {
    if (state is UpdateDownloading) return;
    final device = await _updater.device();
    final asset = release.apkFor(device.abis);
    final sums = release.checksums;
    if (asset == null) {
      state = UpdateFailed(UpdateProblem.noApk, release: release);
      return;
    }
    final network = ref.read(updateNetworkProvider);
    final cancel = _cancel = Completer<void>();
    _announcedQuarter = 0;
    state = UpdateDownloading(release, 0, asset.size);
    final File file;
    try {
      final dir = Directory(
        '${(await ref.read(updateCacheProvider)()).path}/updates',
      );
      if (await dir.exists()) await dir.delete(recursive: true);
      await dir.create(recursive: true);
      file = File('${dir.path}/${asset.name}');
      await network.download(
        asset.url,
        file,
        onProgress: (received, total) =>
            _progress(release, received, total > 0 ? total : asset.size),
        cancel: cancel.future,
      );
    } on Object catch (e, st) {
      if (cancel.isCompleted) {
        state = UpdateAvailable(release);
        return;
      }
      appLog.w('updates', 'Downloading the update failed', e, st);
      state = UpdateFailed(UpdateProblem.download, release: release);
      return;
    } finally {
      _cancel = null;
    }

    try {
      final expected = sums == null
          ? null
          : checksumFor(await network.getText(sums.url), asset.name);
      final actual = await _sha256(file.path);
      if (expected == null || expected != actual) {
        appLog.w('updates', 'Checksum of ${asset.name} does not match');
        state = UpdateFailed(UpdateProblem.checksum, release: release);
        return;
      }
      final apk = await _updater.verify(file.path);
      if (!apk.valid ||
          apk.packageName != device.packageName ||
          !apk.sameSigner) {
        appLog.w(
          'updates',
          '${asset.name} is not this app signed with its key',
        );
        state = UpdateFailed(UpdateProblem.signature, release: release);
        return;
      }
    } on Object catch (e, st) {
      appLog.w('updates', 'Checking the update failed', e, st);
      state = UpdateFailed(UpdateProblem.checksum, release: release);
      return;
    }
    state = UpdateReady(release, file.path);
    ref
        .read(announcerProvider)
        .announce(
          ref.read(appLocalizationsProvider).updateReady('${release.version}'),
        );
  }

  void _progress(AppRelease release, int received, int total) {
    state = UpdateDownloading(release, received, total);
    if (total <= 0) return;
    final quarter = (received * 4 / total).floor();
    if (quarter > _announcedQuarter && quarter < 4) {
      _announcedQuarter = quarter;
      ref
          .read(announcerProvider)
          .announce(
            ref.read(appLocalizationsProvider).updateProgress(quarter * 25),
          );
    }
  }

  void cancelDownload() => _cancel?.complete();

  Future<bool> install() async {
    final ready = state;
    if (ready is! UpdateReady) return false;
    if (!await _updater.canInstall()) {
      await _updater.openInstallSettings();
      return false;
    }
    try {
      await _updater.install(ready.path);
      return true;
    } on Object catch (e, st) {
      appLog.w('updates', 'Starting the installer failed', e, st);
      state = UpdateFailed(UpdateProblem.install, release: ready.release);
      return false;
    }
  }

  void _onInstallStatus(InstallStatus status) {
    final current = state;
    final release = switch (current) {
      UpdateReady(:final release) => release,
      _ => null,
    };
    switch (status) {
      case InstallStatus.failed:
        state = UpdateFailed(UpdateProblem.install, release: release);
      case InstallStatus.confirm ||
          InstallStatus.cancelled ||
          InstallStatus.success:
        break;
    }
  }

  static Future<String> _sha256(String path) => Isolate.run(() async {
    final digest = SHA256Digest();
    await for (final chunk in File(path).openRead()) {
      final bytes = chunk is Uint8List ? chunk : Uint8List.fromList(chunk);
      digest.update(bytes, 0, bytes.length);
    }
    final out = Uint8List(digest.digestSize);
    digest.doFinal(out, 0);
    return [for (final b in out) b.toRadixString(16).padLeft(2, '0')].join();
  });
}
