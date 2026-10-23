import 'package:artha/modules/finance/domain/accounting.dart';
import 'package:artha/modules/finance/domain/ledger.dart';
import 'package:brahma_core/brahma_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'app_harness.dart';

/// The main things a user does, driven through the UI like a person would.
void main() {
  Future<void> seed(Ledger ledger) async {
    await ledger.setUp('GBP');
    await ledger.saveAccount(name: 'Chase US', subtype: 'current', commodityId: 'USD');
  }

  /// The balance shown on an account's own page.
  Finder balance(int minor) => find.text(money(minor, 'GBP'));

  testWidgets('add an account, record, edit, tally and delete transactions', (tester) async {
    final app = AppHarness(tester)..desktop();
    await app.open(seed: seed);
    await app.run();

    // New account with an opening balance.
    await app.go('Accounts');
    await app.tapText('Account');
    expect(find.text('New account'), findsOneWidget);
    await app.enter('Name', 'Monzo');
    await app.enter('Balance today (optional)', '1000');
    await app.tapText('Save');
    expect(find.text('New account'), findsNothing);
    expect(find.text('Monzo'), findsWidgets);

    // Its page shows the opening balance.
    await app.tapText('Monzo');
    expect(balance(100000), findsWidgets);
    expect(find.text('Opening balance'), findsOneWidget);

    // A spend.
    await app.tap(find.byTooltip('Add transaction'));
    expect(find.text('New transaction'), findsOneWidget);
    await app.choose('Category', 'Groceries');
    await app.enter('Amount (GBP) · negative for a refund', '42.50');
    await app.enter('Payee', 'Tesco');
    await app.tapText('Save');
    expect(find.text('New transaction'), findsNothing);
    expect(find.text('Tesco'), findsOneWidget);
    expect(balance(95750), findsWidgets);

    // Edit it.
    await app.tapText('Tesco');
    expect(find.text('Edit transaction'), findsOneWidget);
    expect(find.widgetWithText(TextFormField, '42.50'), findsOneWidget);
    await app.enter('Amount (GBP) · negative for a refund', '40');
    await app.tapText('Save');
    expect(balance(96000), findsWidgets);

    // The statement agrees.
    await app.tap(find.byTooltip(RegExp('^Record statement balance')));
    await app.enter('Balance (GBP)', '960');
    await app.tapText('Save');
    expect(find.text('Ledger agrees with the statement.'), findsOneWidget);

    // A transfer to the dollar account, at the bank's rate.
    await app.tap(find.byTooltip('Add transaction'));
    await app.tapText('Transfer');
    await app.choose('To', 'Chase US · USD');
    await app.enter('Amount (GBP)', '100');
    await app.enter('Amount received (USD)', '127.30');
    await app.tapText('Save');
    expect(balance(86000), findsWidgets);
    final dollars = await tester.runAsync(() => app.ledger.balances());
    final usd = (await tester.runAsync(() => app.ledger.db.select(app.ledger.db.accounts).get()))!
        .firstWhere((a) => a.name == 'Chase US')
        .id;
    expect(dollars![usd], (amount: 12730, value: 10000));

    // Delete the spend.
    await app.tapText('Tesco');
    await app.tap(find.byTooltip('Delete'));
    expect(find.text('Delete this transaction?'), findsOneWidget);
    await app.tap(find.descendant(of: find.byType(AlertDialog), matching: find.text('Delete')));
    expect(find.text('Tesco'), findsNothing);
    expect(balance(90000), findsWidgets);

    // The transactions page and dashboard agree.
    await app.tap(find.byType(BackButton));
    await app.go('Transactions');
    expect(find.text('Opening balance'), findsOneWidget);
    expect(find.text('Transfer'), findsWidgets);
    expect(tester.takeException(), isNull);
    await app.close();
  });

  testWidgets('add a category, set targets, tell Artha something', (tester) async {
    final app = AppHarness(tester)..desktop();
    await app.open(
      seed: (ledger) async {
        await seed(ledger);
        final bank = await ledger.saveAccount(name: 'Monzo', subtype: 'current', commodityId: 'GBP');
        final fund = await ledger.createSecurity(
          code: 'VWRP',
          name: 'FTSE All-World',
          quoteCurrency: 'GBP',
          assetClass: 'equity',
        );
        final isa = await ledger.saveAccount(name: 'ISA', subtype: 'security', commodityId: fund);
        await ledger.saveEntry(
          buyEntry(
            date: today(),
            currency: 'GBP',
            cashAccountId: bank,
            holdingAccountId: isa,
            units: 10000000,
            cost: 100000,
          ),
        );
      },
    );
    await app.run();

    await app.go('Accounts');
    await app.tapText('Categories');
    await app.tapText('Category');
    await app.enter('Name', 'Pets');
    await app.tapText('Save');
    expect(find.text('Pets'), findsOneWidget);

    await app.go('Portfolio');
    await app.tapText('Set targets');
    expect(find.text('Target allocation'), findsOneWidget);
    await app.tapText('Balanced');
    expect(find.text('Adds up to 100%'), findsOneWidget);
    await app.tapText('Save');
    expect(find.text('Target allocation'), findsNothing);
    expect(find.text('Targets'), findsOneWidget);

    await app.go('Insights');
    await app.tap(find.byTooltip(RegExp('^Tell Artha something')));
    await app.enter('Goal, e.g. House deposit by 2029', 'House deposit');
    await app.enter('Amount (GBP, optional)', '30000');
    await app.tapText('Save');
    expect(find.text('House deposit'), findsWidgets);
    expect(tester.takeException(), isNull);
    await app.close();
  });

  testWidgets('a bad amount is refused, not saved', (tester) async {
    final app = AppHarness(tester)..desktop();
    await app.open(seed: seed);
    await app.run();
    await app.go('Transactions');
    await app.tapText('Transaction');
    await app.choose('Paid from', 'Chase US · USD');
    await app.choose('Category', 'Groceries');
    await app.enter('Amount (USD) · negative for a refund', '12.3.4');
    await app.tapText('Save');
    expect(find.text('Enter an amount'), findsOneWidget);
    expect(find.text('New transaction'), findsOneWidget);
    final entries = await tester.runAsync(() => app.ledger.db.select(app.ledger.db.entries).get());
    expect(entries, isEmpty);
    await app.close();
  });

  testWidgets('set a monthly budget and track spending against it', (tester) async {
    final app = AppHarness(tester)..desktop();
    await app.open(
      seed: (ledger) async {
        await seed(ledger);
        final bank = await ledger.saveAccount(name: 'Monzo', subtype: 'current', commodityId: 'GBP');
        await ledger.saveEntry(
          simpleEntry(
            date: today(),
            currency: 'GBP',
            accountId: bank,
            categoryId: 'cat.groceries',
            amount: 12000,
          ),
        );
      },
    );
    await app.run();
    await app.tapText('Set up');
    expect(find.text('Budgets'), findsWidgets);
    await app.tapText('Groceries');
    await app.enter('Per month (GBP)', '100');
    await app.tapText('Save');
    expect(find.text('${money(2000, 'GBP')} over ${money(10000, 'GBP')}'), findsOneWidget);
    expect(await tester.runAsync(() => app.ledger.budgets()), {'cat.groceries': 10000});
    expect(tester.takeException(), isNull);
    await app.close();
  });
}
