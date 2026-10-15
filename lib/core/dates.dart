/// Calendar dates as ISO `yyyy-MM-dd` strings. All maths runs in UTC so a
/// daylight-saving change can never shift a day.
library;

final _iso = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$');

DateTime _utc(String iso) {
  final m = _iso.firstMatch(iso);
  if (m == null) throw FormatException('not a yyyy-MM-dd date', iso);
  return DateTime.utc(int.parse(m[1]!), int.parse(m[2]!), int.parse(m[3]!));
}

String isoDate(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

/// True for real calendar dates only ("2026-02-31" is false).
bool isValidIsoDate(String s) {
  final m = _iso.firstMatch(s);
  if (m == null) return false;
  final y = int.parse(m[1]!), mo = int.parse(m[2]!), d = int.parse(m[3]!);
  final dt = DateTime.utc(y, mo, d);
  return dt.year == y && dt.month == mo && dt.day == d;
}

String today() => isoDate(DateTime.now());

String addDays(String iso, int days) => isoDate(_utc(iso).add(Duration(days: days)));

int daysBetween(String a, String b) => _utc(a).difference(_utc(b)).inDays.abs();

/// Same day [months] later or earlier, clamped to the month's end.
String addMonths(String iso, int months) {
  final d = _utc(iso);
  final first = DateTime.utc(d.year, d.month + months);
  final last = DateTime.utc(first.year, first.month + 1, 0).day;
  return isoDate(DateTime.utc(first.year, first.month, d.day > last ? last : d.day));
}

/// Last day of the month containing [iso].
String monthEnd(String iso) {
  final d = _utc(iso);
  return isoDate(DateTime.utc(d.year, d.month + 1, 0));
}

String monthStart(String iso) => '${iso.substring(0, 7)}-01';
