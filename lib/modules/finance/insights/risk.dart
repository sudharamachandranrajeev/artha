/// Risk tools: how much risk the user wants and can afford, what could hurt
/// them, and the lowest-risk order to put money to work. Pure functions over
/// a [Situation]; nothing here touches the network.
library;

import 'dart:convert';
import 'dart:math' as math;

import '../portfolio/portfolio.dart';
import '../reports/reports.dart';
import 'catalogue.dart';
import 'insights.dart';

/// One account as the risk tools see it.
class Holding {
  const Holding(this.name, this.subtype, this.value, {this.institution, this.rate});
  final String name;
  final String subtype;

  /// Base currency; for debts, the amount owed (positive).
  final int value;
  final String? institution;

  /// Interest rate (% a year) from the account's details, when recorded.
  final double? rate;

  bool get isDebt => const {'credit_card', 'loan', 'mortgage'}.contains(subtype);
  bool get isCash => const {'current', 'savings', 'cash', 'isa_cash'}.contains(subtype);
}

/// Everything the risk tools need, in the base currency.
class Situation {
  const Situation({
    required this.metrics,
    required this.holdings,
    required this.base,
    this.byClass = const {},
    this.invested = 0,
    this.topHolding,
  });
  final Metrics metrics;
  final List<Holding> holdings;
  final String base;

  /// Portfolio value by asset class, cash included.
  final Map<String, int> byClass;

  /// Value of holdings bought at a cost (funds, shares, crypto).
  final int invested;
  final ({String name, double share})? topHolding;

  bool get uk => base == 'GBP';
  bool has(String subtype) => holdings.any((h) => h.subtype == subtype);
  Iterable<Holding> get debts => holdings.where((h) => h.isDebt && h.value > 0);

  /// Debts at 10% a year or more.
  List<Holding> get expensiveDebt => [
    for (final d in debts)
      if ((d.rate ?? (d.subtype == 'credit_card' ? 20 : 0)) >= 10) d,
  ];

  /// Monthly money needed for essentials; total spending when essentials
  /// are not marked.
  int get need => metrics.monthlyEssential > 0 ? metrics.monthlyEssential : metrics.monthlySpend;

  static Situation from(Metrics m, BalanceSheet bs, Portfolio p) {
    double? rate(String meta) => switch ((jsonDecode(meta) as Map)['interestRate']) {
      final num n => n.toDouble(),
      _ => null,
    };
    final top = p.positions.where((x) => x.cost != null).firstOrNull;
    return Situation(
      metrics: m,
      base: p.base,
      holdings: [
        for (final l in [...bs.assets, ...bs.liabilities])
          if (!l.account.closed && (l.baseValue ?? 0) != 0)
            Holding(
              l.account.name,
              l.account.subtype,
              l.account.kind == 'liability' ? -l.baseValue! : l.baseValue!,
              institution: l.account.institution,
              rate: rate(l.account.meta),
            ),
      ],
      byClass: p.byClass,
      invested: p.invested,
      topHolding: top == null || p.invested <= 0
          ? null
          : (name: top.commodity.name, share: (top.value ?? 0) / p.invested),
    );
  }
}

class RiskQuestion {
  const RiskQuestion(this.id, this.text, this.options);
  final String id;
  final String text;

  /// Lowest risk first; answer i scores i + 1.
  final List<String> options;
}

const riskQuestions = [
  RiskQuestion('horizon', 'When might you need most of the money you invest?', [
    'Within a year',
    'In 1 to 3 years',
    'In 3 to 5 years',
    'In 5 to 10 years',
    'Not for 10 years or more',
  ]),
  RiskQuestion('fall', 'Your investments fall 25% in a few months. You would…', [
    'Sell everything',
    'Sell some',
    'Hold, but lose sleep',
    'Hold calmly',
    'Buy more',
  ]),
  RiskQuestion('experience', 'How have you saved or invested before?', [
    'Never',
    'Savings accounts only',
    'A workplace pension',
    'Funds or shares I chose',
    'Years of investing, through falls',
  ]),
  RiskQuestion('goal', 'Which matters most to you?', [
    'Never losing any money',
    'Mostly safety, a little growth',
    'A balance',
    'Mostly growth',
    'The most growth, whatever the swings',
  ]),
];

