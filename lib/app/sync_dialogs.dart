import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/security/crypto.dart' show minPasswordLength;
import '../core/sync/account_service.dart';
import '../core/sync/pairing.dart';
import '../ui/widgets.dart';
import 'providers.dart';

enum SyncMode { signUp, signIn, reset }

/// Sign up, sign in or reset a forgotten password. Returns true when the
/// device ends up signed in. A [setup] link from the server fills in its
/// address and invite code.
Future<bool> showSyncDialog(
  BuildContext context, {
  SyncMode mode = SyncMode.signIn,
  SetupLink? setup,
}) async =>
    await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _SyncDialog(mode, setup),
    ) ??
    false;

class _SyncDialog extends ConsumerStatefulWidget {
  const _SyncDialog(this.mode, this.setup);
  final SyncMode mode;
  final SetupLink? setup;

  @override
  ConsumerState<_SyncDialog> createState() => _SyncDialogState();
}

class _SyncDialogState extends ConsumerState<_SyncDialog> {
  final _form = GlobalKey<FormState>();
  final _server = TextEditingController(text: 'https://');
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  final _invite = TextEditingController();
  final _token = TextEditingController();
  final _recovery = TextEditingController();
  late SyncMode _mode = widget.mode;
  bool _busy = false, _resetSent = false, _show = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    if (widget.setup != null) _useSetup(widget.setup!);
  }

  void _useSetup(SetupLink link) {
    _server.text = '${link.server}';
    _invite.text = link.invite;
  }

  /// The server address field also takes a pasted `artha://` link.
  void _serverChanged(String text) {
    if (!text.trim().startsWith('artha://')) return;
    setState(() {
      try {
        switch (ArthaLink.parse(text)) {
          case SetupLink() && final link:
            _useSetup(link);
            _mode = SyncMode.signUp;
            _error = null;
          case PairingLink():
            _server.clear();
            _error = 'That is a link to join another device. Close this and choose Join from another device.';
        }
      } catch (e) {
        _error = describeError(e);
      }
    });
  }

  @override
  void dispose() {
    for (final c in [_server, _email, _password, _confirm, _invite, _token, _recovery]) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final title = switch (_mode) {
      SyncMode.signUp => 'Create sync account',
      SyncMode.signIn => 'Sign in to sync',
      SyncMode.reset => 'Reset password',
    };
    final needsPassword = _mode != SyncMode.reset || _resetSent;
    return AlertDialog(
      title: Text(title),
      content: SizedBox(
        width: 420,
        child: Form(
          key: _form,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(switch (_mode) {
                  SyncMode.signUp =>
                    'Your data is encrypted on this device before it is sent. The server, and anyone who '
                        'can read it, sees only ciphertext.',
                  SyncMode.signIn =>
                    'Use the server address, e-mail and password of your Artha sync account.',
                  SyncMode.reset =>
                    'The server e-mails you a reset code. Your recovery key is needed too, because only '
                        'it can unlock your encrypted data without the old password.',
                }),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _server,
                  enabled: !_resetSent,
                  keyboardType: TextInputType.url,
                  onChanged: _serverChanged,
                  decoration: const InputDecoration(
                    labelText: 'Server address',
                    helperText: 'Or paste the setup link the server printed.',
                  ),
                  validator: (v) => (v ?? '').trim().length < 10 ? 'Enter the server address' : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _email,
                  enabled: !_resetSent,
                  keyboardType: TextInputType.emailAddress,
                  autofillHints: const [AutofillHints.email],
                  decoration: const InputDecoration(labelText: 'E-mail'),
                  validator: (v) => (v ?? '').contains('@') ? null : 'Enter your e-mail',
                ),
                if (_mode == SyncMode.reset && _resetSent) ...[
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _token,
                    decoration: const InputDecoration(labelText: 'Code from the e-mail'),
                    validator: (v) => (v ?? '').trim().length < 20 ? 'Paste the whole code' : null,
                  ),
                ],
                if (needsPassword) ...[
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _password,
                    obscureText: !_show,
                    autofillHints: [
                      _mode == SyncMode.signIn ? AutofillHints.password : AutofillHints.newPassword,
                    ],
                    decoration: InputDecoration(
                      labelText: _mode == SyncMode.signIn ? 'Password' : 'New password',
                      helperText: _mode == SyncMode.signIn
                          ? null
                          : 'At least $minPasswordLength characters; a passphrase is best.',
                      suffixIcon: IconButton(
                        tooltip: _show ? 'Hide password' : 'Show password',
                        icon: Icon(_show ? Icons.visibility_off_outlined : Icons.visibility_outlined),
                        onPressed: () => setState(() => _show = !_show),
                      ),
                    ),
                    validator: (v) {
                      if (_mode == SyncMode.signIn) return (v ?? '').isEmpty ? 'Enter your password' : null;
                      return (v ?? '').length < minPasswordLength
                          ? 'Use at least $minPasswordLength characters'
                          : null;
                    },
                  ),
                  if (_mode != SyncMode.signIn) ...[
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _confirm,
                      obscureText: !_show,
                      decoration: const InputDecoration(labelText: 'Repeat password'),
                      validator: (v) => v == _password.text ? null : 'Passwords differ',
                    ),
                  ],
                ],
                if (_mode == SyncMode.signUp) ...[
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _invite,
                    obscureText: true,
                    decoration: const InputDecoration(
                      labelText: 'Invite code',
                      helperText: 'Part of the setup link; also ARTHA_SIGNUP_CODE on the server.',
                    ),
                    validator: (v) => (v ?? '').trim().isEmpty ? 'Enter the invite code' : null,
                  ),
                ],
                if (_mode == SyncMode.reset && _resetSent) ...[
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _recovery,
                    decoration: const InputDecoration(labelText: 'Recovery key'),
                    validator: (v) => (v ?? '').trim().length < 20 ? 'Enter your recovery key' : null,
                  ),
                ],
                if (_error != null) ...[const SizedBox(height: 12), StatusLabel(Status.critical, _error!)],
                const SizedBox(height: 8),
                Wrap(
                  children: [
                    if (_mode != SyncMode.signIn)
                      TextButton(
                        onPressed: _busy ? null : () => setState(() => _mode = SyncMode.signIn),
                        child: const Text('I have an account'),
                      ),
                    if (_mode != SyncMode.signUp)
                      TextButton(
                        onPressed: _busy ? null : () => setState(() => _mode = SyncMode.signUp),
                        child: const Text('Create an account'),
                      ),
                    if (_mode == SyncMode.signIn)
                      TextButton(
                        onPressed: _busy ? null : () => setState(() => _mode = SyncMode.reset),
                        child: const Text('Forgot password'),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.pop(context, false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _busy ? null : _submit,
          child: _busy
              ? const SizedBox.square(dimension: 18, child: CircularProgressIndicator(strokeWidth: 2))
              : Text(switch (_mode) {
                  SyncMode.signUp => 'Create',
                  SyncMode.signIn => 'Sign in',
                  SyncMode.reset => _resetSent ? 'Reset' : 'Send code',
                }),
        ),
      ],
    );
  }

  Future<void> _submit() async {
    if (!_form.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    final account = ref.read(sessionProvider).account;
    final server = _server.text.trim(), email = _email.text.trim();
    try {
      switch (_mode) {
        case SyncMode.signUp:
          final key = await account.signUp(
            server: server,
            email: email,
            password: _password.text,
            invite: _invite.text.trim(),
          );
          if (mounted) await showRecoveryKey(context, key);
        case SyncMode.signIn:
          try {
            await account.signIn(server: server, email: email, password: _password.text);
          } on RecoveryKeyNeeded {
            if (!mounted) return;
            final key = await _askRecoveryKey(context);
            if (key == null) {
              setState(() => _busy = false);
              return;
            }
            await account.unlockWithRecoveryKey(key);
          }
        case SyncMode.reset:
          if (!_resetSent) {
            await account.requestPasswordReset(server: server, email: email);
            setState(() {
              _resetSent = true;
              _busy = false;
            });
            return;
          }
          await account.resetPassword(
            server: server,
            email: email,
            token: _token.text.trim(),
            newPassword: _password.text,
            recoveryKey: _recovery.text.trim(),
          );
      }
      await ref.read(syncProvider.notifier).run();
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = describeError(e);
        });
      }
    }
  }
}

