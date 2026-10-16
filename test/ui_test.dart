import 'package:artha/app/app.dart';
import 'package:artha/app/providers.dart';
import 'package:artha/app/session.dart';
import 'package:artha/core/db/store.dart';
import 'package:artha/core/security/key_vault.dart';
import 'package:artha/modules/finance/domain/accounting.dart';
import 'package:artha/modules/finance/domain/ledger.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support.dart';

/// Smoke tests: every page builds, with and without data, on phone and
/// desktop widths, without throwing or overflowing.
void main() {
  late AppSession session;

  Future<void> open(WidgetTester tester, {bool setUp = true}) async {
    await tester.runAsync(() async {
      final db = await openTestDatabase();
      final store = await Store.open(db);
      session = AppSession(KeyVault(MemorySecretStore()), db, store, Ledger(store));
      // No network in tests.
      await db.setLocalSetting('fx.auto', 'off');
      if (!setUp) return;
      final ledger = session.ledger;
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
    });
  }

  Future<void> run(WidgetTester tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [sessionProvider.overrideWithValue(session)],
        retry: (_, _) => null,
        child: const ArthaApp(),
      ),
    );
    await settle(tester);
  }

  Future<void> close(WidgetTester tester) async {
    // Disposing the scope stops the sync timers.
    await tester.pumpWidget(const SizedBox());
    await tester.runAsync(() => session.db.close());
  }

  Future<void> visitAll(WidgetTester tester, Future<void> Function(String label) go) async {
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
      await settle(tester);
      expect(tester.takeException(), isNull, reason: label);
    }
  }

  testWidgets('first run asks for a base currency, then opens the dashboard', (tester) async {
    await open(tester, setUp: false);
    await run(tester);
    expect(find.text('Welcome to Artha'), findsOneWidget);
    await tester.ensureVisible(find.text('Get started'));
    await tester.tap(find.text('Get started'));
    await settle(tester);
    expect(find.text('Welcome to Artha'), findsNothing);
    expect(find.text('Add account'), findsWidgets);
    await close(tester);
  });

  testWidgets('every page builds on a desktop window', (tester) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await open(tester);
    await run(tester);
    expect(find.text('Net worth'), findsWidgets);
    await visitAll(
      tester,
      (label) => tester.tap(find.descendant(of: find.byType(NavigationRail), matching: find.text(label))),
    );
    await close(tester);
  });

  testWidgets('every page builds on a phone', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await open(tester);
    await run(tester);
    await visitAll(tester, (label) async {
      final bar = find.descendant(of: find.byType(NavigationBar), matching: find.text(label));
      if (bar.evaluate().isNotEmpty) return tester.tap(bar);
      await tester.tap(find.descendant(of: find.byType(NavigationBar), matching: find.text('More')));
      await settle(tester);
      await tester.tap(find.descendant(of: find.byType(BottomSheet), matching: find.text(label)));
    });
    await close(tester);
  });
}

/// Lets database work (real I/O) and animations finish.
Future<void> settle(WidgetTester tester) async {
  for (var i = 0; i < 5; i++) {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
    await tester.pump(const Duration(milliseconds: 400));
  }
}
