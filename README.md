# Artha

Personal finance, accounting and investment manager for Linux, Windows 11 and Android.
First module of a wider life-management system.

Status: early, usable on Linux. Built with Flutter 3.47.7; local data in an encrypted SQLite
database (SQLite3MultipleCiphers, ChaCha20-Poly1305); login and cross-device sync through a
self-hosted PocketBase server with end-to-end encryption.

What works: accounts in any currency (bank, cards, savings, ISAs, brokerage, crypto, loans),
double-entry transactions and transfers, buys and sells with pooled cost, statement import
(CSV, OFX, QFX, QIF) with duplicate and transfer matching, statement tallies, balance sheet,
income statement and trial balance, a portfolio view with target allocation and rebalancing,
insights that learn from your feedback, hints on every control, light and dark themes.

On Linux the database key lives in the desktop keyring (libsecret), which must be running and
unlocked. If the key is missing while a database exists, Artha stops rather than create a new
key, so the old database stays recoverable.

## Develop

```sh
flutter pub get
flutter run -d linux
```

## Test

```sh
flutter analyze && flutter test
```

`test/pocketbase_live_test.dart` also runs against a real sync server when one is configured; see
[server/README.md](server/README.md).

## Sync server

Self-hosted PocketBase with end-to-end encryption: setup, HTTPS, recovery and limits are in
[server/README.md](server/README.md). For development, run `scripts/run-local-server.sh`.
