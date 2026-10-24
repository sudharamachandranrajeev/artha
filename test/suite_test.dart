import 'package:artha/app/session.dart';
import 'package:artha/modules/finance/domain/ledger.dart';
import 'package:artha/suite.dart';
import 'package:brahma_core/brahma_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support.dart';

void main() {
  Future<AppSession> pumpCard(WidgetTester tester, {String? base}) async {
    late AppSession session;
    await tester.runAsync(() async {
      final store = await Store.open(await openTestDatabase());
      session = AppSession(KeyVault(MemorySecretStore(), arthaIdentity), store, Ledger(store));
      if (base != null) await session.ledger.setUp(base);
    });
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          coreSessionProvider.overrideWithValue(session),
          appIdentityProvider.overrideWithValue(arthaSuite.identity),
          ...arthaSuite.overrides(session),
        ],
        retry: (_, _) => null,
        child: Consumer(
          builder: (context, ref, _) => MaterialApp(
            theme: arthaSuite.theme(ref, Brightness.light),
            home: Scaffold(body: Builder(builder: arthaSuite.summary)),
          ),
        ),
      ),
    );
    for (var i = 0; i < 5; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
      await tester.pump();
    }
    return session;
  }

  Future<void> close(WidgetTester tester, AppSession session) async {
    await tester.pumpWidget(const SizedBox());
    await tester.runAsync(() => session.db.close());
  }

  testWidgets('the suite card asks for a base currency first', (tester) async {
    final session = await pumpCard(tester);
    expect(find.textContaining('choose your base currency'), findsOneWidget);
    await close(tester, session);
  });

  testWidgets('the suite card shows net worth and the month', (tester) async {
    final session = await pumpCard(tester, base: 'GBP');
    expect(find.text('net worth'), findsOneWidget);
    expect(find.text('spent this month'), findsOneWidget);
    await close(tester, session);
  });
}
