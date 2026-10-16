# Artha

Personal finance, accounting and investment manager for Linux, Windows 11 and Android.
First module of a wider life-management system.

Status: beta, for testing on Linux, Windows and Android. Built with Flutter 3.47.7; local data in an encrypted SQLite
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

## Install a test build

Builds are on the [releases page](https://github.com/sudharamachandranrajeev/artha/releases)
(the repository is private, so sign in first). Each release has `SHA256SUMS.txt`.

- **Linux (x86-64):** unpack `Artha-<version>-linux-x64.tar.gz` and run `./install.sh`. It
  installs for your user only (`~/.local/lib/artha`, a menu entry and `artha` on the PATH);
  `./install.sh --uninstall` removes it. Needs GTK 3, libsecret and a running keyring. From a
  checkout: `flutter build linux --release && scripts/install-linux.sh`.
- **Windows 10/11:** run `Artha-<version>-windows-x64-setup.exe` (no admin rights needed), or
  unzip the portable build anywhere. Windows SmartScreen warns because the build is not
  code-signed: *More info > Run anyway*.
- **Android 7+:** install `Artha-<version>-android.apk` (allow installs from your browser or
  file manager when asked). Updates install over the top, keeping your data.

Your data stays on the device, encrypted, until you turn on sync. Uninstalling does not delete
it on Linux or Windows (`~/.local/share/dev.artha.artha`, `%APPDATA%\Artha`); on Android it
goes with the app, so sync first.

To try sync between devices, run a server on your own network:
`ARTHA_PB_HOST=0.0.0.0 scripts/run-local-server.sh`, then in Artha choose *Settings > Sync >
Create account* with the address it prints and the invite code from `server/.env`. Other devices
use *Sign in*. Plain `http://` works only for private addresses (home network, Tailscale);
anything public needs HTTPS, see [server/README.md](server/README.md).

## Develop

```sh
flutter pub get
flutter run -d linux
```

## Test

```sh
flutter analyze && flutter test
```

The live tests (`test/*live_test.dart`) also run against a real sync server when one is
configured; see [server/README.md](server/README.md). CI runs everything, including those, on each
push; a `v*` tag builds, smoke-tests and publishes the Android, Windows and Linux builds
(`.github/workflows/release.yml`). `scripts/make-icons.sh` regenerates the app icons from
`branding/artha.svg`.

## Sync server

Self-hosted PocketBase with end-to-end encryption: setup, HTTPS, recovery and limits are in
[server/README.md](server/README.md). For development, run `scripts/run-local-server.sh`.
