import 'dart:convert';

import 'package:brahma_core/brahma_core.dart';
import 'package:drift/drift.dart';

import '../../../db/database.dart';
import '../fx/price_book.dart';

/// One account's balance on a date.
class BalanceLine {
  BalanceLine(this.account, this.amount, this.baseValue);
  final Account account;

  /// In the account's own commodity (units for holdings).
  final int amount;

  /// In the base currency; null when no rate connects the two.
  final int? baseValue;
}

class BalanceSheet {
  BalanceSheet({
    required this.asOf,
    required this.assets,
    required this.liabilities,
    required this.contributed,
    required this.earnings,
    required this.missingRates,
  });
  final String asOf;
  final List<BalanceLine> assets;
  final List<BalanceLine> liabilities;

  /// Opening balances and other equity, in base currency.
  final int contributed;

  /// Income less expenses to date, in base currency.
  final int earnings;

  /// Commodities with a balance but no known rate; their value is left out.
  final Set<String> missingRates;

  int get totalAssets => assets.fold(0, (s, l) => s + (l.baseValue ?? 0));

  /// What is owed, as a positive number.
  int get totalLiabilities => -liabilities.fold(0, (s, l) => s + (l.baseValue ?? 0));
  int get netWorth => totalAssets - totalLiabilities;

  /// Exchange-rate and market moves: what makes assets = liabilities + equity
  /// once holdings are valued at today's prices.
  int get revaluation => netWorth - contributed - earnings;
}

class TrialBalanceRow {
  TrialBalanceRow(this.currency, this.account, this.balance);
  final String currency;
  final Account account;

  /// Net of the account's postings in [currency]; debit positive.
  final int balance;
  int get debit => balance > 0 ? balance : 0;
  int get credit => balance < 0 ? -balance : 0;
}

class TrialBalance {
  TrialBalance(this.rows);
  final List<TrialBalanceRow> rows;
  Set<String> get currencies => rows.map((r) => r.currency).toSet();
  int debits(String currency) => rows.where((r) => r.currency == currency).fold(0, (s, r) => s + r.debit);
  int credits(String currency) => rows.where((r) => r.currency == currency).fold(0, (s, r) => s + r.credit);
  bool get balanced => currencies.every((c) => debits(c) == credits(c));
}

class PnlLine {
  PnlLine(this.account, this.amount);
  final Account account;

  /// Earned (income) or spent (expense), positive, in base currency.
  final int amount;
}

class IncomeStatement {
  IncomeStatement(this.from, this.to, this.income, this.expenses, this.missingRates);
  final String from;
  final String to;
  final List<PnlLine> income;
  final List<PnlLine> expenses;
  final Set<String> missingRates;
  int get totalIncome => income.fold(0, (s, l) => s + l.amount);
  int get totalExpenses => expenses.fold(0, (s, l) => s + l.amount);
  int get net => totalIncome - totalExpenses;
}

class MonthFlow {
  MonthFlow(this.month);

  /// yyyy-MM
  final String month;
  int income = 0;
  int expenses = 0;

  /// Spending flagged essential on its category (housing, bills, food...).
  int essential = 0;
  int get net => income - expenses;
  double? get savingsRate => income <= 0 ? null : net / income;
}

class NetWorthPoint {
  NetWorthPoint(this.date, this.assets, this.liabilities);
  final String date;
  final int assets;

  /// Owed, positive.
  final int liabilities;
  int get netWorth => assets - liabilities;
}

class LedgerLine {
  LedgerLine({
    required this.entryId,
    required this.date,
    required this.payee,
    required this.memo,
    required this.status,
    required this.counterparts,
    required this.amount,
    required this.balance,
  });
  final String entryId;
  final String date;
  final String payee;
  final String memo;
  final String status;

  /// Names of the other accounts in the entry.
  final List<String> counterparts;
  final int amount;
  final int balance;
}

/// A statement balance compared with the ledger on the same day.
class TallyRow {
  TallyRow(this.account, this.date, this.statement, this.ledger);
  final Account account;
  final String date;
  final int statement;
  final int ledger;
  int get difference => ledger - statement;
  bool get tallied => difference == 0;
}

