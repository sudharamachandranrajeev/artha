import 'dart:convert';
import 'dart:math' as math;

import 'package:brahma_core/brahma_core.dart';
import 'package:drift/drift.dart';

import '../../../db/database.dart';
import '../domain/ledger.dart';
import '../portfolio/portfolio.dart';
import '../reports/reports.dart';
import 'catalogue.dart';
import 'categorizer.dart';

/// A categorised transaction as the pattern finders see it. [amount] is the
/// money flow: negative out, positive in (base currency).
class Txn {
  const Txn(this.date, this.text, this.amount, this.categoryId);
  final String date;
  final String text;
  final int amount;
  final String categoryId;
}

enum Cadence {
  weekly(7, 6, 8),
  monthly(30, 26, 35),
  quarterly(91, 84, 98),
  yearly(365, 350, 380);

  const Cadence(this.days, this.min, this.max);
  final int days;
  final int min;
  final int max;

  /// Monthly equivalent of one payment.
  int perMonth(int amount) => (amount * 365 / days / 12).round();
}

class Recurring {
  Recurring(this.key, this.label, this.cadence, this.amount, this.lastDate, this.categoryId, this.count);
  final String key;
  final String label;
  final Cadence cadence;

  /// Typical amount, negative for payments out.
  final int amount;
  final String lastDate;
  final String categoryId;
  final int count;
  String get nextDate =>
      cadence == Cadence.monthly ? addMonths(lastDate, 1) : addDays(lastDate, cadence.days);
}

int _median(List<int> xs) {
  final s = [...xs]..sort();
  return s.isEmpty ? 0 : s[s.length ~/ 2];
}

/// Payments or income that repeat at a steady interval with a steady amount.
/// Lapsed ones (overdue by more than half a cycle) are left out.
List<Recurring> detectRecurring(List<Txn> txns, String today) {
  final groups = <String, List<Txn>>{};
  for (final t in txns) {
    final tokens = Categorizer.tokenize(t.text);
    if (tokens.isEmpty || t.amount == 0) continue;
    groups.putIfAbsent('${t.amount < 0 ? '-' : '+'}${Categorizer.merchantKey(tokens)}', () => []).add(t);
  }
  final out = <Recurring>[];
  for (final MapEntry(key: key, value: g) in groups.entries) {
    if (g.length < 3) continue;
    g.sort((a, b) => a.date.compareTo(b.date));
    final gaps = [for (var i = 1; i < g.length; i++) daysBetween(g[i].date, g[i - 1].date)];
    final gap = _median(gaps);
    final cadence = Cadence.values.where((c) => gap >= c.min && gap <= c.max).firstOrNull;
    if (cadence == null) continue;
    if (gaps.where((d) => d >= cadence.min && d <= cadence.max).length * 3 < gaps.length * 2) continue;
    final amount = _median([for (final t in g) t.amount]);
    if (g.where((t) => (t.amount - amount).abs() * 5 <= amount.abs()).length * 3 < g.length * 2) continue;
    final last = g.last;
    if (daysBetween(today, last.date) > cadence.days * 3 ~/ 2) continue;
    out.add(Recurring(key, last.text, cadence, amount, last.date, last.categoryId, g.length));
  }
  out.sort((a, b) => a.cadence.perMonth(a.amount).compareTo(b.cadence.perMonth(b.amount)));
  return out;
}

class Anomaly {
  Anomaly(this.categoryId, this.month, this.amount, this.usual);
  final String categoryId;
  final String month;
  final int amount;
  final int usual;
}

/// Categories where [month]'s spending is well above the median of earlier
/// months: at least 1.5x and at least [floor] more.
List<Anomaly> detectAnomalies(
  Map<String, Map<String, int>> spendByCategoryMonth,
  String month, {
  int floor = 5000,
}) {
  final out = <Anomaly>[];
  for (final MapEntry(key: cat, value: months) in spendByCategoryMonth.entries) {
    final now = months[month] ?? 0;
    final history = [
      for (final MapEntry(key: m, value: v) in months.entries)
        if (m.compareTo(month) < 0) v,
    ];
    if (history.length < 3) continue;
    final usual = _median(history);
    if (now * 2 >= usual * 3 && now - usual >= floor) out.add(Anomaly(cat, month, now, usual));
  }
  out.sort((a, b) => (b.amount - b.usual).compareTo(a.amount - a.usual));
  return out;
}

