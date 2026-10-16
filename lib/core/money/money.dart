/// Exact money arithmetic.
///
/// Ledger amounts are integers in a commodity's smallest unit (pence for GBP,
/// 1e-6 of a share for a fund). Rates and prices are exact rationals ([Rate]).
/// Nothing touches floating point until a value is drawn on screen.
library;

final BigInt _ten = BigInt.from(10);

BigInt pow10(int n) => _ten.pow(n);

/// Divides [num] by [den] and rounds to the nearest integer, ties to even
/// (banker's rounding), so repeated conversions don't drift in one direction.
BigInt divRoundHalfEven(BigInt num, BigInt den) {
  if (den == BigInt.zero) throw ArgumentError('division by zero');
  if (den.isNegative) {
    num = -num;
    den = -den;
  }
  var q = num ~/ den; // truncates toward zero
  final twice = num.remainder(den).abs() * BigInt.two;
  if (twice > den || (twice == den && q.isOdd)) {
    q += num.isNegative ? -BigInt.one : BigInt.one;
  }
  return q;
}

/// An exact non-negative-denominator rational, used for FX rates and prices.
class Rate implements Comparable<Rate> {
  const Rate._(this.num, this.den);

  /// Builds num/den in lowest terms with a positive denominator.
  factory Rate(BigInt num, BigInt den) {
    if (den == BigInt.zero) throw ArgumentError('zero denominator');
    if (den.isNegative) {
      num = -num;
      den = -den;
    }
    final g = num.gcd(den); // den > 0, so g > 0
    return Rate._(num ~/ g, den ~/ g);
  }

  factory Rate.fromInt(int v) => Rate(BigInt.from(v), BigInt.one);

  /// Parses a plain decimal ("1.2345", "-0.5", "12") or scientific ("1e-3").
  static Rate? tryParse(String input) {
    final m = RegExp(r'^([+-]?)(\d*)(?:\.(\d*))?(?:[eE]([+-]?\d+))?$').firstMatch(input.trim());
    if (m == null) return null;
    final whole = m.group(2)!;
    final frac = m.group(3) ?? '';
    if (whole.isEmpty && frac.isEmpty) return null;
    var num = BigInt.parse('${whole.isEmpty ? '0' : whole}$frac');
    var den = pow10(frac.length);
    final exp = int.parse(m.group(4) ?? '0');
    if (exp > 0) num *= pow10(exp);
    if (exp < 0) den *= pow10(-exp);
    if (m.group(1) == '-') num = -num;
    return Rate(num, den);
  }

  static Rate parse(String input) => tryParse(input) ?? (throw FormatException('not a decimal', input));

  final BigInt num;
  final BigInt den;

  bool get isZero => num == BigInt.zero;

  Rate inverse() => Rate(den, num);
  Rate operator *(Rate o) => Rate(num * o.num, den * o.den);

  double toDouble() => num / den;

  /// Decimal text rounded half-even to [scale] places, trailing zeros trimmed.
  String toDecimalString([int scale = 10]) {
    final scaled = divRoundHalfEven(num * pow10(scale), den);
    final neg = scaled.isNegative;
    final digits = scaled.abs().toString().padLeft(scale + 1, '0');
    final whole = digits.substring(0, digits.length - scale);
    var frac = digits.substring(digits.length - scale).replaceFirst(RegExp(r'0+$'), '');
    return '${neg ? '-' : ''}$whole${frac.isEmpty ? '' : '.$frac'}';
  }

  @override
  int compareTo(Rate other) => (num * other.den).compareTo(other.num * den);

  @override
  bool operator ==(Object other) => other is Rate && other.num == num && other.den == den;

  @override
  int get hashCode => Object.hash(num, den);

  @override
  String toString() => toDecimalString();
}

/// Converts [minor] units of a commodity with [fromScale] decimals into minor
/// units of a commodity with [toScale] decimals at [rate] (target per source).
int convertMinor(int minor, Rate rate, int fromScale, int toScale) =>
    divRoundHalfEven(BigInt.from(minor) * rate.num * pow10(toScale), rate.den * pow10(fromScale)).toInt();

