import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/db/store.dart';
import '../modules/finance/domain/ledger.dart' show basePrefKey;
import '../modules/finance/ui/common.dart';
import '../ui/format.dart';
import '../ui/hints.dart';
import '../ui/widgets.dart';
import 'providers.dart';
import 'pairing_dialogs.dart';
import 'sync_dialogs.dart';

final _fxProvider = FutureProvider<({bool auto, String? last})>((ref) async {
  ref.watch(revisionProvider);
  final db = ref.watch(sessionProvider).db;
  return (auto: await db.localSetting('fx.auto') != 'off', last: await db.localSetting('fx.last'));
});

class SettingsPage extends ConsumerWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final base = ref.watch(setupProvider).value;
    final hints = ref.watch(hintsProvider).value ?? const HintsState();
    return PageScaffold(
      title: 'Settings',
      children: [
        SectionCard(
          title: 'Base currency',
          hint: 'settings.base',
          child: Row(
            children: [
              Expanded(
                child: Text(
                  'Totals, reports and charts are shown in ${base ?? '–'}. Accounts keep their own currency.',
                ),
              ),
              const SizedBox(width: 12),
              OutlinedButton(
                onPressed: base == null ? null : () => _changeBase(context, ref, base),
                child: Text(base ?? '–'),
              ),
            ],
          ),
        ),
        SectionCard(
          title: 'Hints',
          padding: const EdgeInsets.only(bottom: 8),
          child: Column(
            children: [
              SwitchListTile(
                title: const Text('Show hints'),
                subtitle: const Text('Explanations on hover or long-press, and tips at the top of pages.'),
                value: hints.enabled,
                onChanged: (v) => ref.read(hintsProvider.notifier).setEnabled(v),
              ),
              ListTile(
                title: const Text('Restore hints'),
                subtitle: Text(
                  hints.dismissed.isEmpty
                      ? 'No tips dismissed.'
                      : '${hints.dismissed.length} dismissed ${hints.dismissed.length == 1 ? 'tip' : 'tips'}.',
                ),
                trailing: Hint(
                  'settings.restoreHints',
                  child: OutlinedButton(
                    onPressed: () async {
                      await ref.read(hintsProvider.notifier).restore();
                      if (context.mounted) showMessage(context, 'Hints are back on.');
                    },
                    child: const Text('Restore'),
                  ),
                ),
              ),
            ],
          ),
        ),
        SectionCard(
          title: 'Exchange rates',
          hint: 'settings.fx',
          padding: const EdgeInsets.only(bottom: 8),
          child: AsyncView(
            ref.watch(_fxProvider),
            builder: (fx) => Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SwitchListTile(
                  title: const Text('Update daily'),
                  subtitle: const Text(
                    'Fetches European Central Bank reference rates from frankfurter.dev once a day. Only '
                    'currency codes are sent.',
                  ),
                  value: fx.auto,
                  onChanged: (v) async {
                    await ref.read(sessionProvider).db.setLocalSetting('fx.auto', v ? 'on' : 'off');
                    ref.invalidate(_fxProvider);
                  },
                ),
                ListTile(
                  title: const Text('Last updated'),
                  subtitle: Text(fx.last == null ? 'Never' : niceDate(fx.last!)),
                  trailing: OutlinedButton(
                    onPressed: base == null ? null : () => _refreshRates(context, ref, base),
                    child: const Text('Update now'),
                  ),
                ),
              ],
            ),
          ),
        ),
        const _SyncCard(),
        SectionCard(
          title: 'Security and privacy',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final (icon, text) in const [
                (
                  Icons.lock_outline,
                  'The database on this device is encrypted with ChaCha20-Poly1305 (SQLite3MultipleCiphers). '
                      'Its key is kept in the system keychain.',
                ),
                (
                  Icons.cloud_off_outlined,
                  'Nothing leaves the device unless you sign in to sync or fetch exchange rates.',
                ),
                (
                  Icons.enhanced_encryption_outlined,
                  'Sync is end-to-end encrypted with XChaCha20-Poly1305. Keys come from your password '
                      'through Argon2id. The server stores only ciphertext and cannot read your data.',
                ),
                (
                  Icons.key_outlined,
                  'Your password and recovery key never leave this device. Lose both and synced data '
                      'cannot be recovered; data on this device is unaffected.',
                ),
              ])
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(icon, size: 20),
                      const SizedBox(width: 12),
                      Expanded(child: Text(text)),
                    ],
                  ),
                ),
            ],
          ),
        ),
        SectionCard(
          title: 'About',
          padding: const EdgeInsets.only(bottom: 8),
          child: ListTile(
            title: const Text('Artha'),
            subtitle: const Text(
              'Personal finance, part of a life ERP. Open-source licences of included software.',
            ),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => showLicensePage(context: context, applicationName: 'Artha'),
          ),
        ),
      ],
    );
  }

  Future<void> _changeBase(BuildContext context, WidgetRef ref, String current) async {
    var picked = current;
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: const Text('Base currency'),
          content: SizedBox(
            width: 400,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                CurrencyField(value: picked, label: 'Currency', onChanged: (c) => setState(() => picked = c)),
                const SizedBox(height: 12),
                const Text(
                  'Reports are converted at stored exchange rates. Existing categories stay in their '
                  'currency; new ones use the new base. Synced devices switch too.',
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
            FilledButton(
              onPressed: picked == current ? null : () => Navigator.pop(context, true),
              child: const Text('Change'),
            ),
          ],
        ),
      ),
    );
    if (ok != true || !context.mounted) return;
    if (await guarded(context, () => ref.mutate((s) => s.ledger.setPref(basePrefKey, picked))) &&
        context.mounted) {
      await _refreshRates(context, ref, picked);
    }
  }

  Future<void> _refreshRates(BuildContext context, WidgetRef ref, String base) async {
    var stored = 0;
    final ok = await guarded(context, () async {
      stored = await ref.mutate((s) => refreshRates(s, base));
    });
    if (ok && context.mounted) {
      showMessage(context, stored == 0 ? 'Rates are up to date.' : 'Stored $stored exchange rates.');
    }
  }
}

