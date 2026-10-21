/// Double-entry rules, independent of storage so they can be tested directly.
///
/// Sign convention: debits positive, credits negative. An asset with money in
/// it has a positive balance; a credit card you owe on is negative. Screens
/// flip liability, equity and income signs for display ("natural" sign).
library;

import 'package:brahma_core/brahma_core.dart';

enum AccountKind { asset, liability, equity, income, expense }

AccountKind accountKindOf(String name) =>
    AccountKind.values.firstWhere((k) => k.name == name, orElse: () => AccountKind.asset);

/// Income, expense and equity accounts. Unlike assets and liabilities they
/// can hold several currencies: each of their postings is in its entry's
/// currency (amount == value), and reports convert from there. Their own
/// commodity is only a display default.
bool isNominal(AccountKind kind) =>
    kind == AccountKind.income || kind == AccountKind.expense || kind == AccountKind.equity;

/// Finer account types. Grouping drives dashboard metrics (liquid vs invested).
class Subtype {
  const Subtype(this.id, this.label, this.kind, this.group);
  final String id;
  final String label;
  final AccountKind kind;

  /// liquid | invested | property | other | debt | category | equity
  final String group;

  bool get isIsa => id.startsWith('isa_') || id == 'lisa';
}

const subtypes = <Subtype>[
  Subtype('current', 'Current account', AccountKind.asset, 'liquid'),
  Subtype('savings', 'Savings account', AccountKind.asset, 'liquid'),
  Subtype('cash', 'Cash / wallet', AccountKind.asset, 'liquid'),
  Subtype('isa_cash', 'Cash ISA', AccountKind.asset, 'liquid'),
  Subtype('forex', 'Foreign currency account', AccountKind.asset, 'liquid'),
  Subtype('isa_stocks', 'Stocks & Shares ISA', AccountKind.asset, 'invested'),
  Subtype('lisa', 'Lifetime ISA', AccountKind.asset, 'invested'),
  Subtype('isa_ifi', 'Innovative Finance ISA', AccountKind.asset, 'invested'),
  Subtype('brokerage', 'Trading / brokerage', AccountKind.asset, 'invested'),
  Subtype('bonds', 'Bonds / gilts', AccountKind.asset, 'invested'),
  Subtype('pension', 'Pension (SIPP / workplace)', AccountKind.asset, 'invested'),
  Subtype('crypto', 'Crypto wallet', AccountKind.asset, 'invested'),
  Subtype('security', 'Holding (single security)', AccountKind.asset, 'invested'),
  Subtype('property', 'Property', AccountKind.asset, 'property'),
  Subtype('receivable', 'Money owed to me', AccountKind.asset, 'other'),
  Subtype('other_asset', 'Other asset', AccountKind.asset, 'other'),
  Subtype('credit_card', 'Credit card', AccountKind.liability, 'debt'),
  Subtype('overdraft', 'Overdraft', AccountKind.liability, 'debt'),
  Subtype('loan', 'Loan', AccountKind.liability, 'debt'),
  Subtype('mortgage', 'Mortgage', AccountKind.liability, 'debt'),
  Subtype('bnpl', 'Buy now, pay later', AccountKind.liability, 'debt'),
  Subtype('payable', 'Money I owe', AccountKind.liability, 'debt'),
  Subtype('other_liability', 'Other liability', AccountKind.liability, 'debt'),
  Subtype('equity', 'Equity', AccountKind.equity, 'equity'),
  Subtype('income', 'Income category', AccountKind.income, 'category'),
  Subtype('expense', 'Expense category', AccountKind.expense, 'category'),
];

final Map<String, Subtype> subtypeById = {for (final s in subtypes) s.id: s};

Subtype subtypeOf(String id) => subtypeById[id] ?? subtypes.last;

/// Balance as a person reads it: liabilities owed, income earned, positive.
int naturalSign(AccountKind kind, int balance) => switch (kind) {
  AccountKind.asset || AccountKind.expense => balance,
  _ => -balance,
};

class PostingInput {
  const PostingInput(this.accountId, this.amount, this.value, {this.memo = ''});

  /// Same-currency posting: amount == value.
  const PostingInput.cash(this.accountId, int amount, {this.memo = ''}) : amount = amount, value = amount;

  final String accountId;

  /// Units of the account's commodity (pence, shares x 10^scale...).
  final int amount;

  /// Minor units of the entry currency; an entry's values sum to zero.
  final int value;
  final String memo;
}

class EntryInput {
  EntryInput({
    this.id,
    required this.date,
    required this.currency,
    required this.postings,
    this.payee = '',
    this.memo = '',
    this.status = 'cleared',
    this.importRef,
    this.tags = const [],
  });

  final String? id;

  /// yyyy-MM-dd
  final String date;
  final String currency;
  final List<PostingInput> postings;
  final String payee;
  final String memo;
  final String status;
  final String? importRef;
  final List<String> tags;
}

