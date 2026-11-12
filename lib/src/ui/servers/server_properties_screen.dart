import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/announcer.dart';
import '../../app/connection/connection_providers.dart';
import '../../app/settings/locale_providers.dart';
import '../../diagnostics/log.dart';
import '../../domain/models.dart';
import '../../domain/tt_types.dart';
import '../../l10n/l10n.dart';
import '../../ui/common/failure_report.dart';
import '../common/insert_variable_button.dart';
import '../common/labels.dart';
import '../common/text_controllers.dart';
import '../common/ui.dart';
import '../common/unsaved_changes.dart';
import '../settings/settings_widgets.dart';

Map<String, String> _motdVariables(AppLocalizations l10n) => {
  '%users%': l10n.motdVarUsers,
  '%admins%': l10n.motdVarAdmins,
  '%uptime%': l10n.motdVarUptime,
  '%voicerx%': l10n.motdVarVoiceRx,
  '%voicetx%': l10n.motdVarVoiceTx,
  '%lastuser%': l10n.motdVarLastUser,
};

bool _supportsServerLog(String protocolVersion) {
  final parts = protocolVersion.split('.');
  final major = int.tryParse(parts.isNotEmpty ? parts[0] : '') ?? 0;
  final minor = int.tryParse(parts.length > 1 ? parts[1] : '') ?? 0;
  return major > 5 || (major == 5 && minor >= 10);
}

class ServerPropertiesScreen extends ConsumerStatefulWidget {
  const ServerPropertiesScreen({super.key});

  @override
  ConsumerState<ServerPropertiesScreen> createState() =>
      _ServerPropertiesScreenState();
}

