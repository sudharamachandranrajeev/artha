import 'package:brahma_core/brahma_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
import '../../../ui/components.dart';
import '../../../ui/theme.dart';

/// Monthly budgets per expense category, set and tracked in the base currency.
class BudgetsPage extends ConsumerWidget {
  const BudgetsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cur = ref.watch(setupProvider).value ?? 'GBP';
    return PageScaffold(
      title: 'Budgets',
      banner: 'page.budgets',
      children: [
        AsyncView(
          ref.watch(budgetsProvider),
          onRetry: () => ref.invalidate(budgetsProvider),
          builder: (lines) => lines.isEmpty
              ? const Card(
                  child: EmptyState(
                    icon: Icons.savings_outlined,
                    title: 'No expense categories yet',
                    message: 'Categories appear here once you record or import some spending.',
                  ),
                )
              : Card(
                  child: Column(
                    children: [
                      for (final l in lines) BudgetRow(l, cur, onTap: () => editBudget(context, ref, l, cur)),
                    ],
                  ),
                ),
        ),
      ],
    );
  }
}

/// A category's spending this month over its budget track. Over budget turns
/// the figure to the warning colour with an icon.
class BudgetRow extends StatelessWidget {
  const BudgetRow(this.line, this.currency, {super.key, this.onTap});
  final BudgetLine line;
  final String currency;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final skin = ArthaSkin.of(context);
    final over = line.budget > 0 && line.spent > line.budget;
    final caption = TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: skin.muted);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 14, 20, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    line.account.name,
                    style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                  ),
                ),
                if (over) ...[
                  Icon(Status.warning.icon, size: 16, color: Status.warning.color),
                  const SizedBox(width: 4),
                ],
                Text(
                  money(line.spent, currency),
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: over ? Status.warning.color : null,
                  ).merge(tabular),
                ),
              ],
            ),
            const SizedBox(height: 8),
            if (line.budget > 0) ...[
              TweenAnimationBuilder<double>(
                tween: Tween(begin: 0, end: line.used),
                duration: Motion.reduced(context) ? Duration.zero : Motion.medium * 2,
                curve: Motion.curve,
                builder: (context, v, _) => ProgressLine(value: v, height: 6),
              ),
              const SizedBox(height: 6),
              Text(
                over
                    ? '${money(line.spent - line.budget, currency)} over ${money(line.budget, currency)}'
                    : '${money(line.budget - line.spent, currency)} left of ${money(line.budget, currency)}',
                style: caption,
              ),
            ] else
              Text('No budget · tap to set one', style: caption),
          ],
        ),
      ),
    );
  }
}

Future<void> editBudget(BuildContext context, WidgetRef ref, BudgetLine line, String cur) async {
  final scale = currencyInfo(cur).scale;
  final amount = TextEditingController(text: line.budget > 0 ? units(line.budget, scale) : '');
  final form = GlobalKey<FormState>();
  final ok = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text('Budget for ${line.account.name}'),
      content: Form(
        key: form,
        child: TextFormField(
          controller: amount,
          autofocus: true,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: InputDecoration(labelText: 'Per month ($cur)', helperText: 'Leave empty for no budget'),
          validator: (v) {
            if ((v ?? '').trim().isEmpty) return null;
            final x = parseMinor(v!, scale);
            return x == null || x < 0 ? 'Not an amount' : null;
          },
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
        FilledButton(
          onPressed: () {
            if (form.currentState!.validate()) Navigator.pop(context, true);
          },
          child: const Text('Save'),
        ),
      ],
    ),
  );
  final text = amount.text.trim();
  if (ok != true || !context.mounted) return;
  final minor = text.isEmpty ? 0 : parseMinor(text, scale)!;
  await guarded(context, () => ref.mutate((s) => s.ledger.saveBudget(line.account.id, minor)));
}
