import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../app/providers.dart';

/// Every hint in the app, by id. Tooltips use the short ones; page banners
/// (ids starting `page.`) explain a whole screen once.
const hints = <String, String>{
  // Navigation
  'nav.dashboard': 'Net worth, cash flow and what needs attention, at a glance.',
  'nav.accounts': 'Bank accounts, cards, savings, ISAs, investments and loans.',
  'nav.transactions': 'Every transaction. Add, edit, split and search them here.',
  'nav.portfolio': 'What your investments are worth, how they are spread and how to rebalance.',
  'nav.insights': 'Patterns in your money, and options worth exploring.',
  'nav.reports': 'Balance sheet, income statement, trial balance and checks.',
  'nav.import': 'Bring in bank statements (CSV, OFX, QFX, QIF).',
  'nav.settings': 'Currency, hints, exchange rates, sync and security.',
  'nav.more': 'The rest of Artha.',
  // Dashboard
  'kpi.networth': 'Everything you own minus everything you owe, in your base currency.',
  'kpi.liquid': 'Money you can use within days: current, savings, cash and cash ISAs.',
  'kpi.debt': 'Cards, loans, overdrafts and mortgages still owed.',
  'kpi.savings': 'Share of income left after spending, averaged over recent full months.',
  'kpi.emergency': 'How many months of essential spending your easy-access money covers.',
  'chart.networth': 'Net worth at the end of each month. Hover or touch a point for the figure.',
  'chart.flows': 'Income and spending per month. Hover or touch a bar for the figures.',
  'card.tally': 'Ledger balance compared with the last statement balance you recorded.',
  'card.attention': 'The most useful insights right now. Open Insights for all of them.',
  'card.missing': 'These hold value but have no exchange rate or price yet, so totals leave them out.',
  // Accounts
  'accounts.add': 'Add a bank account, card, savings, ISA, investment, property or loan.',
  'accounts.balance': 'Statement balance check: record what the bank says to see if the ledger agrees.',
  'accounts.closed': 'Closed accounts keep their history but take no new transactions.',
  // Transactions
  'tx.add': 'Record spending, income, a transfer or a trade.',
  'tx.search': 'Search payee and notes.',
  'tx.kind': 'Spending and income use a category; a transfer moves money between your own accounts.',
  'tx.toAmount': 'Amount that arrived, in the receiving account’s currency. Sets the exchange rate.',
  'tx.split': 'Entries with more than two lines, and trades, open read-only.',
  // Import
  'import.pick': 'Choose a statement file. Nothing leaves this device.',
  'import.status': 'New rows are added; duplicates are skipped; matches link to entries you typed; transfers merge with the other account.',
  'import.category': 'Suggested from your rules and past choices. Change it and Artha learns.',
  // Portfolio
  'portfolio.profile': 'Pick how much ups and downs you can live with. It sets the target mix.',
  'portfolio.drift': 'How far each asset class is from its target. Flags use the 5/25 rule.',
  'portfolio.newMoney': 'Splits new money towards the targets without selling anything.',
  'portfolio.trade': 'Record a buy or sell of a fund, share, bond or crypto.',
  'portfolio.price': 'Record today’s price of a holding to value it.',
  // Insights
  'insights.useful': 'Keep insights like this one higher up.',
  'insights.dismiss': 'Hide this one and show fewer like it.',
  'insights.remember': 'Tell Artha about a goal or a coming cost so suggestions fit.',
  'insights.explore': 'Common ways to save and invest in the UK, with their trade-offs.',
  // Reports
  'reports.period': 'Period the income statement covers.',
  'reports.integrity': 'Checks that every entry balances and points at a real account.',
  // Settings
  'settings.hints': 'Show these tips and the explanations at the top of each page.',
  'settings.restoreHints': 'Turn hints on and show every page explanation again.',
  'settings.fx': 'Fetch European Central Bank reference rates for the currencies you use.',
  'settings.sync':
      'Keep devices in step through your own server. Data is encrypted before it leaves the device.',
  'settings.base': 'Totals, charts and reports are shown in this currency.',
  // Page banners
  'page.dashboard':
      'This is your financial overview. Add accounts and import a statement, and the charts fill in. '
      'Hover or long-press anything for a tip.',
  'page.accounts':
      'Each account keeps its own currency. Record a statement balance now and then: the tick shows '
      'when the ledger agrees with the bank.',
  'page.transactions':
      'Artha uses double-entry bookkeeping behind the scenes: every amount leaves one account and '
      'lands in another, so the books always balance.',
  'page.import':
      'Export a statement from online banking as CSV, OFX, QFX or QIF. Artha spots duplicates, '
      'matches entries you typed and merges both sides of transfers.',
  'page.portfolio':
      'Holdings are valued with the latest price you recorded and today’s exchange rates. '
      'Targets drive the rebalancing and new-money suggestions.',
  'page.insights':
      'Insights are worked out on this device from your own data. Mark them useful or not and the '
      'list adapts. Nothing here is financial advice.',
  'page.reports':
      'Business-standard statements from the same ledger. The trial balance must net to zero in '
      'every currency; the integrity check confirms it.',
};

/// Wraps [child] in a tooltip with hint [id], unless hints are off.
class Hint extends ConsumerWidget {
  const Hint(this.id, {super.key, required this.child});
  final String id;
  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final on = ref.watch(hintsProvider).value?.enabled ?? true;
    final text = hints[id];
    if (!on || text == null) return child;
    return Tooltip(message: text, child: child);
  }
}

/// An icon button whose tooltip is the hint when hints are on and the plain
/// [label] otherwise, so screen readers always get a label.
class HintIconButton extends ConsumerWidget {
  const HintIconButton(this.id, {super.key, required this.icon, required this.label, this.onPressed});
  final String id;
  final IconData icon;
  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final on = ref.watch(hintsProvider).value?.enabled ?? true;
    final hint = hints[id];
    return IconButton(
      icon: Icon(icon),
      tooltip: on && hint != null ? '$label: $hint' : label,
      onPressed: onPressed,
    );
  }
}

/// A page explanation that fades in and can be dismissed ("Got it").
/// Settings > Hints brings dismissed ones back.
class HintBanner extends ConsumerStatefulWidget {
  const HintBanner(this.id, {super.key});
  final String id;

  @override
  ConsumerState<HintBanner> createState() => _HintBannerState();
}

class _HintBannerState extends ConsumerState<HintBanner> {
  bool _closing = false;

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(hintsProvider).value;
    final text = hints[widget.id];
    final visible = state != null && state.shows(widget.id) && text != null;
    final scheme = Theme.of(context).colorScheme;
    return AnimatedSize(
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOut,
      child: !visible
          ? const SizedBox(width: double.infinity)
          : TweenAnimationBuilder<double>(
              tween: Tween(begin: 0, end: _closing ? 0 : 1),
              duration: const Duration(milliseconds: 400),
              curve: Curves.easeOut,
              onEnd: () {
                if (_closing) ref.read(hintsProvider.notifier).dismiss(widget.id);
              },
              builder: (context, t, child) => Opacity(opacity: t, child: child),
              child: Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: Card(
                  color: scheme.secondaryContainer,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
                    child: Row(
                      children: [
                        Icon(Icons.lightbulb_outline, color: scheme.onSecondaryContainer),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(text, style: TextStyle(color: scheme.onSecondaryContainer)),
                        ),
                        TextButton(
                          onPressed: _closing ? null : () => setState(() => _closing = true),
                          child: const Text('Got it'),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
    );
  }
}