const riskAnswersKey = 'risk.answers';

class RiskAssessment {
  const RiskAssessment({required this.attitude, required this.capacity, required this.limits});

  /// 1-5 from the questions; null until all are answered.
  final int? attitude;

  /// 1-5: how big a loss the finances could take.
  final int capacity;

  /// Why capacity is below 5.
  final List<String> limits;

  /// The lower of the two: risk the user both wants and can bear.
  int get level => math.min(attitude ?? capacity, capacity);

  RiskProfile get profile => riskProfiles.firstWhere(
    (p) =>
        p.id ==
        switch (level) {
          <= 2 => 'cautious',
          3 => 'balanced',
          4 => 'growth',
          _ => 'adventurous',
        },
  );

  static const levels = ['Safety first', 'Cautious', 'Balanced', 'Growth', 'Adventurous'];
  String get label => levels[level - 1];
}

RiskAssessment assessRisk(Situation s, Map<String, int> answers) {
  int? attitude;
  final scores = [
    for (final q in riskQuestions)
      if (answers[q.id] case final a? when a >= 0 && a < q.options.length) a + 1,
  ];
  if (scores.length == riskQuestions.length) {
    final mean = scores.reduce((a, b) => a + b) / scores.length;
    // Money needed soon cannot ride out a fall, whatever the appetite.
    attitude = math.min(mean.round(), scores.first).clamp(1, 5);
  }
  var capacity = 5;
  final limits = <String>[];
  void cap(int n, String why) {
    if (n < capacity) capacity = n;
    limits.add(why);
  }

  final m = s.metrics;
  final em = m.emergencyMonths;
  if (em == null) {
    cap(3, 'Not enough history yet to know your spending');
  } else if (em < 1) {
    cap(1, 'Cash covers under a month of essentials');
  } else if (em < 3) {
    cap(2, 'Cash covers under 3 months of essentials');
  } else if (em < 6) {
    cap(4, 'Cash covers under 6 months of essentials');
  }
  final sr = m.savingsRate;
  if (sr != null && sr < 0) {
    cap(1, 'Spending more than you earn');
  } else if (sr != null && sr < 0.05) {
    cap(3, 'Little left over each month');
  }
  if (s.expensiveDebt.isNotEmpty) cap(2, 'Debt at 10% interest or more');
  final unsecured = s.debts.where((d) => d.subtype != 'mortgage').fold(0, (t, d) => t + d.value);
  if (m.monthlyIncome > 0 && unsecured > m.monthlyIncome * 12 * 0.4) {
    cap(2, 'Loans and cards above 40% of yearly income');
  }
  return RiskAssessment(attitude: attitude, capacity: capacity, limits: limits);
}

/// A finding with a severity: good | info | warn | action.
class RiskCheck {
  const RiskCheck(this.id, this.title, this.body, this.severity, {this.ask});
  final String id;
  final String title;
  final String body;
  final String severity;

  /// A question to put to the assistant about it.
  final String? ask;
}

String _gbp(int minor, String base) {
  final whole = (minor / 100).round().abs();
  final s = whole.toString().replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (_) => ',');
  return '${minor < 0 ? '-' : ''}${base == 'GBP' ? '£' : '$base '}$s';
}

