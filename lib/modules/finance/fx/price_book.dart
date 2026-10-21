import 'dart:collection';

import 'package:brahma_core/brahma_core.dart';
import 'package:drift/drift.dart';

import '../../../db/database.dart';

/// A rate between two commodities and the date of the oldest price it used.
typedef Quote = ({Rate rate, String date});

/// Exchange rates and security prices over time. Converts between any two
/// commodities through a chain of known prices, e.g. a US fund -> USD -> EUR
/// -> GBP when only ECB rates are stored. Among possible chains it picks the
/// one whose oldest price is newest, then the shortest.
class PriceBook {
  PriceBook(this.scales);

  /// Decimal places per commodity id.
  final Map<String, int> scales;
  final _series = <String, SplayTreeMap<String, Rate>>{};
  final _links = <String, Set<String>>{};
  final _cache = <String, Quote?>{};

  static const _maxHops = 4;

  /// Prices from the Prices table plus those implied by the user's own trades
  /// and currency transfers, so holdings without a market feed still value at
  /// their last traded price.
  static Future<PriceBook> load(AppDatabase db) async {
    final book = PriceBook({for (final c in await db.select(db.commodities).get()) c.id: c.scale});
    final trades = await db
        .customSelect(
          'SELECT a.commodity_id AS c, e.currency AS q, e.date AS d, p.amount, p.value '
          'FROM postings p JOIN entries e ON e.id = p.entry_id JOIN accounts a ON a.id = p.account_id '
          // Only real conversions: category and equity lines are in the entry
          // currency whatever their account's commodity (see isNominal).
          "WHERE e.deleted = 0 AND a.kind IN ('asset', 'liability') AND a.commodity_id <> e.currency "
          'AND p.amount <> 0 AND p.value <> 0 '
          'ORDER BY e.date',
          readsFrom: {db.postings, db.entries, db.accounts},
        )
        .get();
    for (final t in trades) {
      final c = t.read<String>('c'), q = t.read<String>('q');
      final cs = book.scales[c], qs = book.scales[q];
      if (cs == null || qs == null) continue;
      book.add(
        c,
        q,
        t.read<String>('d'),
        impliedRate(t.read<int>('amount').abs(), cs, t.read<int>('value').abs(), qs),
      );
    }
    // Stored prices go last so they win over a trade on the same day.
    for (final p in await (db.select(db.prices)..where((p) => p.deleted.not())).get()) {
      final r = Rate.tryParse(p.rate);
      if (r != null) book.add(p.commodityId, p.quote, p.date, r);
    }
    return book;
  }

  /// Records that one unit of [from] was worth [rate] units of [to] on [date].
  void add(String from, String to, String date, Rate rate) {
    if (from == to || rate.num <= BigInt.zero) return;
    _series.putIfAbsent('$from>$to', SplayTreeMap.new)[date] = rate;
    _links.putIfAbsent(from, () => {}).add(to);
    _links.putIfAbsent(to, () => {}).add(from);
    _cache.clear();
  }

  /// Units of [to] per unit of [from] on or before [asOf], or null if no
  /// chain of prices connects them by then.
  Quote? quote(String from, String to, String asOf) {
    if (from == to) return (rate: Rate.fromInt(1), date: asOf);
    return _cache.putIfAbsent('$from>$to@$asOf', () => _search(from, to, asOf));
  }

  Rate? rate(String from, String to, String asOf) => quote(from, to, asOf)?.rate;

  /// [minor] units of [from] in minor units of [to]; null when no rate is known.
  int? convert(int minor, String from, String to, String asOf) {
    if (from == to || minor == 0) return minor;
    final q = quote(from, to, asOf);
    final fs = scales[from], ts = scales[to];
    if (q == null || fs == null || ts == null) return null;
    return convertMinor(minor, q.rate, fs, ts);
  }

  Quote? _search(String from, String to, String asOf) {
    // Best known chain to each node: (oldest price date, hops, rate).
    final best = <String, ({String date, int hops, Rate rate})>{
      from: (date: '9999-12-31', hops: 0, rate: Rate.fromInt(1)),
    };
    var frontier = {from};
    for (var hop = 1; hop <= _maxHops && frontier.isNotEmpty; hop++) {
      final next = <String>{};
      for (final node in frontier) {
        final here = best[node]!;
        for (final n in _links[node] ?? const <String>{}) {
          final edge = _edge(node, n, asOf);
          if (edge == null) continue;
          final date = edge.date.compareTo(here.date) < 0 ? edge.date : here.date;
          final seen = best[n];
          if (seen == null || date.compareTo(seen.date) > 0) {
            best[n] = (date: date, hops: hop, rate: here.rate * edge.rate);
            next.add(n);
          }
        }
      }
      frontier = next;
    }
    final hit = best[to];
    return hit == null ? null : (rate: hit.rate, date: hit.date);
  }

  /// The latest direct or inverted price for one link on or before [asOf].
  Quote? _edge(String from, String to, String asOf) {
    final d = _latest(_series['$from>$to'], asOf);
    final i = _latest(_series['$to>$from'], asOf);
    if (i == null) return d;
    final inv = (rate: i.rate.inverse(), date: i.date);
    return d != null && d.date.compareTo(i.date) >= 0 ? d : inv;
  }

  static Quote? _latest(SplayTreeMap<String, Rate>? s, String asOf) {
    if (s == null) return null;
    final key = s.containsKey(asOf) ? asOf : s.lastKeyBefore(asOf);
    return key == null ? null : (rate: s[key]!, date: key);
  }
}
