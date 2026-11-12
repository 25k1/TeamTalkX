import 'dart:async';

import 'package:flutter/material.dart';

import '../../domain/server_entry.dart';
import '../../l10n/l10n.dart';
import '../common/password_field.dart';
import '../common/text_controllers.dart';
import '../common/ui.dart';

enum _LeaveChoice { save, discard, stay }

class ServerEditScreen extends StatefulWidget {
  const ServerEditScreen({super.key, this.entry});

  final ServerEntry? entry;

  @override
  State<ServerEditScreen> createState() => _ServerEditScreenState();
}

class _ServerEditScreenState extends State<ServerEditScreen>
    with TextControllers {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _name;
  late final TextEditingController _host;
  late final TextEditingController _tcpPort;
  late final TextEditingController _udpPort;
  late final TextEditingController _username;
  late final TextEditingController _password;
  late final TextEditingController _nickname;
  late final TextEditingController _channel;
  late final TextEditingController _channelPassword;
  final _hostFocus = FocusNode();
  late bool _encrypted;
  late bool _rememberLastChannel;

  @override
  void initState() {
    super.initState();
    final e = widget.entry ?? const ServerEntry();
    _name = textController(e.name);
    _host = textController(e.host);
    _tcpPort = textController(e.tcpPort.toString());
    _udpPort = textController(e.udpPort.toString());
    _username = textController(e.username);
    _password = textController(e.password);
    _nickname = textController(e.nickname);
    _channel = textController(e.channel);
    _channelPassword = textController(e.channelPassword);
    _encrypted = e.encrypted;
    _rememberLastChannel = e.rememberLastChannel;
  }

  @override
  void dispose() {
    _hostFocus.dispose();
    super.dispose();
  }

  bool get _isDirty {
    final e = widget.entry ?? const ServerEntry();
    return _name.text != e.name ||
        _host.text != e.host ||
        _tcpPort.text != e.tcpPort.toString() ||
        _udpPort.text != e.udpPort.toString() ||
        _username.text != e.username ||
        _password.text != e.password ||
        _nickname.text != e.nickname ||
        _channel.text != e.channel ||
        _channelPassword.text != e.channelPassword ||
        _encrypted != e.encrypted ||
        _rememberLastChannel != e.rememberLastChannel;
  }

  void _save() {
    final l10n = context.l10n;
    if (!(_formKey.currentState?.validate() ?? false)) {
      _hostFocus.requestFocus();
      ScaffoldMessenger.of(context).showMessage(l10n.serverEditEnterAddress);
      return;
    }
    final base = widget.entry ?? const ServerEntry();
    Navigator.of(context).pop(
      base.copyWith(
        name: _name.text.trim(),
        host: _host.text.trim(),
        tcpPort: int.tryParse(_tcpPort.text) ?? ServerEntry.defaultTcpPort,
        udpPort: int.tryParse(_udpPort.text) ?? ServerEntry.defaultUdpPort,
        encrypted: _encrypted,
        username: _username.text,
        password: _password.text,
        nickname: _nickname.text.trim(),
        channel: _channel.text.trim(),
        channelPassword: _channelPassword.text,
        rememberLastChannel: _rememberLastChannel,
      ),
    );
  }

  Future<void> _handleBack() async {
    final navigator = Navigator.of(context);
    if (!_isDirty) {
      navigator.pop();
      return;
    }
    final choice = await _confirmLeave();
    if (!mounted) return;
    switch (choice) {
      case _LeaveChoice.save:
        _save();
      case _LeaveChoice.discard:
        navigator.pop();
      case _LeaveChoice.stay:
        break;
    }
  }

  Future<_LeaveChoice> _confirmLeave() async {
    final l10n = context.l10n;
    final choice = await showDialog<_LeaveChoice>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.serverEditUnsavedTitle),
        content: Text(l10n.serverEditUnsavedBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(_LeaveChoice.stay),
            child: Text(l10n.serverEditKeepEditing),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(_LeaveChoice.discard),
            child: Text(l10n.commonDiscard),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(_LeaveChoice.save),
            child: Text(l10n.commonSave),
          ),
        ],
      ),
    );
    return choice ?? _LeaveChoice.stay;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) unawaited(_handleBack());
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(
            widget.entry == null
                ? l10n.serverEditTitleAdd
                : l10n.serverEditTitleEdit,
          ),
          actions: [TextButton(onPressed: _save, child: Text(l10n.commonSave))],
        ),
        body: Form(
          key: _formKey,
          autovalidateMode: AutovalidateMode.onUserInteraction,
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              TextFormField(
                controller: _name,
                decoration: InputDecoration(labelText: l10n.serverEditName),
              ),
              TextFormField(
                controller: _host,
                focusNode: _hostFocus,
                decoration: InputDecoration(
                  labelText: l10n.serverEditAddress,
                  hintText: 'example.com',
                ),
                keyboardType: TextInputType.url,
                autocorrect: false,
                validator: (v) => (v == null || v.trim().isEmpty)
                    ? l10n.serverEditEnterAddress
                    : null,
              ),
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _tcpPort,
                      decoration: InputDecoration(
                        labelText: l10n.serverEditTcpPort,
                      ),
                      keyboardType: TextInputType.number,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: TextFormField(
                      controller: _udpPort,
                      decoration: InputDecoration(
                        labelText: l10n.serverEditUdpPort,
                      ),
                      keyboardType: TextInputType.number,
                    ),
                  ),
                ],
              ),
              SwitchListTile(
                title: Text(l10n.serverEditEncrypted),
                value: _encrypted,
                onChanged: (value) => setState(() => _encrypted = value),
              ),
              TextFormField(
                controller: _nickname,
                decoration: InputDecoration(
                  labelText: l10n.serverEditNicknameOptional,
                ),
              ),
              TextFormField(
                controller: _username,
                decoration: InputDecoration(
                  labelText: l10n.serverEditUsernameOptional,
                ),
                autocorrect: false,
              ),
              PasswordField(
                controller: _password,
                label: l10n.serverEditPasswordOptional,
              ),
              SwitchListTile(
                title: Text(l10n.serverEditRememberChannel),
                subtitle: Text(l10n.serverEditRememberChannelHint),
                value: _rememberLastChannel,
                onChanged: (value) =>
                    setState(() => _rememberLastChannel = value),
              ),
              if (!_rememberLastChannel) ...[
                TextFormField(
                  controller: _channel,
                  decoration: InputDecoration(
                    labelText: l10n.serverEditChannelOptional,
                    hintText: '/Lobby/',
                  ),
                  autocorrect: false,
                ),
                PasswordField(
                  controller: _channelPassword,
                  label: l10n.serverEditChannelPasswordOptional,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
