import 'package:brahma_core/brahma_core.dart';

import 'insights.dart';

/// One expected payment or receipt in a forecast.
class ForecastEvent {
  const ForecastEvent(this.date, this.label, this.amount, {this.oneOff = false, this.id});
  final String date;
  final String label;

  /// Negative for money out.
  final int amount;

  /// Planned by the user once, rather than repeating.
  final bool oneOff;

  /// The planned item's row, for a one-off.
  final String? id;
}

/// Liquid money day by day over the next [days], in the base currency.
class CashForecast {
  CashForecast(this.today, this.opening, this.balances, this.events, this.everydayPerMonth);
  final String today;

  /// Liquid balance recorded today.
  final int opening;

  /// Balance at the end of each day: index 0 is tomorrow.
  final List<int> balances;

  /// Recurring and one-off payments and income expected, in date order.
  final List<ForecastEvent> events;

  /// Spending that does not repeat on a schedule, spread evenly.
  final int everydayPerMonth;

  int get days => balances.length;
  String dateAt(int i) => addDays(today, i + 1);
  int get closing => balances.isEmpty ? opening : balances.last;

  /// The lowest day, the earliest one on a tie.
  ({String date, int balance}) get lowest {
    var at = -1;
    var low = opening;
    for (var i = 0; i < balances.length; i++) {
      if (balances[i] < low) (at, low) = (i, balances[i]);
    }
    return (date: at < 0 ? today : dateAt(at), balance: low);
  }
}

/// Projects [liquid] forward: every [recurring] item at its cadence, and the
/// rest of [monthlySpend] (the part no recurring payment explains) spent
/// evenly, plus the [oneOffs] the user planned. Other income that does not
/// recur on a schedule is left out, so the forecast errs low. A recurring
/// item already due is expected tomorrow, since statements arrive after the
/// fact; so is a one-off planned for today. Earlier one-offs have passed.
CashForecast forecastCash({
  required int liquid,
  required List<Recurring> recurring,
  required int monthlySpend,
  required String today,
  List<ForecastEvent> oneOffs = const [],
  int days = 90,
}) {
  final end = addDays(today, days);
  final tomorrow = addDays(today, 1);
  final events = <ForecastEvent>[];
  var recurringOut = 0;
  for (final r in recurring) {
    if (r.amount < 0) recurringOut -= r.cadence.perMonth(r.amount);
    // Step from the last payment by whole cycles so monthly dates do not
    // drift after a short month.
    var pulled = false;
    for (var k = 1; ; k++) {
      final due = r.cadence == Cadence.monthly
          ? addMonths(r.lastDate, k)
          : addDays(r.lastDate, k * r.cadence.days);
      if (due.compareTo(end) > 0) break;
      if (due.compareTo(tomorrow) < 0) {
        // Only one overdue occurrence is pulled forward; older ones lapsed.
        if (pulled) continue;
        pulled = true;
        events.add(ForecastEvent(tomorrow, r.label, r.amount));
      } else {
        events.add(ForecastEvent(due, r.label, r.amount));
      }
    }
  }
  for (final o in oneOffs) {
    if (o.date.compareTo(today) < 0 || o.date.compareTo(end) > 0) continue;
    events.add(ForecastEvent(o.date == today ? tomorrow : o.date, o.label, o.amount, oneOff: true, id: o.id));
  }
  events.sort((a, b) => a.date.compareTo(b.date));
  final everyday = monthlySpend > recurringOut ? monthlySpend - recurringOut : 0;
  final byDay = <String, int>{};
  for (final e in events) {
    byDay.update(e.date, (v) => v + e.amount, ifAbsent: () => e.amount);
  }
  final balances = <int>[];
  var scheduled = 0;
  for (var d = 1; d <= days; d++) {
    scheduled += byDay[addDays(today, d)] ?? 0;
    balances.add(liquid + scheduled - (everyday * 12 * d / 365).round());
  }
  return CashForecast(today, liquid, balances, events, everyday);
}
