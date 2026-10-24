import 'dart:convert';

import 'package:brahma_core/brahma_core.dart';
import 'package:drift/drift.dart';

import '../../../db/database.dart';
import '../insights/categorizer.dart';
import 'accounting.dart';

/// Default categories. Fixed ids and the seed HLC make every device create
/// identical rows, so syncing two fresh installs never duplicates them.
const _seedCategories = <(String, String, String, bool)>[
  // (id, name, kind, essential)
  ('cat.salary', 'Salary', 'income', false),
  ('cat.bonus', 'Bonus', 'income', false),
  ('cat.interest', 'Interest received', 'income', false),
  ('cat.dividends', 'Dividends', 'income', false),
  ('cat.gains', 'Capital gains', 'income', false),
  ('cat.rental', 'Rental income', 'income', false),
  ('cat.refunds', 'Refunds', 'income', false),
  ('cat.gifts_in', 'Gifts received', 'income', false),
  ('cat.other_income', 'Other income', 'income', false),
  ('cat.housing', 'Rent / mortgage', 'expense', true),
  ('cat.utilities', 'Utilities', 'expense', true),
  ('cat.council_tax', 'Council tax', 'expense', true),
  ('cat.groceries', 'Groceries', 'expense', true),
  ('cat.eating_out', 'Eating out', 'expense', false),
  ('cat.transport', 'Transport', 'expense', true),
  ('cat.car', 'Car & fuel', 'expense', false),
  ('cat.insurance', 'Insurance', 'expense', true),
  ('cat.health', 'Health', 'expense', true),
  ('cat.phone', 'Phone & internet', 'expense', true),
  ('cat.subscriptions', 'Subscriptions', 'expense', false),
  ('cat.shopping', 'Shopping', 'expense', false),
  ('cat.clothing', 'Clothing', 'expense', false),
  ('cat.entertainment', 'Entertainment', 'expense', false),
  ('cat.travel', 'Travel & holidays', 'expense', false),
  ('cat.education', 'Education', 'expense', false),
  ('cat.childcare', 'Childcare', 'expense', true),
  ('cat.gifts_out', 'Gifts & donations', 'expense', false),
  ('cat.personal_care', 'Personal care', 'expense', false),
  ('cat.fees', 'Bank fees & charges', 'expense', false),
  ('cat.interest_paid', 'Interest paid', 'expense', true),
  ('cat.taxes', 'Taxes', 'expense', true),
  ('cat.remittance', 'Family support / remittance', 'expense', false),
  ('cat.other_expense', 'Miscellaneous', 'expense', false),
  ('cat.uncategorized', 'Uncategorised', 'expense', false),
];

const openingBalancesId = 'equity.opening';
const uncategorizedId = 'cat.uncategorized';
const otherIncomeId = 'cat.other_income';
const gainsId = 'cat.gains';

/// Currency reports and the dashboard are valued in.
const basePrefKey = 'base.currency';

/// Currency the default categories are created in. Set once at first run and
/// never changed, so every device seeds identical rows even after the base
/// currency changes.
const seedCurrencyKey = 'seed.currency';

/// Ledger operations on the database. All writes go through [Store].
class Ledger {
  Ledger(this.store);

  final Store store;
  AppDatabase get db => store.db as AppDatabase;

  /// First run: sets the base currency and, unless another device already
  /// did, the seed currency, then creates the default categories.
  Future<void> setUp(String base) async {
    await setPref(basePrefKey, base);
    if (await pref<String?>(seedCurrencyKey, null) == null) await setPref(seedCurrencyKey, base);
    await seedDefaults(await pref<String?>(seedCurrencyKey, null) ?? base);
  }

