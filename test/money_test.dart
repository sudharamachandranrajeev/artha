import 'package:artha/core/money/money.dart';
import 'package:artha/core/sync/hlc.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('parseMinor', () {
    test('plain, grouped, signed and accounting forms', () {
      expect(parseMinor('12.34', 2), 1234);
      expect(parseMinor('1,234.5', 2), 123450);
      expect(parseMinor('-0.01', 2), -1);
      expect(parseMinor('(45.00)', 2), -4500);
      expect(parseMinor('£1 000.50', 2), 100050);
      expect(parseMinor('12.00 DR', 2), -1200);
      expect(parseMinor('12.00 CR', 2), 1200);
      expect(parseMinor('12.00-', 2), -1200);
      expect(parseMinor('+7', 0), 7);
      expect(parseMinor('1.234,56', 2, decimalSeparator: ','), 123456);
    });

    test('rejects junk and hidden precision instead of rounding', () {
      expect(parseMinor('', 2), isNull);
      expect(parseMinor('abc', 2), isNull);
      expect(parseMinor('1.2.3', 2), isNull);
      expect(parseMinor('1.005', 2), isNull);
      expect(parseMinor('1.2500', 2), 125);
    });
  });

  test('formatMinor is exact with grouping', () {
    expect(formatMinor(123456789, 2, symbol: '£'), '£1,234,567.89');
    expect(formatMinor(-5, 2), '-0.05');
    expect(formatMinor(1000, 0, symbol: '¥'), '¥1,000');
    expect(formatMinor(10, 2, signed: true), '+0.10');
  });

  group('Rate and conversion', () {
    test('parses decimals and exponents exactly', () {
      expect(Rate.parse('1.25'), Rate(BigInt.from(5), BigInt.from(4)));
      expect(Rate.parse('1e-3').toDecimalString(), '0.001');
      expect(Rate.tryParse('.5')!.toDecimalString(), '0.5');
      expect(Rate.tryParse('x'), isNull);
    });

    test('converts between scales with half-even rounding', () {
      // 100.00 GBP at 105.123 INR/GBP = 10512.30 INR
      expect(convertMinor(10000, Rate.parse('105.123'), 2, 2), 1051230);
      // 1 JPY at 0.005 GBP/JPY = 0.5p, a tie: rounds to even 0
      expect(convertMinor(1, Rate.parse('0.005'), 0, 2), 0);
      expect(convertMinor(3, Rate.parse('0.005'), 0, 2), 2); // 1.5p -> 2p
      expect(convertMinor(-3, Rate.parse('0.005'), 0, 2), -2);
      expect(convertMinor(5, Rate.parse('0.5'), 2, 2), 2); // 2.5 -> 2
    });

    test('implied rate round-trips a bank conversion', () {
      final r = impliedRate(10000, 2, 1051230, 2);
      expect(convertMinor(10000, r, 2, 2), 1051230);
      expect(r.toDecimalString(), '105.123');
    });

    test('divRoundHalfEven ties', () {
      int d(int n, int m) => divRoundHalfEven(BigInt.from(n), BigInt.from(m)).toInt();
      expect([d(5, 2), d(7, 2), d(-5, 2), d(-7, 2), d(1, 3), d(2, 3)], [2, 4, -2, -4, 0, 1]);
    });
  });

  group('HlcClock', () {
    test('monotonic even when the wall clock stalls or goes back', () {
      var now = 1000;
      final c = HlcClock('a', now: () => now);
      final a = c.tick();
      final b = c.tick();
      now = 500;
      final d = c.tick();
      expect(a.compareTo(b) < 0 && b.compareTo(d) < 0, isTrue);
    });

    test('receive moves past remote stamps', () {
      final c = HlcClock('a', now: () => 1000);
      c.receive(HlcClock('b', now: () => 9000).tick());
      expect(c.tick().startsWith('000000000009000-000002'), isTrue);
    });

    test('seed sorts below real stamps', () {
      expect(HlcClock.seed.compareTo(HlcClock('a', now: () => 1).tick()) < 0, isTrue);
    });
  });
}
