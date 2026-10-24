import 'dart:async';
import 'dart:convert';

import 'package:brahma_core/brahma_core.dart';
import 'package:http/http.dart' as http;
import 'package:xml/xml.dart';

import 'catalogue.dart';
import 'risk.dart';

/// Headline UK figures fetched live: Bank Rate from the Bank of England and
/// CPI inflation from the ONS. Nothing about the user is sent; these are
/// plain public downloads.
class MarketSnapshot {
  const MarketSnapshot({this.bankRate, this.bankRateDate, this.cpi, this.cpiMonth});
  final double? bankRate;
  final String? bankRateDate;
  final double? cpi;

  /// "September 2026".
  final String? cpiMonth;

  bool get isEmpty => bankRate == null && cpi == null;

  Map<String, Object?> toJson() => {
    'bankRate': bankRate,
    'bankRateDate': bankRateDate,
    'cpi': cpi,
    'cpiMonth': cpiMonth,
  };

  static MarketSnapshot fromJson(Map<String, Object?> j) => MarketSnapshot(
    bankRate: (j['bankRate'] as num?)?.toDouble(),
    bankRateDate: j['bankRateDate'] as String?,
    cpi: (j['cpi'] as num?)?.toDouble(),
    cpiMonth: j['cpiMonth'] as String?,
  );
}

/// What a story is about, with the words that give it away. Matching is on
/// whole words or phrases in the title and summary, any case.
const newsTopics = <String, List<String>>{
  'rates': [
    'bank rate',
    'base rate',
    'interest rate',
    'interest rates',
    'monetary policy',
    'rate cut',
    'rate rise',
  ],
  'inflation': ['inflation', 'cpi', 'cost of living', 'price rises'],
  'savings': [
    'savings',
    'saver',
    'savers',
    'isa',
    'isas',
    'premium bonds',
    'ns&i',
    'easy access',
    'fixed rate',
  ],
  'mortgage': [
    'mortgage',
    'mortgages',
    'remortgage',
    'house prices',
    'first-time buyer',
    'first-time buyers',
  ],
  'tax': ['tax', 'hmrc', 'self assessment', 'budget', 'allowance', 'tax return', 'national insurance'],
  'pension': ['pension', 'pensions', 'retirement', 'state pension', 'annuity'],
  'debt': ['credit card', 'credit cards', 'loan', 'loans', 'debt', 'overdraft', 'buy now pay later', 'bnpl'],
  'scams': ['scam', 'scams', 'fraud warning', 'bank fraud', 'fraudsters', 'phishing', 'impersonation'],
  'bills': ['energy', 'price cap', 'bills', 'council tax', 'broadband', 'water bills', 'warm home discount'],
  'investing': ['shares', 'stocks', 'ftse', 'stock market', 'investors', 'investment', 'funds', 'gilts'],
  'benefits': ['benefit', 'benefits', 'universal credit', 'child benefit', 'tax-free childcare'],
};

final _topicPatterns = {
  for (final MapEntry(key: topic, value: words) in newsTopics.entries)
    topic: RegExp('\\b(${words.map(RegExp.escape).join('|')})\\b', caseSensitive: false),
};

Set<String> topicsOf(String text) => {
  for (final MapEntry(key: t, value: p) in _topicPatterns.entries)
    if (p.hasMatch(text)) t,
};

class NewsItem {
  const NewsItem({
    required this.title,
    required this.link,
    required this.source,
    required this.date,
    this.summary = '',
    this.topics = const {},
  });
  final String title;
  final String link;
  final String source;

  /// yyyy-MM-dd.
  final String date;
  final String summary;
  final Set<String> topics;

  Map<String, Object?> toJson() => {
    'title': title,
    'link': link,
    'source': source,
    'date': date,
    'summary': summary,
    'topics': topics.toList(),
  };

  static NewsItem fromJson(Map<String, Object?> j) => NewsItem(
    title: j['title'] as String,
    link: j['link'] as String,
    source: j['source'] as String,
    date: j['date'] as String,
    summary: j['summary'] as String? ?? '',
    topics: {...(j['topics'] as List? ?? const []).cast<String>()},
  );
}

class NewsFeed {
  const NewsFeed(this.source, this.url);
  final String source;
  final String url;
}

