import 'package:brahma_core/brahma_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app/app.dart';
import 'app/appearance.dart';
import 'app/providers.dart';
import 'app/session.dart';
import 'ui/hints.dart';

/// Artha as the Brahma suite app hosts it.
final arthaSuite = SuiteApp(
  identity: arthaIdentity,
  tagline: 'Money, accounts and investments',
  icon: Icons.account_balance_wallet_outlined,
  open: AppSession.open,
  overrides: (s) => [sessionProvider.overrideWithValue(s as AppSession)],
  hints: arthaHints,
  theme: arthaTheme,
  themeMode: (ref) => ref.watch(appearanceProvider).value?.mode,
  home: (onHome) => ArthaHome(onHome: onHome),
  onStart: startRateRefresh,
  summary: (_) => const _Summary(),
);

class _Summary extends ConsumerWidget {
  const _Summary();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (ref.watch(setupProvider).value == null) {
      return const SummaryFigures([], next: 'Open Artha to choose your base currency.');
    }
    final d = ref.watch(dashboardProvider).value;
    final cur = ref.watch(baseCurrencyProvider).value;
    if (d == null || cur == null) return const SizedBox(height: 48);
    final month = d.flows.isEmpty ? null : d.flows.last;
    return SummaryFigures([
      (money(d.sheet.netWorth, cur, compact: true), 'net worth'),
      (money(month?.income ?? 0, cur, compact: true), 'income this month'),
      (money(month?.expenses ?? 0, cur, compact: true), 'spent this month'),
    ], next: d.integrity.isEmpty ? null : '${d.integrity.length} entries fail the integrity check.');
  }
}