/// Headline numbers of personal financial health, in base currency.
class Metrics {
  int netWorth = 0;
  int liquid = 0;
  int debt = 0;

  /// Averages over recent complete months.
  int monthlyIncome = 0;
  int monthlySpend = 0;
  int monthlyEssential = 0;
  double? savingsRate;

  /// Months of essential spending the liquid money covers.
  double? emergencyMonths;
  double? creditUtilisation;
  double? debtToIncome;

  /// GBP paid into ISAs this tax year (null when the user has none).
  int? isaUsed;
}

class Insight {
  Insight(
    this.id,
    this.kind,
    this.title,
    this.body, {
    this.severity = 'info',
    this.score = 1,
    this.data = const {},
  });
  final String id;
  final String kind;
  final String title;
  final String body;

  /// good | info | warn | action
  final String severity;
  final double score;
  final Map<String, Object?> data;
}

/// Works out metrics and insights from the ledger. Nothing leaves the device.
class InsightEngine {
  InsightEngine(this.db, this.reports, this.portfolio, this.today, {this.targets = const {}});
  final AppDatabase db;
  final Reports reports;
  final Portfolio portfolio;
  final String today;
  final Map<String, int> targets;
  String get base => reports.base;

  static const _liquid = {'current', 'savings', 'cash', 'isa_cash', 'forex'};
  static const _isa = {'isa_cash', 'isa_stocks', 'lisa', 'isa_ifi'};

  /// Two-leg cash <-> category entries of the last 13 months.
  Future<List<Txn>> transactions() async {
    final rows = await db
        .customSelect(
          'SELECT e.date, e.payee, e.memo, p.account_id, p.amount FROM entries e '
          'JOIN postings p ON p.entry_id = e.id JOIN accounts a ON a.id = p.account_id '
          "WHERE e.deleted = 0 AND e.date BETWEEN ? AND ? AND a.kind IN ('income', 'expense') "
          'AND e.currency = ? AND (SELECT COUNT(*) FROM postings q WHERE q.entry_id = e.id) = 2',
          variables: [Variable(addMonths(today, -13)), Variable(today), Variable(base)],
          readsFrom: {db.entries, db.postings, db.accounts},
        )
        .get();
    return [
      for (final r in rows)
        Txn(
          r.read<String>('date'),
          '${r.read<String>('payee')} ${r.read<String>('memo')}'.trim(),
          -r.read<int>('amount'),
          r.read<String>('account_id'),
        ),
    ];
  }

