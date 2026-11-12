part of 'user_accounts_screen.dart';

List<(String, int)> _editableRights(AppLocalizations l10n) => [
  (l10n.rightMultiLogin, 1),
  (l10n.rightViewAllUsers, 2),
  (l10n.rightCreateTempChannel, 4),
  (l10n.rightModifyChannels, 8),
  (l10n.rightBroadcast, 16),
  (l10n.rightKick, 32),
  (l10n.rightBan, 64),
  (l10n.rightMove, 128),
  (l10n.rightOperatorEnable, 256),
  (l10n.rightUpload, 512),
  (l10n.rightDownload, 1024),
  (l10n.rightUpdateServer, 2048),
  (l10n.rightTransmitVoice, 4096),
  (l10n.rightTransmitVideo, 8192),
  (l10n.rightTransmitDesktop, 16384),
  (l10n.rightTransmitDesktopInput, 32768),
  (l10n.rightTransmitMediaAudio, 65536),
  (l10n.rightTransmitMediaVideo, 131072),
  (l10n.rightLockedNickname, 262144),
  (l10n.rightLockedStatus, 524288),
  (l10n.rightRecordVoice, 1048576),
  (l10n.rightViewHiddenChannels, 2097152),
  (l10n.rightTextUser, 4194304),
  (l10n.rightTextChannel, 8388608),
];

class UserAccountEditScreen extends ConsumerStatefulWidget {
  const UserAccountEditScreen({super.key, this.account});

  final TtUserAccount? account;

  @override
  ConsumerState<UserAccountEditScreen> createState() =>
      _UserAccountEditScreenState();
}

const _cmdLimitPresets = <(int, int)>[
  (0, 0),
  (10, 10000),
  (10, 60000),
  (60, 60000),
];

String _presetLabel(AppLocalizations l10n, (int, int) preset) {
  final (limit, intervalMSec) = preset;
  return limit == 0
      ? l10n.cmdLimitDisabled
      : l10n.cmdLimitPerSeconds(limit, intervalMSec ~/ 1000);
}

