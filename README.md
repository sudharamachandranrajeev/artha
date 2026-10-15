# Artha

Personal finance, accounting and investment manager for Linux, Windows 11 and Android.
First module of a wider life-management system.

Status: scaffold. Built with Flutter 3.47.7; local data in an encrypted SQLite database
(SQLite3MultipleCiphers); login and cross-device sync through a self-hosted PocketBase
server with end-to-end encryption.

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