  /// Creates default categories (in [currency]) once; never overwrites rows
  /// the user has edited. Seed rows that are untouched and unused but in
  /// another currency (seeded before this device learnt the synced seed
  /// currency) switch to [currency], so all devices agree.
  Future<void> seedDefaults(String currency) => db.transaction(() async {
    await ensureCurrency(currency);
    final rows = [
      ..._seedCategories.map(
        (c) => AccountsCompanion.insert(
          id: c.$1,
          name: c.$2,
          kind: c.$3,
          subtype: c.$3,
          commodityId: currency,
          hlc: const Value(HlcClock.seed),
          meta: Value(jsonEncode({'essential': c.$4})),
        ),
      ),
      AccountsCompanion.insert(
        id: openingBalancesId,
        name: 'Opening balances',
        kind: 'equity',
        subtype: 'equity',
        commodityId: currency,
        hlc: const Value(HlcClock.seed),
      ),
    ];
    await db.batch((b) => b.insertAll(db.accounts, rows, mode: InsertMode.insertOrIgnore));
    final ids = [for (final r in rows) r.id.value];
    await db.customUpdate(
      'UPDATE accounts SET commodity_id = ? WHERE hlc = ? AND commodity_id <> ? '
      'AND id IN (${List.filled(ids.length, '?').join(', ')}) '
      'AND NOT EXISTS (SELECT 1 FROM postings p WHERE p.account_id = accounts.id)',
      variables: [
        Variable(currency),
        const Variable(HlcClock.seed),
        Variable(currency),
        for (final id in ids) Variable(id),
      ],
      updates: {db.accounts},
    );
  });

  /// Currency commodities use the ISO code as id, identical on every device.
  Future<String> ensureCurrency(String code) async {
    final info = currencyInfo(code);
    await db
        .into(db.commodities)
        .insert(
          CommoditiesCompanion.insert(
            id: code,
            kind: 'currency',
            code: code,
            name: info.name,
            scale: info.scale,
            hlc: const Value(HlcClock.seed),
          ),
          mode: InsertMode.insertOrIgnore,
        );
    return code;
  }

  Future<String> createSecurity({
    required String code,
    required String name,
    required String quoteCurrency,
    required String assetClass,
    int scale = 6,
    String? isin,
  }) async {
    final id = newId();
    await ensureCurrency(quoteCurrency);
    await store.save(
      db.commodities,
      CommoditiesCompanion.insert(
        id: id,
        kind: 'security',
        code: code.toUpperCase(),
        name: name,
        scale: scale,
        quoteCurrency: Value(quoteCurrency),
        assetClass: Value(assetClass),
        isin: Value(isin),
      ),
      id,
    );
    return id;
  }

  Future<String> saveAccount({
    String? id,
    required String name,
    required String subtype,
    required String commodityId,
    String? parentId,
    String? institution,
    String? number,
    String notes = '',
    bool closed = false,
    Map<String, Object?> meta = const {},
  }) async {
    final st = subtypeOf(subtype);
    if (RegExp(r'^[A-Z]{3}$').hasMatch(commodityId)) await ensureCurrency(commodityId);
    final rowId = id ?? newId();
    await store.save(
      db.accounts,
      AccountsCompanion.insert(
        id: rowId,
        name: name.trim(),
        kind: st.kind.name,
        subtype: st.id,
        commodityId: commodityId,
        parentId: Value(parentId),
        institution: Value(institution),
        number: Value(number),
        notes: Value(notes),
        closed: Value(closed),
        meta: Value(jsonEncode(meta)),
        deleted: const Value(false),
      ),
      rowId,
    );
    return rowId;
  }

  /// Deletes an account only when nothing is posted to it.
  Future<void> deleteAccount(String id) => db.transaction(() async {
    final used =
        await (db.select(db.postings)
              ..where((p) => p.accountId.equals(id))
              ..limit(1))
            .get();
    if (used.isNotEmpty) {
      throw LedgerException('Account has transactions; close it instead');
    }
    await store.remove(db.accounts, id);
  });

