import 'package:brahma_core/brahma_core.dart';
import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;

import '../db/database.dart';
import '../modules/finance/domain/ledger.dart';
import '../modules/finance/fx/fx_service.dart';
import '../modules/finance/insights/insights.dart';
import '../modules/finance/portfolio/portfolio.dart';
import '../modules/finance/reports/reports.dart';
import '../ui/hints.dart';
import 'session.dart';

/// The open session; main() overrides this before the first frame.
final sessionProvider = Provider<AppSession>((ref) => throw StateError('No session'));

/// What main() and the tests override: the session, under both its Artha and
/// its shared type, and the app's identity and hints.
List<Override> arthaOverrides(AppSession session) => [
  sessionProvider.overrideWithValue(session),
  coreSessionProvider.overrideWithValue(session),
  appIdentityProvider.overrideWithValue(arthaIdentity),
  hintTextsProvider.overrideWithValue({...coreHints, ...arthaHints}),
];

extension Mutate on WidgetRef {
  /// Runs a write, refreshes the screens and queues a sync.
  Future<T> mutate<T>(Future<T> Function(AppSession s) write) async {
    final result = await write(read(sessionProvider));
    changed();
    return result;
  }
}

final baseCurrencyProvider = FutureProvider<String?>((ref) {
  ref.watch(revisionProvider);
  return ref.watch(sessionProvider).ledger.pref<String?>(basePrefKey, null);
});

Future<String> _base(Ref ref) async {
  final base = await ref.watch(baseCurrencyProvider.future);
  return base ?? 'GBP';
}

/// The base currency once the app is set up (null: show onboarding). Also
/// seeds the default categories, which are local and identical on every
/// device, so a device that joined through sync has them too.
final setupProvider = FutureProvider<String?>((ref) async {
  final base = await ref.watch(baseCurrencyProvider.future);
  if (base != null) {
    final ledger = ref.read(sessionProvider).ledger;
    await ledger.seedDefaults(await ledger.pref<String?>(seedCurrencyKey, null) ?? base);
  }
  return base;
});

/// Fetches exchange rates for the currencies in use and records the day.
Future<int> refreshRates(AppSession s, String base) async {
  final n = await FxService(s.ledger).refresh(baseCurrency: base, today: today());
  await s.db.setLocalSetting('fx.last', today());
  return n;
}

/// Refreshes rates once a day unless turned off in Settings. Offline is fine:
/// the next start tries again.
final fxAutoProvider = FutureProvider<void>((ref) async {
  final s = ref.read(sessionProvider);
  if (await s.db.localSetting('fx.auto') == 'off') return;
  if (await s.db.localSetting('fx.last') == today()) return;
  final base = await ref.read(baseCurrencyProvider.future);
  if (base == null) return;
  try {
    if (await refreshRates(s, base) > 0) ref.read(revisionProvider.notifier).bump();
  } on Object {
    return;
  }
});

final reportsProvider = FutureProvider<Reports>((ref) async {
  ref.watch(revisionProvider);
  return Reports.load(ref.watch(sessionProvider).db, await _base(ref));
});

final accountsProvider = FutureProvider<List<Account>>((ref) {
  ref.watch(revisionProvider);
  final db = ref.watch(sessionProvider).db;
  return (db.select(db.accounts)
        ..where((a) => a.deleted.not())
        ..orderBy([(a) => OrderingTerm(expression: a.name)]))
      .get();
});

final commoditiesProvider = FutureProvider<Map<String, Commodity>>((ref) async {
  ref.watch(revisionProvider);
  final db = ref.watch(sessionProvider).db;
  return {for (final c in await db.select(db.commodities).get()) c.id: c};
});

/// Balances today. Future-dated entries count once their date arrives, as
/// they do in the balance sheet.
final balancesProvider = FutureProvider<Map<String, ({int amount, int value})>>((ref) {
  ref.watch(revisionProvider);
  return ref.watch(sessionProvider).ledger.balances(asOf: ref.watch(todayProvider));
});

final targetsProvider = FutureProvider<Map<String, int>>((ref) {
  ref.watch(revisionProvider);
  return ref.watch(sessionProvider).ledger.targets();
});

final portfolioProvider = FutureProvider<Portfolio>((ref) async {
  final reports = await ref.watch(reportsProvider.future);
  return Portfolio.load(
    ref.watch(sessionProvider).db,
    reports.prices,
    base: reports.base,
    asOf: ref.watch(todayProvider),
  );
});

class InsightsData {
  InsightsData(this.metrics, this.facts, this.recurring);
  final Metrics metrics;
  final List<Fact> facts;
  final List<Recurring> recurring;
}