/// Official and consumer-money sources only, all free of tracking-heavy
/// paywalls. Each is a public RSS or Atom feed.
const newsFeeds = [
  NewsFeed('Bank of England', 'https://www.bankofengland.co.uk/rss/news'),
  NewsFeed('FCA', 'https://www.fca.org.uk/news/rss.xml'),
  NewsFeed(
    'HMRC',
    'https://www.gov.uk/search/news-and-communications.atom?organisations%5B%5D=hm-revenue-customs',
  ),
  NewsFeed('MoneySavingExpert', 'https://www.moneysavingexpert.com/news/feeds/news.rss'),
  NewsFeed('BBC Business', 'https://feeds.bbci.co.uk/news/business/rss.xml'),
];

const _months = {
  'jan': 1,
  'feb': 2,
  'mar': 3,
  'apr': 4,
  'may': 5,
  'jun': 6,
  'jul': 7,
  'aug': 8,
  'sep': 9,
  'oct': 10,
  'nov': 11,
  'dec': 12,
};
final _rfc822 = RegExp(
  r'(\d{1,2})\s+([A-Za-z]{3})\w*\s+(\d{4})\s+(\d{1,2}):(\d{2})(?::(\d{2}))?\s*([+-]\d{4}|[A-Z]{1,3})?',
);

/// The UTC calendar day of an RSS (RFC 822) or Atom (ISO 8601) date.
String? feedDate(String raw) {
  final s = raw.trim();
  final iso = DateTime.tryParse(s);
  if (iso != null) return isoDate(iso.toUtc());
  final m = _rfc822.firstMatch(s);
  final month = m == null ? null : _months[m[2]!.toLowerCase()];
  if (m == null || month == null) return null;
  var t = DateTime.utc(int.parse(m[3]!), month, int.parse(m[1]!), int.parse(m[4]!), int.parse(m[5]!));
  final zone = m[7];
  if (zone != null && (zone.startsWith('+') || zone.startsWith('-'))) {
    final minutes = int.parse(zone.substring(1, 3)) * 60 + int.parse(zone.substring(3, 5));
    t = t.subtract(Duration(minutes: zone.startsWith('+') ? minutes : -minutes));
  }
  return isoDate(t);
}

/// Feed text as plain text: tags and entities gone, whitespace collapsed,
/// cut at [max] characters on a word boundary.
String plainText(String html, {int max = 220}) {
  var s = html.replaceAll(RegExp(r'<[^>]*>'), ' ');
  s = s
      .replaceAll('&nbsp;', ' ')
      .replaceAll('&amp;', '&')
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>')
      .replaceAll('&quot;', '"')
      .replaceAll('&#39;', "'")
      .replaceAll('&rsquo;', '’')
      .replaceAll('&lsquo;', '‘')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
  if (s.length <= max) return s;
  final cut = s.substring(0, max);
  final space = cut.lastIndexOf(' ');
  return '${(space > max ~/ 2 ? cut.substring(0, space) : cut).trimRight()}…';
}

/// Items of an RSS 2.0 or Atom document. Items without a title, an https
/// link or a readable date are dropped; malformed XML throws [WorldException].
List<NewsItem> parseFeed(String body, String source) {
  final XmlDocument doc;
  try {
    doc = XmlDocument.parse(body.startsWith('﻿') ? body.substring(1) : body);
  } on XmlException {
    throw WorldException('$source sent a feed that is not valid XML');
  }
  String text(XmlElement e, String name) => e.findElements(name).firstOrNull?.innerText.trim() ?? '';
  final out = <NewsItem>[];
  void add(String title, String link, String? date, String summary) {
    final uri = Uri.tryParse(link);
    if (title.isEmpty || date == null || uri == null || uri.scheme != 'https' || uri.host.isEmpty) return;
    final clean = plainText(title, max: 200);
    final about = plainText(summary);
    out.add(
      NewsItem(
        title: clean,
        link: link,
        source: source,
        date: date,
        summary: about,
        topics: topicsOf('$clean $about'),
      ),
    );
  }

  for (final item in doc.findAllElements('item')) {
    add(
      text(item, 'title'),
      text(item, 'link'),
      feedDate(text(item, 'pubDate').isNotEmpty ? text(item, 'pubDate') : text(item, 'dc:date')),
      text(item, 'description'),
    );
  }
  for (final entry in doc.findAllElements('entry')) {
    final link =
        entry
            .findElements('link')
            .where((l) => (l.getAttribute('rel') ?? 'alternate') == 'alternate')
            .firstOrNull
            ?.getAttribute('href') ??
        '';
    final updated = text(entry, 'published').isNotEmpty ? text(entry, 'published') : text(entry, 'updated');
    add(text(entry, 'title'), link, feedDate(updated), text(entry, 'summary'));
  }
  return out;
}

