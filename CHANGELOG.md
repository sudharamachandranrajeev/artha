# Changelog

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