/// Read-only reports over the ledger, valued in one base currency.
class Reports {
  Reports(this.db, this.prices, this.base, List<Account> accounts)
    : accounts = {for (final a in accounts) a.id: a};

  final AppDatabase db;
  final PriceBook prices;
  final String base;
  final Map<String, Account> accounts;

  /// Categories flagged essential (rent, bills, food...).
  late final Set<String> essential = {
    for (final a in accounts.values)
      if ((jsonDecode(a.meta) as Map)['essential'] == true) a.id,
  };

  static Future<Reports> load(AppDatabase db, String base) async => Reports(
    db,
    await PriceBook.load(db),
    base,
    await (db.select(db.accounts)..where((a) => a.deleted.not())).get(),
  );

  /// Balances on [asOf] per account and commodity: the account's own for
  /// assets and liabilities, each entry's currency for categories and equity.
  Future<List<({String account, String commodity, int amount})>> _balances(String asOf) async {
    final rows = await db
        .customSelect(
          'SELECT p.account_id, '
          "CASE WHEN a.kind IN ('asset', 'liability') THEN a.commodity_id ELSE e.currency END AS c, "
          'SUM(p.amount) AS amount FROM postings p JOIN entries e ON e.id = p.entry_id '
          'JOIN accounts a ON a.id = p.account_id WHERE e.deleted = 0 AND e.date <= ? '
          'GROUP BY p.account_id, c',
          variables: [Variable(asOf)],
          readsFrom: {db.postings, db.entries, db.accounts},
        )
        .get();
    return [
      for (final r in rows)
        (
          account: r.read<String>('account_id'),
          commodity: r.read<String>('c'),
          amount: r.read<int>('amount'),
        ),
    ];
  }

  Future<BalanceSheet> balanceSheet(String asOf) async {
    final missing = <String>{};
    final assets = <BalanceLine>[], liabilities = <BalanceLine>[];
    var contributed = 0, earnings = 0;
    for (final (:account, :commodity, :amount) in await _balances(asOf)) {
      final a = accounts[account];
      if (a == null || amount == 0) continue;
      final value = prices.convert(amount, commodity, base, asOf);
      if (value == null) missing.add(commodity);
      switch (a.kind) {
        case 'asset':
          assets.add(BalanceLine(a, amount, value));
        case 'liability':
          liabilities.add(BalanceLine(a, amount, value));
        case 'equity':
          contributed -= value ?? 0;
        default:
          earnings -= value ?? 0;
      }
    }
    int byValue(BalanceLine x, BalanceLine y) => (y.baseValue ?? 0).abs().compareTo((x.baseValue ?? 0).abs());
    return BalanceSheet(
      asOf: asOf,
      assets: assets..sort(byValue),
      liabilities: liabilities..sort(byValue),
      contributed: contributed,
      earnings: earnings,
      missingRates: missing,
    );
  }

  /// Account balances per entry currency; debits equal credits in each one
  /// unless the books are damaged.
  Future<TrialBalance> trialBalance(String asOf) async {
    final rows = await db
        .customSelect(
          'SELECT e.currency, p.account_id, SUM(p.value) AS v FROM postings p '
          'JOIN entries e ON e.id = p.entry_id WHERE e.deleted = 0 AND e.date <= ? '
          'GROUP BY e.currency, p.account_id HAVING SUM(p.value) <> 0 ORDER BY e.currency',
          variables: [Variable(asOf)],
          readsFrom: {db.postings, db.entries},
        )
        .get();
    return TrialBalance([
      for (final r in rows)
        if (accounts[r.read<String>('account_id')] case final a?)
          TrialBalanceRow(r.read<String>('currency'), a, r.read<int>('v')),
    ]);
  }