  Future<Metrics> metrics() async {
    final m = Metrics();
    final bs = await reports.balanceSheet(today);
    m.netWorth = bs.netWorth;
    m.debt = bs.totalLiabilities;
    m.liquid = bs.assets
        .where((l) => _liquid.contains(l.account.subtype))
        .fold(0, (s, l) => s + (l.baseValue ?? 0));

    // Complete months only: the current one is still running.
    final flows = (await reports.monthlyFlows(today, months: 7)).sublist(0, 6);
    final active = flows.where((f) => f.income > 0 || f.expenses > 0).toList();
    if (active.isNotEmpty) {
      final recent = active.length > 3 ? active.sublist(active.length - 3) : active;
      m.monthlyIncome = recent.fold(0, (s, f) => s + f.income) ~/ recent.length;
      m.monthlySpend = recent.fold(0, (s, f) => s + f.expenses) ~/ recent.length;
      m.monthlyEssential = active.fold(0, (s, f) => s + f.essential) ~/ active.length;
      if (m.monthlyIncome > 0) m.savingsRate = (m.monthlyIncome - m.monthlySpend) / m.monthlyIncome;
      final need = m.monthlyEssential > 0 ? m.monthlyEssential : m.monthlySpend;
      if (need > 0) m.emergencyMonths = m.liquid / need;
      if (m.monthlyIncome > 0) m.debtToIncome = m.debt / (m.monthlyIncome * 12);
    }

    var limits = 0, owed = 0;
    for (final l in bs.liabilities.where((l) => l.account.subtype == 'credit_card')) {
      final limit = (jsonDecode(l.account.meta) as Map)['creditLimit'];
      if (limit is int && limit > 0) {
        limits += limit;
        owed -= l.baseValue ?? 0;
      }
    }
    if (limits > 0) m.creditUtilisation = owed / limits;

    if (reports.accounts.values.any((a) => _isa.contains(a.subtype))) {
      final r = await db
          .customSelect(
            'SELECT COALESCE(SUM(p.amount), 0) AS paid FROM postings p JOIN entries e ON e.id = p.entry_id '
            'JOIN accounts a ON a.id = p.account_id '
            "WHERE e.deleted = 0 AND e.date BETWEEN ? AND ? AND a.subtype IN ('isa_cash','isa_stocks','lisa','isa_ifi') "
            "AND a.commodity_id = 'GBP' AND p.amount > 0 AND NOT EXISTS (SELECT 1 FROM postings q "
            'JOIN accounts b ON b.id = q.account_id WHERE q.entry_id = e.id AND q.id <> p.id '
            "AND (b.subtype IN ('isa_cash','isa_stocks','lisa','isa_ifi','security') OR b.kind = 'income'))",
            variables: [Variable(ukTaxYearStart(today)), Variable(today)],
            readsFrom: {db.postings, db.entries, db.accounts},
          )
          .getSingle();
      m.isaUsed = r.read<int>('paid');
    }
    return m;
  }

