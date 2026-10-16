import 'dart:io';

import 'package:artha/modules/finance/domain/accounting.dart';
import 'package:artha/ui/format.dart';
import 'package:flutter_test/flutter_test.dart';

import 'app_harness.dart';
import 'support.dart';

/// Sync through the real dialogs against a local server: create an account
/// on one device, then bring the data onto a fresh one.
void main() {
  final server = LiveServer.fromEnvironment();
  final run = DateTime.now().microsecondsSinceEpoch;
  final email = 'ui$run@artha.test';
  const password = 'correct horse battery';

  setUpAll(() async {
    // The widget test binding fakes HTTP; these tests need the real thing.
    HttpOverrides.global = null;
    await server?.relax();
  });
  tearDownAll(() => server?.restore('$run@artha.test'));

  /// Pumps until [f] shows, with real time for network and key derivation.
  Future<void> waitFor(AppHarness app, Finder f, {int seconds = 60}) async {
    for (var i = 0; i < seconds * 5 && f.evaluate().isEmpty; i++) {
      await app.tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 200)));
      await app.tester.pump(const Duration(milliseconds: 100));
    }
    expect(f, findsWidgets);
  }

  Future<void> fillIn(AppHarness app, Map<String, String> fields) async {
    for (final MapEntry(:key, :value) in fields.entries) {
      await app.enter(key, value);
    }
  }

  testWidgets('sign up on one device, sign in on another', skip: server == null, (tester) async {
    final a = AppHarness(tester)..desktop();
    await a.open(
      seed: (ledger) async {
        await ledger.setUp('GBP');
        final bank = await ledger.saveAccount(name: 'Monzo', subtype: 'current', commodityId: 'GBP');
        await ledger.saveEntry(
          simpleEntry(
            date: '2026-10-01',
            currency: 'GBP',
            accountId: bank,
            categoryId: 'cat.salary',
            amount: -250000,
          ),
        );
      },
    );
    await a.run();
    await a.go('Settings');
    await a.tapText('Create account');
    await fillIn(a, {
      'Server address': server!.url,
      'E-mail': email,
      'New password': password,
      'Repeat password': password,
      'Invite code': server.invite,
    });
    await a.tapText('Create');
    await waitFor(a, find.text('Save your recovery key'));
    expect(find.text('Done'), findsOneWidget);
    await a.tapText('I have saved it somewhere safe');
    await a.tapText('Done');
    await waitFor(a, find.text(email));
    await a.close();

    final b = AppHarness(tester)..desktop();
    await b.open();
    await b.run();
    expect(find.text('Welcome to Artha'), findsOneWidget);
    await b.tapText('Already use Artha? Sign in to sync');
    await fillIn(b, {'Server address': server.url, 'E-mail': email, 'Password': password});
    await b.tapText('Sign in');
    // The synced base currency takes the new device past onboarding.
    await waitFor(b, find.text('Net worth'));
    await b.go('Accounts');
    expect(find.text('Monzo'), findsWidgets);
    expect(find.text(money(250000, 'GBP')), findsWidgets);
    expect(tester.takeException(), isNull);
    await b.close();
  });
}
