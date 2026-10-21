import 'package:brahma_core/brahma_core.dart';
import 'package:drift/drift.dart';

/// Currencies, securities and crypto: anything an account can hold.
@DataClassName('Commodity')
class Commodities extends Table with SyncedRow {
  /// currency | security | crypto
  TextColumn get kind => text()();
  TextColumn get code => text()();
  TextColumn get name => text()();

  /// Decimal places of one unit as stored in postings (GBP 2, a fund 6).
  IntColumn get scale => integer()();

  /// Currency a security is priced in.
  TextColumn get quoteCurrency => text().nullable()();

  /// equity | bond | cash | property | commodity | crypto | alternative
  TextColumn get assetClass => text().nullable()();
  TextColumn get isin => text().nullable()();
}

/// Chart of accounts. Categories are income/expense accounts (double entry).
@DataClassName('Account')
class Accounts extends Table with SyncedRow {
  TextColumn get name => text()();

  /// asset | liability | equity | income | expense
  TextColumn get kind => text()();

  /// Finer type, e.g. current, credit_card, isa_stocks (see finance/domain).
  TextColumn get subtype => text()();
  TextColumn get commodityId => text()();
  TextColumn get parentId => text().nullable()();
  TextColumn get institution => text().nullable()();
  TextColumn get number => text().nullable()();
  TextColumn get notes => text().withDefault(const Constant(''))();
  BoolColumn get closed => boolean().withDefault(const Constant(false))();

  /// JSON: credit limit, interest rate, essential flag and similar extras.
  TextColumn get meta => text().withDefault(const Constant('{}'))();
}

/// Journal entries (transactions). Their postings live in [Postings] and
/// always sync together with the entry, so an entry never arrives half-done.
@DataClassName('Entry')
class Entries extends Table with SyncedRow {
  /// ISO date, yyyy-MM-dd (no time zone games).
  TextColumn get date => text()();

  /// Currency the postings' `value` column is expressed in.
  TextColumn get currency => text()();
  TextColumn get payee => text().withDefault(const Constant(''))();
  TextColumn get memo => text().withDefault(const Constant(''))();

  /// uncleared | cleared | reconciled
  TextColumn get status => text().withDefault(const Constant('cleared'))();

  /// Bank transaction id (OFX FITID) or a content hash, for duplicate checks.
  TextColumn get importRef => text().nullable()();

  /// JSON array of tag strings.
  TextColumn get tags => text().withDefault(const Constant('[]'))();
}

/// One leg of an entry. `amount` is in the account's commodity units; `value`
/// is in the entry currency. The values of an entry always sum to zero.
@DataClassName('Posting')
class Postings extends Table {
  TextColumn get id => text()();
  TextColumn get entryId => text().references(Entries, #id, onDelete: KeyAction.cascade)();
  TextColumn get accountId => text()();
  IntColumn get amount => integer()();
  IntColumn get value => integer()();
  TextColumn get memo => text().withDefault(const Constant(''))();
  IntColumn get position => integer()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

/// Price of one unit of a commodity in [quote] on a date (FX rates included).
@DataClassName('Price')
class Prices extends Table with SyncedRow {
  TextColumn get commodityId => text()();
  TextColumn get quote => text()();
  TextColumn get date => text()();

  /// Exact decimal text, parsed with Rate.parse.
  TextColumn get rate => text()();

  /// manual | ecb | import
  TextColumn get source => text()();
}

/// "The statement said this account held X at the end of this day."
/// Reconciliation compares the ledger against these.
@DataClassName('BalanceCheck')
class BalanceChecks extends Table with SyncedRow {
  TextColumn get accountId => text()();
  TextColumn get date => text()();
  IntColumn get amount => integer()();
  TextColumn get note => text().withDefault(const Constant(''))();
}

/// User categorisation rules: when [field] contains [pattern], use [accountId].
@DataClassName('Rule')
class Rules extends Table with SyncedRow {
  TextColumn get field => text()();
  TextColumn get pattern => text()();
  TextColumn get accountId => text()();
  IntColumn get position => integer().withDefault(const Constant(0))();
}

/// Monthly budget for an expense category, in the base currency.
@DataClassName('Budget')
class Budgets extends Table with SyncedRow {
  TextColumn get accountId => text()();
  IntColumn get amount => integer()();
}

/// Target portfolio weight for an asset class, in basis points (100 = 1%).
@DataClassName('Target')
class Targets extends Table with SyncedRow {
  TextColumn get assetClass => text()();
  IntColumn get weightBp => integer()();
}

/// Knowledge base: facts learned from the data or told by the user (salary
/// day, rent, risk appetite, goals). Insights read these; the user can confirm
/// or correct them, and that feedback steers later suggestions.
@DataClassName('Fact')
class Facts extends Table with SyncedRow {
  TextColumn get kind => text()();
  TextColumn get title => text()();
  TextColumn get body => text().withDefault(const Constant(''))();

  /// JSON payload specific to the kind.
  TextColumn get data => text().withDefault(const Constant('{}'))();

  /// auto | confirmed | user | dismissed
  TextColumn get state => text().withDefault(const Constant('auto'))();
  RealColumn get confidence => real().withDefault(const Constant(1))();
}

/// Saved CSV column mappings per account.
@DataClassName('ImportProfile')
class ImportProfiles extends Table with SyncedRow {
  TextColumn get accountId => text()();
  TextColumn get mapping => text()();
}

// The tables sync needs; their columns come from brahma_core.

@DataClassName('Pref')
class Prefs extends Table with SyncedRow, PrefColumns {}

@DataClassName('OutboxItem')
class Outbox extends Table with OutboxColumns {}

@DataClassName('SyncCursor')
class SyncCursors extends Table with SyncCursorColumns {}

@DataClassName('LocalSetting')
class LocalSettings extends Table with LocalSettingColumns {}
