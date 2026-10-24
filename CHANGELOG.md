# Changelog

## 0.2.0-beta.13

- Insights: "The world this week" shows the live Bank of England Bank Rate and ONS inflation,
  quick tips that fit your accounts (inflation against your savings, the next rate decision, the
  31 January Self Assessment deadline, the cash ISA limit falling to £12,000 in April 2027,
  Premium Bonds, deposit protection) and the headlines most relevant to you, ranked by what you
  hold or owe, from the Bank of England, FCA, HMRC, MoneySavingExpert and BBC Business. Only
  public pages are downloaded, at most every 6 hours when you open Insights; nothing about you is
  sent. Switch it off in Settings → News and rates.
- Risk and safest plan: four questions set how much risk you are comfortable with, your
  finances set how much you can take, and the lower one is your level. Risk checks (thin
  emergency fund, debt at 10%+, cash above the £120,000 FSCS limit at one bank, savings losing to
  inflation, one holding above 20%, crypto above 10%), three stress tests (income stops, markets
  fall, rates rise 1 point) and a safety-first plan: spend less than you earn, clear expensive
  debt, one month in cash, the employer pension match, a 3-6 month emergency fund, money for 1-5
  years, then a global index fund for 5+ years. Each step lists the lowest-risk options first
  with current UK best-buy rates, dated.
- Ask Artha: ask a money question in the app and get a short, sourced answer from Claude with web
  search, using your own Anthropic API key (Settings → Ask Artha; billed to your Anthropic
  account). The key stays in the system keychain, never in the database or sync. Each question
  sends a rounded summary (no payees, account names or numbers) which you can read under the eye
  icon. Questions can also start from a tip, a headline, a risk check or a plan step. If Claude
  declines a request, the API retries it on a fallback model.

## 0.2.0-beta.12

- Review queue: imported entries wait under Transactions → "To review" until you have looked at
  them, and the dashboard says how many. Tick several to set their category or mark them
  reviewed in one go; on a keyboard, arrows move, R marks the current one, Space selects and
  Enter opens it. Saving an entry in the editor also marks it reviewed.
- Payee renaming: a rule can give a payee a tidier name ("AMZN MKTP UK*2X4" → Amazon), with or
  without a category. Imports apply it, and the rules page applies it to what is already
  recorded; the bank's own text moves to the memo, so search and rules still find it.
- Bills and subscriptions page (dashboard → Upcoming bills → Manage, or Insights): add a monthly
  (or weekly, quarterly, yearly) subscription by hand and it shows in Upcoming bills and the
  forecast straight away. Edit or delete your own, hide spotted ones that are not really bills,
  or edit a spotted one to keep it as your own. A fixed price that changed is flagged, and the
  new price is the one expected.
- The database moves to schema 2 (review flag, rename rules, recurring items); existing data is
  kept.

## 0.2.0-beta.11

- Cash-flow forecast on the dashboard: spendable money day by day for the next 90 days, from
  recurring pay and bills on their schedule plus everyday spending spread evenly. It shows the
  lowest point and warns when money would run short; one-off income is left out, so it errs low.
- Make a rule from an import row: the rule icon beside a new row's category saves "first word →
  that category", and the other new rows it catches are filed straight away.
- Fixes: overdue bills said "Due in N days"; monthly recurring amounts were counted 1.4% high.

## 0.2.0-beta.10

- Categorisation rules: Import → rules lists text to look for and the category it files into,
  tried top to bottom before learned history. Add, edit, reorder and delete them, and sort
  every uncategorised entry that matches in one go. Spending rules only catch money out and
  income rules only money in.

## 0.2.0-beta.9

- Overlapping imports no longer double-count: a statement row that matches an entry already
  imported from another file (a CSV export and the PDF for the same month, say) is linked to it
  instead of copied, matching the same day first and then up to three days apart. "Keep
  separate" on a matched row adds it as a new entry instead.
- Add a standalone Linux installer with authenticated release downloads, checksum checks,
  dependency setup for Ubuntu/Debian, Fedora, Arch and Omarchy, and safe updates and removal.
- Add beginner installation and quick-start guides, plus a browser feasibility and Hetzner
  hosting assessment.

## 0.2.0-beta.6

- Lloyds credit card statements import: the card-ending column, a second "date entered", payments
  listed before purchases and a statement that prints only its date are all read, and the card is
  recognised by its last four digits rather than the bank's payment account.

## 0.2.0-beta.5

- Statements can arrive month by month, in any order, or all at once: choose several PDFs in
  one go and Artha merges them, orders them, checks each opens where the one before closed and
  reports any month that is missing. Every balance a statement prints is kept as a check, so an
  account's page shows whether the ledger agrees with each statement and where it first stops
  agreeing. An earlier statement imported later moves the opening balance back to its start.

## 0.2.0-beta.4

- Import PDF statements from UK banks and card issuers. Artha reads the transaction table by its
  column headings, recognises the account from its sort code and account number (or card
  digits), and creates the account when none matches. Every row is checked against the
  statement's own running balance, opening and closing balances and totals; a statement that
  does not add up is not imported. Scanned PDFs without text are refused.

## 0.2.0-beta.3

- Buttons have depth: a soft shadow (an accent glow on filled ones) that lifts on hover and
  sinks on press, with a light sheen from the top edge.
- Monthly budgets per expense category (Dashboard > Budgets): spending this month against each
  limit, with what is left or how far over.
- Upcoming bills on the Dashboard: each recurring payment's next expected date, soonest first.
  The upcoming-bills total no longer counts recurring income.

## 0.2.0-beta.2

- Add motion: pages slide and fade forwards when opened, tabs fade in when switched,
  page cards fade up in a short stagger, and loading states cross-fade to content.
  All of it stops when the system asks for reduced motion.

## 0.2.0-beta.1

- Pair devices from Settings with a QR code or link and a matching verification code.
  New devices can join a signed-in account without entering its password.
- Use the shared Brahma core for encrypted storage, sync, account management and common UI.
- Share the pinned PocketBase version and checksums between local startup and Docker builds.
- Require live sync tests and a sync-server container build before packaging a release.
- Redesigned the interface after the paper-soft indigo reference (docs/ui-design-map.md):
  grey canvas, borderless white cards, Inter type, indigo and sky accents, pill buttons,
  mock-style dashboard (hero, net-worth chart card with pill badge, savings progress and
  banner, activity and stats cards), account tiles and grouped transaction rows.
- Theme manager in Settings > Appearance: Indigo Paper (the reference), Emerald Classic,
  Ocean and Rose palettes, each with light and dark renderings, plus System/Light/Dark
  mode. The choice is kept per device and applies live.

## 0.1.0-beta.1

First test build for Linux, Windows and Android.

- Double-entry ledger in any mix of currencies, with a base currency for totals.
- Accounts of every kind: current, savings, cards, loans, ISAs, pensions, property, holdings.
- Spending, income, transfers (across currencies at the bank's rate), buys and sells.
- Statement import (CSV, OFX, QIF) with duplicate and transfer matching, and
  statement balances tallied against the ledger.
- Dashboard, reports (balance sheet, income statement, trial balance, cash flow),
  portfolio with allocation targets, and insights that learn from feedback.
- Daily ECB exchange rates (can be turned off).
- Encrypted on the device (SQLite3MultipleCiphers, key in the system keychain).
- Optional sync through your own PocketBase server, end-to-end encrypted, with a
  recovery key.
- Hints on every screen, which can be hidden and brought back in Settings.