List<RiskCheck> riskChecks(Situation s, {double? cpi}) {
  final out = <RiskCheck>[];
  final m = s.metrics;
  final em = m.emergencyMonths;
  if (em != null) {
    out.add(
      em >= 3
          ? RiskCheck(
              'emergency',
              'Emergency fund in place',
              '${em.toStringAsFixed(1)} months of essentials in cash.',
              'good',
            )
          : RiskCheck(
              'emergency',
              'Emergency fund is thin',
              'Cash covers ${em.toStringAsFixed(1)} months of essentials; aim for 3 to 6 before investing.',
              'action',
              ask: 'How do I build a 3 to 6 month emergency fund fastest and where should I keep it?',
            ),
    );
  }
  final pricey = s.expensiveDebt;
  if (pricey.isNotEmpty) {
    for (final d in pricey) {
      out.add(
        RiskCheck(
          'debt/${d.name}',
          'Clear ${d.name}',
          '${_gbp(d.value, s.base)} at ${d.rate == null ? 'card rates (about 20%)' : '${d.rate}%'}: '
              'repaying it is a guaranteed return no safe investment matches.',
          'action',
          ask: 'Should I pay off my ${d.rate ?? 20}% debt before saving or investing, and how fast?',
        ),
      );
    }
  } else if (s.debts.isNotEmpty) {
    out.add(
      const RiskCheck('debt', 'No high-interest debt', 'Every debt recorded is under 10% a year.', 'good'),
    );
  }
  final cu = m.creditUtilisation;
  if (cu != null && cu > 0.3) {
    out.add(
      RiskCheck(
        'utilisation',
        'Cards ${(cu * 100).round()}% used',
        'Above 30% of limits can lower your credit score.',
        'warn',
      ),
    );
  }
  if (s.uk) {
    final byBank = <String, int>{};
    for (final h in s.holdings.where((h) => h.isCash && (h.institution ?? '').trim().isNotEmpty)) {
      byBank.update(h.institution!.trim(), (v) => v + h.value, ifAbsent: () => h.value);
    }
    for (final MapEntry(key: bank, value: v) in byBank.entries) {
      if (v > UkRates.fscsLimit) {
        out.add(
          RiskCheck(
            'fscs/$bank',
            'Over the protection limit at $bank',
            '${_gbp(v, s.base)} held; the FSCS protects ${_gbp(UkRates.fscsLimit, s.base)} per person per '
                'banking licence. Brands can share a licence.',
            'warn',
            ask: 'How should I spread savings above the FSCS limit across banks?',
          ),
        );
      }
    }
  }
  if (cpi != null) {
    for (final h in s.holdings.where((h) => h.isCash && h.rate != null && h.value >= 100000)) {
      if (h.rate! < cpi) {
        out.add(
          RiskCheck(
            'real/${h.name}',
            '${h.name} loses to inflation',
            'Pays ${h.rate}% while prices rise $cpi% a year.',
            'warn',
            ask: 'My savings earn ${h.rate}% and inflation is $cpi%. What are the safest better options?',
          ),
        );
      }
    }
  }
  if (s.invested > 0 && em != null && em < 3) {
    out.add(
      const RiskCheck(
        'forced_sale',
        'Investing without a cushion',
        'A surprise bill could force you to sell investments after a fall.',
        'warn',
      ),
    );
  }
  final top = s.topHolding;
  if (top != null && top.share > 0.2) {
    out.add(
      RiskCheck(
        'concentration',
        '${top.name} is ${(top.share * 100).round()}% of investments',
        'One holding above 20% ties your results to it. A global index fund spreads this.',
        'warn',
      ),
    );
  }
  final crypto = s.byClass['crypto'] ?? 0;
  if (s.invested > 0 && crypto * 10 > s.invested) {
    out.add(
      RiskCheck(
        'crypto',
        'Crypto is ${(crypto * 100 / s.invested).round()}% of investments',
        'Crypto can lose most of its value and has no FSCS protection; many keep it under 5%.',
        'warn',
      ),
    );
  }
  return out;
}

class StressTest {
  const StressTest(this.title, this.body, this.severity);
  final String title;
  final String body;
  final String severity;
}

