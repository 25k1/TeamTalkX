import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/announcer.dart';
import '../../app/platform_services.dart';
import '../../app/settings/locale_providers.dart';
import '../../diagnostics/log.dart';
import 'failure_report.dart';
import 'ui.dart';

Future<void> exportToDownloads(
  WidgetRef ref,
  ScaffoldMessengerState messenger, {
  required String fileName,
  required String content,
}) async {
  final announcer = ref.read(announcerProvider);
  final downloads = ref.read(downloadsProvider);
  try {
    final path = await downloads.saveText(fileName, content);
    final text = ref.read(appLocalizationsProvider).exportedTo(path);
    messenger.showMessage(text);
    announcer.announceShown(text);
  } on PlatformException catch (e) {
    appLog.w('export', 'Export of $fileName failed', e);
    reportFailure(ref, messenger, action: (l) => l.actionExport, error: e);
  }
}
