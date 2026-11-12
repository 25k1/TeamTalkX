import 'dart:async';

import 'native_channel.dart';

class UpdateDevice {
  const UpdateDevice({
    required this.packageName,
    required this.abis,
    required this.debuggable,
  });

  final String packageName;

  final List<String> abis;
  final bool debuggable;
}

class ApkCheck {
  const ApkCheck({
    required this.valid,
    this.packageName = '',
    this.versionName = '',
    this.sameSigner = false,
  });

  final bool valid;
  final String packageName;
  final String versionName;

  final bool sameSigner;
}

enum InstallStatus { confirm, success, cancelled, failed }

abstract interface class AppUpdater {
  Future<UpdateDevice> device();
  Future<bool> isMetered();
  Future<ApkCheck> verify(String path);

  Future<bool> canInstall();
  Future<void> openInstallSettings();

  Future<void> install(String path);

  Stream<InstallStatus> get statuses;
}

class AndroidAppUpdater implements AppUpdater {
  AndroidAppUpdater() {
    _channel.setHandler((call) async {
      if (call.method != 'installStatus') return;
      final args = call.arguments as Map;
      final status = InstallStatus.values
          .where((s) => s.name == args['status'])
          .firstOrNull;
      if (status != null) _statuses.add(status);
    });
  }

  final _channel = NativeChannel('updates');
  final _statuses = StreamController<InstallStatus>.broadcast();

  @override
  Stream<InstallStatus> get statuses => _statuses.stream;

  @override
  Future<UpdateDevice> device() async {
    final m = await _channel.invoke<Map<Object?, Object?>>('device');
    return UpdateDevice(
      packageName: m?['packageName'] as String? ?? '',
      abis: [for (final a in (m?['abis'] as List? ?? const [])) '$a'],
      debuggable: m?['debuggable'] as bool? ?? true,
    );
  }

  @override
  Future<bool> isMetered() async =>
      await _channel.invokeQuiet<bool>('isMetered') ?? false;

  @override
  Future<ApkCheck> verify(String path) async {
    final m = await _channel.invoke<Map<Object?, Object?>>('verify', {
      'path': path,
    });
    return ApkCheck(
      valid: m?['valid'] as bool? ?? false,
      packageName: m?['packageName'] as String? ?? '',
      versionName: m?['versionName'] as String? ?? '',
      sameSigner: m?['sameSigner'] as bool? ?? false,
    );
  }

  @override
  Future<bool> canInstall() async =>
      await _channel.invoke<bool>('canInstall') ?? false;

  @override
  Future<void> openInstallSettings() =>
      _channel.invoke<bool>('openInstallSettings');

  @override
  Future<void> install(String path) =>
      _channel.invoke<bool>('install', {'path': path});
}
