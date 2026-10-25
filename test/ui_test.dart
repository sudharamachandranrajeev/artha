import 'package:artha/modules/finance/domain/accounting.dart';
import 'package:artha/modules/finance/domain/ledger.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'app_harness.dart';

/// Smoke tests: every page builds, with and without data, on phone and
/// desktop widths, without throwing or overflowing.
void main() {
  Future<void> seed(Ledger ledger) async {
    await ledger.setUp('GBP');
    final bank = await ledger.saveAccount(name: 'Monzo', subtype: 'current', commodityId: 'GBP');
    await ledger.saveAccount(name: 'Chase US', subtype: 'current', commodityId: 'USD');
    for (final (date, cat, amount) in [
      ('2026-08-01', 'cat.salary', -300000),
      ('2026-08-03', 'cat.groceries', 6420),
      ('2026-09-01', 'cat.salary', -300000),
      ('2026-09-04', 'cat.groceries', 7110),
      ('2026-10-01', 'cat.salary', -300000),
      ('2026-10-05', 'cat.groceries', 5230),
    ]) {
      await ledger.saveEntry(
        simpleEntry(date: date, currency: 'GBP', accountId: bank, categoryId: cat, amount: amount),
      );
    }
    await ledger.saveBalanceCheck(bank, '2026-10-05', 880240);
  }

  Future<void> visitAll(AppHarness app, Future<void> Function(String label) go) async {
    for (final label in [
      'Accounts',
      'Transactions',
      'Portfolio',
      'Insights',
      'Reports',
      'Import',
      'Settings',
    ]) {
      await go(label);
      await app.settle();
      expect(app.tester.takeException(), isNull, reason: label);
    }
  }

  testWidgets('first run asks for a base currency, then opens the dashboard', (tester) async {
    final app = AppHarness(tester);
    await app.open();
    await app.run();
    expect(find.text('Welcome to Artha'), findsOneWidget);
    await app.tapText('Get started');
    expect(find.text('Welcome to Artha'), findsNothing);
    expect(find.text('Add account'), findsWidgets);
    await app.close();
  });

  testWidgets('every page builds on a desktop window', (tester) async {
    final app = AppHarness(tester)..desktop();
    await app.open(seed: seed);
    await app.run();
    expect(find.text('Net worth'), findsWidgets);
    await visitAll(
      app,
      (label) => tester.tap(find.descendant(of: find.byType(NavigationRail), matching: find.text(label))),
    );
    await app.close();
  });

  testWidgets('every page builds on a phone', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final app = AppHarness(tester);
    await app.open(seed: seed);
    await app.run();
    await visitAll(app, (label) async {
      // The dock holds every screen; scroll it to the one asked for.
      final item = find.descendant(
        of: find.byWidgetPredicate((w) => '${w.runtimeType}' == '_Dock'),
        matching: find.byTooltip(label),
      );
      await tester.ensureVisible(item);
      await tester.pump();
      await tester.tap(item);
    });
    await app.close();
  });
}
