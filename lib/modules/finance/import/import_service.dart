import 'dart:convert';

import 'package:brahma_core/brahma_core.dart';
import 'package:drift/drift.dart';

import '../../../db/database.dart';
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

  /// Same as an entry imported from another file covering the same days (a
  /// CSV export and the PDF statement, say); that entry gets linked, not copied.
  overlap,

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

  /// The name a rename rule gives the payee; the bank's text then goes to
  /// the memo.
  String? rename;

  /// Payee and memo the new entry gets.
  ({String payee, String memo}) get text {
    final payee = line.payee.isNotEmpty ? line.payee : line.memo;
    final memo = line.payee.isNotEmpty ? line.memo : '';
    final to = rename;
    return to == null || to == payee ? (payee: payee, memo: memo) : Ledger.renamed(payee, memo, to);
  }

  /// The user says a matched or overlapping row is a different transaction:
  /// it is created as a new entry instead of being linked.
  void keepSeparate() {
    status = RowStatus.fresh;
    existingEntryId = null;
    include = true;
    final s = suggestion;
    categoryId = s != null && s.confidence >= 0.5
        ? s.categoryId
        : line.amount > 0
        ? otherIncomeId
        : uncategorizedId;
  }
}

class ImportPlan {
  ImportPlan({
    required this.account,
    required this.currency,
    required this.statement,
    required this.rows,
    this.createsAccount = false,
  });
  final Account account;

  /// [account] does not exist yet; committing creates it first.
  final bool createsAccount;
  final String currency;
  final ParsedStatement statement;
  final List<ImportRow> rows;

  /// Set when the account holds nothing before the statement: the balance
  /// brought forward, booked against Opening balances.
  int? openingBalance;
  String? openingDate;

  /// Statement balances that disagree with ones already recorded for the
  /// same day. The recorded ones are kept.
  final conflicts = <String>[];

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
      rules: await ledger.categoryRules(),
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

  /// Open cash accounts the statement names by its account number, sort code
  /// or card digits, best match first. Empty when it names none of them.
  Future<List<Account>> matchAccounts(ParsedStatement st) async {
    final number = _digits(st.accountNumber);
    if (number.length < 4) return const [];
    final sort = _digits(st.sortCode);
    final accounts = await (db.select(
      db.accounts,
    )..where((a) => a.deleted.not() & a.closed.not() & a.kind.isIn(['asset', 'liability']))).get();
    final scored = <(int, Account)>[];
    for (final a in accounts) {
      final d = _digits(a.number);
      if (d.isEmpty) continue;
      var score = 0;
      if (number.length >= 8 && d.endsWith(number)) {
        // A full account number; the sort code, when both have one, must agree.
        if (sort.isNotEmpty && d.length >= 14 && !d.startsWith(sort)) continue;
        score = sort.isNotEmpty && d.startsWith(sort) ? 3 : 2;
      } else if (number.length == 4 && d.endsWith(number) && (a.subtype == 'credit_card') == st.isCard) {
        score = 1;
      } else {
        continue;
      }
      if (st.institution != null &&
          a.institution != null &&
          a.institution!.toLowerCase() == st.institution!.toLowerCase()) {
        score += 1;
      }
      scored.add((score, a));
    }
    scored.sort((x, y) => y.$1.compareTo(x.$1));
    return [for (final (_, a) in scored) a];
  }

  static String _digits(String? s) => (s ?? '').replaceAll(RegExp(r'\D'), '');

  /// The account to create for a statement that matches none: named after
  /// the bank and the last digits, in the statement's currency.
  Account newAccountFor(ParsedStatement st, String fallbackCurrency) {
    final last4 = _digits(st.accountNumber);
    final tail = last4.length >= 4 ? ' ••${last4.substring(last4.length - 4)}' : '';
    final subtype = subtypeOf(st.isCard ? 'credit_card' : 'current');
    final number = st.isCard ? last4 : [if (st.sortCode != null) st.sortCode!, ?st.accountNumber].join(' ');
    return Account(
      id: newId(),
      hlc: '',
      deleted: false,
      name: '${st.institution ?? (st.isCard ? 'Credit' : 'Bank')} ${st.isCard ? 'card' : 'current'}$tail',
      kind: subtype.kind.name,
      subtype: subtype.id,
      commodityId: st.currency ?? fallbackCurrency,
      institution: st.institution,
      number: number.isEmpty ? null : number,
      notes: 'Created from an imported statement',
      closed: false,
      meta: '{}',
    );
  }

