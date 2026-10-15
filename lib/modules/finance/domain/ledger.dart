import 'dart:convert';

import 'package:drift/drift.dart';

import '../../../core/db/database.dart';
import '../../../core/db/store.dart';
import '../../../core/money/currencies.dart';
import '../../../core/sync/hlc.dart';
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

/// Ledger operations on the database. All writes go through [Store].
class Ledger {
  Ledger(this.store);

  final Store store;
  AppDatabase get db => store.db;

  /// Creates default categories (in [currency]) once; never overwrites rows.
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
}