Future<String?> _askRecoveryKey(BuildContext context) {
  final c = TextEditingController();
  return showDialog<String>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Recovery key'),
      content: SizedBox(
        width: 400,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'The password changed on another device, or a change did not finish. Enter the recovery key '
              'you saved when you created the account.',
            ),
            const SizedBox(height: 12),
            TextField(
              controller: c,
              autofocus: true,
              decoration: const InputDecoration(labelText: 'Recovery key'),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(onPressed: () => Navigator.pop(context, c.text.trim()), child: const Text('Unlock')),
      ],
    ),
  );
}

/// Shows the recovery key once; the user must confirm they saved it.
Future<void> showRecoveryKey(BuildContext context, String key) {
  var saved = false;
  return showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (context) => StatefulBuilder(
      builder: (context, setState) => AlertDialog(
        title: const Text('Save your recovery key'),
        content: SizedBox(
          width: 440,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'If you forget your password, this key is the only way to unlock your synced data. '
                'Artha shows it once and does not store it. Write it down or keep it in a password manager.',
              ),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: SelectableText(
                  key,
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontFamily: 'monospace', fontSize: 16, letterSpacing: 1),
                ),
              ),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton.icon(
                  onPressed: () async {
                    await Clipboard.setData(ClipboardData(text: key));
                    if (context.mounted) {
                      showMessage(
                        context,
                        'Copied. Paste it into your password manager, then clear the clipboard.',
                      );
                    }
                  },
                  icon: const Icon(Icons.copy, size: 18),
                  label: const Text('Copy'),
                ),
              ),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                value: saved,
                onChanged: (v) => setState(() => saved = v ?? false),
                title: const Text('I have saved it somewhere safe'),
              ),
            ],
          ),
        ),
        actions: [
          FilledButton(onPressed: saved ? () => Navigator.pop(context) : null, child: const Text('Done')),
        ],
      ),
    ),
  );
}