/// How much each topic matters to this user: always a little for rates,
/// inflation, tax, bills and scams; more for what they hold or owe.
Map<String, double> newsInterests({
  required bool saves,
  required bool invests,
  required bool mortgage,
  required bool borrows,
  required bool pension,
}) => {
  'rates': 2,
  'inflation': 1.5,
  'tax': 1,
  'bills': 1,
  'scams': 1.5,
  'benefits': 0.5,
  'savings': saves ? 2 : 1,
  'investing': invests ? 2 : 0.5,
  'mortgage': mortgage ? 3 : 0.5,
  'debt': borrows ? 2 : 0.5,
  'pension': pension ? 2 : 1,
};

/// Committee minutes, market notices and appointments: official but not for a household.
final _noise = RegExp(
  r'\b(minutes of|market notice|statistical notice|green notice|questionnaire|appointments?\b|consults? on|'
  r'working group|sub-committee|taskforce|stakeholder|transcript|speech by)',
  caseSensitive: false,
);

/// The [limit] most relevant stories of the last three weeks: topic weight
/// by [interests], fading with age; one copy of each headline.
List<NewsItem> rankNews(List<NewsItem> items, Map<String, double> interests, String today, {int limit = 8}) {
  final seen = <String>{};
  final scored = <(double, NewsItem)>[];
  for (final n in items) {
    if (n.topics.isEmpty || n.date.compareTo(today) > 0 || _noise.hasMatch(n.title)) continue;
    final age = daysBetween(today, n.date);
    if (age > 21) continue;
    final key = n.title.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
    if (!seen.add(key)) continue;
    final weight = n.topics.fold(0.0, (s, t) => s + (interests[t] ?? 0.5));
    scored.add((weight / (1 + age / 4), n));
  }
  scored.sort((a, b) => b.$1.compareTo(a.$1));
  return [for (final (_, n) in scored.take(limit)) n];
}

/// Bank Rate from the Bank of England's database CSV (series IUDBEDR):
/// "DATE,IUDBEDR" lines, newest last.
({double rate, String date})? parseBankRate(String csv) {
  for (final line in csv.trim().split('\n').reversed) {
    final parts = line.trim().split(',');
    if (parts.length != 2) continue;
    final rate = double.tryParse(parts[1]);
    final date = feedDate('${parts[0]} 00:00');
    if (rate == null || date == null || rate < 0 || rate > 25) continue;
    return (rate: rate, date: date);
  }
  return null;
}

/// The latest month of an ONS time-series JSON (CPI annual rate, D7G7).
({double rate, String month})? parseCpi(String body) {
  final Object? json;
  try {
    json = jsonDecode(body);
  } on FormatException {
    return null;
  }
  final months = json is Map ? json['months'] : null;
  if (months is! List || months.isEmpty) return null;
  final last = months.last;
  if (last is! Map) return null;
  final rate = double.tryParse('${last['value']}');
  final month = last['month'], year = last['year'];
  if (rate == null || rate < -10 || rate > 50 || month is! String || year is! String) return null;
  return (rate: rate, month: '$month $year');
}

class WorldException implements Exception, UserFacingError {
  WorldException(this.message);
  @override
  final String message;
  @override
  String toString() => message;
}

/// What was fetched, and when.
class WorldData {
  const WorldData({required this.fetched, required this.market, required this.news, this.failed = const []});
  final String fetched;
  final MarketSnapshot market;
  final List<NewsItem> news;

  /// Sources that could not be read on the last refresh.
  final List<String> failed;

  static const empty = WorldData(fetched: '', market: MarketSnapshot(), news: []);

  String encode() => jsonEncode({
    'fetched': fetched,
    'market': market.toJson(),
    'news': [for (final n in news) n.toJson()],
    'failed': failed,
  });

