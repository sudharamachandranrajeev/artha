/// Artha's hints, by id, on top of the shared ones (coreHints). Tooltips use
/// the short ones; page banners (ids starting `page.`) explain a whole screen
/// once.
const arthaHints = <String, String>{
  // Navigation
  'nav.dashboard': 'Net worth, cash flow and what needs attention, at a glance.',
  'nav.accounts': 'Bank accounts, cards, savings, ISAs, investments and loans.',
  'nav.transactions': 'Every transaction. Add, edit, split and search them here.',
  'nav.portfolio': 'What your investments are worth, how they are spread and how to rebalance.',
  'nav.insights': 'Patterns in your money, and options worth exploring.',
  'nav.reports': 'Balance sheet, income statement, trial balance and checks.',
  'nav.import': 'Bring in bank statements (PDF, CSV, OFX, QFX, QIF).',
  'nav.settings': 'Currency, hints, exchange rates, sync and security.',
  // Dashboard
  'kpi.networth': 'Everything you own minus everything you owe, in your base currency.',
  'kpi.liquid': 'Money you can use within days: current, savings, cash and cash ISAs.',
  'kpi.debt': 'Cards, loans, overdrafts and mortgages still owed.',
  'kpi.savings': 'Share of income left after spending, averaged over recent full months.',
  'kpi.emergency': 'How many months of essential spending your easy-access money covers.',
  'chart.networth': 'Net worth at the end of each month. Hover or touch a point for the figure.',
  'chart.flows': 'Income and spending per month. Hover or touch a bar for the figures.',
  'card.tally': 'Ledger balance compared with the last statement balance you recorded.',
  'card.attention': 'The most useful insights right now. Open Insights for all of them.',
  'card.missing': 'These hold value but have no exchange rate or price yet, so totals leave them out.',
  // Accounts
  'accounts.add': 'Add a bank account, card, savings, ISA, investment, property or loan.',
  'accounts.balance': 'Statement balance check: record what the bank says to see if the ledger agrees.',
  'accounts.closed': 'Closed accounts keep their history but take no new transactions.',
  // Transactions
  'tx.add': 'Record spending, income, a transfer or a trade.',
  'tx.search': 'Search payee and notes.',
  'tx.kind': 'Spending and income use a category; a transfer moves money between your own accounts.',
  'tx.toAmount': 'Amount that arrived, in the receiving account’s currency. Sets the exchange rate.',
  'tx.split': 'Entries with more than two lines, and trades, open read-only.',
  // Import
  'import.pick': 'Choose a statement file. Nothing leaves this device.',
  'import.status': 'New rows are added; duplicates are skipped; matches link to entries you typed or imported from another file; transfers merge with the other account.',
  'import.category': 'Suggested from your rules and past choices. Change it and Artha learns.',
  'import.separate': 'Not the same payment? Add this row as a new entry instead of linking it.',
  // Portfolio
  'portfolio.profile': 'Pick how much ups and downs you can live with. It sets the target mix.',
  'portfolio.drift': 'How far each asset class is from its target. Flags use the 5/25 rule.',
  'portfolio.newMoney': 'Splits new money towards the targets without selling anything.',
  'portfolio.trade': 'Record a buy or sell of a fund, share, bond or crypto.',
  'portfolio.price': 'Record today’s price of a holding to value it.',
  // Insights
  'insights.useful': 'Keep insights like this one higher up.',
  'insights.dismiss': 'Hide this one and show fewer like it.',
  'settings.world': 'Public downloads only: Bank Rate, inflation and news headlines.',
  'settings.assistant': 'Optional. Uses your own Anthropic API key, kept in the system keychain.',
  'insights.ask': 'Ask a money question; answers use the web and your own Anthropic key.',
  'insights.remember': 'Tell Artha about a goal or a coming cost so suggestions fit.',
  'risk.profile':
      'Your level is the lower of how much risk you are comfortable with and how much your finances can '
      'absorb. Cash cushion, debt and spare income all count.',
  'insights.world': 'News and rates from the Bank of England, ONS, HMRC, the FCA and consumer-money sites.',
  'insights.explore': 'Common ways to save and invest in the UK, with their trade-offs.',
  // Reports
  'reports.period': 'Period the income statement covers.',
  'reports.integrity': 'Checks that every entry balances and points at a real account.',
  // Settings
  'settings.fx': 'Fetch European Central Bank reference rates for the currencies you use.',
  'settings.base': 'Totals, charts and reports are shown in this currency.',
  'settings.appearance': 'Pick a colour palette and light or dark. Kept on this device, never synced.',
  'card.forecast':
      'Where your spendable money is heading if bills, pay and everyday spending carry on as they have, '
      'plus the one-offs you plan (dots on the line).',
  'card.budgets': 'This month’s spending against the monthly budget you set for each category.',
  'card.bills': 'Payments that repeat on a steady schedule, with the date each is next expected.',
  // Page banners
  'page.dashboard':
      'This is your financial overview. Add accounts and import a statement, and the charts fill in. '
      'Hover or long-press anything for a tip.',
  'page.accounts':
      'Each account keeps its own currency. Record a statement balance now and then: the tick shows '
      'when the ledger agrees with the bank.',
  'page.transactions':
      'Artha uses double-entry bookkeeping behind the scenes: every amount leaves one account and '
      'lands in another, so the books always balance.',
  'page.import':
      'Choose a PDF statement or an export (CSV, OFX, QFX, QIF). PDFs are matched to their account by '
      'number, or a new account is made, and only import when their own balances add up. Pick several '
      'PDFs to import a whole period; the account page shows where its balances tally. Artha spots '
      'duplicates, matches entries you typed and merges both sides of transfers.',
  'page.portfolio':
      'Holdings are valued with the latest price you recorded and today’s exchange rates. '
      'Targets drive the rebalancing and new-money suggestions.',
  'page.insights':
      'Insights are worked out on this device from your own data. Mark them useful or not and the '
      'list adapts. Nothing here is financial advice.',
  'page.risk':
      'Worked out on this device from your accounts. The plan puts safety first: spend less than you earn, '
      'clear expensive debt, hold a cash cushion, then invest for the long term.',
  'page.reports':
      'Business-standard statements from the same ledger. The trial balance must net to zero in '
      'every currency; the integrity check confirms it.',
  'page.budgets':
      'Give a category a monthly limit and Artha tracks this month’s spending against it, in your '
      'base currency. Insights warn when one goes over.',
  'page.rules':
      'Imports try these rules first, top to bottom: the first whose text appears in a description '
      'picks the category and can give the payee a tidier name. Spending categories catch money '
      'out, income categories money in.',
  'page.recurring':
      'Bills and subscriptions: the ones Artha spots in your history and the ones you add. They feed '
      'Upcoming bills and the 90-day forecast. Hide a spotted one that is not really a bill.',
  'tx.review':
      'Imported entries wait here until you have looked at them. Select some to set their category '
      'or mark them reviewed; on a keyboard, arrows move and R marks the current one.',
};
