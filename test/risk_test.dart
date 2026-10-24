import 'dart:convert';

import 'package:artha/modules/finance/insights/assistant.dart';
import 'package:artha/modules/finance/insights/insights.dart';
import 'package:artha/modules/finance/insights/risk.dart';
import 'package:artha/modules/finance/insights/world.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

Metrics metrics({
  int liquid = 600000,
  int income = 300000,
  int spend = 200000,
  int essential = 150000,
  double? months,
  double? savings,
  int debt = 0,
}) => Metrics()
  ..liquid = liquid
  ..debt = debt
  ..monthlyIncome = income
  ..monthlySpend = spend
  ..monthlyEssential = essential
  ..emergencyMonths = months ?? liquid / essential
  ..savingsRate = savings ?? (income - spend) / income
  ..netWorth = liquid - debt;

Situation situation(
  Metrics m, {
  List<Holding> holdings = const [],
  Map<String, int> byClass = const {},
  int invested = 0,
  ({String name, double share})? top,
}) => Situation(
  metrics: m,
  holdings: holdings,
  base: 'GBP',
  byClass: byClass,
  invested: invested,
  topHolding: top,
);

const allHigh = {'horizon': 4, 'fall': 4, 'experience': 4, 'goal': 4};

void main() {
  group('assessment', () {
    test('level is the lower of comfort and capacity', () {
      // 4 months of cash: capacity 4; very comfortable: attitude 5.
      final a = assessRisk(situation(metrics(liquid: 600000)), allHigh);
      expect((a.attitude, a.capacity, a.level, a.label), (5, 4, 4, 'Growth'));
      // A nervous investor with plenty of cash is held back by comfort.
      final nervous = assessRisk(situation(metrics(liquid: 1200000)), {
        'horizon': 3,
        'fall': 0,
        'experience': 1,
        'goal': 1,
      });
      expect((nervous.attitude, nervous.capacity, nervous.level), (2, 5, 2));
    });

    test('money needed within a year caps the comfort level', () {
      final a = assessRisk(situation(metrics(liquid: 1200000)), {
        'horizon': 0,
        'fall': 4,
        'experience': 4,
        'goal': 4,
      });
      expect(a.attitude, 1);
      expect(a.profile.id, 'cautious');
    });

    test('without answers it rests on the finances alone', () {
      final a = assessRisk(situation(metrics(liquid: 1200000)), const {});
      expect((a.attitude, a.level), (null, 5));
      expect(assessRisk(situation(metrics(liquid: 1200000)), {'horizon': 9}).attitude, isNull);
    });

    test('thin cash, overspending and expensive debt each lower capacity', () {
      expect(assessRisk(situation(metrics(liquid: 100000)), const {}).capacity, 1);
      expect(assessRisk(situation(metrics(liquid: 300000)), const {}).capacity, 2);
      final over = assessRisk(situation(metrics(liquid: 1200000, spend: 320000, savings: -0.07)), const {});
      expect((over.capacity, over.limits.single), (1, 'Spending more than you earn'));
      final card = assessRisk(
        situation(
          metrics(liquid: 1200000, debt: 200000),
          holdings: const [Holding('Visa', 'credit_card', 200000)],
        ),
        const {},
      );
      expect(card.capacity, 2);
      expect(card.limits, contains('Debt at 10% interest or more'));
    });
  });

  group('checks', () {
    test('expensive debt, thin cash and inflation losers are flagged', () {
      final s = situation(
        metrics(liquid: 200000, debt: 300000),
        holdings: const [
          Holding('Visa', 'credit_card', 300000),
          Holding('Old savings', 'savings', 200000, rate: 1.0, institution: 'Bank A'),
        ],
      );
      final checks = {for (final c in riskChecks(s, cpi: 3.5)) c.id: c};
      expect(checks['emergency']!.severity, 'action');
      expect(checks['debt/Visa']!.severity, 'action');
      expect(checks['debt/Visa']!.body, contains('about 20%'));
      expect(checks['real/Old savings']!.severity, 'warn');
    });

    test('cash above the protection limit at one bank is flagged; spread across banks it is not', () {
      Situation at(String second) => situation(
        metrics(liquid: 20000000, essential: 100000),
        holdings: [
          const Holding('A1', 'savings', 7000000, institution: 'Bank A'),
          Holding('A2', 'current', 7000000, institution: second),
        ],
      );
      expect({for (final c in riskChecks(at('Bank A'))) c.id}, contains('fscs/Bank A'));
      expect(riskChecks(at('Bank B')).where((c) => c.id.startsWith('fscs')), isEmpty);
    });

    test('concentration, crypto and investing without a cushion', () {
      final s = situation(
        metrics(liquid: 100000),
        invested: 1000000,
        byClass: const {'equity': 800000, 'crypto': 200000},
        top: (name: 'Acme plc', share: 0.5),
      );
      final ids = {for (final c in riskChecks(s)) c.id};
      expect(ids, containsAll(['concentration', 'crypto', 'forced_sale']));
    });
  });

  group('stress', () {
    test('income stop, market fall and rate rise', () {
      final s = situation(
        metrics(liquid: 600000, debt: 12000000)..netWorth = 5000000,
        holdings: const [Holding('Mortgage', 'mortgage', 12000000)],
        byClass: const {'equity': 1000000, 'crypto': 100000},
      );
      final t = {for (final x in stressTests(s)) x.title: x};
      expect(t['Income stops']!.severity, 'warn');
      // 30% of £10,000 + 60% of £1,000 = £3,600.
      expect(t['Markets fall sharply']!.body, contains('£3,600'));
      // 1% of £120,000 a year.
      expect(t['Rates rise 1 point']!.body, contains('£100 more a month'));
    });
  });

  group('plan', () {
    test('the first unfinished step is "now"; later ones wait', () {
      final s = situation(
        metrics(liquid: 100000, spend: 350000, income: 300000, savings: -0.17),
        holdings: const [Holding('Current', 'current', 100000)],
      );
      final plan = buildPlan(s, assessRisk(s, const {}));
      expect(
        [for (final p in plan) p.id],
        ['budget', 'debt', 'starter', 'match', 'emergency', 'goals', 'invest'],
      );
      expect(plan.first.state, 'now');
      expect(plan.first.gap, 50000);
      expect(plan.firstWhere((p) => p.id == 'debt').state, 'done');
      expect(plan.where((p) => p.state == 'now'), hasLength(1));
    });

    test('a sound position moves to the long-term step', () {
      final s = situation(
        metrics(liquid: 1200000),
        holdings: const [Holding('Pension', 'pension', 5000000), Holding('Cash', 'savings', 1200000)],
      );
      final plan = {for (final p in buildPlan(s, assessRisk(s, allHigh))) p.id: p};
      expect([
        plan['budget']!.state,
        plan['debt']!.state,
        plan['starter']!.state,
        plan['emergency']!.state,
      ], everyElement('done'));
      expect(plan['match']!.state, 'done');
      expect(plan['invest']!.state, 'now');
      expect(plan['invest']!.body, contains('Adventurous'));
      // Safest options first, with the lowest risk leading.
      expect(plan['emergency']!.options, ['easy_access', 'premium_bonds', 'cash_isa']);
    });

    test('once investing in a wrapper the last step is ongoing', () {
      final s = situation(
        metrics(liquid: 1200000),
        holdings: const [Holding('S&S ISA', 'isa_stocks', 500000)],
        invested: 500000,
      );
      expect(buildPlan(s, assessRisk(s, allHigh)).last.state, 'ongoing');
    });

    test('a thin position holds back investing', () {
      final s = situation(metrics(liquid: 50000));
      final plan = buildPlan(s, assessRisk(s, allHigh));
      final invest = plan.firstWhere((p) => p.id == 'invest');
      expect(invest.state, 'next');
      expect(invest.body, startsWith('Not yet'));
    });
  });

  group('assistant', () {
    final brief = assistantBrief(
      s: situation(
        metrics(liquid: 1234567),
        holdings: const [
          Holding('Secret Account Name', 'savings', 1234567, institution: 'Monzo', rate: 4.0),
          Holding('Card 4929', 'credit_card', 120000, rate: 24.9),
        ],
      ),
      risk: const RiskAssessment(
        attitude: 3,
        capacity: 4,
        limits: ['Cash covers under 6 months of essentials'],
      ),
      plan: const [],
      market: const MarketSnapshot(
        bankRate: 3.75,
        bankRateDate: '2026-09-17',
        cpi: 3.5,
        cpiMonth: 'September 2026',
      ),
      news: const [NewsItem(title: 'Rates held', link: 'https://e.com', source: 'BoE', date: '2026-10-22')],
      today: '2026-10-24',
      goals: const ['House deposit by 2029'],
    );

    test('the brief rounds amounts and leaves out names and numbers', () {
      expect(brief, contains('£12,000'));
      expect(brief, contains('Bank Rate 3.75%'));
      expect(brief, contains('House deposit by 2029'));
      expect(brief, contains('Rates held'));
      for (final secret in ['Secret Account Name', 'Monzo', '4929', '1,234,567', '12,345']) {
        expect(brief, isNot(contains(secret)));
      }
    });

    test('rounding steps', () {
      expect(roughMoney(123456, 'GBP'), '£1,200');
      expect(roughMoney(12345678, 'GBP'), '£123,000');
      expect(roughMoney(-50000, 'USD'), '-USD 500');
    });

    Map<String, Object?> msg(List<Map<String, Object?>> content, {String stop = 'end_turn'}) => {
      'content': content,
      'stop_reason': stop,
    };

    test('sends the key, headers, search tool and fallbacks; returns text and sources', () async {
      late http.Request seen;
      final client = MockClient((req) async {
        seen = req;
        return http.Response(
          jsonEncode(
            msg([
              {'type': 'thinking', 'thinking': '...', 'signature': 'x'},
              {
                'type': 'text',
                'text': 'Fix at 5.15%.',
                'citations': [
                  {'url': 'https://www.moneyfacts.co.uk', 'title': 'Moneyfacts'},
                  {'url': 'https://www.moneyfacts.co.uk', 'title': 'Moneyfacts'},
                ],
              },
            ]),
          ),
          200,
        );
      });
      final a = Assistant('sk-ant-test-key-1234567890', client: client);
      final r = await a.ask('Where should I save?', brief);
      expect(r.text, 'Fix at 5.15%.');
      expect([for (final s in r.sources) s.url], ['https://www.moneyfacts.co.uk']);
      expect(seen.url.toString(), 'https://api.anthropic.com/v1/messages');
      expect(seen.headers['x-api-key'], 'sk-ant-test-key-1234567890');
      expect(seen.headers['anthropic-version'], '2026-10-21');
      expect(seen.headers['anthropic-beta'], 'server-side-fallback-2026-07-01');
      final body = jsonDecode(seen.body) as Map;
      expect(body['model'], 'claude-opus-5-5');
      expect(body['fallbacks'], 'default');
      expect(body.containsKey('temperature'), isFalse);
      expect((body['tools'] as List).single['type'], 'web_search_20260209');
      expect(body['system'], contains('House deposit by 2029'));
      expect((body['messages'] as List).single, {'role': 'user', 'content': 'Where should I save?'});
      // The whole turn, thinking included, is kept for the next question.
      expect(a.history, hasLength(2));
      expect((a.history.last['content'] as List).first['type'], 'thinking');
    });

    test('a paused search is resumed with the turn so far', () async {
      var calls = 0;
      late Map second;
      final client = MockClient((req) async {
        calls++;
        if (calls == 1) {
          return http.Response(
            jsonEncode(
              msg([
                {
                  'type': 'server_tool_use',
                  'id': 's1',
                  'name': 'web_search',
                  'input': {'query': 'rates'},
                },
              ], stop: 'pause_turn'),
            ),
            200,
          );
        }
        second = jsonDecode(req.body) as Map;
        return http.Response(
          jsonEncode(
            msg([
              {'type': 'text', 'text': 'Done.'},
            ]),
          ),
          200,
        );
      });
      final r = await Assistant('k' * 30, client: client).ask('q', brief);
      expect(r.text, 'Done.');
      final messages = second['messages'] as List;
      expect(messages.map((m) => (m as Map)['role']), ['user', 'assistant']);
      expect(((messages.last as Map)['content'] as List).single['type'], 'server_tool_use');
    });

    test('errors are readable and leave the history alone', () async {
      Future<String> fail(http.Response r) async {
        final a = Assistant('k' * 30, client: MockClient((_) async => r));
        try {
          await a.ask('q', brief);
        } on AssistantException catch (e) {
          expect(a.history, isEmpty);
          return e.message;
        }
        return 'no error';
      }

      expect(
        await fail(http.Response('{"error":{"message":"invalid x-api-key"}}', 401)),
        contains('key was not accepted'),
      );
      expect(await fail(http.Response('{}', 429)), contains('Too many'));
      expect(await fail(http.Response('{}', 529)), contains('busy'));
      expect(await fail(http.Response('<html>', 502)), contains('unreadable'));
      expect(
        await fail(http.Response('{"error":{"message":"credit balance is too low"}}', 400)),
        contains('credit balance'),
      );
      expect(
        await fail(http.Response(jsonEncode(msg(const [], stop: 'refusal')), 200)),
        contains('declined'),
      );
      expect(await fail(http.Response(jsonEncode(msg(const [])), 200)), contains('no answer'));
    });

    test('offline is a readable error', () async {
      final a = Assistant('k' * 30, client: MockClient((_) async => throw http.ClientException('down')));
      await expectLater(a.ask('q', brief), throwsA(isA<AssistantException>()));
    });
  });
}