/// What three common shocks would do.
List<StressTest> stressTests(Situation s) {
  final m = s.metrics;
  final em = m.emergencyMonths;
  // Typical peak-to-trough falls in a bad year.
  const falls = {
    'equity': 0.3,
    'crypto': 0.6,
    'property': 0.2,
    'commodity': 0.2,
    'bond': 0.1,
    'alternative': 0.15,
  };
  final loss = s.byClass.entries.fold(0.0, (t, e) => t + e.value * (falls[e.key] ?? 0)).round();
  final variable = s.debts.where((d) => d.subtype != 'credit_card').fold(0, (t, d) => t + d.value);
  final extra = variable ~/ 100 ~/ 12;
  return [
    StressTest(
      'Income stops',
      em == null
          ? 'Not enough history to tell how long cash would last.'
          : 'Cash would cover ${em.toStringAsFixed(1)} months of essentials.',
      em == null
          ? 'info'
          : em < 3
          ? 'action'
          : em < 6
          ? 'warn'
          : 'good',
    ),
    StressTest(
      'Markets fall sharply',
      loss == 0
          ? 'No market investments recorded.'
          : 'Shares down 30%, crypto 60%, bonds 10% would cost about ${_gbp(loss, s.base)}'
                '${m.netWorth > 0 ? ', ${(loss * 100 / m.netWorth).round()}% of net worth' : ''}.',
      loss == 0 || m.netWorth <= 0 || loss * 4 < m.netWorth ? 'good' : 'warn',
    ),
    StressTest(
      'Rates rise 1 point',
      variable == 0
          ? 'No loans or mortgage recorded.'
          : 'If your loans and mortgage were on variable rates, about ${_gbp(extra, s.base)} more a month.',
      variable == 0 || m.monthlyIncome <= 0 || extra * 20 < m.monthlyIncome ? 'good' : 'warn',
    ),
  ];
}

/// done | now | next. Steps 6 and 7 are never finished: "ongoing" once
/// the user has the right accounts.
class PlanStep {
  const PlanStep(this.id, this.title, this.body, this.state, {this.gap, this.options = const [], this.ask});
  final String id;
  final String title;
  final String body;
  final String state;

  /// How much is still needed, base currency.
  final int? gap;

  /// Investment option ids, safest first.
  final List<String> options;
  final String? ask;
}

/// The current UK rate behind an option, for showing next to it.
String? currentRate(String optionId) => switch (optionId) {
  'easy_access' => 'top easy access ${UkRates.bestEasyAccess.toStringAsFixed(2)}%',
  'fixed_savings' => 'top 1-year fix ${UkRates.bestOneYearFix.toStringAsFixed(2)}%',
  'cash_isa' => 'top 1-year fixed ISA ${UkRates.bestOneYearFixIsa.toStringAsFixed(2)}%, tax-free',
  'premium_bonds' => 'prize rate ${UkRates.premiumBondsPrize.toStringAsFixed(2)}%, tax-free',
  _ => null,
};

