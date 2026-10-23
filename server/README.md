# Artha sync server

A [PocketBase](https://pocketbase.io) server (pinned to v0.40.5) with Artha's schema
(`pb_migrations/`) and account rules (`pb_hooks/`). It keeps:

- `users`: e-mail plus a login secret derived in the app. The typed password never reaches the server.
- `vaults`: the data key, wrapped once under the password key and once under the recovery key.
- `devices`: the devices of each account.
- `changes`: an append-only log of encrypted change batches per device. Nobody can edit or delete
  entries through the API.

Everything financial is encrypted on the device (XChaCha20-Poly1305) before upload. A copy of the
server data does not reveal balances, payees or amounts. It does reveal account e-mails, device
names and when each device synced.

## Try it locally

```sh
scripts/run-local-server.sh            # http://127.0.0.1:8090, admin UI at /_/
```

The first run downloads PocketBase, checks its SHA-256, and writes `server/.env` (mode 600,
git-ignored). That file holds the invite code (`ARTHA_SIGNUP_CODE`) and a superuser login. In the
app, sign up with server `http://127.0.0.1:8090` and that invite code.

The app accepts plain `http://` only for loopback, private-network (10/8, 172.16/12, 192.168/16),
Tailscale (100.64/10) and `.local` addresses. Any other server needs `https://`.

Live server tests (another terminal, server running):

```sh
set -a; . server/.env; set +a
flutter test test/pocketbase_live_test.dart
```

## Run it for real

1. Create `server/.env` with a long random invite code:

   ```sh
   echo "ARTHA_SIGNUP_CODE=$(openssl rand -base64 24)" > server/.env && chmod 600 server/.env
   ```

   Without a code of at least 12 characters, nobody can sign up. A superuser can still add
   accounts.

2. Start it. The container runs as a non-root user with a read-only root filesystem and listens
   on 127.0.0.1:8090 only:

   ```sh
   cd server && docker compose up -d --build
   docker compose exec artha-sync /pb/pocketbase superuser upsert you@example.com 'a long password' --dir=/pb/pb_data
   ```

3. Put HTTPS in front. With [Caddy](https://caddyserver.com), which gets certificates by itself:

   ```caddyfile
   sync.example.com {
   	reverse_proxy 127.0.0.1:8090
   }
   ```

   Alternatively, keep the server inside a Tailscale network and use `http://100.x.y.z:8090`.

4. In the admin UI (`https://sync.example.com/_/`), under **Settings**:
   - **Application**: set the URL to `https://sync.example.com`.
   - **Trusted proxy**: add the header `X-Forwarded-For` and keep "use leftmost IP" off. Without
     this, every request seems to come from the proxy, so the per-IP rate limits apply to all
     users together.
   - **Mail settings**: add SMTP. Password-reset e-mails need it.

## Accounts and recovery

- Sign-up shows a **recovery key** once. A forgotten password can be reset by e-mail, but the
  synced data opens again only with that recovery key. Without both the password and the recovery
  key, the data survives only on devices that are still signed in.
- The reset e-mail carries a code to paste into the app, not a link. PocketBase's own reset page
  would store the typed password, and Artha never sends the typed password.
- An account's e-mail address cannot change: it salts the password key. Do not change it from
  the admin UI either, or the account can no longer sign in.

## Built-in limits

| What | Limit (per client IP) |
| --- | --- |
| Sign-in attempts (`*:auth`) | 10 per minute |
| Sign-ups (`users:create`) | 5 per hour |
| Change uploads (`changes:create`, signed in) | 100 per 10 s |
| Any API call | 300 per 10 s |

Batch requests are off. Users can see only their own records.

## Backups and upgrades

- Back up the `pb_data` volume, or use **Settings > Backups** in the admin UI. Its contents stay
  encrypted, but it holds account e-mails, so store it privately.
- To upgrade PocketBase, take the new version and its `checksums.txt` lines from
  [the releases page](https://github.com/pocketbase/pocketbase/releases). Update
  `pocketbase-version.sh`, shared by the Docker build and local launcher, and the version
  noted at the top of this page. Read the changelog for breaking changes before you rebuild
  with `docker compose up -d --build`.
