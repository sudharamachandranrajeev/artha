/// Places money can go, for the Explore screen and for suggestions. Plain
/// descriptions, not recommendations: the app shows "not financial advice"
/// next to anything drawn from here.
library;

import 'package:brahma_core/brahma_core.dart' show daysBetween;

class InvestmentOption {
  const InvestmentOption({
    required this.id,
    required this.name,
    required this.assetClass,
    required this.risk,
    required this.access,
    required this.summary,
    required this.watchOut,
    this.region = 'any',
  });
  final String id;
  final String name;
  final String assetClass;

  /// 1 (capital very stable) .. 7 (can lose most of it), like a fund's SRRI.
  final int risk;

  /// How quickly money comes back: instant | days | fixed term | retirement.
  final String access;
  final String summary;
  final String watchOut;

  /// ISO country code when the option is specific to one tax system.
  final String region;
}

/// UK allowances for the 2026/27 tax year (6 April 2026 - 5 April 2027).
/// Review each April; the app labels them with the tax year they belong to.
class UkAllowances {
  static const taxYear = '2026/27';
  static const isa = 2000000; // pence
  static const lisa = 400000; // counts towards the ISA allowance
  static const premiumBondsMax = 5000000;
  static const pensionAnnual = 6000000;
}

/// Best-buy rates and rules checked on [asOf], with where they came from.
/// Bank Rate and CPI are fetched live (see world.dart); these are not, so the
/// app shows their date and flags them when they get old.
class UkRates {
  static const asOf = '2026-10-24';
  static const bestEasyAccess = 5.00; // AER, includes an introductory bonus
  static const bestOneYearFix = 5.15;
  static const bestOneYearFixIsa = 5.00;
  static const premiumBondsPrize = 4.35; // prize fund rate, tax-free
  static const premiumBondsOdds = '21,000 to 1';
  static const fscsLimit = 12000000; // pence, per person per banking licence
  static const cashIsaFrom = '2027-04-06';
  static const cashIsaUnder65 = 1200000; // pence a year from [cashIsaFrom]
  static const nextRateDecision = '2026-11-05';
  static const sources = [
    ('Moneyfacts best buys, 23 Oct 2026', 'https://moneyfactscompare.co.uk/savings-accounts/'),
    ('NS&I Premium Bonds', 'https://www.nsandi.com/products/premium-bonds'),
    ('FSCS deposit protection', 'https://www.fscs.org.uk/check/check-your-money-is-protected/'),
    ('Cash ISA changes from April 2027', 'https://www.gov.uk/individual-savings-accounts'),
    (
      'Bank of England Bank Rate',
      'https://www.bankofengland.co.uk/monetary-policy/the-interest-rate-bank-rate',
    ),
  ];

  /// More than two months old: rates move, so say so.
  static bool stale(String today) => daysBetween(today, asOf) > 60;
}

/// First day of the UK tax year containing [iso] (yyyy-MM-dd).
String ukTaxYearStart(String iso) {
  final y = int.parse(iso.substring(0, 4));
  return iso.compareTo('$y-04-06') >= 0 ? '$y-04-06' : '${y - 1}-04-06';
}

