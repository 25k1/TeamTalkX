import 'package:flutter/services.dart';

import '../domain/app_identity.dart';
import 'native_channel.dart';

Future<String> loadAppVersion() async {
  try {
    final version = await NativeChannel('appinfo').invoke<String>('version');
    return (version == null || version.isEmpty) ? unknownAppVersion : version;
  } on PlatformException {
    return unknownAppVersion;
  }
}

Future<void> reportFullyDrawn() =>
    NativeChannel('appinfo').invokeQuiet<void>('fullyDrawn');