  Future<Map<String, AccountRef>> accountRefs(Iterable<String> ids) async {
    final list = ids.toSet().toList();
    final rows = await db
        .customSelect(
          'SELECT a.id, a.kind, a.commodity_id, a.closed, a.deleted, '
          "COALESCE(c.kind, 'currency') AS ckind "
          'FROM accounts a LEFT JOIN commodities c ON c.id = a.commodity_id '
          'WHERE a.id IN (${List.filled(list.length, '?').join(',')})',
          variables: [for (final id in list) Variable(id)],
        )
        .get();
    return {
      for (final r in rows)
        if (!r.read<bool>('deleted'))
          r.read<String>('id'): AccountRef(
            kind: accountKindOf(r.read<String>('kind')),
            commodityId: r.read<String>('commodity_id'),
            commodityKind: r.read<String>('ckind'),
            closed: r.read<bool>('closed'),
          ),
    };
  }

  /// Validates and writes an entry with its postings atomically.
  Future<String> saveEntry(EntryInput e) async {
    final id = e.id ?? newId();
    await db.transaction(() async {
      validateEntry(e, await accountRefs(e.postings.map((p) => p.accountId)));
      await db
          .into(db.entries)
          .insertOnConflictUpdate(
            EntriesCompanion.insert(
              id: id,
              date: e.date,
              currency: e.currency,
              payee: Value(e.payee),
              memo: Value(e.memo),
              status: Value(e.status),
              importRef: Value(e.importRef),
              tags: Value(jsonEncode(e.tags)),
              deleted: const Value(false),
            ),
          );
      await writePostings(id, e.postings);
      await store.touch(db.entries, id);
    });
    return id;
  }

  /// Replaces an entry's postings. Postings ids are derived from the entry id
  /// so replays from sync are idempotent.
  Future<void> writePostings(String entryId, List<PostingInput> postings) async {
    await (db.delete(db.postings)..where((p) => p.entryId.equals(entryId))).go();
    await db.batch(
      (b) => b.insertAll(db.postings, [
        for (var i = 0; i < postings.length; i++)
          PostingsCompanion.insert(
            id: '$entryId:$i',
            entryId: entryId,
            accountId: postings[i].accountId,
            amount: postings[i].amount,
            value: postings[i].value,
            memo: Value(postings[i].memo),
            position: i,
          ),
      ]),
    );
  }

  Future<void> deleteEntry(String id) => db.transaction(() async {
    await (db.delete(db.postings)..where((p) => p.entryId.equals(id))).go();
    await store.remove(db.entries, id);
  });

  /// Per-account totals up to and including [asOf] (yyyy-MM-dd).
  /// `amount` is in the account's commodity; `value` in entry currencies.
  Future<Map<String, ({int amount, int value})>> balances({String? asOf}) async {
    final rows = await db
        .customSelect(
          'SELECT p.account_id, SUM(p.amount) AS amount, SUM(p.value) AS value '
          'FROM postings p JOIN entries e ON e.id = p.entry_id '
          'WHERE e.deleted = 0 ${asOf == null ? '' : 'AND e.date <= ?'} '
          'GROUP BY p.account_id',
          variables: [if (asOf != null) Variable(asOf)],
          readsFrom: {db.postings, db.entries},
        )
        .get();
    return {
      for (final r in rows)
        r.read<String>('account_id'): (amount: r.read<int>('amount'), value: r.read<int>('value')),
    };
  }

  /// Records a statement balance (one per account and day) to tally against.
  Future<void> saveBalanceCheck(String accountId, String date, int amount, {String note = ''}) {
    if (!isValidIsoDate(date)) throw LedgerException('Invalid date "$date"');
    final id = '$accountId@$date';
    return store.save(
      db.balanceChecks,
      BalanceChecksCompanion.insert(
        id: id,
        accountId: accountId,
        date: date,
        amount: amount,
        note: Value(note),
        deleted: const Value(false),
      ),
      id,
    );
  }