/// What validation needs to know about an account.
class AccountRef {
  const AccountRef({
    required this.kind,
    required this.commodityId,
    required this.commodityKind,
    this.closed = false,
  });
  final AccountKind kind;
  final String commodityId;

  /// currency | security | crypto
  final String commodityKind;
  final bool closed;
}

class LedgerException implements Exception, UserFacingError {
  LedgerException(this.message);
  @override
  final String message;
  @override
  String toString() => message;
}

/// Enforces the ledger invariants. Throws [LedgerException] on the first
/// violation; a valid entry can always be posted without unbalancing books.
void validateEntry(EntryInput e, Map<String, AccountRef> accounts) {
  if (!isValidIsoDate(e.date)) {
    throw LedgerException('Invalid date "${e.date}"');
  }
  if (e.postings.length < 2) {
    throw LedgerException('An entry needs at least two postings');
  }
  var total = 0;
  for (final p in e.postings) {
    final a = accounts[p.accountId];
    if (a == null) throw LedgerException('Unknown account ${p.accountId}');
    if (a.closed) throw LedgerException('Account is closed');
    if (isNominal(a.kind)) {
      // Categories and equity hold whatever currency the entry is in, so
      // their lines carry no conversion of their own.
      if (p.amount != p.value) {
        throw LedgerException('Category and equity lines must be in the entry currency');
      }
    } else if (a.commodityKind == 'currency' && a.commodityId == e.currency) {
      if (p.amount != p.value) {
        throw LedgerException('Amount and value differ in the entry currency');
      }
    } else if (a.commodityKind == 'currency') {
      // Cross-currency leg: both sides move the same direction.
      if (p.amount.sign != p.value.sign) {
        throw LedgerException('Currency conversion legs must share a sign');
      }
    } else if (p.value != 0 && p.amount.sign != p.value.sign) {
      // Securities: buying adds units at a cost; a zero value is allowed for
      // splits and bonus units.
      throw LedgerException('Units and cost must share a sign');
    }
    total += p.value;
  }
  if (total != 0) {
    throw LedgerException('Entry does not balance (off by $total)');
  }
}

/// Spend or receive money in one account against a category.
/// [amount] > 0 spends from [accountId]; < 0 receives into it.
EntryInput simpleEntry({
  required String date,
  required String currency,
  required String accountId,
  required String categoryId,
  required int amount,
  String payee = '',
  String memo = '',
  String? importRef,
  String status = 'cleared',
  String? id,
}) => EntryInput(
  id: id,
  date: date,
  currency: currency,
  payee: payee,
  memo: memo,
  importRef: importRef,
  status: status,
  postings: [PostingInput.cash(accountId, -amount), PostingInput.cash(categoryId, amount)],
);

/// Move money between two of the user's accounts, possibly across
/// currencies: [fromAmount] leaves (entry currency), [toAmount] arrives in the
/// destination account's currency.
EntryInput transferEntry({
  required String date,
  required String currency,
  required String fromId,
  required String toId,
  required int fromAmount,
  int? toAmount,
  String memo = '',
  String? id,
}) => EntryInput(
  id: id,
  date: date,
  currency: currency,
  memo: memo,
  payee: 'Transfer',
  postings: [PostingInput.cash(fromId, -fromAmount), PostingInput(toId, toAmount ?? fromAmount, fromAmount)],
);

/// Buy [units] of a security for [cost] (fees included, as UK CGT allows).
EntryInput buyEntry({
  required String date,
  required String currency,
  required String cashAccountId,
  required String holdingAccountId,
  required int units,
  required int cost,
  String memo = '',
}) => EntryInput(
  date: date,
  currency: currency,
  payee: 'Buy',
  memo: memo,
  postings: [PostingInput.cash(cashAccountId, -cost), PostingInput(holdingAccountId, units, cost)],
);

/// Sell [units] for [proceeds] (after fees). [costBasis] is the pooled average
/// cost of those units (Section 104 style); the difference books a gain/loss.
EntryInput sellEntry({
  required String date,
  required String currency,
  required String cashAccountId,
  required String holdingAccountId,
  required String gainsAccountId,
  required int units,
  required int proceeds,
  required int costBasis,
  String memo = '',
}) => EntryInput(
  date: date,
  currency: currency,
  payee: 'Sell',
  memo: memo,
  postings: [
    PostingInput.cash(cashAccountId, proceeds),
    PostingInput(holdingAccountId, -units, -costBasis),
    PostingInput.cash(gainsAccountId, costBasis - proceeds),
  ],
);

/// Average cost of [units] out of a pool holding [poolUnits] that cost
/// [poolCost], rounded half-even to the minor unit.
int pooledCost(int poolUnits, int poolCost, int units) => poolUnits == 0
    ? 0
    : divRoundHalfEven(BigInt.from(poolCost) * BigInt.from(units), BigInt.from(poolUnits)).toInt();