Future<void> showChangePassword(BuildContext context, WidgetRef ref) async {
  final old = TextEditingController(), fresh = TextEditingController(), again = TextEditingController();
  final form = GlobalKey<FormState>();
  final ok = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Change password'),
      content: SizedBox(
        width: 400,
        child: Form(
          key: form,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: old,
                obscureText: true,
                decoration: const InputDecoration(labelText: 'Current password'),
                validator: (v) => (v ?? '').isEmpty ? 'Enter your current password' : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: fresh,
                obscureText: true,
                decoration: const InputDecoration(labelText: 'New password'),
                validator: (v) => (v ?? '').length < minPasswordLength
                    ? 'Use at least $minPasswordLength characters'
                    : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: again,
                obscureText: true,
                decoration: const InputDecoration(labelText: 'Repeat new password'),
                validator: (v) => v == fresh.text ? null : 'Passwords differ',
              ),
              const SizedBox(height: 12),
              const Text('Other devices ask for the new password the next time they sync.'),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
        FilledButton(
          onPressed: () {
            if (form.currentState!.validate()) Navigator.pop(context, true);
          },
          child: const Text('Change'),
        ),
      ],
    ),
  );
  if (ok != true || !context.mounted) return;
  if (await guarded(
        context,
        () =>
            ref.read(sessionProvider).account.changePassword(oldPassword: old.text, newPassword: fresh.text),
      ) &&
      context.mounted) {
    showMessage(context, 'Password changed.');
  }
}
