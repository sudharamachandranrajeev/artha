import 'package:artha/db/database.dart';
import 'package:artha/modules/finance/domain/accounting.dart';
import 'package:artha/modules/finance/domain/ledger.dart';
import 'package:artha/modules/finance/insights/insights.dart';
import 'package:brahma_core/brahma_core.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support.dart';

RecurringRow row(
  String id, {
  String label = 'Netflix',
  String pattern = 'netflix',
  int amount = -1099,
  String cadence = 'monthly',
  String anchor = '2026-01-15',
  bool dismissed = false,
}) => RecurringRow(
  id: id,
  hlc: '',
  deleted: false,
  label: label,
  pattern: pattern,
  amount: amount,
  cadence: cadence,
  anchorDate: anchor,
  categoryId: '',
  dismissed: dismissed,
);

List<Txn> monthly(String text, int amount, List<String> dates) => [
  for (final d in dates) Txn(d, text, amount, 'cat.subscriptions'),
];

void main() {
  group('merge', () {
    const today = '2026-10-24';

    test('an added item is dated from its anchor when no payment is seen', () {
      final r = mergeRecurring(const [], [row('a')], const [], today).single;
      expect(
        (r.key, r.manual, r.lastDate, r.nextDate, r.count),
        ('manual/a', true, '2026-10-15', '2026-11-15', 0),
      );
      // An anchor ahead is the next payment.
      final ahead = mergeRecurring(const [], [row('b', anchor: '2026-11-03')], const [], today).single;
      expect((ahead.lastDate, ahead.nextDate), ('2026-10-03', '2026-11-03'));
      // Month ends do not drift: the 31st stays the 31st after February.
      final end = mergeRecurring(const [], [row('c', anchor: '2026-01-31')], const [], '2026-03-30').single;
      expect((end.lastDate, end.nextDate), ('2026-02-28', '2026-03-31'));
    });

    test('a payment seen late or early moves the dates', () {
      final late = mergeRecurring(
        const [],
        [row('a')],
        monthly('NETFLIX.COM', -1099, ['2026-09-15', '2026-10-17']),
        today,
      ).single;
      expect(
        (late.lastDate, late.nextDate, late.count, late.lastAmount),
        ('2026-10-17', '2026-11-15', 2, -1099),
      );
      final early = mergeRecurring(
        const [],
        [row('a')],
        monthly('NETFLIX.COM', -1099, ['2026-11-12']),
        '2026-11-12',
      ).single;
      expect((early.lastDate, early.nextDate), ('2026-11-12', '2026-12-15'));
    });

    test('added items take over detected ones; hidden ones go', () {
      final txns = [
        ...monthly('NETFLIX.COM', -1099, ['2026-07-15', '2026-08-15', '2026-09-15', '2026-10-15']),
        ...monthly('SPOTIFY', -1199, ['2026-07-02', '2026-08-02', '2026-09-02', '2026-10-02']),
        // Money in that mentions the text is not the bill.
        ...monthly('NETFLIX REFUND', 500, ['2026-07-20', '2026-08-20', '2026-09-20', '2026-10-20']),
      ];
      final detected = detectRecurring(txns, today);
      expect(detected, hasLength(3));
      final spotify = detected.firstWhere((d) => d.label == 'SPOTIFY');
      final merged = mergeRecurring(
        detected,
        [row('a'), row('h', label: 'SPOTIFY', pattern: spotify.key, amount: 0, dismissed: true)],
        txns,
        today,
      );
      expect([for (final r in merged) r.label]..sort(), ['NETFLIX REFUND', 'Netflix']);
      expect(merged.firstWhere((r) => r.manual).count, 4);
    });

    test('a changed fixed price is flagged and expected from then on', () {
      final txns = monthly('DISNEY PLUS', -799, ['2026-06-05', '2026-07-05', '2026-08-05', '2026-09-05'])
        ..add(const Txn('2026-10-05', 'DISNEY PLUS', -899, 'cat.subscriptions'));
      final d = detectRecurring(txns, today).single;
      expect((d.amount, d.lastAmount, d.priceFrom), (-899, -899, -799));
      // Bills that always vary are not flagged.
      final gas = [
        for (final (i, a) in [-4200, -4500, -3900, -4100].indexed)
          Txn(addMonths('2026-07-10', i), 'OCTOPUS ENERGY', a, 'cat.utilities'),
      ];
      expect(detectRecurring(gas, today).single.priceFrom, isNull);
    });
  });

  group('ledger', () {
    late AppDatabase db;
    late Ledger ledger;

    setUp(() async {
      db = await openTestDatabase();
      ledger = Ledger(await Store.open(db));
      await ledger.seedDefaults('GBP');
    });
    tearDown(() => db.close());

    test('saves, validates, edits and deletes added items', () async {
      Future<String> save({
        String label = 'Netflix',
        int amount = -1099,
        String date = '2026-10-15',
        String c = '',
      }) => ledger.saveRecurring(label: label, amount: amount, anchorDate: date, categoryId: c);
      expect(() => save(label: ' '), throwsA(isA<LedgerException>()));
      expect(() => save(amount: 0), throwsA(isA<LedgerException>()));
      expect(() => save(date: '2026-02-30'), throwsA(isA<LedgerException>()));
      expect(() => save(c: 'cat.salary'), throwsA(isA<LedgerException>()));
      expect(
        () => ledger.saveRecurring(label: 'x', amount: -1, anchorDate: '2026-10-01', cadence: 'daily'),
        throwsA(isA<LedgerException>()),
      );
      final id = await save(c: 'cat.subscriptions');
      var r = (await ledger.recurrings()).single;
      expect(
        (r.label, r.pattern, r.cadence, r.categoryId),
        ('Netflix', 'Netflix', 'monthly', 'cat.subscriptions'),
      );
      await ledger.saveRecurring(
        id: id,
        label: 'Netflix',
        pattern: 'NETFLIX.COM',
        amount: -1299,
        cadence: 'yearly',
        anchorDate: '2026-12-01',
      );
      r = (await ledger.recurrings()).single;
      expect((r.pattern, r.amount, r.cadence, r.categoryId), ('NETFLIX.COM', -1299, 'yearly', ''));
      await ledger.deleteRecurring(id);
      expect(await ledger.recurrings(), isEmpty);
      expect(
        () => ledger.saveRecurring(id: id, label: 'Netflix', amount: -1, anchorDate: '2026-10-01'),
        throwsA(isA<LedgerException>()),
      );
    });

    test('hides and shows detected items', () async {
      await ledger.hideRecurring('-tesco', 'TESCO');
      await ledger.hideRecurring('-tesco', 'TESCO');
      final h = (await ledger.recurrings()).single;
      expect((h.dismissed, h.pattern, h.label), (true, '-tesco', 'TESCO'));
      await ledger.unhideRecurring('-tesco');
      expect(await ledger.recurrings(), isEmpty);
      // Hiding again after showing works.
      await ledger.hideRecurring('-tesco', 'TESCO');
      expect((await ledger.recurrings()).single.dismissed, isTrue);
    });
  });
}