  /// Income and expense postings per account and day, in base currency at
  /// that day's rate. Income comes out positive, spending positive.
  Future<List<({Account account, String date, int amount})>> _flows(
    String from,
    String to,
    Set<String> missing,
  ) async {
    // Category postings are in their entry's currency (see isNominal).
    final rows = await db
        .customSelect(
          'SELECT p.account_id, e.date, e.currency, SUM(p.value) AS amount FROM postings p '
          'JOIN entries e ON e.id = p.entry_id JOIN accounts a ON a.id = p.account_id '
          "WHERE e.deleted = 0 AND e.date BETWEEN ? AND ? AND a.kind IN ('income', 'expense') "
          'GROUP BY p.account_id, e.date, e.currency',
          variables: [Variable(from), Variable(to)],
          readsFrom: {db.postings, db.entries, db.accounts},
        )
        .get();
    final out = <({Account account, String date, int amount})>[];
    for (final r in rows) {
      final a = accounts[r.read<String>('account_id')];
      if (a == null) continue;
      final date = r.read<String>('date');
      final currency = r.read<String>('currency');
      final v = prices.convert(r.read<int>('amount'), currency, base, date);
      if (v == null) {
        missing.add(currency);
        continue;
      }
      out.add((account: a, date: date, amount: a.kind == 'income' ? -v : v));
    }
    return out;
  }

  Future<IncomeStatement> incomeStatement(String from, String to) async {
    final missing = <String>{};
    final totals = <String, int>{};
    for (final f in await _flows(from, to, missing)) {
      totals.update(f.account.id, (v) => v + f.amount, ifAbsent: () => f.amount);
    }
    List<PnlLine> lines(String kind) => [
      for (final MapEntry(key: id, value: v) in totals.entries)
        if (accounts[id]!.kind == kind && v != 0) PnlLine(accounts[id]!, v),
    ]..sort((x, y) => y.amount.compareTo(x.amount));
    return IncomeStatement(from, to, lines('income'), lines('expense'), missing);
  }

  /// The last [months] calendar months up to and including [asOf]'s month.
  Future<List<MonthFlow>> monthlyFlows(String asOf, {int months = 12}) async {
    final from = monthStart(addMonths(asOf, -(months - 1)));
    final byMonth = {
      for (var i = 0; i < months; i++)
        addMonths(from, i).substring(0, 7): MonthFlow(addMonths(from, i).substring(0, 7)),
    };
    for (final f in await _flows(from, asOf, {})) {
      final m = byMonth[f.date.substring(0, 7)]!;
      if (f.account.kind == 'income') {
        m.income += f.amount;
      } else {
        m.expenses += f.amount;
        if (essential.contains(f.account.id)) m.essential += f.amount;
      }
    }
    return byMonth.values.toList();
  }

  /// Month-end assets and liabilities for the last [months] months, valued at
  /// each month end's rates.
  Future<List<NetWorthPoint>> netWorthTrend(String asOf, {int months = 12}) async {
    final rows = await db
        .customSelect(
          'SELECT p.account_id, substr(e.date, 1, 7) AS m, SUM(p.amount) AS amount FROM postings p '
          'JOIN entries e ON e.id = p.entry_id JOIN accounts a ON a.id = p.account_id '
          "WHERE e.deleted = 0 AND e.date <= ? AND a.kind IN ('asset', 'liability') "
          'GROUP BY p.account_id, m ORDER BY m',
          variables: [Variable(asOf)],
          readsFrom: {db.postings, db.entries, db.accounts},
        )
        .get();
    final ends = [for (var i = months - 1; i >= 0; i--) i == 0 ? asOf : monthEnd(addMonths(asOf, -i))];
    final running = <String, int>{};
    final points = <NetWorthPoint>[];
    var next = 0;
    for (final end in ends) {
      final month = end.substring(0, 7);
      while (next < rows.length && rows[next].read<String>('m').compareTo(month) <= 0) {
        final r = rows[next++];
        running.update(
          r.read<String>('account_id'),
          (v) => v + r.read<int>('amount'),
          ifAbsent: () => r.read<int>('amount'),
        );
      }
      var assets = 0, liabilities = 0;
      for (final MapEntry(key: id, value: amount) in running.entries) {
        final a = accounts[id];
        if (a == null || amount == 0) continue;
        final v = prices.convert(amount, a.commodityId, base, end) ?? 0;
        if (a.kind == 'asset') {
          assets += v;
        } else {
          liabilities -= v;
        }
      }
      points.add(NetWorthPoint(end, assets, liabilities));
    }
    return points;
  }

