import 'dart:convert';

import 'package:drift/drift.dart';

import '../../../db/database.dart';
import '../fx/price_book.dart';

/// Asset classes that targets and allocation use.
const assetClasses = {
  'equity': 'Shares',
  'bond': 'Bonds',
  'cash': 'Cash',
  'property': 'Property',
  'commodity': 'Commodities',
  'crypto': 'Crypto',
  'alternative': 'Other / mixed',
};

class RiskProfile {
  const RiskProfile(this.id, this.label, this.description, this.targets);
  final String id;
  final String label;
  final String description;

  /// Weights in basis points (10000 = 100%).
  final Map<String, int> targets;
}

/// Starting points only; the user edits targets freely.
const riskProfiles = [
  RiskProfile('cautious', 'Cautious', 'Capital stability first; small growth share.', {
    'equity': 3000,
    'bond': 5000,
    'cash': 1500,
    'alternative': 500,
  }),
  RiskProfile('balanced', 'Balanced', 'Growth and stability in similar measure.', {
    'equity': 6000,
    'bond': 3000,
    'cash': 1000,
  }),
  RiskProfile('growth', 'Growth', 'Long horizon; accepts large swings.', {
    'equity': 8000,
    'bond': 1500,
    'cash': 500,
  }),
  RiskProfile('adventurous', 'Adventurous', 'Very long horizon; maximum growth share.', {
    'equity': 9000,
    'bond': 500,
    'cash': 300,
    'crypto': 200,
  }),
];

class Position {
  Position({
    required this.account,
    required this.commodity,
    required this.assetClass,
    required this.currency,
    required this.units,
    required this.value,
    required this.cost,
    required this.priceDate,
  });
  final Account account;
  final Commodity commodity;
  final String assetClass;

  /// Currency the position's price moves with (exposure).
  final String currency;

  /// In the account's commodity (security units or currency minor units).
  final int units;

  /// In base currency; null when no rate or price is known.
  final int? value;

  /// Pooled cost in base currency at purchase-date rates; null for cash.
  final int? cost;
  final String? priceDate;

  int? get gain => value == null || cost == null ? null : value! - cost!;
  double? get gainRatio => gain == null || cost == null || cost == 0 ? null : gain! / cost!;
}

class Drift {
  Drift(this.assetClass, this.currentBp, this.targetBp);
  final String assetClass;
  final int currentBp;
  final int targetBp;
  int get driftBp => currentBp - targetBp;

  /// The 5/25 rule: off by 5 percentage points, or by a quarter of a small target.
  bool get outOfBand =>
      driftBp.abs() >= 500 || (targetBp > 0 && driftBp.abs() * 4 >= targetBp && driftBp.abs() >= 100);
}

/// Investments and cash valued in one base currency.
class Portfolio {
  Portfolio(this.base, this.asOf, this.positions, this.missingRates);

  final String base;
  final String asOf;
  final List<Position> positions;
  final Set<String> missingRates;

  static const _cashLike = {
    'current',
    'savings',
    'cash',
    'isa_cash',
    'forex',
    'isa_stocks',
    'lisa',
    'brokerage',
  };

  /// Asset class of an account: its meta override, else its security's
  /// class, else what the account type implies.
  static String classify(Account a, Commodity c) {
    final override = (jsonDecode(a.meta) as Map)['assetClass'];
    if (override is String && assetClasses.containsKey(override)) return override;
    if (c.kind != 'currency') return c.assetClass ?? (c.kind == 'crypto' ? 'crypto' : 'equity');
    if (_cashLike.contains(a.subtype)) return 'cash';
    return switch (a.subtype) {
      'bonds' => 'bond',
      'property' => 'property',
      'crypto' => 'crypto',
      _ => 'alternative',
    };
  }

  /// Every asset account except money owed to the user; property only when
  /// [includeProperty] (a home usually is not part of an investment plan).
  static Future<Portfolio> load(
    AppDatabase db,
    PriceBook prices, {
    required String base,
    required String asOf,
    bool includeProperty = false,
  }) async {
    final accounts = {
      for (final a in await (db.select(
        db.accounts,
      )..where((a) => a.deleted.not() & a.kind.equals('asset'))).get())
        a.id: a,
    };
    final commodities = {for (final c in await db.select(db.commodities).get()) c.id: c};
    final units = await db
        .customSelect(
          'SELECT p.account_id, SUM(p.amount) AS u FROM postings p JOIN entries e ON e.id = p.entry_id '
          'WHERE e.deleted = 0 AND e.date <= ? GROUP BY p.account_id HAVING SUM(p.amount) <> 0',
          variables: [Variable(asOf)],
          readsFrom: {db.postings, db.entries},
        )
        .get();
    final costRows = await db
        .customSelect(
          'SELECT p.account_id, e.currency, e.date, SUM(p.value) AS v FROM postings p '
          'JOIN entries e ON e.id = p.entry_id JOIN accounts a ON a.id = p.account_id '
          "WHERE e.deleted = 0 AND e.date <= ? AND a.subtype = 'security' "
          'GROUP BY p.account_id, e.currency, e.date',
          variables: [Variable(asOf)],
          readsFrom: {db.postings, db.entries, db.accounts},
        )
        .get();
    final missing = <String>{};
    final costs = <String, int>{};
    for (final r in costRows) {
      final c = prices.convert(r.read<int>('v'), r.read<String>('currency'), base, r.read<String>('date'));
      if (c == null) {
        missing.add(r.read<String>('currency'));
        continue;
      }
      costs.update(r.read<String>('account_id'), (v) => v + c, ifAbsent: () => c);
    }

    final positions = <Position>[];
    for (final r in units) {
      final a = accounts[r.read<String>('account_id')];
      final c = a == null ? null : commodities[a.commodityId];
      if (a == null || c == null || a.subtype == 'receivable') continue;
      final cls = classify(a, c);
      if (cls == 'property' && !includeProperty) continue;
      final u = r.read<int>('u');
      final quote = prices.quote(c.id, base, asOf);
      final value = c.id == base ? u : (quote == null ? null : prices.convert(u, c.id, base, asOf));
      if (value == null) missing.add(c.id);
      positions.add(
        Position(
          account: a,
          commodity: c,
          assetClass: cls,
          currency: c.kind == 'currency' ? c.id : (c.quoteCurrency ?? base),
          units: u,
          value: value,
          cost: a.subtype == 'security' ? costs[a.id] ?? 0 : null,
          priceDate: c.id == base ? null : quote?.date,
        ),
      );
    }
    positions.sort((x, y) => (y.value ?? 0).compareTo(x.value ?? 0));
    return Portfolio(base, asOf, positions, missing);
  }

