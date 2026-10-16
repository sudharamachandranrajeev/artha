import 'dart:async';
import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:flutter/widgets.dart' show AppLifecycleListener;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/dates.dart';
import '../core/db/database.dart';
import '../core/db/store.dart';
import '../core/security/crypto.dart';
import '../core/sync/sync_engine.dart';
import '../modules/finance/domain/accounting.dart';
import '../modules/finance/domain/ledger.dart';
import '../modules/finance/fx/fx_service.dart';
import '../modules/finance/import/statement.dart';
import '../modules/finance/insights/insights.dart';
import '../modules/finance/portfolio/portfolio.dart';
import '../modules/finance/reports/reports.dart';
import 'session.dart';

/// The open session; main() overrides this before the first frame.
final sessionProvider = Provider<AppSession>((ref) => throw StateError('No session'));

/// Bumped after every write so screens reading the ledger load again.
class Revision extends Notifier<int> {
  @override
  int build() => 0;
  void bump() => state++;
}

final revisionProvider = NotifierProvider<Revision, int>(Revision.new);

extension Mutate on WidgetRef {
  /// Runs a write, refreshes the screens and queues a sync.
  Future<T> mutate<T>(Future<T> Function(AppSession s) write) async {
    final result = await write(read(sessionProvider));
    read(revisionProvider.notifier).bump();
    read(syncProvider.notifier).soon();
    return result;
  }
}

/// A message fit to show the user.
String describeError(Object e) => switch (e) {
  LedgerException(:final message) ||
  SyncException(:final message) ||
  CryptoException(:final message) ||
  StatementFormatException(:final message) ||
  FxException(:final message) => message,
  _ => 'Something went wrong: $e',
};

final todayProvider = Provider<String>((ref) {
  ref.watch(revisionProvider);
  return today();
});

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

/// Device-only UI preferences.
class HintsState {
  const HintsState({this.enabled = true, this.dismissed = const {}});
  final bool enabled;
  final Set<String> dismissed;
  bool shows(String id) => enabled && !dismissed.contains(id);
}

class Hints extends AsyncNotifier<HintsState> {
  static const _on = 'ui.hints', _dismissed = 'ui.hints.dismissed';
  AppDatabase get _db => ref.read(sessionProvider).db;

  @override
  Future<HintsState> build() async {
    final db = ref.watch(sessionProvider).db;
    final dismissed = await db.localSetting(_dismissed);
    return HintsState(
      enabled: await db.localSetting(_on) != 'off',
      dismissed: dismissed == null ? {} : {...(jsonDecode(dismissed) as List).cast<String>()},
    );
  }

  Future<void> _save(HintsState s) async {
    state = AsyncData(s);
    await _db.setLocalSetting(_on, s.enabled ? 'on' : 'off');
    await _db.setLocalSetting(_dismissed, jsonEncode(s.dismissed.toList()));
  }

  HintsState get _now => state.value ?? const HintsState();

  Future<void> setEnabled(bool on) => _save(HintsState(enabled: on, dismissed: _now.dismissed));
  Future<void> dismiss(String id) =>
      _save(HintsState(enabled: _now.enabled, dismissed: {..._now.dismissed, id}));

  /// Turns hints back on and shows every dismissed one again.
  Future<void> restore() => _save(const HintsState());
}

final hintsProvider = AsyncNotifierProvider<Hints, HintsState>(Hints.new);

enum SyncPhase { signedOut, idle, running, failed }

class SyncState {
  const SyncState(this.phase, {this.lastSync, this.error, this.email, this.server});
  final SyncPhase phase;
  final String? lastSync;
  final String? error;
  final String? email;
  final String? server;
}

/// Runs sync on start, a few seconds after each change and every 15 minutes.
class SyncController extends Notifier<SyncState> {
  Timer? _debounce, _periodic;
  bool _again = false;
  DateTime _lastRun = DateTime.now();

  @override
  SyncState build() {
    // Back in the app: fetch what other devices did, at most once a minute
    // (desktops resume on every focus). Leaving it: send what is queued now,
    // since a phone may not run again for hours.
    final lifecycle = AppLifecycleListener(
      onResume: () {
        if (DateTime.now().difference(_lastRun) > const Duration(minutes: 1)) run();
      },
      onHide: () {
        if (_debounce?.isActive ?? false) {
          _debounce!.cancel();
          run();
        }
      },
    );
    ref.onDispose(() {
      lifecycle.dispose();
      _debounce?.cancel();
      _periodic?.cancel();
    });
    _periodic = Timer.periodic(const Duration(minutes: 15), (_) => run());
    Future.microtask(run);
    return const SyncState(SyncPhase.idle);
  }

  void soon() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(seconds: 4), run);
  }

  Future<void> run() async {
    if (state.phase == SyncPhase.running) {
      _again = true;
      return;
    }
    _lastRun = DateTime.now();
    final s = ref.read(sessionProvider);
    final session = await s.keys.session();
    if (session == null) {
      state = const SyncState(SyncPhase.signedOut);
      return;
    }
    final email = session['email'] as String?, server = session['server'] as String?;
    final last = await s.db.localSetting('sync.last');
    state = SyncState(SyncPhase.running, lastSync: last, email: email, server: server);
    try {
      final engine = await s.account.engine(s.store);
      if (engine == null) {
        state = const SyncState(SyncPhase.signedOut);
        return;
      }
      final result = await engine.run();
      final now = DateTime.now().toUtc().toIso8601String();
      await s.db.setLocalSetting('sync.last', now);
      state = SyncState(SyncPhase.idle, lastSync: now, email: email, server: server);
      if (result.pulled > 0) ref.read(revisionProvider.notifier).bump();
    } catch (e) {
      state = SyncState(
        SyncPhase.failed,
        lastSync: last,
        error: describeError(e),
        email: email,
        server: server,
      );
    }
    if (_again) {
      _again = false;
      await run();
    }
  }

  Future<void> signOut() async {
    await ref.read(sessionProvider).account.signOut();
    state = const SyncState(SyncPhase.signedOut);
  }
}

final syncProvider = NotifierProvider<SyncController, SyncState>(SyncController.new);