class _SyncCard extends ConsumerWidget {
  const _SyncCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sync = ref.watch(syncProvider);
    final signedOut = sync.phase == SyncPhase.signedOut;
    return SectionCard(
      title: 'Sync',
      hint: 'settings.sync',
      padding: const EdgeInsets.only(bottom: 8),
      child: signedOut
          ? Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text(
                    'Keep Artha in step across your devices through your own sync server. '
                    'Everything is encrypted on the device first.',
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      FilledButton.icon(
                        onPressed: () => showJoinDialog(context),
                        icon: const Icon(Icons.devices_outlined),
                        label: const Text('Join from another device'),
                      ),
                      OutlinedButton(
                        onPressed: () => showSyncDialog(context, mode: SyncMode.signIn),
                        child: const Text('Sign in with e-mail'),
                      ),
                      TextButton(
                        onPressed: () => showSyncDialog(context, mode: SyncMode.signUp),
                        child: const Text('Create account'),
                      ),
                    ],
                  ),
                ],
              ),
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                ListTile(
                  leading: const Icon(Icons.account_circle_outlined),
                  title: Text(sync.email ?? 'Signed in'),
                  subtitle: Text(sync.server ?? ''),
                ),
                ListTile(
                  leading: const Icon(Icons.qr_code_2),
                  title: const Text('Add a device'),
                  subtitle: const Text('Show a code your phone or another computer can join with'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => showAddDevice(context),
                ),
                ListTile(
                  leading: Icon(switch (sync.phase) {
                    SyncPhase.failed => Status.critical.icon,
                    SyncPhase.running => Icons.sync,
                    _ => Status.good.icon,
                  }, color: sync.phase == SyncPhase.failed ? Status.critical.color : null),
                  title: Text(switch (sync.phase) {
                    SyncPhase.running => 'Syncing…',
                    SyncPhase.failed => 'Last sync failed',
                    _ => sync.lastSync == null ? 'Not synced yet' : 'Synced',
                  }),
                  subtitle: Text(
                    [
                      if (sync.error != null) sync.error!,
                      if (sync.lastSync != null) 'Last success ${_when(sync.lastSync!)}',
                    ].join('\n'),
                  ),
                  trailing: OutlinedButton(
                    onPressed: sync.phase == SyncPhase.running
                        ? null
                        : () => ref.read(syncProvider.notifier).run(),
                    child: const Text('Sync now'),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: Wrap(
                    spacing: 8,
                    children: [
                      TextButton(
                        onPressed: () => showChangePassword(context, ref),
                        child: const Text('Change password'),
                      ),
                      TextButton(
                        onPressed: () async {
                          final yes = await confirm(
                            context,
                            title: 'Sign out of sync?',
                            message:
                                'Data stays on this device and on the server. Signing back in needs your '
                                'password, or your recovery key if the password changed.',
                            action: 'Sign out',
                          );
                          if (yes && context.mounted) {
                            await guarded(context, () => ref.read(syncProvider.notifier).signOut());
                          }
                        },
                        child: const Text('Sign out'),
                      ),
                    ],
                  ),
                ),
              ],
            ),
    );
  }

  static String _when(String iso) {
    final t = DateTime.tryParse(iso)?.toLocal();
    if (t == null) return iso;
    final hm = '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
    return '${niceDate(t.toIso8601String().substring(0, 10))} at $hm';
  }
}
