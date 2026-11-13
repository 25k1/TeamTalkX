import '../../l10n/l10n.dart';
import '../../platform/foreground_service.dart';

NotificationText notificationText(AppLocalizations l10n) => NotificationText(
  title: l10n.appTitle,
  channel: l10n.notificationChannel,
  transmitting: l10n.notificationTransmitting,
  recording: l10n.notificationRecording,
  transmit: l10n.notificationTransmit,
  stopTransmitting: l10n.notificationStopTransmitting,
  stopRecording: l10n.notificationStopRecording,
);
