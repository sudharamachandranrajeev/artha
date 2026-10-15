#!/usr/bin/env bash
# Runs the Artha sync server (PocketBase) on this machine for development.
#
#   scripts/run-local-server.sh            # serve on 127.0.0.1:8090
#   ARTHA_PB_PORT=8099 scripts/run-local-server.sh
#
# First run downloads the pinned PocketBase release (checksum-verified) and
# writes server/.env (mode 600, git-ignored) with a random invite code and
# superuser password. Data lives in server/pb_data (git-ignored).
#
# Live server tests, in another terminal:
#   set -a; . server/.env; set +a; flutter test test/pocketbase_live_test.dart
set -euo pipefail

PB_VERSION=0.40.5
declare -A PB_SHA256=(
  [amd64]=1dbea1b01eb3dfe64953513859d01e759c96650c4e3264fa4eecd54b769382e4
  [arm64]=570baa1c45d2fb92fc0073582b945ca0ece03cbf9837ccabf49a222f99dd02e3
)

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
server="$root/server"
port="${ARTHA_PB_PORT:-8090}"

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
  echo "${PB_SHA256[$arch]}  $tmp/$zip" | sha256sum -c --quiet -
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
exec "$pb" serve --http="127.0.0.1:$port" --dev=false "${args[@]}"
