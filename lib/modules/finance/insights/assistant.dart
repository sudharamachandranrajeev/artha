/// "Ask Artha": questions answered by Claude with web search, using the
/// user's own Anthropic API key. Off until a key is added. Only the brief
/// built by [assistantBrief] goes with a question, and the user can read it
/// first: rounded totals, no payees, account names or numbers.
library;

import 'dart:async';
import 'dart:convert';

import 'package:brahma_core/brahma_core.dart';
import 'package:http/http.dart' as http;

import 'catalogue.dart';
import 'risk.dart';
import 'world.dart';

/// The key lives in the system keychain only, never in the database or sync.
const assistantKeyName = 'artha.claude.key';

class AssistantException implements Exception, UserFacingError {
  AssistantException(this.message);
  @override
  final String message;
  @override
  String toString() => message;
}

class Source {
  const Source(this.title, this.url);
  final String title;
  final String url;
}

class AssistantReply {
  const AssistantReply(this.text, this.sources);
  final String text;
  final List<Source> sources;
}

/// £ amounts rounded so the brief carries the shape of the finances, not
/// exact balances: to £100 below £10,000, else to £1,000.
String roughMoney(int minor, String base) {
  final whole = (minor / 100).abs();
  final step = whole < 10000 ? 100 : 1000;
  final r = (whole / step).round() * step;
  final s = r.toString().replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (_) => ',');
  return '${minor < 0 ? '-' : ''}${base == 'GBP' ? '£' : '$base '}$s';
}

/// What is sent with each question. [goals] are the titles of what the user
/// told Artha (goals, coming costs, preferences); [planned] are one-offs the
/// user expects, sent as dated totals without their names.
String assistantBrief({
  required Situation s,
  required RiskAssessment risk,
  required List<PlanStep> plan,
  required MarketSnapshot market,
  required List<NewsItem> news,
  required String today,
  List<String> goals = const [],
  List<({String date, int amount})> planned = const [],
}) {
  final m = s.metrics;
  String money(int v) => roughMoney(v, s.base);
  String pct(double v) => '${(v * 100).round()}%';
  final b = StringBuffer()
    ..writeln('Date: $today. Base currency: ${s.base}. Amounts rounded.')
    ..writeln(
      'Monthly: income ${money(m.monthlyIncome)}, spending ${money(m.monthlySpend)} '
      '(essentials ${money(m.monthlyEssential)})'
      '${m.savingsRate == null ? '' : ', saving ${pct(m.savingsRate!)} of income'}.',
    )
    ..writeln(
      'Cash ${money(m.liquid)}'
      '${m.emergencyMonths == null ? '' : ' (${m.emergencyMonths!.toStringAsFixed(1)} months of essentials)'}; '
      'net worth ${money(m.netWorth)}.',
    );
  if (s.invested > 0) {
    final total = s.byClass.values.fold(0, (t, v) => t + v);
    b.writeln(
      'Investments ${money(s.invested)}; mix: '
      '${[for (final MapEntry(:key, :value) in s.byClass.entries) '$key ${(value * 100 / total).round()}%'].join(', ')}.',
    );
  }
  final kinds = {for (final h in s.holdings) h.subtype};
  b.writeln('Account types: ${kinds.join(', ')}.');
  for (final type in ['mortgage', 'loan', 'credit_card']) {
    final ds = s.debts.where((d) => d.subtype == type).toList();
    if (ds.isEmpty) continue;
    final rates = [for (final d in ds) ?d.rate];
    b.writeln(
      'Owes ${money(ds.fold(0, (t, d) => t + d.value))} on $type'
      '${rates.isEmpty ? '' : ' at ${rates.join('%, ')}%'}.',
    );
  }
  if (m.creditUtilisation != null) b.writeln('Card utilisation ${pct(m.creditUtilisation!)}.');
  b.writeln(
    'Risk: ${risk.label} (attitude ${risk.attitude ?? 'not answered'}/5, capacity ${risk.capacity}/5'
    '${risk.limits.isEmpty ? '' : '; limited by: ${risk.limits.join('; ')}'}).',
  );
  final step = plan.where((p) => p.state == 'now').firstOrNull;
  if (step != null) {
    b.writeln('Current plan step: ${step.title}${step.gap == null ? '' : ' (${money(step.gap!)} to go)'}.');
  }
  if (goals.isNotEmpty) b.writeln('Told Artha: ${goals.join('; ')}.');
  final ahead = planned.where((p) => p.date.compareTo(today) >= 0).toList();
  if (ahead.isNotEmpty) {
    b.writeln(
      'Planned one-offs: ${[for (final p in ahead.take(8)) '${money(p.amount)} on ${p.date}'].join(', ')}.',
    );
  }
  if (market.bankRate != null) b.writeln('UK Bank Rate ${market.bankRate}% (${market.bankRateDate}).');
  if (market.cpi != null) b.writeln('UK CPI inflation ${market.cpi}% (${market.cpiMonth}).');
  if (s.uk) {
    b.writeln(
      'Best buys checked ${UkRates.asOf}: easy access ${UkRates.bestEasyAccess}%, 1-year fix '
      '${UkRates.bestOneYearFix}%, Premium Bonds prize rate ${UkRates.premiumBondsPrize}%; FSCS limit '
      '£${UkRates.fscsLimit ~/ 100}.',
    );
  }
  if (news.isNotEmpty) {
    b.writeln('Recent headlines:');
    for (final n in news.take(6)) {
      b.writeln('- ${n.title} (${n.source}, ${n.date})');
    }
  }
  return b.toString().trim();
}

