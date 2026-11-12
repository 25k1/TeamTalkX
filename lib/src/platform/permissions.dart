import 'dart:io';

import 'package:permission_handler/permission_handler.dart';

import '../domain/app_permission.dart';

export '../domain/app_permission.dart';

abstract interface class Permissions {
  Future<bool> isGranted(AppPermission permission);

  Future<bool> request(AppPermission permission);

  Future<bool> requestConnect();

  Future<bool> requestPhone();

  Future<bool> requestBluetooth();
}

class AndroidPermissions implements Permissions {
  static Permission _of(AppPermission p) => switch (p) {
    AppPermission.microphone => Permission.microphone,
    AppPermission.notifications => Permission.notification,
    AppPermission.phone => Permission.phone,
    AppPermission.bluetooth => Permission.bluetoothConnect,
    AppPermission.battery => Permission.ignoreBatteryOptimizations,
  };

  @override
  Future<bool> isGranted(AppPermission permission) async {
    if (!Platform.isAndroid) return true;
    return _of(permission).isGranted;
  }

  @override
  Future<bool> request(AppPermission permission) async {
    if (!Platform.isAndroid) return true;
    return (await _of(permission).request()).isGranted;
  }

  @override
  Future<bool> requestConnect() async {
    if (!Platform.isAndroid) return true;
    final statuses = await [
      Permission.microphone,
      Permission.notification,
      Permission.phone,
    ].request();
    return statuses[Permission.microphone]?.isGranted ?? false;
  }

  @override
  Future<bool> requestPhone() async {
    if (!Platform.isAndroid) return true;
    return (await Permission.phone.request()).isGranted;
  }

  @override
  Future<bool> requestBluetooth() async {
    if (!Platform.isAndroid) return true;
    return (await Permission.bluetoothConnect.request()).isGranted;
  }
}