  static WorldData decode(String? s) {
    if (s == null || s.isEmpty) return empty;
    try {
      final j = jsonDecode(s) as Map<String, Object?>;
      return WorldData(
        fetched: j['fetched'] as String? ?? '',
        market: MarketSnapshot.fromJson((j['market'] as Map?)?.cast<String, Object?>() ?? const {}),
        news: [for (final n in (j['news'] as List? ?? const [])) NewsItem.fromJson((n as Map).cast())],
        failed: [...(j['failed'] as List? ?? const []).cast<String>()],
      );
    } on Object {
      return empty;
    }
  }
}

/// Downloads the feeds and figures. Every request is a plain GET of a public
/// page with a timeout and a size cap; one source failing leaves the others.
class WorldService {
  WorldService({http.Client? client}) : _client = client ?? http.Client();
  final http.Client _client;

  static const bankRateUrl =
      'https://www.bankofengland.co.uk/boeapps/database/_iadb-fromshowcolumns.asp'
      '?csv.x=yes&SeriesCodes=IUDBEDR&CSVF=TN&UsingCodes=Y&VPD=Y&VFD=N&Dateto=now';
  static const cpiUrl = 'https://www.ons.gov.uk/economy/inflationandpriceindices/timeseries/d7g7/mm23/data';
  static const _maxBytes = 3 * 1024 * 1024;

  Future<String> _get(String url) async {
    final http.Response res;
    try {
      res = await _client
          .get(Uri.parse(url), headers: {'User-Agent': 'Mozilla/5.0 (Artha personal finance)'})
          .timeout(const Duration(seconds: 15));
    } on TimeoutException {
      throw WorldException('timed out');
    } on http.ClientException catch (e) {
      throw WorldException(e.message);
    }
    if (res.statusCode != 200) throw WorldException('answered ${res.statusCode}');
    if (res.bodyBytes.length > _maxBytes) throw WorldException('sent too much data');
    return utf8.decode(res.bodyBytes, allowMalformed: true);
  }

  Future<WorldData> refresh(String today, {WorldData previous = WorldData.empty}) async {
    final failed = <String>[];
    // Bank Rate: the last year is plenty and keeps the download small.
    final from = DateTime.parse(addMonths(today, -12));
    const names = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    final rateUrl =
        '$bankRateUrl&Datefrom=${from.day.toString().padLeft(2, '0')}/${names[from.month - 1]}/${from.year}';
    final results = await Future.wait([
      _get(rateUrl).then<Object?>((b) => parseBankRate(b)).catchError((Object _) => null),
      _get(cpiUrl).then<Object?>((b) => parseCpi(b)).catchError((Object _) => null),
      for (final f in newsFeeds)
        _get(f.url).then<Object?>((b) => parseFeed(b, f.source)).catchError((Object _) {
          failed.add(f.source);
          return null;
        }),
    ]);
    final rate = results[0] as ({double rate, String date})?;
    final cpi = results[1] as ({double rate, String month})?;
    if (rate == null) failed.add('Bank of England rates');
    if (cpi == null) failed.add('ONS inflation');
    final news = [
      for (final r in results.skip(2))
        if (r is List<NewsItem>) ...r,
    ];
    final old = previous.market;
    return WorldData(
      fetched: DateTime.now().toUtc().toIso8601String(),
      market: MarketSnapshot(
        bankRate: rate?.rate ?? old.bankRate,
        bankRateDate: rate?.date ?? old.bankRateDate,
        cpi: cpi?.rate ?? old.cpi,
        cpiMonth: cpi?.month ?? old.cpiMonth,
      ),
      // A feed that failed keeps its earlier stories.
      news: [...news, ...previous.news.where((n) => failed.contains(n.source))],
      failed: failed,
    );
  }
}

/// A short, dated pointer about what is happening now and what it means for
/// this user. [ask] is the follow-up question for the assistant.
class Tip {
  const Tip(this.id, this.title, this.body, {this.ask, this.source});
  final String id;
  final String title;
  final String body;
  final String? ask;
  final String? source;
}