/// The lowest-risk order to use money: each step protects the next. Options
/// are filtered to the user's tax system.
List<PlanStep> buildPlan(Situation s, RiskAssessment r) {
  final m = s.metrics;
  final need = s.need;
  bool fits(String id) => s.uk || optionById(id).region == 'any';
  List<String> pick(List<String> ids) => ids.where(fits).toList();
  final raw = <(String, String, String, bool?, int?, List<String>, String?)>[];

  final sr = m.savingsRate;
  final short = m.monthlySpend - m.monthlyIncome;
  raw.add((
    'budget',
    'Spend less than you earn',
    sr == null
        ? 'Add a few months of transactions to see this.'
        : short > 0
        ? 'You spend ${_gbp(short, s.base)} a month more than you earn. Start with regular payments.'
        : 'You keep ${(sr * 100).round()}% of income. Everything below builds on this.',
    sr == null ? null : short <= 0,
    short > 0 ? short : null,
    const [],
    'Where can I cut ${_gbp(math.max(short, 0), s.base)} a month from my spending?',
  ));

  final pricey = s.expensiveDebt;
  final owed = pricey.fold(0, (t, d) => t + d.value);
  raw.add((
    'debt',
    'Clear debt above 10% interest',
    owed == 0
        ? 'None recorded.'
        : '${_gbp(owed, s.base)} owed. Highest rate first; a 0% balance transfer can stop the interest.',
    owed == 0,
    owed == 0 ? null : owed,
    const [],
    'What is the fastest safe way to clear ${_gbp(owed, s.base)} of high-interest debt?',
  ));

  final liquid = m.liquid;
  raw.add((
    'starter',
    'Keep one month in cash',
    need == 0 ? 'Add spending to size this.' : 'A starter cushion of ${_gbp(need, s.base)} for surprises.',
    need == 0 ? null : liquid >= need,
    need > liquid ? need - liquid : null,
    pick(['easy_access']),
    null,
  ));

  final pension = s.has('pension');
  raw.add((
    'match',
    'Take any employer pension match',
    pension
        ? 'Pension recorded. Check you pay enough to get the full match: it is an instant return.'
        : 'If your employer matches contributions, that is free money with tax relief on top.',
    // Unknown without a pension: not everyone has an employer.
    pension ? true : null,
    null,
    pick(['pension']),
    'How does an employer pension match work and how much should I pay in?',
  ));

  final target = need * 6;
  raw.add((
    'emergency',
    'Build 3 to 6 months of essentials',
    need == 0
        ? 'Add spending to size this.'
        : 'Target ${_gbp(target, s.base)}, kept where it cannot fall in value and comes back fast.',
    need == 0 ? null : liquid >= target,
    need > 0 && target > liquid ? target - liquid : null,
    pick(['easy_access', 'premium_bonds', 'cash_isa']),
    'Where is the safest place for my emergency fund with the best rate right now?',
  ));

  final saverAccounts = s.has('savings') || s.has('isa_cash');
  raw.add((
    'goals',
    'Money for the next 1 to 5 years',
    'Do not put it in shares. Fix a rate for as long as you can wait, inside an ISA where possible.',
    saverAccounts ? null : false,
    null,
    pick(['fixed_savings', 'cash_isa', 'gilts']),
    'I need money in 2 to 3 years. Fixed savings, cash ISA or short-dated gilts?',
  ));

  final p = r.profile;
  final mix = p.targets.entries
      .map((e) => '${e.value ~/ 100}% ${assetClasses[e.key]?.toLowerCase()}')
      .join(', ');
  raw.add((
    'invest',
    'Invest for 5+ years',
    r.level <= 1
        ? 'Not yet: finish the steps above first. Your finances cannot take a fall right now.'
        : 'Your mix: ${p.label} ($mix). A low-cost global index fund, paid in monthly, '
              'spreads risk across thousands of companies.',
    s.invested > 0 && (s.has('isa_stocks') || s.has('pension')) ? null : false,
    null,
    pick(['isa_stocks', 'global_index', 'bond_index', if (s.uk) 'lisa']),
    'For a ${p.label.toLowerCase()} investor, how should I start investing for 5+ years?',
  ));

  // The first unfinished step is the one to work on; unknown ones wait.
  var now = false;
  final out = <PlanStep>[];
  for (final (id, title, body, done, gap, options, ask) in raw) {
    var state = 'next';
    if (done == true) {
      state = 'done';
    } else if (done == null && (id == 'goals' || id == 'invest')) {
      state = 'ongoing';
    } else if (id == 'invest' && r.level <= 1) {
      state = 'next';
    } else if (done == false && !now) {
      state = 'now';
      now = true;
    }
    out.add(PlanStep(id, title, body, state, gap: gap, options: options, ask: ask));
  }
  return out;
}
