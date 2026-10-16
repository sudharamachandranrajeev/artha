# Changelog

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
