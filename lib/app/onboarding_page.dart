import 'dart:ui';

import 'package:brahma_core/brahma_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../modules/finance/ui/common.dart';
import 'providers.dart';

/// The currency of the device's region, if Artha knows it.
String _localCurrency() {
  try {
    final code = NumberFormat.simpleCurrency(locale: PlatformDispatcher.instance.locale.toString())
        .currencyName;
    if (code != null && currencies.containsKey(code)) return code;
  } on Object {
    // Unknown locale: fall through.
  }
  return 'GBP';
}

/// First run: pick the base currency, or sign in to bring data from another
/// device.
class OnboardingPage extends ConsumerStatefulWidget {
  const OnboardingPage({super.key});

  @override
  ConsumerState<OnboardingPage> createState() => _OnboardingPageState();
}

class _OnboardingPageState extends ConsumerState<OnboardingPage> {
  String _base = _localCurrency();
  bool _busy = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final sync = ref.watch(syncProvider);
    final joined = sync.phase != SyncPhase.signedOut && sync.lastSync != null;
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 480),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  CircleAvatar(
                    radius: 32,
                    backgroundColor: theme.colorScheme.primary,
                    child: Text(
                      'A',
                      style: theme.textTheme.headlineMedium?.copyWith(color: theme.colorScheme.onPrimary),
                    ),
                  ),
                  const SizedBox(height: 24),
                  Text(
                    'Welcome to Artha',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.headlineMedium,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Accounts, spending, investments and reports in one private, double-entry ledger.',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodyLarge,
                  ),
                  const SizedBox(height: 24),
                  for (final (icon, text) in const [
                    (
                      Icons.lock_outline,
                      'Encrypted on this device. Nothing is sent anywhere unless you turn on sync.',
                    ),
                    (
                      Icons.currency_exchange,
                      'Any mix of currencies; totals are shown in your base currency.',
                    ),
                    (
                      Icons.fact_check_outlined,
                      'Statements are tallied against your records, so mistakes show up.',
                    ),
                  ])
                    ListTile(contentPadding: EdgeInsets.zero, leading: Icon(icon), title: Text(text)),
                  const SizedBox(height: 16),
                  CurrencyField(
                    value: _base,
                    label: 'Base currency',
                    onChanged: (c) => setState(() => _base = c),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Usually the currency you are paid in. You can change it later.',
                    style: theme.textTheme.bodySmall,
                  ),
                  const SizedBox(height: 16),
                  FilledButton(
                    onPressed: _busy ? null : _start,
                    child: Text(joined ? 'Continue' : 'Get started'),
                  ),
                  const SizedBox(height: 24),
                  const Divider(),
                  const SizedBox(height: 8),
                  if (joined)
                    StatusLabel(
                      Status.info,
                      'Signed in as ${sync.email}. The account has no data yet, so choose a base currency.',
                    )
                  else ...[
                    Text(
                      'Already use Artha on another device?',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.titleSmall,
                    ),
                    const SizedBox(height: 8),
                    OutlinedButton.icon(
                      onPressed: _busy ? null : () => showJoinDialog(context),
                      icon: const Icon(Icons.devices_outlined),
                      label: const Text('Join from another device'),
                    ),
                    TextButton(
                      onPressed: _busy ? null : () => showSyncDialog(context),
                      child: const Text('Sign in with e-mail instead'),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _start() async {
    setState(() => _busy = true);
    // On success the root rebuilds into the app and this page goes away.
    if (!await guarded(context, () => ref.mutate((s) => s.ledger.setUp(_base))) && mounted) {
      setState(() => _busy = false);
    }
  }
}