  int get total => positions.fold(0, (s, p) => s + (p.value ?? 0));
  int get invested => positions.where((p) => p.cost != null).fold(0, (s, p) => s + (p.value ?? 0));
  int get totalCost => positions.fold(0, (s, p) => s + (p.cost ?? 0));
  int get unrealisedGain => positions.fold(0, (s, p) => s + (p.gain ?? 0));

  Map<String, int> _sumBy(String Function(Position) key) {
    final m = <String, int>{};
    for (final p in positions) {
      if ((p.value ?? 0) > 0) m.update(key(p), (v) => v + p.value!, ifAbsent: () => p.value!);
    }
    return m;
  }

  Map<String, int> get byClass => _sumBy((p) => p.assetClass);
  Map<String, int> get byCurrency => _sumBy((p) => p.currency);

  /// Herfindahl-Hirschman index of position weights, 0..1. Lower is more
  /// diversified; cash accounts count as positions.
  double get concentration {
    final t = total;
    if (t <= 0) return 0;
    return positions.fold(0.0, (s, p) {
      final w = (p.value ?? 0) / t;
      return w > 0 ? s + w * w : s;
    });
  }

  /// "Behaves like this many equal holdings."
  double get effectiveHoldings => concentration == 0 ? 0 : 1 / concentration;

  List<Drift> drift(Map<String, int> targetsBp) {
    final t = total;
    final current = byClass;
    return [
      for (final c in {...targetsBp.keys, ...current.keys})
        Drift(c, t <= 0 ? 0 : ((current[c] ?? 0) * 10000 / t).round(), targetsBp[c] ?? 0),
    ]..sort((a, b) => b.driftBp.abs().compareTo(a.driftBp.abs()));
  }

  /// Trades per class (buy positive, sell negative) that reach the targets.
  Map<String, int> rebalance(Map<String, int> targetsBp) {
    final goal = apportion(total, targetsBp);
    final current = byClass;
    return {
      for (final c in {...goal.keys, ...current.keys})
        if ((goal[c] ?? 0) != (current[c] ?? 0)) c: (goal[c] ?? 0) - (current[c] ?? 0),
    };
  }

  /// Splits new money across classes to close the gaps without selling:
  /// underweight classes first, any surplus by target weight.
  Map<String, int> allocateNewMoney(Map<String, int> targetsBp, int amount) {
    if (amount <= 0) return {};
    final goal = apportion(total + amount, targetsBp);
    final current = byClass;
    final gaps = {
      for (final c in goal.keys)
        if (goal[c]! > (current[c] ?? 0)) c: goal[c]! - (current[c] ?? 0),
    };
    final gapSum = gaps.values.fold(0, (s, v) => s + v);
    if (gapSum >= amount) return apportion(amount, gaps);
    final extra = apportion(amount - gapSum, targetsBp);
    return {
      for (final c in {...gaps.keys, ...extra.keys}) c: (gaps[c] ?? 0) + (extra[c] ?? 0),
    }..removeWhere((_, v) => v == 0);
  }
}

/// Splits [total] in proportion to [weights] so the parts sum exactly to it
/// (largest remainder method).
Map<String, int> apportion(int total, Map<String, int> weights) {
  final sum = weights.values.fold(0, (s, w) => s + (w > 0 ? w : 0));
  if (sum == 0 || total == 0) return {};
  final parts = <String, int>{}, rest = <String, int>{};
  for (final MapEntry(key: k, value: w) in weights.entries) {
    if (w <= 0) continue;
    final exact = BigInt.from(total) * BigInt.from(w);
    parts[k] = (exact ~/ BigInt.from(sum)).toInt();
    rest[k] = (exact.remainder(BigInt.from(sum))).toInt().abs();
  }
  var left = total - parts.values.fold<int>(0, (s, v) => s + v);
  final step = left.sign;
  for (final k in rest.keys.toList()..sort((a, b) => rest[b]!.compareTo(rest[a]!))) {
    if (left == 0) break;
    parts[k] = parts[k]! + step;
    left -= step;
  }
  return parts;
}
