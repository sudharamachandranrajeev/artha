import 'dart:convert';

import 'package:artha/modules/finance/insights/catalogue.dart';
import 'package:artha/modules/finance/insights/insights.dart';
import 'package:artha/modules/finance/insights/risk.dart';
import 'package:artha/modules/finance/insights/world.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

const rss = '''﻿<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:dc="http://purl.org/dc/elements/1.1/"><channel>
<item><title>Bank Rate held at 3.75%</title><link>https://www.bankofengland.co.uk/news/1</link>
<pubDate>Thu, 22 Oct 2026 23:30:00 +0100</pubDate>
<description>&lt;p&gt;The MPC voted to keep the &lt;b&gt;interest rate&lt;/b&gt; unchanged &amp;amp; watched inflation.&lt;/p&gt;</description></item>
<item><title>Best savings rates</title><link>http://insecure.example/x</link><pubDate>Thu, 22 Oct 2026 10:00:00 GMT</pubDate></item>
<item><title>No date savings</title><link>https://example.com/y</link></item>
<item><title>Football results</title><link>https://example.com/z</link><dc:date>2026-10-23T09:00:00Z</dc:date></item>
</channel></rss>''';

const atom = '''<?xml version="1.0" encoding="UTF-8"?>
<feed xmlns="http://www.w3.org/2005/Atom">
<entry><title>Self Assessment: 100 days to go</title>
<link rel="alternate" type="text/html" href="https://www.gov.uk/government/news/100-days"/>
<updated>2026-10-23T08:00:00+01:00</updated><summary>File your tax return online before 31 January.</summary></entry>
</feed>''';

const boeCsv = 'DATE,IUDBEDR\n18 Sep 2026,3.75\n22 Oct 2026,3.75\n';

String cpiJson(String value) => jsonEncode({
  'months': [
    {'date': '2026 AUG', 'value': '3.4', 'year': '2026', 'month': 'August'},
    {'date': '2026 SEP', 'value': value, 'year': '2026', 'month': 'September'},
  ],
});

Situation situation({
  Metrics? metrics,
  List<Holding> holdings = const [],
  Map<String, int> byClass = const {},
  int invested = 0,
}) => Situation(
  metrics: metrics ?? Metrics(),
  holdings: holdings,
  base: 'GBP',
  byClass: byClass,
  invested: invested,
);

