import 'dart:io';

import 'package:artha/modules/finance/domain/accounting.dart';
import 'package:brahma_core/brahma_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'app_harness.dart';
import 'support.dart';

/// Sync through the real setup wizard and dialogs against a local server:
/// create an account on one device, add devices to it by pairing, and sign
/// in with e-mail.
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

  /// Real-time work outside the widget tree, such as the other device.
  Future<T> real<T>(WidgetTester tester, Future<T> Function() f) async => (await tester.runAsync(f)) as T;

  Future<T> until<T>(WidgetTester tester, Future<T?> Function() f) => real(tester, () async {
    for (var i = 0; i < 100; i++) {
      final v = await f();
      if (v != null) return v;
      await Future<void>.delayed(const Duration(milliseconds: 200));
    }
    throw StateError('timed out');
  });

  Future<void> fillIn(AppHarness app, Map<String, String> fields) async {
    for (final MapEntry(:key, :value) in fields.entries) {
      await app.enter(key, value);
    }
  }

  testWidgets('sign up, add devices by pairing, sign in with e-mail', skip: server == null, (tester) async {
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
    // The setup wizard: sync, an existing server, then a new account on it.
    await a.tapText('Set up sync');
    await a.tapText('Sync across my devices');
    await a.tapText('I already have a server');
    await a.enter('Setup link or server address', server!.url);
    await a.tapText('Check server');
    await waitFor(a, find.text('Continue'));
    await a.tapText('Continue');
    await a.tapText('Create account');
    expect(find.text('Create your account'), findsOneWidget);
    await fillIn(a, {
      'E-mail': email,
      'Password': password,
      'Repeat password': password,
      'Invite code': server.invite,
    });
    // The segment and the submit button now both read 'Create account'.
    await a.tapText('Create account');
    await waitFor(a, find.text('Save your recovery key'));
    expect(find.text('Done'), findsOneWidget);
    await a.tapText('I have saved it somewhere safe');
    await a.tapText('Done');
    // The last step shows once the first sync is done.
    await waitFor(a, find.text("You're set"));
    await a.tapText('Open Artha');
    expect(find.text("You're set"), findsNothing);
    expect(find.text(email), findsOneWidget);

    // Add a device: the QR code's link, approved in the dialog.
    await a.tapText('Add a device');
    await waitFor(a, find.byType(QrCodeView));
    final shown = BrahmaLink.parse(tester.widget<QrCodeView>(find.byType(QrCodeView)).data) as PairingLink;
    final tablet = await real(tester, () => Phone.open(name: 'Tablet'));
    final ticket = await real(tester, () => tablet.account.requestJoin(shown));
    await waitFor(a, find.text('Let this device in?'));
    expect(find.text('“Tablet” asks to join your sync account.'), findsOneWidget);
    expect(find.text(ticket.code), findsOneWidget);
    await a.tapText('Allow');
    final grant = await until(tester, () => tablet.account.joinGrant(ticket));
    await real(tester, () => tablet.account.join(ticket, grant));
    await waitFor(a, find.text('Device added'));
    await a.tapText('Done');
    await a.close();
    await real(tester, () => tablet.db.close());

    // Join from another device: paste the link, compare codes, confirm.
    final link = await real(tester, () => a.session.account.offerPairing());
    final b = AppHarness(tester)..desktop();
    await b.open();
    await b.run();
    expect(find.text('Welcome to Artha'), findsOneWidget);
    await b.tapText('Join from another device');
    await tester.enterText(find.widgetWithText(TextField, 'Link from the other device'), '$link');
    await b.tapText('Next');
    await waitFor(b, find.text('Waiting for the other device…'));
    final request = await until(tester, () => a.session.account.pairingRequest(link));
    expect(find.text(await real(tester, () => PairingCrypto.code(link, request.publicKey))), findsOneWidget);
    await real(tester, () => a.session.account.approvePairing(link, request));
    await waitFor(b, find.text('Join this account?'));
    expect(find.textContaining(email), findsOneWidget);
    await b.tapText('Join');
    // The synced base currency takes the new device past onboarding.
    await waitFor(b, find.text('Net worth'));
    await b.go('Accounts');
    expect(find.text('Monzo'), findsWidgets);
    expect(find.text(money(250000, 'GBP')), findsWidgets);
    expect(tester.takeException(), isNull);
    await b.close();

    // Signing in with the e-mail address still works.
    final c = AppHarness(tester)..desktop();
    await c.open();
    await c.run();
    await c.tapText('Sign in with e-mail instead');
    await fillIn(c, {'Server address': server.url, 'E-mail': email, 'Password': password});
    await c.tapText('Sign in');
    await waitFor(c, find.text('Net worth'));
    expect(tester.takeException(), isNull);
    await c.close();
    // Sign-in's HTTP leaves an idle keep-alive connection whose 15 s timer
    // runs on the test clock; let it expire.
    await tester.pump(const Duration(seconds: 16));
  });
}