  Future<ImportPlan> plan(String accountId, ParsedStatement st) async {
    final account = await (db.select(db.accounts)..where((a) => a.id.equals(accountId))).getSingle();
    return planFor(account, st);
  }

  /// Plans the import into [account]; with [create] it is a new account
  /// from [newAccountFor] that commit creates.
  Future<ImportPlan> planFor(Account account, ParsedStatement st, {bool create = false}) async {
    final accountId = account.id;
    final String code;
    if (create) {
      code = account.commodityId;
    } else {
      final commodity = await (db.select(
        db.commodities,
      )..where((c) => c.id.equals(account.commodityId))).getSingle();
      if (commodity.kind != 'currency') {
        throw StatementFormatException('Statements import into cash accounts, not holdings');
      }
      code = commodity.code;
    }
    if (st.currency != null && st.currency != code) {
      throw StatementFormatException('Statement is in ${st.currency} but ${account.name} is a $code account');
    }

    final existing = await db
        .customSelect(
          'SELECT e.id, e.date, e.import_ref, p.amount FROM entries e '
          'JOIN postings p ON p.entry_id = e.id '
          'WHERE e.deleted = 0 AND p.account_id = ?',
          variables: [Variable(accountId)],
        )
        .get();
    final refs = lineRefs(st.lines);
    final ownTokens = {for (final r in refs) '$accountId/$r'};
    final tokens = <String>{};
    final unlinked = <({String id, String date, int amount})>[];
    final imported = <({String id, String date, int amount})>[];
    for (final r in existing) {
      final entryRefs = (r.readNullable<String>('import_ref') ?? '').split(' ');
      tokens.addAll(entryRefs);
      final e = (id: r.read<String>('id'), date: r.read<String>('date'), amount: r.read<int>('amount'));
      if (!entryRefs.any((t) => t.startsWith('$accountId/'))) {
        unlinked.add(e);
      } else if (e.id != '$accountId-opening' && !entryRefs.any(ownTokens.contains)) {
        imported.add(e);
      }
    }

    // Rows that another file already brought in: same amount, on a day this
    // statement covers, the same day first and then up to three days apart
    // (exports and statements can date a payment differently).
    final overlap = <int, String>{};
    final used = <String>{};
    if (st.lines.isNotEmpty) {
      final first = st.lines.map((l) => l.date).reduce((a, b) => a.compareTo(b) <= 0 ? a : b);
      final last = st.lines.map((l) => l.date).reduce((a, b) => a.compareTo(b) >= 0 ? a : b);
      final inPeriod = imported.where((e) => e.date.compareTo(first) >= 0 && e.date.compareTo(last) <= 0);
      for (final slack in [0, 3]) {
        for (var i = 0; i < st.lines.length; i++) {
          final line = st.lines[i];
          if (overlap.containsKey(i) || tokens.contains('$accountId/${refs[i]}')) continue;
          final hits = inPeriod.where(
            (e) => !used.contains(e.id) && e.amount == line.amount && daysBetween(e.date, line.date) <= slack,
          );
          if (hits.isEmpty) continue;
          final best = hits.reduce(
            (a, b) => daysBetween(a.date, line.date) <= daysBetween(b.date, line.date) ? a : b,
          );
          used.add(best.id);
          overlap[i] = best.id;
        }
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
      // Kept so that "keep separate" can still offer a category.
      row.suggestion = cat.suggest(line.text, line.amount);
      row.rename = renamedPayee(cat.rules, line.text);
      if (overlap[i] case final id?) {
        row
          ..status = RowStatus.overlap
          ..existingEntryId = id;
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
      final s = row.suggestion;
      if (s != null && s.confidence >= 0.5) {
        row.categoryId = s.categoryId;
      } else if (line.amount > 0) {
        row.categoryId = otherIncomeId;
      }
    }

    final plan = ImportPlan(
      account: account,
      currency: code,
      statement: st,
      rows: rows,
      createsAccount: create,
    );
    // The account's opening balance sits before its earliest statement. A new
    // account takes this statement's; an account whose history so far came
    // from later statements moves it back here, so months can arrive in any
    // order.
    if (st.lines.isNotEmpty) {
      final opening = st.openingBalance ?? (st.closingBalance == null ? null : st.closingBalance! - st.total);
      final date = st.openingDate ?? addDays(st.lines.first.date, -1);
      final openingId = '$accountId-opening';
      final current = existing.where((r) => r.read<String>('id') == openingId).firstOrNull;
      final earliestOther = existing
          .where((r) => r.read<String>('id') != openingId)
          .map((r) => r.read<String>('date'))
          .fold<String?>(null, (m, d) => m == null || d.compareTo(m) < 0 ? d : m);
      final reanchor =
          current != null &&
          date.compareTo(current.read<String>('date')) < 0 &&
          (earliestOther == null || earliestOther.compareTo(date) > 0);
      if (opening != null && (existing.isEmpty || reanchor)) {
        plan
          ..openingBalance = opening
          ..openingDate = date;
      }
    }
    final recorded = {
      for (final c in await (db.select(
        db.balanceChecks,
      )..where((c) => c.accountId.equals(accountId) & c.deleted.not())).get())
        c.date: c.amount,
    };
    for (final c in st.checkpoints) {
      final had = recorded[c.date];
      if (had != null && had != c.balance) {
        plan.conflicts.add(
          '${niceDate(c.date)}: this statement says ${money(c.balance, code)}, '
          'an earlier one said ${money(had, code)}',
        );
      }
    }
    return plan;
  }

  /// After a rule is added, files and renames the plan's new rows that a rule
  /// now catches. Returns how many rows changed.
  Future<int> reapplyRules(ImportPlan plan) async {
    final cat = await categorizer();
    var changed = 0;
    for (final r in plan.rows) {
      if (r.status == RowStatus.duplicate) continue;
      final rename = renamedPayee(cat.rules, r.line.text);
      var moved = rename != r.rename;
      r.rename = rename;
      final s = cat.suggest(r.line.text, r.line.amount);
      if (s?.source == 'rule') {
        r.suggestion = s;
        if (r.status == RowStatus.fresh && r.categoryId != s!.categoryId) {
          r.categoryId = s.categoryId;
          moved = true;
        }
      }
      if (moved && r.status == RowStatus.fresh) changed++;
    }
    return changed;
  }

  Future<ImportResult> commit(ImportPlan plan) async {
    var created = 0, linked = 0, merged = 0, skipped = 0;
    final acc = plan.account.id;
    if (plan.statement.problems.isNotEmpty) {
      throw StatementFormatException('The statement does not add up, so nothing was imported');
    }
    await db.transaction(() async {
      if (plan.createsAccount) {
        final a = plan.account;
        await ledger.saveAccount(
          id: a.id,
          name: a.name,
          subtype: a.subtype,
          commodityId: a.commodityId,
          institution: a.institution,
          number: a.number,
          notes: a.notes,
        );
      }
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
            final text = row.text;
            await ledger.saveEntry(
              EntryInput(
                date: line.date,
                currency: plan.currency,
                payee: text.payee,
                memo: text.memo,
                importRef: row.token,
                reviewed: false,
                postings: [
                  PostingInput.cash(acc, line.amount),
                  PostingInput.cash(row.categoryId, -line.amount),
                ],
              ),
            );
            created++;
          case RowStatus.matched || RowStatus.overlap:
            await _addToken(row.existingEntryId!, row.token, null);
            linked++;
          case RowStatus.transfer:
            await _addToken(row.existingEntryId!, row.token, acc);
            merged++;
        }
      }
      // Every balance the statements print becomes a check, so the account
      // tallies statement by statement; a day already recorded keeps its value.
      final recorded = {
        for (final c in await (db.select(
          db.balanceChecks,
        )..where((c) => c.accountId.equals(acc) & c.deleted.not())).get())
          c.date,
      };
      for (final c in plan.statement.checkpoints) {
        if (recorded.add(c.date)) {
          await ledger.saveBalanceCheck(acc, c.date, c.balance, note: 'From imported statement');
        }
      }
      if (plan.statement.checkpoints.isEmpty) {
        final closing = plan.statement.closingBalance;
        final closingDate = plan.statement.closingDate;
        if (closing != null && closingDate != null && recorded.add(closingDate)) {
          await ledger.saveBalanceCheck(acc, closingDate, closing, note: 'From imported statement');
        }
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
