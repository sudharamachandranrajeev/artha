import 'package:artha/modules/finance/domain/accounting.dart';
import 'package:artha/modules/finance/domain/ledger.dart';
import 'package:brahma_core/brahma_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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

  testWidgets('add a rule that sorts and renames uncategorised spending', (tester) async {
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
            categoryId: uncategorizedId,
            amount: 899,
            payee: 'TESCO STORES 3021',
          ),
        );
      },
    );
    await app.run();
    await app.go('Import');
    await app.tap(find.byTooltip('Rules: categories and payee names'));
    expect(find.text('No rules yet'), findsOneWidget);
    await app.tapText('Add rule');
    await app.enter('When the description contains', 'tesco');
    await app.choose('File it under', 'Groceries');
    await app.enter('Show the payee as (optional)', 'Tesco');
    await app.tapText('Save');
    expect(find.text('“tesco”'), findsOneWidget);
    expect(find.text('Shows as Tesco · Groceries'), findsOneWidget);
    await app.tap(find.byTooltip('Apply these rules to recorded entries'));
    expect(find.text('Updated 1 entry'), findsOneWidget);
    final legs = await tester.runAsync(() => app.ledger.db.select(app.ledger.db.postings).get());
    expect(legs!.map((p) => p.accountId), contains('cat.groceries'));
    final e = (await tester.runAsync(() => app.ledger.db.select(app.ledger.db.entries).get()))!.single;
    expect((e.payee, e.memo), ('Tesco', 'TESCO STORES 3021'));
    expect(tester.takeException(), isNull);
    await app.close();
  });

  testWidgets('the dashboard forecasts the next 90 days from recurring pay and bills', (tester) async {
    final app = AppHarness(tester)..desktop();
    await app.open(
      seed: (ledger) async {
        await seed(ledger);
        final bank = await ledger.saveAccount(name: 'Monzo', subtype: 'current', commodityId: 'GBP');
        for (var k = 4; k >= 1; k--) {
          for (final (payee, cat, amount) in [
            ('ACME LTD SALARY', 'cat.salary', -280000),
            ('RENT LANDLORD', 'cat.housing', 140000),
          ]) {
            await ledger.saveEntry(
              simpleEntry(
                date: addMonths(today(), -k),
                currency: 'GBP',
                accountId: bank,
                categoryId: cat,
                amount: amount,
                payee: payee,
              ),
            );
          }
        }
      },
    );
    await app.run();
    expect(find.text('Next 90 days'), findsOneWidget);
    expect(find.textContaining('2 recurring items on schedule'), findsOneWidget);
    expect(find.textContaining('expected on'), findsOneWidget);
    await app.tapText('Plan a one-off');
    await app.enter('Name', 'Car insurance');
    await app.enter('Amount (GBP)', '450');
    await app.tapText('Save');
    expect(find.text('Car insurance'), findsOneWidget);
    expect(find.text('-£450.00'), findsOneWidget);
    expect(find.textContaining('1 planned one-off and'), findsOneWidget);
    await app.tapText('Car insurance');
    await app.tapText('Delete');
    expect(find.text('Car insurance'), findsNothing);
    expect(await tester.runAsync(app.ledger.planned), isEmpty);
    expect(tester.takeException(), isNull);
    await app.close();
  });

  testWidgets('work through the review queue with the keyboard and in bulk', (tester) async {
    final app = AppHarness(tester)..desktop();
    late List<String> ids;
    await app.open(
      seed: (ledger) async {
        await seed(ledger);
        final bank = await ledger.saveAccount(name: 'Monzo', subtype: 'current', commodityId: 'GBP');
        ids = [
          for (final (i, payee) in ['TESCO STORES', 'PRET A MANGER', 'CORNER SHOP'].indexed)
            await ledger.saveEntry(
              simpleEntry(
                date: addDays(today(), -i),
                currency: 'GBP',
                accountId: bank,
                categoryId: uncategorizedId,
                amount: 500 + i,
                payee: payee,
              ),
            ),
        ];
        await ledger.setReviewed(ids, reviewed: false);
      },
    );
    await app.run();
    await app.tapText('3 imported entries to review');
    expect(find.text('To review (3)'), findsOneWidget);
    // R marks the row under the cursor, the newest.
    await tester.sendKeyEvent(LogicalKeyboardKey.keyR);
    await app.settle();
    expect(find.text('To review (2)'), findsOneWidget);
    expect(find.text('TESCO STORES'), findsNothing);
    await app.tap(find.byType(Checkbox).at(1));
    expect(find.text('1 selected'), findsOneWidget);
    await app.tapText('Set category');
    await app.tapText('Groceries');
    expect(find.text('Filed 1 entry'), findsOneWidget);
    expect(find.text('To review (1)'), findsOneWidget);
    await app.tapText('Mark all reviewed');
    expect(find.text('All reviewed'), findsOneWidget);
    final legs = await tester.runAsync(
      () => (app.ledger.db.select(app.ledger.db.postings)..where((p) => p.entryId.equals(ids[1]))).get(),
    );
    expect(legs!.map((p) => p.accountId), contains('cat.groceries'));
    expect(tester.takeException(), isNull);
    await app.close();
  });

  testWidgets('add a monthly subscription and see it in upcoming bills', (tester) async {
    final app = AppHarness(tester)..desktop();
    await app.open(
      seed: (ledger) async {
        await seed(ledger);
        await ledger.saveAccount(name: 'Monzo', subtype: 'current', commodityId: 'GBP');
      },
    );
    await app.run();
    expect(find.text('No bills spotted yet'), findsOneWidget);
    await app.tapText('Add subscription');
    await app.enter('Name', 'Netflix');
    await app.enter('Amount (GBP)', '10.99');
    await app.tapText('Save');
    expect(find.text('No bills spotted yet'), findsNothing);
    expect(find.text('Netflix'), findsWidgets);
    expect(find.textContaining('· monthly'), findsOneWidget);
    await app.tapText('Manage');
    expect(find.text('Bills and subscriptions'), findsWidgets);
    expect(find.textContaining('added by you'), findsOneWidget);
    await app.tap(find.byTooltip('Delete'));
    expect(find.text('Nothing regular yet'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await app.close();
  });

  testWidgets('risk level, safest plan and the assistant setup, with the network off', (tester) async {
    final app = AppHarness(tester)..desktop();
    await app.open(
      seed: (ledger) async {
        await seed(ledger);
        await ledger.saveAccount(name: 'Monzo', subtype: 'current', commodityId: 'GBP');
      },
    );
    await app.run();
    await app.go('Insights');
    expect(find.text('The world this week'), findsOneWidget);
    expect(find.text('Quick tips'), findsOneWidget);
    expect(find.textContaining('Nothing fetched yet'), findsOneWidget);
    expect(find.text('Risk and safest plan'), findsOneWidget);
    expect(find.textContaining('Your level:'), findsOneWidget);

    await app.tapText('Open');
    expect(find.text('Safest plan for you'), findsOneWidget);
    expect(find.text('Spend less than you earn'), findsOneWidget);
    await app.tapText('Answer 4 questions');
    expect(find.text('How much risk is right for you?'), findsOneWidget);
    // Save waits for all four answers.
    expect(tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Save')).onPressed, isNull);
    for (final answer in ['In 5 to 10 years', 'Hold calmly', 'Funds or shares I chose', 'A balance']) {
      await app.tap(find.text(answer));
    }
    await app.tapText('Save');
    expect(find.text('Retake'), findsOneWidget);
    final saved = await tester.runAsync(() => app.ledger.pref<Map>('risk.answers', const {}));
    expect(saved, {'horizon': 3, 'fall': 3, 'experience': 3, 'goal': 2});

    await app.tap(find.byTooltip('Ask Artha').first);
    expect(find.text('Add API key'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await app.close();
  });

  testWidgets('the assistant key is kept in the keychain, not the database', (tester) async {
    final app = AppHarness(tester)..desktop();
    await app.open(seed: seed);
    await app.run();
    await app.go('Settings');
    expect(find.text('News and rates'), findsOneWidget);
    await app.tapText('Add key');
    await app.enter('API key', 'not a key');
    await app.tapText('Save');
    expect(find.text('That does not look like an API key.'), findsOneWidget);
    expect(await tester.runAsync(() => app.session.keys.store.read('artha.claude.key')), isNull);
    await app.tapText('Add key');
    await app.enter('API key', 'sk-ant-api03-abcdefghijklmnopqrstuvwxyz');
    await app.tapText('Save');
    expect(find.text('On, using your Anthropic key'), findsOneWidget);
    expect(
      await tester.runAsync(() => app.session.keys.store.read('artha.claude.key')),
      'sk-ant-api03-abcdefghijklmnopqrstuvwxyz',
    );
    final inDb = await tester.runAsync(() => app.ledger.db.select(app.ledger.db.prefs).get());
    expect(inDb!.any((p) => p.value.contains('sk-ant')), isFalse);
    await app.tapText('Remove');
    expect(find.text('Off'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await app.close();
  });
}