void main() {
  group('feeds', () {
    test('RSS items are read, cleaned and tagged', () {
      final items = parseFeed(rss, 'BoE');
      // Insecure link and missing date are dropped.
      expect([for (final i in items) i.title], ['Bank Rate held at 3.75%', 'Football results']);
      final boe = items.first;
      // 23:30 at +01:00 is 22:30 UTC the same day.
      expect(boe.date, '2026-10-22');
      expect(boe.summary, 'The MPC voted to keep the interest rate unchanged & watched inflation.');
      expect(boe.topics, containsAll(['rates', 'inflation']));
      expect(items.last.date, '2026-10-23');
      expect(items.last.topics, isEmpty);
    });

    test('Atom entries are read', () {
      final i = parseFeed(atom, 'HMRC').single;
      expect((i.date, i.link), ('2026-10-23', 'https://www.gov.uk/government/news/100-days'));
      expect(i.topics, {'tax'});
    });

    test('a late offset moves the day', () {
      expect(feedDate('Fri, 23 Oct 2026 00:30:00 +0100'), '2026-10-22');
      expect(feedDate('Fri, 23 Oct 2026 23:30:00 -0500'), '2026-10-24');
      expect(feedDate('not a date'), isNull);
    });

    test('bad XML is an error the user can read', () {
      expect(() => parseFeed('<html><body>Access denied', 'FCA'), throwsA(isA<WorldException>()));
    });

    test('long text is cut on a word', () {
      final t = plainText('word ' * 100, max: 50);
      expect(t.length, lessThanOrEqualTo(51));
      expect(t, endsWith('word…'));
    });
  });

  group('figures', () {
    test('Bank Rate is the last valid line', () {
      expect(parseBankRate(boeCsv), (rate: 3.75, date: '2026-10-22'));
      expect(parseBankRate('DATE,IUDBEDR\n22 Oct 2026,375\n'), isNull);
      expect(parseBankRate('<html>blocked</html>'), isNull);
    });

    test('CPI is the latest month, within sane bounds', () {
      expect(parseCpi(cpiJson('3.5')), (rate: 3.5, month: 'September 2026'));
      expect(parseCpi(cpiJson('900')), isNull);
      expect(parseCpi('nope'), isNull);
      expect(parseCpi('{"months": []}'), isNull);
    });
  });

  group('ranking', () {
    NewsItem item(String title, String date, Set<String> topics) =>
        NewsItem(title: title, link: 'https://e.com/$title', source: 's', date: date, topics: topics);
    const today = '2026-10-24';

    test('a mortgage holder sees mortgage news first; stale and off-topic stories go', () {
      final items = [
        item('Mortgage rates jump', '2026-10-22', {'mortgage'}),
        item('Pension news', '2026-10-23', {'pension'}),
        item('Rates held', '2026-10-23', {'rates'}),
        item('Old story', '2026-08-01', {'rates'}),
        item('Celebrity news', '2026-10-24', {}),
        item('Mortgage rates jump', '2026-10-22', {'mortgage'}),
      ];
      final owner = newsInterests(saves: true, invests: false, mortgage: true, borrows: true, pension: false);
      expect(
        [for (final n in rankNews(items, owner, today)) n.title],
        ['Mortgage rates jump', 'Rates held', 'Pension news'],
      );
      final renter = newsInterests(
        saves: true,
        invests: false,
        mortgage: false,
        borrows: false,
        pension: false,
      );
      expect(rankNews(items, renter, today).first.title, 'Rates held');
    });

    test('the limit and future dates are respected', () {
      final items = [
        for (var i = 0; i < 20; i++) item('Story $i', '2026-10-23', {'rates'}),
        item('Tomorrow', '2026-10-25', {'rates'}),
      ];
      final r = rankNews(items, const {'rates': 1}, today);
      expect(r, hasLength(8));
      expect(r.any((n) => n.title == 'Tomorrow'), isFalse);
    });
  });

  group('tips', () {
    const market = MarketSnapshot(
      bankRate: 3.75,
      bankRateDate: '2026-09-17',
      cpi: 3.5,
      cpiMonth: 'September 2026',
    );

    test('UK tips cite the live figures and dated rates', () {
      final tips = quickTips(situation(), market, '2026-10-24');
      final byId = {for (final t in tips) t.id: t};
      expect(byId['real_return']!.title, contains('3.5%'));
      expect(byId['bank_rate']!.body, contains('5 Nov 2026'));
      expect(byId['self_assessment']!.title, contains('99 days'));
      expect(byId['cash_isa_cut']!.body, contains('£12,000'));
      expect(byId.keys, contains('scams'));
      expect(tips.every((t) => !t.body.contains('may be out of date')), isTrue);
    });

    test('old catalogue figures are flagged, and after the cut the ISA tip goes', () {
      final tips = quickTips(situation(), market, '2027-05-01');
      expect({for (final t in tips) t.id}, isNot(contains('cash_isa_cut')));
      expect(tips.firstWhere((t) => t.id == 'real_return').body, contains('may be out of date'));
    });

    test('Self Assessment only appears within 120 days of the deadline', () {
      expect({
        for (final t in quickTips(situation(), market, '2026-08-01')) t.id,
      }, isNot(contains('self_assessment')));
    });

    test('a mortgage changes the Bank Rate tip', () {
      final s = situation(holdings: const [Holding('Home', 'mortgage', 15000000)]);
      expect(
        quickTips(s, market, '2026-10-24').firstWhere((t) => t.id == 'bank_rate').ask,
        contains('fix my mortgage'),
      );
    });

    test('nothing UK-specific for another currency', () {
      final s = Situation(metrics: Metrics(), holdings: const [], base: 'USD');
      expect([for (final t in quickTips(s, market, '2026-10-24')) t.id], ['scams']);
    });
  });

  group('service', () {
    test('a failing source is reported and the rest are kept', () async {
      final client = MockClient((req) async {
        final u = req.url.toString();
        if (u.contains('iadb')) return http.Response(boeCsv, 200);
        if (u.contains('d7g7')) return http.Response(cpiJson('3.5'), 200);
        if (u.contains('moneysavingexpert')) return http.Response('forbidden', 403);
        if (u.contains('gov.uk')) return http.Response(atom, 200);
        return http.Response('<rss><channel/></rss>', 200);
      });
      final data = await WorldService(client: client).refresh('2026-10-24');
      expect(data.market.bankRate, 3.75);
      expect(data.market.cpi, 3.5);
      expect(data.failed, ['MoneySavingExpert']);
      expect(data.news.single.source, 'HMRC');
      final again = WorldData.decode(data.encode());
      expect((again.market.cpi, again.news.single.title), (3.5, data.news.single.title));
      expect(again.failed, ['MoneySavingExpert']);
    });

    test('with no network the earlier figures and stories stay', () async {
      const old = WorldData(
        fetched: '2026-10-20T00:00:00Z',
        market: MarketSnapshot(bankRate: 3.75, cpi: 3.4),
        news: [
          NewsItem(title: 'Old', link: 'https://e.com', source: 'FCA', date: '2026-10-20', topics: {'scams'}),
        ],
      );
      final client = MockClient((_) async => throw http.ClientException('offline'));
      final data = await WorldService(client: client).refresh('2026-10-24', previous: old);
      expect((data.market.bankRate, data.market.cpi), (3.75, 3.4));
      expect(data.news.single.title, 'Old');
      expect(data.failed, contains('FCA'));
    });

    test('a broken cache decodes as empty', () {
      expect(WorldData.decode('{oops').news, isEmpty);
      expect(WorldData.decode(null).fetched, '');
    });
  });

  test('the dated catalogue goes stale', () {
    expect(UkRates.stale('2026-12-01'), isFalse);
    expect(UkRates.stale('2027-02-01'), isTrue);
  });
}