class _ServerPropertiesScreenState extends ConsumerState<ServerPropertiesScreen>
    with TextControllers, UnsavedChanges {
  @override
  List<Object?> get formValues => [_autoSave, _logEventsMask];

  late final TtServerProperties _props;
  late final bool _editable;

  late final TextEditingController _serverName;
  late final TextEditingController _motd;
  late final TextEditingController _maxUsers;
  late final TextEditingController _maxLoginAttempts;
  late final TextEditingController _maxLoginsPerIp;
  late final TextEditingController _loginDelay;
  late final TextEditingController _userTimeout;
  late final TextEditingController _tcpPort;
  late final TextEditingController _udpPort;
  late final TextEditingController _maxVoiceTx;
  late final TextEditingController _maxVideoTx;
  late final TextEditingController _maxMediaFileTx;
  late final TextEditingController _maxDesktopTx;
  late final TextEditingController _maxTotalTx;

  bool _autoSave = false;
  late int _logEventsMask;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final client = ref.read(teamTalkClientProvider);
    _props = client.getServerProperties();
    _editable = client.state.hasRight(UserRights.updateServerProperties);

    _serverName = textController(_props.serverName);
    _motd = textController(_editable ? _props.motdRaw : _props.motd);
    _maxUsers = textController('${_props.maxUsers}');
    _maxLoginAttempts = textController('${_props.maxLoginAttempts}');
    _maxLoginsPerIp = textController('${_props.maxLoginsPerIpAddress}');
    _loginDelay = textController('${_props.loginDelayMSec}');
    _userTimeout = textController('${_props.userTimeout}');
    _tcpPort = textController('${_props.tcpPort}');
    _udpPort = textController('${_props.udpPort}');
    _maxVoiceTx = textController('${_props.maxVoiceTxPerSecond ~/ 1024}');
    _maxVideoTx = textController('${_props.maxVideoTxPerSecond ~/ 1024}');
    _maxMediaFileTx = textController(
      '${_props.maxMediaFileTxPerSecond ~/ 1024}',
    );
    _maxDesktopTx = textController('${_props.maxDesktopTxPerSecond ~/ 1024}');
    _maxTotalTx = textController('${_props.maxTotalTxPerSecond ~/ 1024}');
    _autoSave = _props.autoSave;
    _logEventsMask = _props.serverLogEvents;
    markSaved();
  }

  Future<void> _save() async {
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    setState(() => _saving = true);
    final updated = TtServerProperties(
      serverName: _serverName.text.trim(),
      motd: _props.motd,
      motdRaw: _motd.text,
      maxUsers: intFromField(_maxUsers, _props.maxUsers),
      maxLoginAttempts: intFromField(
        _maxLoginAttempts,
        _props.maxLoginAttempts,
      ),
      maxLoginsPerIpAddress: intFromField(
        _maxLoginsPerIp,
        _props.maxLoginsPerIpAddress,
      ),
      loginDelayMSec: intFromField(_loginDelay, _props.loginDelayMSec),
      maxVoiceTxPerSecond: intFromField(_maxVoiceTx, 0) * 1024,
      maxVideoTxPerSecond: intFromField(_maxVideoTx, 0) * 1024,
      maxMediaFileTxPerSecond: intFromField(_maxMediaFileTx, 0) * 1024,
      maxDesktopTxPerSecond: intFromField(_maxDesktopTx, 0) * 1024,
      maxTotalTxPerSecond: intFromField(_maxTotalTx, 0) * 1024,
      autoSave: _autoSave,
      tcpPort: intFromField(_tcpPort, _props.tcpPort),
      udpPort: intFromField(_udpPort, _props.udpPort),
      userTimeout: intFromField(_userTimeout, _props.userTimeout),
      serverVersion: _props.serverVersion,
      protocolVersion: _props.protocolVersion,
      serverLogEvents: _logEventsMask,
    );
    try {
      await ref.read(teamTalkClientProvider).updateServer(updated);
      final saved = ref.read(appLocalizationsProvider).serverPropsSaved;
      messenger.showMessage(saved);
      ref.read(announcerProvider).announceShown(saved);
      navigator.pop();
    } on Object catch (e, st) {
      appLog.w('server', 'Saving server properties failed', e, st);
      if (mounted) setState(() => _saving = false);
      reportFailure(ref, messenger, action: (l) => l.actionSave, error: e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final showLog = _supportsServerLog(_props.protocolVersion);
    final l10n = context.l10n;
    return guardUnsaved(
      save: _save,
      child: Scaffold(
        appBar: AppBar(
          title: Text(l10n.navServerProperties),
          actions: [
            if (_editable)
              TextButton(
                onPressed: _saving ? null : _save,
                child: Text(l10n.commonSave),
              ),
          ],
        ),
        body: ListView(
          padding: const EdgeInsets.symmetric(vertical: 8),
          children: [
            SectionHeader(l10n.serverPropsGeneral),
            _field(_serverName, l10n.serverPropsName),
            _motdField(l10n),
            _field(_maxUsers, l10n.serverPropsMaxUsers, number: true),
            _field(_userTimeout, l10n.serverPropsUserTimeout, number: true),
            SwitchListTile(
              title: Text(l10n.serverPropsAutoSave),
              value: _autoSave,
              onChanged: _editable
                  ? (value) => setState(() => _autoSave = value)
                  : null,
            ),
            SectionHeader(l10n.serverPropsConnection),
            _field(_tcpPort, l10n.serverPropsTcpPort, number: true),
            _field(_udpPort, l10n.serverPropsUdpPort, number: true),
            _field(
              _maxLoginAttempts,
              l10n.serverPropsMaxLoginAttempts,
              number: true,
            ),
            _field(_maxLoginsPerIp, l10n.serverPropsMaxIpLogins, number: true),
            _field(_loginDelay, l10n.serverPropsLoginDelay, number: true),
            SectionHeader(l10n.serverPropsBandwidth),
            _field(_maxVoiceTx, l10n.serverPropsVoice, number: true),
            _field(_maxVideoTx, l10n.serverPropsVideo, number: true),
            _field(_maxMediaFileTx, l10n.serverPropsMediaFile, number: true),
            _field(_maxDesktopTx, l10n.serverPropsDesktop, number: true),
            _field(_maxTotalTx, l10n.serverPropsTotal, number: true),
            SectionHeader(l10n.serverPropsServer),
            ListTile(
              title: Text(l10n.serverPropsVersion),
              subtitle: Text(
                _props.serverVersion.isEmpty
                    ? l10n.commonUnknown
                    : _props.serverVersion,
              ),
            ),
            if (showLog) ...[
              SectionHeader(l10n.serverPropsLoggedEvents),
              for (final event in ServerLogEvent.values)
                SwitchListTile(
                  title: Text(event.label(l10n)),
                  value: _logEventsMask & event.value != 0,
                  onChanged: _editable
                      ? (on) => setState(
                          () => _logEventsMask = on
                              ? _logEventsMask | event.value
                              : _logEventsMask & ~event.value,
                        )
                      : null,
                ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _field(
    TextEditingController controller,
    String label, {
    bool number = false,
  }) => LabeledTextField(
    controller: controller,
    label: label,
    number: number,
    readOnly: !_editable,
  );

  Widget _motdField(AppLocalizations l10n) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          TextField(
            controller: _motd,
            readOnly: !_editable,
            maxLines: 3,
            decoration: InputDecoration(labelText: l10n.serverPropsMotd),
          ),
          if (_editable)
            InsertVariableButton(
              controller: _motd,
              variables: _motdVariables(l10n),
            ),
        ],
      ),
    );
  }
}
