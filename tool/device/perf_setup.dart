import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:teamtalkx/src/domain/server_entry.dart';

const _host = String.fromEnvironment('TT_PERF_HOST');
const _keepAwake = bool.fromEnvironment(
  'TT_PERF_KEEP_AWAKE',
  defaultValue: false,
);

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(
    const MaterialApp(
      home: Scaffold(body: Center(child: Text('Performance setup'))),
    ),
  );
  final servers = [
    if (_host.isNotEmpty)
      const ServerEntry(
        name: 'E2E',
        host: _host,
        username: 'alice',
        password: 'alice-e2e',
        connectOnStartup: true,
      ),
    for (var i = _host.isEmpty ? 1 : 2; i <= 20; i++)
      ServerEntry(name: 'Server $i', host: 'server$i.example'),
  ];
  final prefs = await SharedPreferences.getInstance();
  await prefs.setBool('first_run_done', true);
  await prefs.setString('nickname', 'perf');
  await prefs.setString('server_list', ServerEntry.encodeList(servers));
  await prefs.setBool('keep_awake_while_connected', _keepAwake);
  debugPrint(
    'TTX-BENCH setup: ${servers.length} servers'
    '${_host.isEmpty ? '' : ', connect on startup to $_host'}'
    '${_keepAwake ? ', wake lock' : ''}',
  );
}