/// The rate implied by two amounts, e.g. a bank's FX transfer (to per from).
Rate impliedRate(int fromMinor, int fromScale, int toMinor, int toScale) =>
    Rate(BigInt.from(toMinor) * pow10(fromScale), BigInt.from(fromMinor) * pow10(toScale));

/// Parses an amount as written on a statement or typed by the user into minor
/// units with [scale] decimals. Accepts "1,234.56", "-12.3", "(45.00)",
/// "£1 000.50", "12.00 DR", "12.00-". Returns null when the text is not a
/// number or carries non-zero digits beyond [scale] (never silently rounds).
int? parseMinor(String input, int scale, {String decimalSeparator = '.'}) {
  var s = input.trim();
  if (s.isEmpty) return null;
  var negative = false;
  final upper = s.toUpperCase();
  if (upper.endsWith('DR')) {
    negative = true;
    s = s.substring(0, s.length - 2);
  } else if (upper.endsWith('CR')) {
    s = s.substring(0, s.length - 2);
  }
  s = s.trim();
  if (s.startsWith('(') && s.endsWith(')')) {
    negative = !negative;
    s = s.substring(1, s.length - 1);
  }
  // Drop currency symbols and codes but keep digits, separators and signs.
  s = s.replaceAll(RegExp(r"[^\d.,+\-]"), '');
  if (s.endsWith('-')) {
    negative = !negative;
    s = s.substring(0, s.length - 1);
  }
  if (s.startsWith('-')) {
    negative = !negative;
    s = s.substring(1);
  } else if (s.startsWith('+')) {
    s = s.substring(1);
  }
  final thousands = decimalSeparator == '.' ? ',' : '.';
  s = s.replaceAll(thousands, '');
  if (decimalSeparator != '.') s = s.replaceAll(decimalSeparator, '.');
  final m = RegExp(r'^(\d*)(?:\.(\d*))?$').firstMatch(s);
  if (m == null) return null;
  final whole = m.group(1)!;
  var frac = m.group(2) ?? '';
  if (whole.isEmpty && frac.isEmpty) return null;
  if (frac.length > scale) {
    if (frac.substring(scale).contains(RegExp('[1-9]'))) return null;
    frac = frac.substring(0, scale);
  }
  final value = int.parse('${whole.isEmpty ? '0' : whole}${frac.padRight(scale, '0')}');
  return negative ? -value : value;
}

/// Formats minor units exactly, with thousands grouping: 123456 -> "1,234.56".
String formatMinor(int minor, int scale, {String symbol = '', bool signed = false}) {
  final neg = minor < 0;
  final digits = minor.abs().toString().padLeft(scale + 1, '0');
  final whole = digits.substring(0, digits.length - scale);
  final frac = scale == 0 ? '' : '.${digits.substring(digits.length - scale)}';
  final grouped = whole.replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (_) => ',');
  final sign = neg ? '-' : (signed && minor > 0 ? '+' : '');
  return '$sign$symbol$grouped$frac';
}

/// Short form for charts and tiles: 1234567 pence -> "12.3k".
String formatCompact(int minor, int scale, {String symbol = ''}) {
  final v = minor / pow10(scale).toDouble();
  final a = v.abs();
  final sign = v < 0 ? '-' : '';
  // One decimal at most, dropped when it is zero: 8000 -> 8k, 1500 -> 1.5k.
  String short(double x) => x.toStringAsFixed(1).replaceFirst(RegExp(r'\.0$'), '');
  final body = a >= 1e9
      ? '${short(a / 1e9)}B'
      : a >= 1e6
      ? '${short(a / 1e6)}M'
      : a >= 1e3
      ? '${short(a / 1e3)}k'
      : a == a.roundToDouble()
      ? a.toStringAsFixed(0)
      : a.toStringAsFixed(2);
  return '$sign$symbol$body';
}
