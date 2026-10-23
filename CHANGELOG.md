# Changelog

## Unreleased

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
