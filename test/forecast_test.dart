import 'package:artha/modules/finance/insights/forecast.dart';
import 'package:artha/modules/finance/insights/insights.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Recurring r(String label, Cadence c, int amount, String last) =>
      Recurring(label, label, c, amount, last, 'x', 4);

  test('recurring items land on their cycle and everyday spending is spread', () {
    final f = forecastCash(
      liquid: 100000,
      recurring: [
        r('SALARY', Cadence.monthly, 300000, '2026-09-28'),
        r('RENT', Cadence.monthly, -120000, '2026-10-01'),
        r('GYM', Cadence.weekly, -1000, '2026-10-20'),
      ],
      // Rent 1200 + gym ~43 a month recur; the other ~757 is everyday spending.
      monthlySpend: 200000,
      today: '2026-10-24',
      days: 60,
    );
    expect(f.days, 60);
    expect(f.everydayPerMonth, 200000 - 120000 - Cadence.weekly.perMonth(1000).abs());
    final salary = f.events.where((e) => e.label == 'SALARY').map((e) => e.date);
    expect(salary, ['2026-10-28', '2026-11-28']);
    expect(f.events.where((e) => e.label == 'RENT').map((e) => e.date), ['2026-11-01', '2026-12-01']);
    expect(f.events.where((e) => e.label == 'GYM').first.date, '2026-10-27');
    // Day 4 (10-28): salary in, one gym session out, four days of everyday spending.
    final everyday4 = (f.everydayPerMonth * 12 * 4 / 365).round();
    expect(f.balances[3], 100000 + 300000 - 1000 - everyday4);
    expect(f.dateAt(3), '2026-10-28');
  });

  test('an overdue payment is expected tomorrow, once, and the lowest day is found', () {
    final f = forecastCash(
      liquid: 50000,
      recurring: [r('COUNCIL TAX', Cadence.monthly, -60000, '2026-09-15')],
      monthlySpend: 60000,
      today: '2026-10-24',
      days: 30,
    );
    expect(f.everydayPerMonth, 0);
    expect([for (final e in f.events) e.date], ['2026-10-25', '2026-11-15']);
    expect(f.lowest, (date: '2026-11-15', balance: 50000 - 120000));
    expect(f.closing, -70000);
  });

  test('with nothing scheduled the balance only falls by everyday spending', () {
    final f = forecastCash(liquid: 10000, recurring: const [], monthlySpend: 0, today: '2026-10-24');
    expect(f.balances.toSet(), {10000});
    expect(f.lowest, (date: '2026-10-24', balance: 10000));
  });
}