  /// Records the price of one unit of [commodityId] in [quote] on [date].
  Future<void> savePrice(
    String commodityId,
    String quote,
    String date,
    Rate rate, {
    String source = 'manual',
  }) {
    if (!isValidIsoDate(date)) throw LedgerException('Invalid date "$date"');
    if (rate.num <= BigInt.zero) throw LedgerException('A price must be above zero');
    final id = '$source/$commodityId/$quote/$date';
    return store.save(
      db.prices,
      PricesCompanion.insert(
        id: id,
        commodityId: commodityId,
        quote: quote,
        date: date,
        rate: rate.toDecimalString(10),
        source: source,
        deleted: const Value(false),
      ),
      id,
    );
  }

  /// A synced preference, or [fallback] when unset or of another type.
  Future<T> pref<T>(String key, T fallback) async {
    final row = await (db.select(db.prefs)..where((p) => p.id.equals(key))).getSingleOrNull();
    if (row == null || row.deleted) return fallback;
    final v = jsonDecode(row.value);
    return v is T ? v : fallback;
  }

  Future<void> setPref(String key, Object value) => store.save(
    db.prefs,
    PrefsCompanion.insert(id: key, value: jsonEncode(value), deleted: const Value(false)),
    key,
  );

  /// Target allocation in basis points per asset class (empty when unset).
  Future<Map<String, int>> targets() async {
    final rows = await (db.select(db.targets)..where((t) => t.deleted.not())).get();
    return {
      for (final t in rows)
        if (t.weightBp > 0) t.assetClass: t.weightBp,
    };
  }

  /// Replaces the target allocation. Weights are basis points summing to 10000.
  Future<void> saveTargets(Map<String, int> bp) => db.transaction(() async {
    if (bp.values.any((w) => w < 0) || bp.values.fold(0, (a, b) => a + b) != 10000) {
      throw LedgerException('Targets must add up to 100%');
    }
    final existing = {for (final t in await db.select(db.targets).get()) t.assetClass: t};
    for (final cls in {...existing.keys, ...bp.keys}) {
      final w = bp[cls] ?? 0;
      final old = existing[cls];
      if (old != null && old.weightBp == w && !old.deleted) continue;
      final id = 'target.$cls';
      await store.save(
        db.targets,
        TargetsCompanion.insert(id: id, assetClass: cls, weightBp: w, deleted: const Value(false)),
        id,
      );
    }
  });

  /// Monthly budget per expense category, in base-currency minor units.
  Future<Map<String, int>> budgets() async {
    final rows = await (db.select(db.budgets)..where((b) => b.deleted.not())).get();
    return {
      for (final b in rows)
        if (b.amount > 0) b.accountId: b.amount,
    };
  }

  /// Sets an expense category's monthly budget; zero removes it.
  Future<void> saveBudget(String accountId, int amount) => db.transaction(() async {
    if (amount < 0) throw LedgerException('A budget cannot be negative');
    final account = await (db.select(db.accounts)..where((a) => a.id.equals(accountId))).getSingleOrNull();
    if (account == null || account.deleted || account.kind != AccountKind.expense.name) {
      throw LedgerException('Budgets apply to expense categories only');
    }
    final id = 'budget.$accountId';
    await store.save(
      db.budgets,
      BudgetsCompanion.insert(id: id, accountId: accountId, amount: amount, deleted: Value(amount == 0)),
      id,
    );
  });

  /// Categorisation rules in the order they are tried; the first match wins.
  Future<List<Rule>> rules() =>
      (db.select(db.rules)
            ..where((r) => r.deleted.not())
            ..orderBy([(r) => OrderingTerm(expression: r.position), (r) => OrderingTerm(expression: r.id)]))
          .get();