  /// Postings to one account with a running balance (account's commodity).
  Future<List<LedgerLine>> accountLedger(String accountId, {String? from, String? to}) async {
    var balance = 0;
    if (from != null) {
      final r = await db
          .customSelect(
            'SELECT COALESCE(SUM(p.amount), 0) AS b FROM postings p JOIN entries e ON e.id = p.entry_id '
            'WHERE e.deleted = 0 AND p.account_id = ? AND e.date < ?',
            variables: [Variable(accountId), Variable(from)],
          )
          .getSingle();
      balance = r.read<int>('b');
    }
    final rows = await db
        .customSelect(
          'SELECT e.id, e.date, e.payee, e.memo, e.status, SUM(p.amount) AS amount, '
          '(SELECT group_concat(q.account_id, char(31)) FROM postings q '
          ' WHERE q.entry_id = e.id AND q.account_id <> ?) AS others '
          'FROM postings p JOIN entries e ON e.id = p.entry_id '
          'WHERE e.deleted = 0 AND p.account_id = ? '
          '${from == null ? '' : 'AND e.date >= ? '}${to == null ? '' : 'AND e.date <= ? '}'
          'GROUP BY e.id ORDER BY e.date, e.rowid',
          variables: [
            Variable(accountId),
            Variable(accountId),
            if (from != null) Variable(from),
            if (to != null) Variable(to),
          ],
          readsFrom: {db.postings, db.entries},
        )
        .get();
    return [
      for (final r in rows)
        LedgerLine(
          entryId: r.read<String>('id'),
          date: r.read<String>('date'),
          payee: r.read<String>('payee'),
          memo: r.read<String>('memo'),
          status: r.read<String>('status'),
          counterparts: [
            for (final id in (r.readNullable<String>('others') ?? '').split('\x1f'))
              if (id.isNotEmpty) accounts[id]?.name ?? id,
          ],
          amount: r.read<int>('amount'),
          balance: balance += r.read<int>('amount'),
        ),
    ];
  }

  /// The newest statement balance per account against the ledger that day.
  Future<List<TallyRow>> tally() => _tally(latestOnly: true);

  /// Every recorded statement balance of one account, oldest first, each
  /// compared with the ledger on its day.
  Future<List<TallyRow>> accountTally(String accountId) => _tally(accountId: accountId);

  Future<List<TallyRow>> _tally({bool latestOnly = false, String? accountId}) async {
    final checks = await db
        .customSelect(
          'SELECT account_id, date, amount FROM balance_checks c WHERE deleted = 0 '
          '${accountId == null ? '' : 'AND account_id = ? '}'
          '${latestOnly ? 'AND date = (SELECT MAX(date) FROM balance_checks d WHERE d.account_id = c.account_id AND d.deleted = 0) ' : ''}'
          'ORDER BY date',
          variables: [if (accountId != null) Variable(accountId)],
          readsFrom: {db.balanceChecks},
        )
        .get();
    final out = <TallyRow>[];
    for (final c in checks) {
      final a = accounts[c.read<String>('account_id')];
      if (a == null) continue;
      final date = c.read<String>('date');
      final r = await db
          .customSelect(
            'SELECT COALESCE(SUM(p.amount), 0) AS b FROM postings p JOIN entries e ON e.id = p.entry_id '
            'WHERE e.deleted = 0 AND p.account_id = ? AND e.date <= ?',
            variables: [Variable(a.id), Variable(date)],
          )
          .getSingle();
      out.add(TallyRow(a, date, c.read<int>('amount'), r.read<int>('b')));
    }
    return out;
  }

  /// Entries that break double entry (possible only through damaged or
  /// tampered data, since every local write is validated).
  Future<List<String>> integrityProblems() async {
    final rows = await db
        .customSelect(
          'SELECT e.id FROM entries e LEFT JOIN postings p ON p.entry_id = e.id WHERE e.deleted = 0 '
          'GROUP BY e.id HAVING COUNT(p.id) < 2 OR COALESCE(SUM(p.value), 0) <> 0 '
          'UNION SELECT p.entry_id FROM postings p LEFT JOIN accounts a ON a.id = p.account_id '
          "WHERE a.id IS NULL OR a.deleted = 1 OR (a.kind IN ('income', 'expense', 'equity') "
          'AND p.amount <> p.value)',
          readsFrom: {db.postings, db.entries, db.accounts},
        )
        .get();
    return [for (final r in rows) r.read<String>('id')];
  }
}
