#!/usr/bin/env bash
# Runs the Artha sync server (PocketBase) on this machine for development.
#
#   scripts/run-local-server.sh            # serve on 127.0.0.1:8090
#   ARTHA_PB_PORT=8099 scripts/run-local-server.sh
#   ARTHA_PB_HOST=0.0.0.0 scripts/run-local-server.sh   # let phones on this network sync
#
# Only open it to your own network (home Wi-Fi, Tailscale): it serves plain
# http. Data is end-to-end encrypted and sign-up needs the invite code, but
# a public server belongs behind https (see server/README.md).
#
# First run downloads the pinned PocketBase release (checksum-verified) and
# writes server/.env (mode 600, git-ignored) with a random invite code and
# superuser password. Data lives in server/pb_data (git-ignored).
#
# Live server tests, in another terminal:
#   set -a; . server/.env; set +a; flutter test test/pocketbase_live_test.dart
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
server="$root/server"
# shellcheck source=../server/pocketbase-version.sh
. "$server/pocketbase-version.sh"
port="${ARTHA_PB_PORT:-8090}"
host="${ARTHA_PB_HOST:-127.0.0.1}"

case "$(uname -m)" in
  x86_64) arch=amd64 ;;
  aarch64 | arm64) arch=arm64 ;;
  *) echo "Unsupported architecture: $(uname -m)" >&2; exit 1 ;;
esac

bin_dir="${XDG_CACHE_HOME:-$HOME/.cache}/artha/pocketbase-$PB_VERSION"
pb="$bin_dir/pocketbase"
if [[ ! -x "$pb" ]]; then
  zip="pocketbase_${PB_VERSION}_linux_${arch}.zip"
  tmp="$(mktemp -d)"
  trap 'rm -rf "$tmp"' EXIT
  echo "Downloading PocketBase $PB_VERSION ($arch)..."
  curl -fsSLo "$tmp/$zip" "https://github.com/pocketbase/pocketbase/releases/download/v$PB_VERSION/$zip"
  sum="PB_SHA256_$arch"
  echo "${!sum}  $tmp/$zip" | sha256sum -c --quiet -
  mkdir -p "$bin_dir"
  unzip -qo "$tmp/$zip" pocketbase -d "$bin_dir"
  chmod 755 "$pb"
fi

random() { head -c 24 /dev/urandom | base64 | tr '+/' '-_'; }
if [[ ! -f "$server/.env" ]]; then
  umask 077
  cat > "$server/.env" <<ENV
ARTHA_SIGNUP_CODE=$(random)
ARTHA_PB_URL=http://127.0.0.1:$port
ARTHA_PB_ADMIN=admin@artha.local
ARTHA_PB_ADMIN_PASSWORD=$(random)
ENV
  echo "Wrote $server/.env (invite code and superuser password)."
fi
set -a
# shellcheck source=/dev/null
. "$server/.env"
set +a

args=(--dir="$server/pb_data" --migrationsDir="$server/pb_migrations" --hooksDir="$server/pb_hooks")
"$pb" superuser upsert "$ARTHA_PB_ADMIN" "$ARTHA_PB_ADMIN_PASSWORD" "${args[@]}" >/dev/null
echo "Admin UI: http://127.0.0.1:$port/_/  (login from server/.env)"
if [[ $host != 127.0.0.1 ]]; then
  lan="$(ip -4 route get 1.1.1.1 2>/dev/null | awk '{for (i = 1; i < NF; i++) if ($i == "src") print $(i + 1)}')"
  echo "Listening on $host:$port. Other devices use: http://${lan:-THIS-MACHINE-IP}:$port"
  echo "Invite code for sign-up: ARTHA_SIGNUP_CODE in server/.env"
fi
exec "$pb" serve --http="$host:$port" --dev=false "${args[@]}"
