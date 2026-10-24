/// Common shape every statement parser produces.
library;

import 'package:brahma_core/brahma_core.dart';

class StatementLine {
  StatementLine({
    required this.date,
    required this.amount,
    this.payee = '',
    this.memo = '',
    this.ref = '',
    this.balance,
    this.currency,
  });

  /// yyyy-MM-dd
  final String date;

  /// Minor units; negative = money out of the account.
  final int amount;
  final String payee;
  final String memo;

  /// Bank's own transaction id when the format has one (OFX FITID).
  final String ref;

  /// Running balance after this line, if the statement shows one.
  final int? balance;
  final String? currency;

  String get text => [payee, memo].where((s) => s.isNotEmpty).join(' · ');
}

/// A balance the bank printed: the account held [balance] at the end of [date].
typedef BalancePoint = ({String date, int balance});

class ParsedStatement {
  ParsedStatement({
    required this.lines,
    this.currency,
    this.accountNumber,
    this.sortCode,
    this.institution,
    this.isCard = false,
    this.openingBalance,
    this.openingDate,
    this.closingBalance,
    this.closingDate,
    this.warnings = const [],
    this.checks = const [],
    this.problems = const [],
    this.checkpoints = const [],
  });

  /// Oldest first.
  final List<StatementLine> lines;
  final String? currency;

  /// Account number, or a card's last four digits.
  final String? accountNumber;

  /// UK sort code as 12-34-56, when the statement prints one.
  final String? sortCode;

  /// Bank or card issuer named on the statement.
  final String? institution;
  final bool isCard;

  /// Balance before the first line, when derivable.
  final int? openingBalance;

  /// The day [openingBalance] stands at (the day before the period starts).
  final String? openingDate;

  /// Balance at the end of [closingDate], when the statement states it.
  final int? closingBalance;
  final String? closingDate;
  final List<String> warnings;

  /// Figures on the statement that the rows agree with, and those they do not.
  /// Only formats that print balances or totals have any.
  final List<String> checks;
  final List<String> problems;

  /// Balances the bank printed for the account, oldest first. Imports keep
  /// them as balance checks, so the account tallies across statements.
  final List<BalancePoint> checkpoints;

  /// Every printed figure was checked and agrees.
  bool get verified => checks.isNotEmpty && problems.isEmpty;

  int get total => lines.fold(0, (s, l) => s + l.amount);
}

class StatementFormatException implements Exception, UserFacingError {
  StatementFormatException(this.message);
  @override
  final String message;
  @override
  String toString() => message;
}

// ---- dates ----

const _months = {
  'jan': 1,
  'feb': 2,
  'mar': 3,
  'apr': 4,
  'may': 5,
  'jun': 6,
  'jul': 7,
  'aug': 8,
  'sep': 9,
  'oct': 10,
  'nov': 11,
  'dec': 12,
};

/// Date layouts seen in bank exports.
enum DateOrder { ymd, dmy, mdy }

String _iso(int y, int m, int d) {
  final s = '${y.toString().padLeft(4, '0')}-${m.toString().padLeft(2, '0')}-${d.toString().padLeft(2, '0')}';
  if (!isValidIsoDate(s)) throw const FormatException('no such day');
  return s;
}

int _year(String y) {
  final v = int.parse(y);
  if (y.length > 2) return v;
  final now = DateTime.now().year % 100;
  return v <= now + 1 ? 2000 + v : 1900 + v;
}

/// Parses one date in [order] to yyyy-MM-dd, or null.
String? parseDate(String input, DateOrder order) {
  final s = input.trim().replaceAll("'", '/');
  try {
    var m = RegExp(r'^(\d{4})[-/.]?(\d{1,2})[-/.]?(\d{1,2})(?:[T ].*)?$').firstMatch(s);
    if (m != null) {
      return _iso(int.parse(m.group(1)!), int.parse(m.group(2)!), int.parse(m.group(3)!));
    }
    m = RegExp(r'^(\d{1,2})[-/. ]\s*(\d{1,2})[-/. ]\s*(\d{2,4})(?:[T ,].*)?$').firstMatch(s);
    if (m != null) {
      // Only numeric day/month triples depend on the order; ISO and
      // month-name dates parse under any order.
      if (order == DateOrder.ymd) return null;
      final a = int.parse(m.group(1)!), b = int.parse(m.group(2)!), y = _year(m.group(3)!);
      return order == DateOrder.mdy ? _iso(y, a, b) : _iso(y, b, a);
    }
    m = RegExp(r'^(\d{1,2})[-/ ]([A-Za-z]{3,9})[-/ ,]*(\d{2,4})').firstMatch(s);
    if (m != null) {
      final mon = _months[m.group(2)!.substring(0, 3).toLowerCase()];
      if (mon == null) return null;
      return _iso(_year(m.group(3)!), mon, int.parse(m.group(1)!));
    }
    m = RegExp(r'^([A-Za-z]{3,9})[ -](\d{1,2}),?[ -](\d{4})').firstMatch(s);
    if (m != null) {
      final mon = _months[m.group(1)!.substring(0, 3).toLowerCase()];
      if (mon == null) return null;
      return _iso(int.parse(m.group(3)!), mon, int.parse(m.group(2)!));
    }
  } on FormatException {
    return null;
  }
  return null;
}

/// Picks the order that parses every sample. Day-first wins ties (UK banks),
/// unless [preferMonthFirst].
DateOrder? detectDateOrder(Iterable<String> samples, {bool preferMonthFirst = false}) {
  final list = samples.where((s) => s.trim().isNotEmpty).take(200).toList();
  if (list.isEmpty) return null;
  final orders = preferMonthFirst
      ? [DateOrder.ymd, DateOrder.mdy, DateOrder.dmy]
      : [DateOrder.ymd, DateOrder.dmy, DateOrder.mdy];
  for (final o in orders) {
    if (list.every((s) => parseDate(s, o) != null)) return o;
  }
  return null;
}

// ---- refs ----

/// Stable 64-bit FNV-1a hash as hex, for content-based duplicate detection.
String stableHash(String s) {
  var h = 0xcbf29ce484222325;
  for (final c in s.codeUnits) {
    h ^= c;
    h *= 0x100000001b3; // wraps mod 2^64 on native platforms
  }
  return h.toUnsigned(64).toRadixString(16).padLeft(16, '0');
}

/// Duplicate-detection key per line: the bank id when present, otherwise a
/// hash of date, amount, text and its position among identical same-day lines
/// (two £3 coffees on one day stay two).
List<String> lineRefs(List<StatementLine> lines) {
  final seen = <String, int>{};
  return [
    for (final l in lines)
      if (l.ref.isNotEmpty)
        'id:${l.ref}'
      else
        () {
          final base = '${l.date}|${l.amount}|${l.text.toLowerCase().replaceAll(RegExp(r'\s+'), ' ')}';
          final n = seen.update(base, (v) => v + 1, ifAbsent: () => 0);
          return 'h:${stableHash('$base|$n')}';
        }(),
  ];
}
