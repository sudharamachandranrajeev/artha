import 'dart:convert';

import 'package:drift/drift.dart';

import '../../../core/dates.dart';
import '../../../core/db/database.dart';
import '../domain/accounting.dart';
import '../domain/ledger.dart';
import '../insights/categorizer.dart';
import 'statement.dart';

enum RowStatus {
  /// New transaction; will be created with [ImportRow.categoryId].
  fresh,

  /// Already imported before; skipped.
  duplicate,

  /// Same as an entry typed in by hand; that entry gets linked, not copied.
  matched,

  /// Other side of a transfer already imported from another account; the two
  /// are merged into one transfer instead of counting the money twice.
  transfer,
}

class ImportRow {
  ImportRow(this.line, this.token);
  final StatementLine line;

  /// Account-scoped duplicate key stored in Entry.importRef.
  final String token;
  RowStatus status = RowStatus.fresh;
  String categoryId = uncategorizedId;
  Suggestion? suggestion;
  String? existingEntryId;
  bool include = true;
}

class ImportPlan {
  ImportPlan({required this.account, required this.currency, required this.statement, required this.rows});
  final Account account;
  final String currency;
  final ParsedStatement statement;
  final List<ImportRow> rows;

  /// Set when the account holds nothing before the statement: the balance
  /// brought forward, booked against Opening balances.
  int? openingBalance;
  String? openingDate;

  int count(RowStatus s) => rows.where((r) => r.status == s && r.include).length;
}

class ImportResult {
  ImportResult(this.created, this.linked, this.merged, this.skipped);
  final int created;
  final int linked;
  final int merged;
  final int skipped;
}

class ImportService {
  ImportService(this.ledger);
  final Ledger ledger;
  AppDatabase get db => ledger.db;

  /// Builds a categoriser from rules and every categorised two-leg entry.
  Future<Categorizer> categorizer() async {
    final accounts = {for (final a in await db.select(db.accounts).get()) a.id: a};
    final rules =
        await (db.select(db.rules)
              ..where((r) => r.deleted.not())
              ..orderBy([(r) => OrderingTerm(expression: r.position)]))
            .get();
    final rows = await db
        .customSelect(
          'SELECT e.payee, e.memo, p.account_id FROM entries e '
          'JOIN postings p ON p.entry_id = e.id '
          "WHERE e.deleted = 0 AND p.account_id <> '$uncategorizedId' "
          "AND (SELECT COUNT(*) FROM postings q WHERE q.entry_id = e.id) = 2 "
          "AND p.account_id IN (SELECT id FROM accounts WHERE kind IN ('income','expense')) "
          'ORDER BY e.date DESC LIMIT 5000',
          readsFrom: {db.entries, db.postings, db.accounts},
        )
        .get();
    return Categorizer(
      rules: [for (final r in rules) CategoryRule(r.pattern, r.accountId)],
      history: [
        for (final r in rows)
          Example('${r.read<String>('payee')} ${r.read<String>('memo')}', r.read<String>('account_id')),
      ],
      directionOf: (id) => switch (accounts[id]?.kind) {
        'expense' => 'out',
        'income' => 'in',
        _ => 'any',
      },
    );
  }

