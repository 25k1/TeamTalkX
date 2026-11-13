import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/tt_format.dart';
import '../../domain/server_entry.dart';
import '../../domain/tt_types.dart';
import '../settings/settings_providers.dart';

Map<String, String> bearwareUrlArgs() => {
  'client': 'TeamTalk5Flutter',
  'version': '1.0.0',
  'dllversion': teamTalkSdkVersion,
  'os': 'Android',
};

Uri publicServerListUri({bool official = true, bool unofficial = true}) =>
    Uri.https('www.bearware.dk', '/teamtalk/tt5servers.php', {
      ...bearwareUrlArgs(),
      'official': official ? '1' : '0',
      'unofficial': unofficial ? '1' : '0',
    });

Uri joinCodeUri(String code) => Uri.https(
  'www.bearware.dk',
  '/teamtalk/tt5servers.php',
  {...bearwareUrlArgs(), 'action': 'joincode', 'joincode': code},
);

Future<ServerEntry?> lookupJoinCode(String code) async {
  final client = HttpClient()..connectionTimeout = const Duration(seconds: 10);
  try {
    final request = await client.getUrl(joinCodeUri(code.trim()));
    final response = await request.close();
    if (response.statusCode != HttpStatus.ok) return null;
    final xml = await response.transform(utf8.decoder).join();
    final entries = decodeTtFile(xml);
    return entries.isEmpty ? null : entries.first;
  } finally {
    client.close();
  }
}

final publicServersProvider = FutureProvider<List<ServerEntry>>((ref) async {
  final official = ref.watch(
    serverListSettingsProvider.select((s) => s.showOfficialServers),
  );
  final unofficial = ref.watch(
    serverListSettingsProvider.select((s) => s.showUnofficialServers),
  );
  if (!official && !unofficial) return const [];
  final client = HttpClient()..connectionTimeout = const Duration(seconds: 10);
  try {
    final request = await client.getUrl(
      publicServerListUri(official: official, unofficial: unofficial),
    );
    final response = await request.close();
    if (response.statusCode != HttpStatus.ok) {
      throw HttpException('Server list returned ${response.statusCode}');
    }
    final xml = await response.transform(utf8.decoder).join();
    return decodeTtFile(xml);
  } finally {
    client.close();
  }
});
