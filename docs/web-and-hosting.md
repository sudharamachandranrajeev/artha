# Artha in a browser and on Hetzner

Assessment date: 23 October 2026. This is research and an implementation plan, not a deployed
web version. No server has been ordered. Sizing below assumes personal use or a small invited
beta, without large attachments or heavy analytics; it is not a measured user-capacity guarantee.

## Recommendation

Use a **Hetzner Cloud CPX12 in Germany or Finland** for an initial small deployment: 1 shared
vCPU, 2 GB RAM and 40 GB NVMe. Run the existing PocketBase server behind Caddy HTTPS. Later,
serve a compiled Flutter web client from the same machine. Build the client in CI, not on
this small server. Choose **CPX22** if sharing the host with other services or needing more
headroom. Monitor memory, disk growth and sync latency before increasing capacity.

**CX23 would be better value if it becomes available**, but the public cost-optimized page
currently marks it unavailable. Check actual location stock and the checkout total in Hetzner
Console before choosing. Public page availability messages are not a reservation.

## Monthly cost comparison

EU prices in euros, excluding VAT. The last column includes one IPv4 address and Hetzner
server backups; it excludes a domain, SMTP service, separate off-server application backups
and traffic overages. Rounded to cents.

| Plan | vCPU / RAM / NVMe | Server only | With IPv4 | With IPv4 + backups | Fit |
| --- | --- | ---: | ---: | ---: | --- |
| CX23 | 2 / 4 GB / 40 GB | €5.49 | €5.99 | €7.09 | Best value if stock returns |
| CX33 | 4 / 8 GB / 80 GB | €8.49 | €8.99 | €10.69 | More headroom, also currently marked unavailable |
| CAX11 | 2 ARM / 4 GB / 40 GB | €5.99 | €6.49 | €7.69 | ARM alternative; also marked unavailable |
| CPX12 | 1 / 2 GB / 40 GB | €11.49 | €11.99 | €14.29 | Recommended small starting server |
| CPX22 | 2 / 4 GB / 80 GB | €19.49 | €19.99 | €23.89 | More room for multiple services |

Sources: Hetzner's [cost-optimized specifications and availability](https://www.hetzner.com/cloud/cost-optimized/),
[regular-performance specifications and prices](https://www.hetzner.com/cloud/regular-performance/),
and [June 2026 price schedule](https://docs.hetzner.com/general/infrastructure-and-availability/price-adjustment/).
The regular-performance page's HTML lists CPX12 at €11.99 **including IPv4**; subtracting
€0.50 gives the server-only amount. Do not add IPv4 twice. Its rendered price widgets may
depend on location, currency and country settings.

[Primary IPv4 costs €0.50/month](https://docs.hetzner.com/cloud/servers/overview/).
[Backups cost 20% of the server price](https://docs.hetzner.com/cloud/billing/faq/), with seven
slots. Example: CPX12 is €11.49 + €0.50 + (€11.49 × 20%) = €14.29 before VAT.
Billing continues while a server exists, even when powered off. A domain and email delivery
need separate budgeting. Prefer the region nearest your users; the table is not a Singapore
or US price quote.

The 1 GB CPX02 is a possible tiny experiment, but gives less room for database growth,
backups and OS updates. Dedicated CCX or physical servers are unnecessary for this starting
scope. Shared web-hosting S/M/L/XL could serve static files, but is not our recommended home
for the existing PocketBase daemon and persistent SQLite volume. Its documented PHP/CGI
features, and Node.js on higher tiers, do not establish support for our Docker deployment.
See [web-hosting features](https://www.hetzner.com/webhosting/).

## Smallest hosting arrangement

Keep the current single PocketBase instance and local persistent `pb_data` volume. Caddy
serves HTTPS and proxies the sync endpoint. For a browser client, use a static app subdomain
and the HTTPS sync subdomain; restrict CORS to the intended app origin and test it. Keep the
admin interface restricted, preserve invite-only signup, and configure SMTP for recovery.

Use the existing [server deployment guide](../server/README.md) and Docker Compose configuration.
The image supports both amd64 and arm64; the Linux desktop release is separately x86-64 only.
An ARM cloud server therefore does not require an ARM desktop app.

Enable host backups and schedule PocketBase application backups to separate storage. Test a
restore before relying on them. A VM snapshot alone is not proof of a consistent, restorable
live SQLite database. Keep one writer instance; do not put multiple PocketBase processes over
a shared SQLite volume to imitate horizontal scaling. A single VM is also a single point of
failure; higher availability is a later requirement, not part of this initial estimate.

## Can the existing app run on the web?

Yes, with a deliberate port. Merely adding a web folder or running `flutter build web` is not
enough. Finance calculations, report generation, statement parsing and most Flutter widgets
can be reused. The native application currently depends on these boundaries:

| Boundary | Current implementation | Browser work |
| --- | --- | --- |
| Database | `lib/db/database.dart` calls core `openEncryptedDatabase`; `brahma/core/lib/src/db/synced_database.dart` opens native SQLite3MultipleCiphers | A web database implementation; ordinary SQLite WASM does not reproduce native at-rest encryption |
| Device secrets | `brahma/core/lib/src/security/key_vault.dart` uses `FlutterSecureStorage` | Explicit unlock and key-lifetime design; browser storage is not an OS keyring |
| Startup and links | Core `src/app/session.dart` and `src/app/links.dart` use files, platform checks and native channels | Web-safe startup and link handling through existing platform seams |
| Crypto work | Core `src/security/crypto.dart` uses `dart:io` gzip and `dart:isolate` | Compatible compression and key derivation; preserve existing encrypted message format |
| Server validation | Core `src/sync/pocketbase_remote.dart` uses `InternetAddress` | Web-safe URL validation; browser requests must work over HTTPS and CORS |
| Statement selection | `lib/modules/finance/ui/import_page.dart` reads picker bytes | Verify browser file selection, cancellation, file-size limits and parsing |

The shared core paths refer to the sibling Brahma repository, not files inside Artha.
[Drift supports web SQLite through WASM with browser storage options](https://drift.simonbinder.eu/platforms/web/),
so the existing query layer has a viable migration route. Persistent OPFS/IndexedDB storage,
private browsing and multiple-tab behavior still need explicit testing. Browser persistence
must not silently downgrade the current confidentiality guarantee.

## Suggested first web milestone

Start with an **online, read-only browser companion**: sign in, decrypt synced data locally,
then show accounts, balances and reports. Use a session-only in-memory database initially,
keeping keys and plaintext out of persistent browser storage. Require unlocking again after
the session ends. Reuse the current encrypted sync protocol and native finance logic.

Before calling that milestone complete:

1. Separate native and browser startup, database and platform imports in the shared core.
2. Prove existing accounts can decrypt their data in Chrome, Firefox and Safari, including
   key derivation and compression compatibility. Measure unlock time on a low-power phone.
3. Verify refresh, logout, expired sessions and multiple tabs do not persist plaintext or
   lose unsynced work. Keep editing disabled for this initial read-only scope.
4. Test HTTPS, CORS, browser storage restrictions and recovery against an isolated server.
5. Review client delivery security. Browser code served by a compromised host can steal keys
   when unlocked; web E2EE does not remove that additional trust in the code-delivery host.

Add transactions, statement import and encrypted offline persistence only after that proof.
Offline editing needs encrypted storage, key recovery, eviction handling and conflict tests;
it is a separate milestone. No web stack rewrite, managed database or additional cloud service
is needed just to investigate this path.