  Future<List<Insight>> generate() async {
    final m = await metrics();
    final out = <Insight>[];
    final txns = await transactions();
    String name(String id) => reports.accounts[id]?.name ?? id;

    // Spending habits.
    for (final r in detectRecurring(txns, today)) {
      final monthly = r.cadence.perMonth(r.amount).abs();
      out.add(
        Insight(
          'recurring/${r.key}',
          r.amount < 0 ? 'recurring' : 'income_pattern',
          r.label,
          '${r.cadence.name[0].toUpperCase()}${r.cadence.name.substring(1)}, next around ${r.nextDate}',
          score: 0.3 + math.min(monthly / 100000, 1) * 0.4,
          data: {
            'amount': r.amount,
            'cadence': r.cadence.name,
            'next': r.nextDate,
            'category': r.categoryId,
            'monthly': monthly,
          },
        ),
      );
    }
    final spend = <String, Map<String, int>>{};
    for (final t in txns.where((t) => t.amount < 0)) {
      spend
          .putIfAbsent(t.categoryId, () => {})
          .update(t.date.substring(0, 7), (v) => v - t.amount, ifAbsent: () => -t.amount);
    }
    for (final a in detectAnomalies(spend, today.substring(0, 7))) {
      out.add(
        Insight(
          'anomaly/${a.categoryId}/${a.month}',
          'anomaly',
          '${name(a.categoryId)} is high this month',
          '${(a.amount / math.max(a.usual, 1)).toStringAsFixed(1)}x a usual month',
          severity: 'warn',
          score: 0.7,
          data: {'category': a.categoryId, 'amount': a.amount, 'usual': a.usual},
        ),
      );
    }
    await _budgets(out, spend, name);

    // Health.
    final em = m.emergencyMonths;
    if (em != null) {
      if (em < 3) {
        out.add(
          Insight(
            'health/emergency_fund',
            'emergency_fund',
            'Build an emergency fund',
            'Cash covers ${em.toStringAsFixed(1)} months of essentials; 3-6 months is the usual cushion.',
            severity: 'action',
            score: 0.95,
            data: {'months': em, 'option': 'easy_access'},
          ),
        );
      } else if (em > 9 && m.monthlyEssential > 0) {
        final idle = m.liquid - m.monthlyEssential * 6;
        out.add(
          Insight(
            'health/idle_cash',
            'idle_cash',
            'Cash beyond a 6-month cushion',
            'About ${idle ~/ 100} $base could work harder: savings rates, gilts or long-term investing.',
            score: 0.6,
            data: {
              'idle': idle,
              'options': ['money_market', 'gilts', 'global_index'],
            },
          ),
        );
      }
    }
    final sr = m.savingsRate;
    if (sr != null) {
      out.add(
        Insight(
          'health/savings_rate',
          'savings_rate',
          sr >= 0.2 ? 'Strong savings rate' : (sr < 0 ? 'Spending more than earning' : 'Savings rate'),
          'Recent months saved ${(sr * 100).round()}% of income.',
          severity: sr >= 0.2 ? 'good' : (sr < 0.05 ? 'warn' : 'info'),
          score: sr < 0 ? 0.9 : 0.5,
          data: {'rate': sr},
        ),
      );
    }
    final cu = m.creditUtilisation;
    if (cu != null && cu > 0.3) {
      out.add(
        Insight(
          'health/credit_utilisation',
          'credit_utilisation',
          'Credit cards ${(cu * 100).round()}% used',
          'Keeping balances under 30% of limits helps credit scores and interest costs.',
          severity: 'warn',
          score: 0.75,
          data: {'ratio': cu},
        ),
      );
    }
    for (final a in reports.accounts.values.where((a) => a.kind == 'liability' && !a.closed)) {
      final apr = (jsonDecode(a.meta) as Map)['interestRate'];
      if (apr is num && apr >= 10) {
        out.add(
          Insight(
            'debt/${a.id}',
            'expensive_debt',
            'Pay down ${a.name} first',
            '$apr% interest is higher than most investments reliably return.',
            severity: 'action',
            score: 0.85 + math.min(apr / 1000, 0.1),
            data: {'account': a.id, 'apr': apr},
          ),
        );
      }
    }
    final isaUsed = m.isaUsed;
    if (isaUsed != null && base == 'GBP') {
      final left = UkAllowances.isa - isaUsed;
      final yearEnd = addDays(addMonths(ukTaxYearStart(today), 12), -1);
      final daysLeft = daysBetween(yearEnd, today);
      if (left > 0 && daysLeft <= 90) {
        out.add(
          Insight(
            'isa/${UkAllowances.taxYear}',
            'isa_allowance',
            'ISA allowance left: £${left ~/ 100}',
            'Unused allowance is lost after $yearEnd.',
            severity: 'action',
            score: 0.8,
            data: {'left': left, 'deadline': yearEnd},
          ),
        );
      }
    }

    // Investments.
    if (targets.isNotEmpty && portfolio.total > 0) {
      final off = portfolio.drift(targets).where((d) => d.outOfBand).toList();
      if (off.isNotEmpty) {
        out.add(
          Insight(
            'portfolio/rebalance',
            'rebalance',
            'Portfolio has drifted from its targets',
            off
                .map(
                  (d) =>
                      '${assetClasses[d.assetClass] ?? d.assetClass} ${d.driftBp > 0 ? '+' : ''}${d.driftBp / 100}pp',
                )
                .join(', '),
            severity: 'action',
            score: 0.7,
            data: {for (final d in off) d.assetClass: d.driftBp},
          ),
        );
      }
    }
    final invested = portfolio.positions.where((p) => p.cost != null).toList();
    if (invested.length > 1) {
      final top = invested.first;
      final share = (top.value ?? 0) / math.max(portfolio.invested, 1);
      if (share > 0.2 && (top.commodity.assetClass ?? 'equity') == 'equity') {
        out.add(
          Insight(
            'portfolio/concentration/${top.account.id}',
            'concentration',
            '${top.commodity.name} is ${(share * 100).round()}% of investments',
            'A single holding above 20% ties results to one company or fund manager.',
            severity: 'warn',
            score: 0.6,
            data: {'account': top.account.id, 'share': share},
          ),
        );
      }
    }
    if (em != null &&
        em >= 3 &&
        !reports.accounts.values.any((a) => a.subtype == 'pension') &&
        base == 'GBP') {
      out.add(
        Insight(
          'explore/pension',
          'explore',
          'No pension recorded',
          'Pensions add tax relief and often an employer match. Add one here if you already have it.',
          score: 0.55,
          data: {'option': 'pension'},
        ),
      );
    }
    return out;
  }