class _UserAccountEditScreenState extends ConsumerState<UserAccountEditScreen>
    with TextControllers, UnsavedChanges {
  @override
  List<Object?> get formValues => [
    _userType,
    _rights,
    _autoOps.join(','),
    _cmdLimit,
    _cmdIntervalMSec,
  ];

  late final TextEditingController _username;
  late final TextEditingController _password;
  late final TextEditingController _note;
  late final TextEditingController _initChannel;
  late final TextEditingController _audioKbps;
  late int _userType;
  late int _rights;
  late List<int> _autoOps;
  late int _cmdLimit;
  late int _cmdIntervalMSec;
  bool _saving = false;

  bool get _isNew => widget.account == null;
  bool get _admin => _userType == 2;
  bool get _isWebLogin => isWebLogin(_username.text.trim());

  @override
  void initState() {
    super.initState();
    final a = widget.account ?? const TtUserAccount();
    _username = textController(a.username);
    _password = textController(a.password);
    _note = textController(a.note);
    _initChannel = textController(a.initChannel);
    _audioKbps = textController(
      a.audioCodecBpsLimit > 0 ? '${a.audioCodecBpsLimit ~/ 1000}' : '',
    );
    _userType = a.userType;
    _rights = a.userRights;
    _autoOps = List.of(a.autoOperatorChannels);
    _cmdLimit = a.commandsLimit;
    _cmdIntervalMSec = a.commandsIntervalMSec;
    _username.addListener(() => setState(() {}));
    markSaved();
  }

  String _cmdLabel(AppLocalizations l10n) {
    for (final preset in _cmdLimitPresets) {
      if (preset == (_cmdLimit, _cmdIntervalMSec)) {
        return _presetLabel(l10n, preset);
      }
    }
    return l10n.cmdLimitCustom(_cmdLimit, _cmdIntervalMSec ~/ 1000);
  }

  Future<int?> _pickChannel() {
    final client = ref.read(teamTalkClientProvider);
    final channels =
        client.state.channels.values
            .where((c) => (c.channelType & 1) != 0)
            .map((c) => (id: c.id, path: client.channelPath(c.id)))
            .where((c) => c.path.isNotEmpty)
            .toList()
          ..sort(
            (a, b) => a.path.toLowerCase().compareTo(b.path.toLowerCase()),
          );
    return showAccessibleMenu<int>(
      context,
      title: context.l10n.accountSelectChannel,
      items: [for (final c in channels) MenuItemSpec<int>(c.id, c.path)],
    );
  }

  Future<void> _pickInitChannel() async {
    final id = await _pickChannel();
    if (id == null) return;
    _initChannel.text = ref.read(teamTalkClientProvider).channelPath(id);
  }

  Future<void> _addAutoOp() async {
    if (_autoOps.length >= TtUserAccount.maxAutoOperatorChannels) {
      ScaffoldMessenger.of(context).showMessage(context.l10n.accountMaxAutoOp);
      return;
    }
    final id = await _pickChannel();
    if (id == null || _autoOps.contains(id)) return;
    setState(() => _autoOps = [..._autoOps, id]);
  }

  Future<void> _chooseCommandLimit() async {
    final l10n = context.l10n;
    final choice = await showAccessibleMenu<int>(
      context,
      title: l10n.accountCommandLimit,
      items: [
        for (var i = 0; i < _cmdLimitPresets.length; i++)
          MenuItemSpec<int>(i, _presetLabel(l10n, _cmdLimitPresets[i])),
        MenuItemSpec<int>(-1, l10n.accountCustomLimit),
      ],
    );
    if (choice == null) return;
    if (choice == -1) {
      await _editCommandLimit();
    } else {
      final preset = _cmdLimitPresets[choice];
      setState(() {
        _cmdLimit = preset.$1;
        _cmdIntervalMSec = preset.$2;
      });
    }
  }

  Future<void> _editCommandLimit() async {
    final result = await showDialog<(int, int)>(
      context: context,
      builder: (_) => _CommandLimitDialog(
        limit: _cmdLimit,
        intervalSec: _cmdIntervalMSec > 0 ? _cmdIntervalMSec ~/ 1000 : 1,
      ),
    );
    if (result == null) return;
    setState(() {
      _cmdLimit = result.$1;
      _cmdIntervalMSec = result.$1 > 0 ? result.$2 * 1000 : 0;
    });
  }

  Future<void> _save() async {
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    final l10n = context.l10n;
    if (_username.text.trim().isEmpty) {
      final anon = await confirm(
        context,
        title: l10n.accountAnonymousTitle,
        message: l10n.accountAnonymousBody,
        confirmLabel: l10n.commonYes,
        cancelLabel: l10n.commonNo,
      );
      if (!anon) return;
    }
    final kbps = int.tryParse(_audioKbps.text.trim()) ?? 0;
    final account = TtUserAccount(
      username: _username.text.trim(),
      password: _isWebLogin ? '' : _password.text,
      userType: _userType,
      userRights: _admin ? 0 : _rights,
      note: _note.text,
      initChannel: _initChannel.text.trim(),
      autoOperatorChannels: _autoOps,
      audioCodecBpsLimit: kbps > 0 ? kbps * 1000 : 0,
      commandsLimit: _cmdLimit,
      commandsIntervalMSec: _cmdIntervalMSec,
    );
    setState(() => _saving = true);
    try {
      await ref.read(teamTalkClientProvider).createUserAccount(account);
      final saved = ref
          .read(appLocalizationsProvider)
          .accountSaved(account.username);
      messenger.showMessage(saved);
      ref.read(announcerProvider).announceShown(saved);
      navigator.pop(true);
    } on Object catch (e, st) {
      appLog.w('users', 'Saving user account failed', e, st);
      if (mounted) setState(() => _saving = false);
      reportFailure(ref, messenger, action: (l) => l.actionSave, error: e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final client = ref.read(teamTalkClientProvider);
    final account = widget.account;
    final l10n = context.l10n;
    final cmdLabel = _cmdLabel(l10n);
    return guardUnsaved(
      save: _save,
      child: Scaffold(
        appBar: AppBar(
          title: Text(_isNew ? l10n.accountNewTitle : l10n.accountEditTitle),
          actions: [
            TextButton(
              onPressed: _saving ? null : _save,
              child: Text(l10n.commonSave),
            ),
          ],
        ),
        body: ListView(
          padding: const EdgeInsets.symmetric(vertical: 8),
          children: [
            if (account != null &&
                (account.lastModified.isNotEmpty ||
                    account.lastLogin.isNotEmpty))
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: Text(
                  [
                    if (account.lastModified.isNotEmpty)
                      l10n.accountLastEdited(account.lastModified),
                    if (account.lastLogin.isNotEmpty)
                      l10n.accountLastLogin(account.lastLogin),
                  ].join('\n'),
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: TextField(
                controller: _username,
                readOnly: !_isNew,
                decoration: InputDecoration(labelText: l10n.commonUsername),
              ),
            ),
            if (!_isWebLogin)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: TextField(
                  controller: _password,
                  decoration: InputDecoration(labelText: l10n.commonPassword),
                ),
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: DropdownButtonFormField<int>(
                initialValue: _userType,
                isExpanded: true,
                decoration: InputDecoration(labelText: l10n.accountUserType),
                items: [
                  DropdownMenuItem(
                    value: 1,
                    child: Text(l10n.accountTypeDefault),
                  ),
                  DropdownMenuItem(
                    value: 2,
                    child: Text(l10n.accountTypeAdmin),
                  ),
                  DropdownMenuItem(
                    value: 0,
                    child: Text(l10n.accountTypeDisabled),
                  ),
                ],
                onChanged: (value) {
                  if (value != null) setState(() => _userType = value);
                },
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 4, 0),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _initChannel,
                      decoration: InputDecoration(
                        labelText: l10n.accountInitialChannel,
                        hintText: '/path/to/channel',
                      ),
                    ),
                  ),
                  Semantics(
                    label: l10n.accountPickInitialChannel,
                    button: true,
                    excludeSemantics: true,
                    onTap: _pickInitChannel,
                    child: IconButton(
                      icon: const Icon(Icons.list),
                      tooltip: l10n.accountPickChannel,
                      onPressed: _pickInitChannel,
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: TextField(
                controller: _audioKbps,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  labelText: l10n.accountCodecLimit,
                  hintText: l10n.accountNoLimitHint,
                ),
              ),
            ),
            Semantics(
              label: l10n.accountCommandLimitValue(cmdLabel),
              button: true,
              excludeSemantics: true,
              onTap: _chooseCommandLimit,
              child: ListTile(
                title: Text(l10n.accountCommandLimit),
                subtitle: Text(cmdLabel),
                trailing: const Icon(Icons.arrow_drop_down),
                onTap: _chooseCommandLimit,
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: TextField(
                controller: _note,
                maxLines: 3,
                decoration: InputDecoration(labelText: l10n.accountNote),
              ),
            ),
            SectionHeader(l10n.accountAutoOpChannels),
            for (final id in _autoOps)
              ListTile(
                dense: true,
                leading: const Icon(Icons.security),
                title: Text(
                  client.channelPath(id).isEmpty
                      ? l10n.accountChannelId(id)
                      : client.channelPath(id),
                ),
                trailing: Semantics(
                  label: l10n.accountRemoveAutoOp,
                  child: IconButton(
                    icon: const Icon(Icons.remove_circle_outline),
                    tooltip: l10n.commonRemove,
                    onPressed: () =>
                        setState(() => _autoOps = [..._autoOps]..remove(id)),
                  ),
                ),
              ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  icon: const Icon(Icons.add),
                  label: Text(l10n.accountAddAutoOp),
                  onPressed: _addAutoOp,
                ),
              ),
            ),
            if (!_admin) ...[
              SectionHeader(l10n.accountUserRights),
              for (final (label, bit) in _editableRights(l10n))
                CheckboxListTile(
                  dense: true,
                  title: Text(label),
                  value: (_rights & bit) != 0,
                  onChanged: (checked) => setState(() {
                    _rights = (checked ?? false)
                        ? (_rights | bit)
                        : (_rights & ~bit);
                  }),
                ),
            ],
          ],
        ),
      ),
    );
  }
}

