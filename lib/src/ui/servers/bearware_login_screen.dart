import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/servers/bearware_login.dart';
import '../../app/settings/locale_providers.dart';
import '../../diagnostics/log.dart';
import '../../l10n/l10n.dart';
import '../../ui/common/failure_report.dart';
import '../common/password_field.dart';
import '../common/ui.dart';

class BearwareLoginScreen extends ConsumerStatefulWidget {
  const BearwareLoginScreen({super.key});

  @override
  ConsumerState<BearwareLoginScreen> createState() =>
      _BearwareLoginScreenState();
}

class _BearwareLoginScreenState extends ConsumerState<BearwareLoginScreen> {
  final _username = TextEditingController();
  final _password = TextEditingController();
  bool _busy = false;

  Future<void> _login() async {
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _busy = true);
    try {
      final result = await authenticateBearware(
        _username.text.trim(),
        _password.text,
      );
      if (result == null) {
        messenger.showMessage(
          ref.read(appLocalizationsProvider).bearwareLoginFailed,
        );
        return;
      }
      ref
          .read(bearwareAccountProvider.notifier)
          .save(
            BearwareAccount(username: result.username, token: result.token),
          );
      messenger.showMessage(
        ref
            .read(appLocalizationsProvider)
            .bearwareLoggedInAs(
              result.nickname.isEmpty ? result.username : result.nickname,
            ),
      );
      _password.clear();
    } on Object catch (e, st) {
      appLog.w('bearware', 'BearWare login failed', e, st);
      reportFailure(ref, messenger, action: (l) => l.actionLogin, error: e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final account = ref.watch(bearwareAccountProvider);
    final l10n = context.l10n;

    return Scaffold(
      appBar: AppBar(title: Text(l10n.bearwareTitle)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (account.isLinked) ...[
            ListTile(
              leading: const Icon(Icons.verified_user),
              title: Text(l10n.bearwareLinkedAs(account.username)),
              subtitle: Text(l10n.bearwareLinkedHint),
            ),
            FilledButton.tonal(
              onPressed: () {
                ref.read(bearwareAccountProvider.notifier).reset();
                ScaffoldMessenger.of(
                  context,
                ).showMessage(l10n.bearwareUnlinked);
              },
              child: Text(l10n.bearwareUnlink),
            ),
            const Divider(height: 32),
          ],
          Text(l10n.bearwareIntro),
          TextField(
            controller: _username,
            decoration: InputDecoration(labelText: l10n.bearwareId),
            autocorrect: false,
          ),
          PasswordField(controller: _password, label: l10n.commonPassword),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: _busy ? null : _login,
            child: _busy
                ? Semantics(
                    label: l10n.bearwareLoggingIn,
                    child: const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  )
                : Text(l10n.bearwareLogIn),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _username.dispose();
    _password.dispose();
    super.dispose();
  }
}
