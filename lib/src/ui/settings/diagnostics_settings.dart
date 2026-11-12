import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/app_info.dart';
import '../../diagnostics/diagnostics.dart';
import '../../diagnostics/diagnostics_report.dart';
import '../../diagnostics/log.dart';
import '../../l10n/l10n.dart';
import '../common/export.dart';

class DiagnosticsSettings extends ConsumerWidget {
  const DiagnosticsSettings({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ListView(
      children: [
        ListTile(
          leading: const Icon(Icons.bug_report),
          title: Text(context.l10n.diagnosticsExport),
          subtitle: Text(context.l10n.diagnosticsExportSub),
          onTap: () => _export(context, ref),
        ),
      ],
    );
  }

  Future<void> _export(BuildContext context, WidgetRef ref) async {
    final messenger = ScaffoldMessenger.of(context);
    appLog.i('diagnostics', 'Exporting diagnostics');
    final report = await buildDiagnosticsReport(
      appVersion: ref.read(appVersionProvider),
      logSink: ref.read(logFileSinkProvider),
    );
    await exportToDownloads(
      ref,
      messenger,
      fileName: diagnosticsFileName(DateTime.now()),
      content: report,
    );
  }
}

String diagnosticsFileName(DateTime t) {
  String two(int v) => v.toString().padLeft(2, '0');
  return 'teamtalkx-diagnostics-${t.year}${two(t.month)}${two(t.day)}-'
      '${two(t.hour)}${two(t.minute)}.txt';
}