String assistantSystem(String brief) => '''
You are Artha's money assistant inside a personal finance app. The user is most likely in the UK.
Answer in plain English, precise and short: a direct answer first, then at most 5 bullet points.
Use the user's situation below. When a question depends on current rates, rules or news, search the
web and prefer official sources (Bank of England, ONS, HMRC, GOV.UK, FCA, FSCS, NS&I, MoneyHelper).
Give numbers with their date. Put safety first: emergency fund and expensive debt before investing,
and say plainly when something risks capital. You are not a regulated adviser: for big or
irreversible decisions (pensions transfers, large investments) suggest MoneyHelper or a regulated
financial adviser. Never ask for account numbers, passwords or other personal identifiers.

The user's situation:
$brief''';

/// One conversation with Claude over HTTPS. The conversation lives in memory
/// only; nothing is stored.
class Assistant {
  Assistant(this.apiKey, {http.Client? client, this.model = 'claude-opus-5-5'})
    : _client = client ?? http.Client();
  final String apiKey;
  final String model;
  final http.Client _client;
  static final endpoint = Uri.parse('https://api.anthropic.com/v1/messages');

  /// Messages in API form. Assistant turns are kept exactly as returned.
  final List<Map<String, Object?>> history = [];

  Future<Map<String, Object?>> _post(String system, List<Map<String, Object?>> messages) async {
    final http.Response res;
    try {
      res = await _client
          .post(
            endpoint,
            headers: {
              'x-api-key': apiKey,
              'anthropic-version': '2026-10-21',
              // A declined request is retried server-side on a fallback model.
              'anthropic-beta': 'server-side-fallback-2026-07-01',
              'content-type': 'application/json',
            },
            body: jsonEncode({
              'model': model,
              'max_tokens': 16000,
              'system': system,
              'messages': messages,
              'tools': [
                {'type': 'web_search_20260209', 'name': 'web_search', 'max_uses': 3},
              ],
              'output_config': {'effort': 'low'},
              'fallbacks': 'default',
              'cache_control': {'type': 'ephemeral'},
            }),
          )
          .timeout(const Duration(seconds: 120));
    } on TimeoutException {
      throw AssistantException('Claude took too long to answer. Try again.');
    } on http.ClientException {
      throw AssistantException('Could not reach Claude. Check the connection.');
    }
    final Object? json;
    try {
      json = jsonDecode(utf8.decode(res.bodyBytes));
    } on FormatException {
      throw AssistantException('Claude sent an unreadable answer (${res.statusCode}).');
    }
    if (res.statusCode != 200 || json is! Map<String, Object?>) {
      throw AssistantException(switch (res.statusCode) {
        401 || 403 => 'The API key was not accepted. Check it in Settings.',
        429 => 'Too many questions for now. Wait a minute and try again.',
        >= 500 => 'Claude is busy. Try again shortly.',
        _ => 'Claude could not answer: ${_errorText(json) ?? res.statusCode}',
      });
    }
    return json;
  }

  static String? _errorText(Object? json) => switch (json) {
    {'error': {'message': final String m}} => m,
    _ => null,
  };

  /// Asks [question]; [brief] is the user's situation, sent as the system
  /// prompt. The question only joins the history once answered.
  Future<AssistantReply> ask(String question, String brief) async {
    final system = assistantSystem(brief);
    final messages = [
      ...history,
      {'role': 'user', 'content': question},
    ];
    final turn = <Object?>[];
    for (var round = 0; ; round++) {
      final r = await _post(system, [
        ...messages,
        if (turn.isNotEmpty) {'role': 'assistant', 'content': turn},
      ]);
      turn.addAll(r['content'] as List? ?? const []);
      final stop = r['stop_reason'];
      if (stop == 'refusal') {
        throw AssistantException('Claude declined to answer that. Try rewording the question.');
      }
      // A long web search pauses; sending the turn back lets it carry on.
      if (stop != 'pause_turn') break;
      if (round >= 3) throw AssistantException('The search took too long. Try a narrower question.');
    }
    final text = StringBuffer();
    final sources = <String, Source>{};
    for (final block in turn) {
      if (block case {'type': 'text', 'text': final String t}) {
        text.write(t);
        for (final c in (block['citations'] as List?) ?? const []) {
          if (c case {'url': final String url, 'title': final String? title}) {
            sources.putIfAbsent(url, () => Source(title ?? url, url));
          }
        }
      }
    }
    if (text.isEmpty) throw AssistantException('Claude sent no answer. Try again.');
    history
      ..add({'role': 'user', 'content': question})
      ..add({'role': 'assistant', 'content': turn});
    return AssistantReply(text.toString().trim(), sources.values.toList());
  }
}