class _CommandLimitDialog extends StatefulWidget {
  const _CommandLimitDialog({required this.limit, required this.intervalSec});

  final int limit;
  final int intervalSec;

  @override
  State<_CommandLimitDialog> createState() => _CommandLimitDialogState();
}

class _CommandLimitDialogState extends State<_CommandLimitDialog>
    with TextControllers {
  late final TextEditingController _limit;
  late final TextEditingController _interval;

  @override
  void initState() {
    super.initState();
    _limit = textController('${widget.limit}');
    _interval = textController('${widget.intervalSec}');
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return AlertDialog(
      title: Text(l10n.accountSetCommandLimit),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _limit,
            keyboardType: TextInputType.number,
            decoration: InputDecoration(
              labelText: l10n.accountCommandLimit,
              hintText: l10n.accountNoLimitHint,
            ),
          ),
          TextField(
            controller: _interval,
            keyboardType: TextInputType.number,
            decoration: InputDecoration(labelText: l10n.accountInterval),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.commonCancel),
        ),
        FilledButton(
          onPressed: () {
            final limit = int.tryParse(_limit.text.trim()) ?? 0;
            final interval = int.tryParse(_interval.text.trim()) ?? 1;
            Navigator.of(context).pop((limit, interval < 1 ? 1 : interval));
          },
          child: Text(l10n.commonOk),
        ),
      ],
    );
  }
}