  Future<void> _budgets(
    List<Insight> out,
    Map<String, Map<String, int>> spend,
    String Function(String) name,
  ) async {
    final month = today.substring(0, 7);
    for (final b in await (db.select(db.budgets)..where((b) => b.deleted.not())).get()) {
      final used = spend[b.accountId]?[month] ?? 0;
      if (b.amount > 0 && used > b.amount) {
        out.add(
          Insight(
            'budget/${b.accountId}/$month',
            'budget',
            '${name(b.accountId)} over budget',
            '${(used * 100 / b.amount).round()}% of the monthly budget used.',
            severity: 'warn',
            score: 0.8,
            data: {'category': b.accountId, 'used': used, 'budget': b.amount},
          ),
        );
      }
    }
  }
}

/// The learned knowledge base: insights become Facts the user can confirm or
/// dismiss. Dismissed facts stay dismissed; kinds the user keeps dismissing
/// rank lower, kinds they confirm rank higher.
class KnowledgeBase {
  KnowledgeBase(this.ledger);
  final Ledger ledger;
  AppDatabase get db => ledger.db;

  static const derived = 'auto';

  Future<List<Fact>> facts() => (db.select(db.facts)..where((f) => f.deleted.not())).get();

  /// Stores fresh insights and retires automatic ones that no longer apply.
  Future<void> apply(List<Insight> insights) => db.transaction(() async {
    final existing = {for (final f in await facts()) f.id: f};
    final fresh = <String>{};
    for (final i in insights) {
      fresh.add(i.id);
      final old = existing[i.id];
      if (old?.state == 'dismissed') continue;
      final data = jsonEncode({...i.data, 'severity': i.severity});
      if (old != null && old.title == i.title && old.body == i.body && old.data == data) continue;
      await ledger.store.save(
        db.facts,
        FactsCompanion.insert(
          id: i.id,
          kind: i.kind,
          title: i.title,
          body: Value(i.body),
          data: Value(data),
          state: Value(old?.state ?? derived),
          confidence: Value(i.score),
          deleted: const Value(false),
        ),
        i.id,
      );
    }
    for (final f in existing.values) {
      if (f.state == derived && !fresh.contains(f.id)) await ledger.store.remove(db.facts, f.id);
    }
  });

  Future<void> feedback(String id, {required bool useful}) async {
    final f = await (db.select(db.facts)..where((x) => x.id.equals(id))).getSingle();
    await ledger.store.save(
      db.facts,
      f.toCompanion(true).copyWith(state: Value(useful ? 'confirmed' : 'dismissed')),
      id,
    );
  }

  /// Something the user tells the app (a goal, an upcoming cost, risk appetite).
  Future<String> remember(
    String kind,
    String title, {
    String body = '',
    Map<String, Object?> data = const {},
  }) async {
    final id = 'user/${newId()}';
    await ledger.store.save(
      db.facts,
      FactsCompanion.insert(
        id: id,
        kind: kind,
        title: title,
        body: Value(body),
        data: Value(jsonEncode(data)),
        state: const Value('user'),
        deleted: const Value(false),
      ),
      id,
    );
    return id;
  }

  /// Visible facts, best first: score scaled by how the user has treated
  /// that kind before.
  Future<List<Fact>> ranked() async {
    final all = await facts();
    final weight = <String, double>{};
    for (final f in all) {
      final w = weight[f.kind] ?? 1;
      weight[f.kind] = switch (f.state) {
        'confirmed' => w * 1.2,
        'dismissed' => w * 0.5,
        _ => w,
      };
    }
    final visible = all.where((f) => f.state != 'dismissed').toList()
      ..sort((a, b) => (b.confidence * weight[b.kind]!).compareTo(a.confidence * weight[a.kind]!));
    return visible;
  }
}