const investmentOptions = [
  InvestmentOption(
    id: 'easy_access',
    name: 'Easy-access savings',
    assetClass: 'cash',
    risk: 1,
    access: 'instant',
    summary: 'Variable interest, withdraw any time. The usual home for an emergency fund.',
    watchOut:
        'Rates change without notice; compare against inflation. Deposit protection has a per-bank limit.',
  ),
  InvestmentOption(
    id: 'fixed_savings',
    name: 'Fixed-term savings',
    assetClass: 'cash',
    risk: 1,
    access: 'fixed term',
    summary: 'A fixed rate for 1-5 years in exchange for locking the money away.',
    watchOut: 'Usually no access before the term ends.',
  ),
  InvestmentOption(
    id: 'cash_isa',
    name: 'Cash ISA',
    assetClass: 'cash',
    risk: 1,
    access: 'instant',
    summary: 'Savings interest free of UK tax, within the yearly ISA allowance.',
    watchOut: 'Counts towards the shared ISA allowance; check the transfer rules before moving providers.',
    region: 'GB',
  ),
  InvestmentOption(
    id: 'premium_bonds',
    name: 'Premium Bonds (NS&I)',
    assetClass: 'cash',
    risk: 1,
    access: 'days',
    summary: 'Government-backed; instead of interest, monthly tax-free prize draws.',
    watchOut: 'Returns vary with luck; small holdings often win nothing for months.',
    region: 'GB',
  ),
  InvestmentOption(
    id: 'money_market',
    name: 'Money market fund',
    assetClass: 'cash',
    risk: 2,
    access: 'days',
    summary: 'Pools very short-term loans to governments and banks; tracks the central bank rate.',
    watchOut: 'An investment, not a deposit: no deposit protection. Mind the fund charge.',
  ),
  InvestmentOption(
    id: 'gilts',
    name: 'Government bonds (gilts / treasuries)',
    assetClass: 'bond',
    risk: 2,
    access: 'days',
    summary: 'Lending to a government for a fixed term; known return if held to maturity.',
    watchOut: 'Prices move with interest rates if sold early.',
  ),
  InvestmentOption(
    id: 'bond_index',
    name: 'Global bond index fund',
    assetClass: 'bond',
    risk: 3,
    access: 'days',
    summary: 'Thousands of bonds in one fund; usually steadier than shares.',
    watchOut: 'Can fall when interest rates rise; prefer currency-hedged versions for stability.',
  ),
  InvestmentOption(
    id: 'global_index',
    name: 'Global shares index fund',
    assetClass: 'equity',
    risk: 5,
    access: 'days',
    summary: 'Low-cost tracker of thousands of companies worldwide; the core of most long-term portfolios.',
    watchOut: 'Can fall 30-50% in a bad year; suits money left for 5+ years.',
  ),
  InvestmentOption(
    id: 'isa_stocks',
    name: 'Stocks & Shares ISA',
    assetClass: 'equity',
    risk: 4,
    access: 'days',
    summary: 'A tax wrapper: growth and income inside it are free of UK tax.',
    watchOut: 'The wrapper is tax-free, the investments inside still carry their own risk.',
    region: 'GB',
  ),
  InvestmentOption(
    id: 'lisa',
    name: 'Lifetime ISA',
    assetClass: 'equity',
    risk: 4,
    access: 'retirement',
    summary: 'Government adds 25% to savings for a first home or for age 60+.',
    watchOut: 'Open between 18 and 39; withdrawing for anything else costs a 25% charge.',
    region: 'GB',
  ),
  InvestmentOption(
    id: 'pension',
    name: 'Workplace pension / SIPP',
    assetClass: 'equity',
    risk: 4,
    access: 'retirement',
    summary:
        'Tax relief on contributions, often an employer match: typically the strongest long-term return.',
    watchOut: 'Locked until minimum pension age; check the employer match before anything else.',
    region: 'GB',
  ),
  InvestmentOption(
    id: 'reit',
    name: 'Property funds / REITs',
    assetClass: 'property',
    risk: 5,
    access: 'days',
    summary: 'Rental property exposure without buying a building.',
    watchOut: 'Sensitive to interest rates; some property funds suspend withdrawals in stress.',
  ),
  InvestmentOption(
    id: 'gold',
    name: 'Gold (ETC)',
    assetClass: 'commodity',
    risk: 5,
    access: 'days',
    summary: 'Often moves differently from shares; a small diversifier.',
    watchOut: 'Pays no income; long flat periods are common.',
  ),
  InvestmentOption(
    id: 'fx_account',
    name: 'Multi-currency account',
    assetClass: 'cash',
    risk: 1,
    access: 'instant',
    summary: 'Hold and send foreign currency at near-market rates; useful for family support abroad.',
    watchOut: 'Check whether balances are deposit-protected or only safeguarded.',
  ),
  InvestmentOption(
    id: 'crypto',
    name: 'Cryptoassets',
    assetClass: 'crypto',
    risk: 7,
    access: 'days',
    summary: 'Highly speculative; some keep a very small share for upside.',
    watchOut: 'Can lose most of its value; scams are common; little regulatory protection.',
  ),
  InvestmentOption(
    id: 'p2p',
    name: 'Peer-to-peer lending (IF ISA)',
    assetClass: 'alternative',
    risk: 6,
    access: 'fixed term',
    summary: 'Lending to people or businesses for higher interest.',
    watchOut: 'Borrowers default and platforms fail; not deposit-protected.',
    region: 'GB',
  ),
];

InvestmentOption optionById(String id) => investmentOptions.firstWhere((o) => o.id == id);
