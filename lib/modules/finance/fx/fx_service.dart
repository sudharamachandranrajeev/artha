import 'dart:async';
import 'dart:convert';

import 'package:brahma_core/brahma_core.dart';
import 'package:drift/drift.dart';
import 'package:http/http.dart' as http;

import '../../../db/database.dart';
import '../domain/ledger.dart';

class FxException implements Exception, UserFacingError {
  FxException(this.message);
  @override
  final String message;
  @override
  String toString() => message;
}

/// Daily reference rates from the European Central Bank, fetched through the
/// Frankfurter API (open source, no key). Only currency codes leave the
/// device; amounts and accounts never do.
class FxService {
  FxService(this.ledger, {http.Client? client, this.endpoint = 'https://api.frankfurter.dev/v2/rates'})
    : _client = client ?? http.Client() {
    if (!endpoint.startsWith('https://')) throw ArgumentError('FX endpoint must use HTTPS');
  }

  final Ledger ledger;
  final String endpoint;
  final http.Client _client;
  AppDatabase get db => ledger.db;

  static final _date = RegExp(r'^\d{4}-\d{2}-\d{2}$');

  /// Fetches EUR rates for every ECB currency the user holds or reports in,
  /// from the day after the newest stored rate (or the first transaction)
  /// to [today]. Returns the number of rates stored.
  Future<int> refresh({required String baseCurrency, required String today}) async {
    final used = await db
        .customSelect(
          "SELECT DISTINCT commodity_id AS c FROM accounts WHERE deleted = 0 "
          "UNION SELECT DISTINCT currency FROM entries WHERE deleted = 0 "
          "UNION SELECT DISTINCT quote_currency FROM commodities WHERE deleted = 0 AND quote_currency IS NOT NULL",
          readsFrom: {db.accounts, db.entries, db.commodities},
        )
        .get();
    final codes = {
      baseCurrency,
      for (final r in used) r.read<String>('c'),
    }.where((c) => c != 'EUR' && ecbCurrencies.contains(c)).toList()..sort();
    if (codes.isEmpty) return 0;

    // Each currency resumes after its own newest rate; a newly added one
    // backfills from the first transaction.
    final latest = {
      for (final r
          in await db
              .customSelect(
                "SELECT quote, MAX(date) AS d FROM prices WHERE source = 'ecb' AND deleted = 0 GROUP BY quote",
              )
              .get())
        r.read<String>('quote'): r.read<String>('d'),
    };
    final first = await db.customSelect('SELECT MIN(date) AS d FROM entries WHERE deleted = 0').getSingle();
    final start = first.readNullable<String>('d') ?? today;
    final from = codes
        .map((c) => latest[c] == null ? start : addDays(latest[c]!, 1))
        .reduce((a, b) => a.compareTo(b) <= 0 ? a : b);
    if (from.compareTo(today) > 0) return 0;

    final uri = Uri.parse(endpoint).replace(
      queryParameters: {
        'from': from,
        'to': today,
        'base': 'EUR',
        'quotes': codes.join(','),
        'providers': 'ECB',
      },
    );
    final http.Response res;
    try {
      res = await _client
          .get(uri, headers: {'Accept': 'application/json'})
          .timeout(const Duration(seconds: 30));
    } on TimeoutException {
      throw FxException('Exchange-rate service timed out');
    } on http.ClientException catch (e) {
      throw FxException('Could not reach the exchange-rate service: ${e.message}');
    }
    if (res.statusCode != 200) throw FxException('Exchange-rate service answered ${res.statusCode}');

    final rates = [
      for (final r in parseRates(res.body, codes.toSet()))
        if (latest[r.quote] == null || r.date.compareTo(latest[r.quote]!) > 0) r,
    ];
    await db.transaction(() async {
      for (final r in rates) {
        final id = 'ecb/EUR/${r.quote}/${r.date}';
        await ledger.store.save(
          db.prices,
          PricesCompanion.insert(
            id: id,
            commodityId: 'EUR',
            quote: r.quote,
            date: r.date,
            rate: r.rate.toDecimalString(10),
            source: 'ecb',
            deleted: const Value(false),
          ),
          id,
        );
      }
      if (rates.isNotEmpty) await ledger.ensureCurrency('EUR');
    });
    return rates.length;
  }

  /// Parses and validates a Frankfurter v2 response. Anything unexpected is
  /// rejected rather than stored: wrong base, unknown codes, bad dates or
  /// non-positive rates.
  static List<({String date, String quote, Rate rate})> parseRates(String body, Set<String> wanted) {
    final Object? json;
    try {
      json = jsonDecode(body);
    } on FormatException {
      throw FxException('Exchange-rate service sent invalid data');
    }
    if (json is! List) throw FxException('Exchange-rate service sent an unexpected response');
    final out = <({String date, String quote, Rate rate})>[];
    for (final item in json) {
      if (item is! Map) throw FxException('Exchange-rate service sent an unexpected response');
      final date = item['date'], base = item['base'], quote = item['quote'], rate = item['rate'];
      if (base != 'EUR' || date is! String || !_date.hasMatch(date) || quote is! String || rate is! num) {
        throw FxException('Exchange-rate service sent an unexpected record');
      }
      if (!wanted.contains(quote)) continue;
      final r = Rate.tryParse(rate.toString());
      if (r == null || r.num <= BigInt.zero) throw FxException('Exchange-rate service sent a bad rate');
      out.add((date: date, quote: quote, rate: r));
    }
    return out;
  }

  void close() => _client.close();
}
