import 'package:flutter_test/flutter_test.dart';
import 'package:teamtalkx/src/l10n/generated/app_localizations_en.dart';
import 'package:teamtalkx/src/protocol/command.dart';
import 'package:teamtalkx/src/protocol/wire_models.dart';
import 'package:teamtalkx/src/ui/servers/server_statistics_screen.dart';

void main() {
  test('the stats line is read', () {
    final stats = serverStatsFromCommand(
      TtCommand.parse(
        'stats totaltx=1000 totalrx=2000 voicetx=300 voicerx=400 '
        'mediafiletx=5 mediafilerx=6 filestx=7 filesrx=8 usersserved=12 '
        'userspeak=4 uptime=90061000',
      ),
    );
    expect(stats.totalRx, 2000);
    expect(stats.voiceTx, 300);
    expect(stats.filesRx, 8);
    expect(stats.usersServed, 12);
    expect(stats.usersSpoke, 4);
    expect(
      stats.uptime,
      const Duration(days: 1, hours: 1, minutes: 1, seconds: 1),
    );
  });

  test('uptime reads as days, hours and minutes', () {
    final l10n = AppLocalizationsEn();
    String uptime(Duration d) => ServerStatisticsScreenUptime.format(l10n, d);
    expect(
      uptime(const Duration(days: 2, hours: 3, minutes: 1)),
      '2 days, 3 hours, 1 minute',
    );
    expect(uptime(const Duration(minutes: 5)), '5 minutes');
  });
}