  Future<ImportPlan> plan(String accountId, ParsedStatement st) async {
    final account = await (db.select(db.accounts)..where((a) => a.id.equals(accountId))).getSingle();
    final commodity = await (db.select(
      db.commodities,
    )..where((c) => c.id.equals(account.commodityId))).getSingle();
    if (commodity.kind != 'currency') {
      throw StatementFormatException('Statements import into cash accounts, not holdings');
    }
    if (st.currency != null && st.currency != commodity.code) {
      throw StatementFormatException(
        'Statement is in ${st.currency} but ${account.name} is a ${commodity.code} account',
      );
    }

    final existing = await db
        .customSelect(
          'SELECT e.id, e.date, e.import_ref, p.amount FROM entries e '
          'JOIN postings p ON p.entry_id = e.id '
          'WHERE e.deleted = 0 AND p.account_id = ?',
          variables: [Variable(accountId)],
        )
        .get();
    final tokens = <String>{};
    final unlinked = <({String id, String date, int amount})>[];
    for (final r in existing) {
      final refs = (r.readNullable<String>('import_ref') ?? '').split(' ');
      tokens.addAll(refs);
      if (!refs.any((t) => t.startsWith('$accountId/'))) {
        unlinked.add((id: r.read<String>('id'), date: r.read<String>('date'), amount: r.read<int>('amount')));
      }
    }

    // Uncategorised two-leg entries in the user's other cash accounts: the
    // possible far side of a transfer.
    final far = await db
        .customSelect(
          'SELECT e.id, e.date, p.amount FROM entries e '
          'JOIN postings p ON p.entry_id = e.id JOIN accounts a ON a.id = p.account_id '
          "WHERE e.deleted = 0 AND p.account_id <> ? AND a.kind IN ('asset','liability') "
          'AND a.commodity_id = ? '
          "AND EXISTS (SELECT 1 FROM postings u WHERE u.entry_id = e.id AND u.account_id = '$uncategorizedId') "
          'AND (SELECT COUNT(*) FROM postings q WHERE q.entry_id = e.id) = 2',
          variables: [Variable(accountId), Variable(account.commodityId)],
        )
        .get();
    final farSide = [
      for (final r in far)
        (id: r.read<String>('id'), date: r.read<String>('date'), amount: r.read<int>('amount')),
    ];

    final cat = await categorizer();
    final refs = lineRefs(st.lines);
    final used = <String>{};
    final rows = <ImportRow>[];
    for (var i = 0; i < st.lines.length; i++) {
      final line = st.lines[i];
      final row = ImportRow(line, '$accountId/${refs[i]}');
      rows.add(row);
      if (tokens.contains(row.token)) {
        row
          ..status = RowStatus.duplicate
          ..include = false;
        continue;
      }
      final manual = unlinked
          .where(
            (e) => !used.contains(e.id) && e.amount == line.amount && daysBetween(e.date, line.date) <= 4,
          )
          .firstOrNull;
      if (manual != null) {
        used.add(manual.id);
        row
          ..status = RowStatus.matched
          ..existingEntryId = manual.id;
        continue;
      }
      final other = farSide
          .where(
            (e) => !used.contains(e.id) && e.amount == -line.amount && daysBetween(e.date, line.date) <= 3,
          )
          .firstOrNull;
      if (other != null) {
        used.add(other.id);
        row
          ..status = RowStatus.transfer
          ..existingEntryId = other.id;
        continue;
      }
      final s = cat.suggest(line.text, line.amount);
      row.suggestion = s;
      if (s != null && s.confidence >= 0.5) {
        row.categoryId = s.categoryId;
      } else if (line.amount > 0) {
        row.categoryId = otherIncomeId;
      }
    }

    final plan = ImportPlan(account: account, currency: commodity.code, statement: st, rows: rows);
    // A brand-new account starts from the statement's brought-forward balance.
    if (st.lines.isNotEmpty && existing.isEmpty) {
      final opening = st.openingBalance ?? (st.closingBalance == null ? null : st.closingBalance! - st.total);
      if (opening != null && opening != 0) {
        plan
          ..openingBalance = opening
          ..openingDate = addDays(st.lines.first.date, -1);
      }
    }
    return plan;
  }

  Future<ImportResult> commit(ImportPlan plan) async {
    var created = 0, linked = 0, merged = 0, skipped = 0;
    final acc = plan.account.id;
    await db.transaction(() async {
      if (plan.openingBalance != null) {
        await ledger.saveEntry(
          EntryInput(
            id: '$acc-opening',
            date: plan.openingDate!,
            currency: plan.currency,
            payee: 'Opening balance',
            importRef: '$acc/opening',
            status: 'reconciled',
            postings: [
              PostingInput.cash(acc, plan.openingBalance!),
              PostingInput.cash(openingBalancesId, -plan.openingBalance!),
            ],
          ),
        );
      }
      for (final row in plan.rows) {
        if (!row.include) {
          skipped++;
          continue;
        }
        final line = row.line;
        switch (row.status) {
          case RowStatus.duplicate:
            skipped++;
          case RowStatus.fresh:
            await ledger.saveEntry(
              EntryInput(
                date: line.date,
                currency: plan.currency,
                payee: line.payee.isNotEmpty ? line.payee : line.memo,
                memo: line.payee.isNotEmpty ? line.memo : '',
                importRef: row.token,
                postings: [
                  PostingInput.cash(acc, line.amount),
                  PostingInput.cash(row.categoryId, -line.amount),
                ],
              ),
            );
            created++;
          case RowStatus.matched:
            await _addToken(row.existingEntryId!, row.token, null);
            linked++;
          case RowStatus.transfer:
            await _addToken(row.existingEntryId!, row.token, acc);
            merged++;
        }
      }
      final closing = plan.statement.closingBalance;
      final closingDate = plan.statement.closingDate;
      if (closing != null && closingDate != null) {
        await ledger.saveBalanceCheck(acc, closingDate, closing, note: 'From imported statement');
      }
    });
    return ImportResult(created, linked, merged, skipped);
  }

  /// Links an existing entry to a statement line. With [replaceUncategorised]
  /// set, the entry's uncategorised leg becomes that account (a transfer).
  Future<void> _addToken(String entryId, String token, String? replaceUncategorised) async {
    final e = await (db.select(db.entries)..where((x) => x.id.equals(entryId))).getSingle();
    final postings =
        await (db.select(db.postings)
              ..where((p) => p.entryId.equals(entryId))
              ..orderBy([(p) => OrderingTerm(expression: p.position)]))
            .get();
    await ledger.saveEntry(
      EntryInput(
        id: e.id,
        date: e.date,
        currency: e.currency,
        payee: replaceUncategorised != null ? 'Transfer' : e.payee,
        memo: e.memo,
        status: 'cleared',
        tags: (jsonDecode(e.tags) as List).cast<String>(),
        importRef: [...?e.importRef?.split(' ').where((t) => t.isNotEmpty), token].join(' '),
        postings: [
          for (final p in postings)
            PostingInput(
              replaceUncategorised != null && p.accountId == uncategorizedId
                  ? replaceUncategorised
                  : p.accountId,
              p.amount,
              p.value,
              memo: p.memo,
            ),
        ],
      ),
    );
  }
}