/// Works out insights, stores them in the knowledge base and returns the
/// ranked facts. Storing is idempotent, so reloading costs no writes.
final insightsProvider = FutureProvider<InsightsData>((ref) async {
  final s = ref.watch(sessionProvider);
  final day = ref.watch(todayProvider);
  final engine = InsightEngine(
    s.db,
    await ref.watch(reportsProvider.future),
    await ref.watch(portfolioProvider.future),
    day,
    targets: await ref.watch(targetsProvider.future),
  );
  final kb = KnowledgeBase(s.ledger);
  await kb.apply(await engine.generate());
  return InsightsData(
    await engine.metrics(),
    await kb.ranked(),
    detectRecurring(await engine.transactions(), day),
  );
});

class DashboardData {
  DashboardData(this.sheet, this.flows, this.trend, this.tally, this.integrity);
  final BalanceSheet sheet;
  final List<MonthFlow> flows;
  final List<NetWorthPoint> trend;
  final List<TallyRow> tally;
  final List<String> integrity;
}

/// [xs] from the first item with activity, keeping at least two so a chart
/// still has a line to draw.
List<T> _sinceFirst<T>(List<T> xs, bool Function(T x) empty) {
  var i = 0;
  while (i < xs.length - 2 && empty(xs[i])) {
    i++;
  }
  return xs.sublist(i);
}

final dashboardProvider = FutureProvider<DashboardData>((ref) async {
  final r = await ref.watch(reportsProvider.future);
  final day = ref.watch(todayProvider);
  return DashboardData(
    await r.balanceSheet(day),
    _sinceFirst(await r.monthlyFlows(day), (f) => f.income == 0 && f.expenses == 0),
    _sinceFirst(await r.netWorthTrend(day), (p) => p.assets == 0 && p.liabilities == 0),
    await r.tally(),
    await r.integrityProblems(),
  );
});

/// One journal entry with its postings, for lists and the editor.
class EntryView {
  EntryView(this.entry, this.postings);
  final Entry entry;
  final List<Posting> postings;
}

/// Latest entries, newest first, optionally narrowed by text or account.
final entriesProvider = FutureProvider.family<List<EntryView>, ({String query, String? accountId})>((
  ref,
  filter,
) async {
  ref.watch(revisionProvider);
  final db = ref.watch(sessionProvider).db;
  final q = filter.query.trim().toLowerCase();
  final rows = await db
      .customSelect(
        'SELECT * FROM entries e WHERE e.deleted = 0 '
        "${q.isEmpty ? '' : "AND (lower(e.payee) LIKE ? ESCAPE '\\' OR lower(e.memo) LIKE ? ESCAPE '\\') "}"
        '${filter.accountId == null ? '' : 'AND EXISTS (SELECT 1 FROM postings p WHERE p.entry_id = e.id AND p.account_id = ?) '}'
        'ORDER BY e.date DESC, e.rowid DESC LIMIT 500',
        variables: [
          if (q.isNotEmpty) ...[
            Variable('%${q.replaceAll(r'\', r'\\').replaceAll('%', r'\%').replaceAll('_', r'\_')}%'),
            Variable('%${q.replaceAll(r'\', r'\\').replaceAll('%', r'\%').replaceAll('_', r'\_')}%'),
          ],
          if (filter.accountId != null) Variable(filter.accountId),
        ],
        readsFrom: {db.entries, db.postings},
      )
      .map((r) => db.entries.map(r.data))
      .get();
  if (rows.isEmpty) return [];
  final postings =
      await (db.select(db.postings)
            ..where((p) => p.entryId.isIn(rows.map((e) => e.id)))
            ..orderBy([(p) => OrderingTerm(expression: p.position)]))
          .get();
  final byEntry = <String, List<Posting>>{};
  for (final p in postings) {
    byEntry.putIfAbsent(p.entryId, () => []).add(p);
  }
  return [for (final e in rows) EntryView(e, byEntry[e.id] ?? const [])];
});

class BudgetLine {
  BudgetLine(this.account, this.budget, this.spent);
  final Account account;

  /// Monthly budget and spending so far this month, in base currency.
  final int budget;
  final int spent;
  double get used => budget > 0 ? spent / budget : 0;
}

/// Every open expense category with its budget and this month's spending,
/// budgeted categories first, the most used at the top.
final budgetsProvider = FutureProvider<List<BudgetLine>>((ref) async {
  ref.watch(revisionProvider);
  final reports = await ref.watch(reportsProvider.future);
  final today = ref.watch(todayProvider);
  final budgets = await ref.watch(sessionProvider).ledger.budgets();
  final pnl = await reports.incomeStatement(monthStart(today), today);
  final spent = {for (final l in pnl.expenses) l.account.id: l.amount};
  final lines = [
    for (final a in reports.accounts.values)
      if (a.kind == 'expense' && !a.closed && !a.deleted) BudgetLine(a, budgets[a.id] ?? 0, spent[a.id] ?? 0),
  ];
  int rank(BudgetLine l) => l.budget > 0 ? 0 : 1;
  return lines..sort((x, y) {
    final r = rank(x).compareTo(rank(y));
    if (r != 0) return r;
    return x.budget > 0 ? y.used.compareTo(x.used) : y.spent.compareTo(x.spent);
  });
});