  /// Adds a rule at the end of the list, or changes rule [id]: payee or memo
  /// text containing [pattern] (any case) goes to category [accountId].
  Future<String> saveRule({String? id, required String pattern, required String accountId}) => db.transaction(
    () async {
      final p = pattern.trim();
      if (p.length < 2) throw LedgerException('A rule needs at least two characters to look for');
      final account = await (db.select(db.accounts)..where((a) => a.id.equals(accountId))).getSingleOrNull();
      if (account == null ||
          account.deleted ||
          accountId == uncategorizedId ||
          !(account.kind == AccountKind.income.name || account.kind == AccountKind.expense.name)) {
        throw LedgerException('Rules sort into income or spending categories only');
      }
      final existing = id == null
          ? null
          : await (db.select(db.rules)..where((r) => r.id.equals(id) & r.deleted.not())).getSingleOrNull();
      if (id != null && existing == null) throw LedgerException('That rule no longer exists');
      final all = await rules();
      if (all.any((r) => r.id != id && r.pattern.toLowerCase() == p.toLowerCase())) {
        throw LedgerException('A rule already looks for “$p”');
      }
      final ruleId = id ?? 'rule.${newId()}';
      await store.save(
        db.rules,
        RulesCompanion.insert(
          id: ruleId,
          field: 'text',
          pattern: p,
          accountId: accountId,
          position: Value(existing?.position ?? (all.isEmpty ? 0 : all.last.position + 1)),
          deleted: const Value(false),
        ),
        ruleId,
      );
      return ruleId;
    },
  );

  Future<void> deleteRule(String id) => store.remove(db.rules, id);

  /// Moves rule [id] one place earlier ([by] -1) or later ([by] 1).
  Future<void> moveRule(String id, int by) => db.transaction(() async {
    final all = await rules();
    final i = all.indexWhere((r) => r.id == id);
    final j = i + by;
    if (i < 0 || j < 0 || j >= all.length) return;
    final order = [...all];
    order.insert(j, order.removeAt(i));
    // Renumber so equal positions from other devices cannot tie.
    for (var k = 0; k < order.length; k++) {
      if (order[k].position != k) {
        await store.save(db.rules, order[k].copyWith(position: k), order[k].id);
      }
    }
  });

  /// Files every uncategorised two-line entry whose text matches a rule into
  /// that rule's category. Returns how many entries changed.
  Future<int> applyRules() => db.transaction(() async {
    final list = await rules();
    if (list.isEmpty) return 0;
    final kinds = {for (final a in await db.select(db.accounts).get()) a.id: a.kind};
    final cat = Categorizer(
      rules: [for (final r in list) CategoryRule(r.pattern, r.accountId)],
      history: const [],
      directionOf: (id) => switch (kinds[id]) {
        'expense' => 'out',
        'income' => 'in',
        _ => 'any',
      },
    );
    final candidates = await db
        .customSelect(
          'SELECT e.id FROM entries e WHERE e.deleted = 0 '
          "AND EXISTS (SELECT 1 FROM postings u WHERE u.entry_id = e.id AND u.account_id = '$uncategorizedId') "
          'AND (SELECT COUNT(*) FROM postings q WHERE q.entry_id = e.id) = 2',
          readsFrom: {db.entries, db.postings},
        )
        .get();
    var changed = 0;
    for (final row in candidates) {
      final id = row.read<String>('id');
      final e = await (db.select(db.entries)..where((x) => x.id.equals(id))).getSingle();
      final postings =
          await (db.select(db.postings)
                ..where((p) => p.entryId.equals(id))
                ..orderBy([(p) => OrderingTerm(expression: p.position)]))
              .get();
      final own = postings.where((p) => p.accountId != uncategorizedId).singleOrNull;
      // Only money moving through one of the user's accounts.
      if (own == null || !(kinds[own.accountId] == 'asset' || kinds[own.accountId] == 'liability')) continue;
      final text = [e.payee, e.memo].where((s) => s.isNotEmpty).join(' · ');
      final s = cat.suggest(text, own.value);
      if (s == null) continue;
      await saveEntry(
        EntryInput(
          id: e.id,
          date: e.date,
          currency: e.currency,
          payee: e.payee,
          memo: e.memo,
          status: e.status,
          tags: (jsonDecode(e.tags) as List).cast<String>(),
          importRef: e.importRef,
          postings: [
            for (final p in postings)
              PostingInput(
                p.accountId == uncategorizedId ? s.categoryId : p.accountId,
                p.amount,
                p.value,
                memo: p.memo,
              ),
          ],
        ),
      );
      changed++;
    }
    return changed;
  });
}