/// Tips for [today] from the live [market] figures, the dated UK rates
/// catalogue and the user's [s]ituation. UK rules only apply to a GBP base.
List<Tip> quickTips(Situation s, MarketSnapshot market, String today) {
  final out = <Tip>[];
  final cpi = market.cpi;
  final rate = market.bankRate;
  final stale = UkRates.stale(today) ? ' (rates checked ${niceDate(UkRates.asOf)}; may be out of date)' : '';
  if (s.uk && cpi != null) {
    out.add(
      Tip(
        'real_return',
        'Beat ${cpi.toStringAsFixed(1)}% inflation',
        'Prices rose $cpi% in the year to ${market.cpiMonth}. Top easy access pays '
            '${UkRates.bestEasyAccess.toStringAsFixed(2)}%, a 1-year fix ${UkRates.bestOneYearFix.toStringAsFixed(2)}%'
            '$stale. Money below inflation shrinks.',
        ask: 'Inflation is $cpi%. Which safe savings beat it right now?',
        source: 'ONS',
      ),
    );
  }
  if (s.uk && rate != null) {
    final next = UkRates.nextRateDecision.compareTo(today) >= 0
        ? ' Next decision ${niceDate(UkRates.nextRateDecision)}.'
        : '';
    final mortgage = s.has('mortgage') || s.has('loan');
    out.add(
      Tip(
        'bank_rate',
        'Bank Rate is ${rate.toStringAsFixed(2)}%',
        'Set by the Bank of England${market.bankRateDate == null ? '' : ' on ${niceDate(market.bankRateDate!)}'}.$next '
            '${mortgage ? 'On a variable or tracker deal, each 0.25-point rise adds about £21 a month per £100,000.' : 'Savings rates follow it: fixing now locks today\'s rate.'}',
        ask: mortgage
            ? 'Bank Rate is $rate%. Should I fix my mortgage or stay variable?'
            : 'Bank Rate is $rate%. Should I fix my savings now or stay in easy access?',
        source: 'Bank of England',
      ),
    );
  }
  if (s.uk) {
    final y = int.parse(today.substring(0, 4));
    final sa = today.compareTo('$y-01-31') <= 0 ? '$y-01-31' : '${y + 1}-01-31';
    final left = daysBetween(sa, today);
    if (left <= 120) {
      out.add(
        Tip(
          'self_assessment',
          'Self Assessment due in $left days',
          'Online returns and payment for the last tax year are due by ${niceDate(sa)}; '
              'the late penalty starts at £100. Only if you are self-employed, a landlord or earn untaxed income.',
          ask: 'Do I need to file a Self Assessment return, and what happens if I miss the deadline?',
          source: 'HMRC',
        ),
      );
    }
    if (today.compareTo(UkRates.cashIsaFrom) < 0) {
      out.add(
        Tip(
          'cash_isa_cut',
          'Cash ISA limit falls in April 2027',
          'From ${niceDate(UkRates.cashIsaFrom)} under-65s can save ${_pounds(UkRates.cashIsaUnder65)} a year in cash '
              'ISAs (the total stays ${_pounds(UkAllowances.isa)}). This tax year you can still put the full '
              '${_pounds(UkAllowances.isa)} in cash.',
          ask: 'Should I fill my cash ISA before the limit falls to £12,000 in April 2027?',
          source: 'HM Treasury',
        ),
      );
    }
    out.add(
      Tip(
        'premium_bonds',
        'Premium Bonds: ${UkRates.premiumBondsPrize.toStringAsFixed(2)}% prize rate',
        'Tax-free and 100% government-backed, but prizes are luck: odds ${UkRates.premiumBondsOdds} per £1 bond. '
            'Most useful to higher-rate taxpayers past their savings allowance.$stale',
        ask: 'Are Premium Bonds better for me than a savings account?',
        source: 'NS&I',
      ),
    );
    if (s.holdings.where((h) => h.isCash).fold(0, (t, h) => t + h.value) > UkRates.fscsLimit ~/ 2) {
      out.add(
        Tip(
          'fscs',
          'Deposit protection: ${_pounds(UkRates.fscsLimit)}',
          'Per person, per banking licence. Brands under one licence share it; joint accounts get double.',
          ask: 'How does FSCS protection work for savings spread across brands?',
          source: 'FSCS',
        ),
      );
    }
  }
  out.add(
    const Tip(
      'scams',
      'Check before you invest',
      'Cold calls, social media "guaranteed returns" and pressure to act fast are scam signs. '
          'Check any firm on the FCA register first.',
      ask: 'How do I check an investment offer is not a scam?',
      source: 'FCA',
    ),
  );
  return out;
}

String _pounds(int pence) =>
    '£${(pence ~/ 100).toString().replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (_) => ',')}';
