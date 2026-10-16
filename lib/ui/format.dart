import 'package:intl/intl.dart';

import '../core/money/currencies.dart';
import '../core/money/money.dart';

/// Minor units of [code] as text: "£1,234.56", or "£1.2k" when [compact].
String money(int minor, String code, {bool signed = false, bool compact = false}) {
  final info = currencyInfo(code);
  return compact
      ? formatCompact(minor, info.scale, symbol: info.symbol)
      : formatMinor(minor, info.scale, symbol: info.symbol, signed: signed);
}

/// Units of a security or crypto, without trailing zeros: 1.500000 -> "1.5".
String units(int amount, int scale) {
  final s = formatMinor(amount, scale);
  return s.contains('.') ? s.replaceFirst(RegExp(r'\.?0+$'), '') : s;
}

String percent(double v, {int digits = 1}) => '${(v * 100).toStringAsFixed(digits)}%';

/// Basis points as a percentage: 2550 -> "25.5%".
String basisPoints(int bp) => '${(bp / 100).toStringAsFixed(bp % 100 == 0 ? 0 : 1)}%';

DateTime _utc(String iso) => DateTime.utc(
  int.parse(iso.substring(0, 4)),
  int.parse(iso.substring(5, 7)),
  iso.length >= 10 ? int.parse(iso.substring(8, 10)) : 1,
);

/// "2026-10-15" -> "15 Oct 2026".
String niceDate(String iso) => DateFormat('d MMM y').format(_utc(iso));

/// "2026-10" -> "Oct", or "Oct 26" with [year].
String monthLabel(String yyyyMm, {bool year = false}) =>
    DateFormat(year ? 'MMM yy' : 'MMM').format(_utc(yyyyMm));
