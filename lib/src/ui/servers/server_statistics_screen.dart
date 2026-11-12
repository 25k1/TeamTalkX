import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/connection/connection_providers.dart';
import '../../app/failures.dart';
import '../../domain/models.dart';
import '../../l10n/failure_messages.dart';
import '../../l10n/l10n.dart';

class ServerStatisticsScreen extends ConsumerStatefulWidget {
  const ServerStatisticsScreen({super.key});

  @override
  ConsumerState<ServerStatisticsScreen> createState() =>
      _ServerStatisticsScreenState();
}

class _ServerStatisticsScreenState
    extends ConsumerState<ServerStatisticsScreen> {
  late Future<TtServerStats> _stats = _query();

  Future<TtServerStats> _query() =>
      ref.read(teamTalkClientProvider).queryServerStats();

  void _refresh() => setState(() => _stats = _query());

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.statsTitle),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: l10n.commonRefresh,
            onPressed: _refresh,
          ),
        ],
      ),
      body: FutureBuilder<TtServerStats>(
        future: _stats,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(
              child: Text(l10n.failureMessage(failureFrom(snapshot.error!))),
            );
          }
          final stats = snapshot.data;
          if (stats == null) {
            return const Center(child: CircularProgressIndicator());
          }
          String size(int bytes) => localizedFileSize(l10n, bytes);
          Widget row(String title, String value) =>
              ListTile(title: Text(title), subtitle: Text(value));
          String traffic(int sent, int received) =>
              l10n.statsTraffic(size(sent), size(received));
          return ListView(
            children: [
              ListTile(subtitle: Text(l10n.statsSinceStart)),
              row(
                l10n.statsUptime,
                ServerStatisticsScreenUptime.format(l10n, stats.uptime),
              ),
              row(l10n.statsUsersServed, '${stats.usersServed}'),
              row(l10n.statsUsersSpoke, '${stats.usersSpoke}'),
              row(l10n.statsVoice, traffic(stats.voiceTx, stats.voiceRx)),
              row(
                l10n.statsMediaFiles,
                traffic(stats.mediaFileTx, stats.mediaFileRx),
              ),
              row(l10n.statsFiles, traffic(stats.filesTx, stats.filesRx)),
              row(l10n.statsTotal, traffic(stats.totalTx, stats.totalRx)),
            ],
          );
        },
      ),
    );
  }
}

abstract final class ServerStatisticsScreenUptime {
  static String format(AppLocalizations l10n, Duration d) => [
    if (d.inDays > 0) l10n.statsDays(d.inDays),
    if (d.inHours > 0) l10n.statsHours(d.inHours % 24),
    l10n.statsMinutes(d.inMinutes % 60),
  ].join(', ');
}
