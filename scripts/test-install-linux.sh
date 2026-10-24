#!/usr/bin/env bash
# Isolated integration checks for install-linux.sh. Uses temporary fixtures and mocks.
set -euo pipefail
source_script="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/install-linux.sh"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
fixture="$tmp/fixture"
test_home="$tmp/test_home"
mocks="$tmp/bin"
mkdir -p "$fixture" "$test_home" "$mocks"

die() { echo "FAIL: $*" >&2; exit 1; }
ok() { echo "ok - $*"; }
contains() { grep -Fq -- "$2" "$1" || { cat "$1" >&2 2>/dev/null || true; die "expected '$2' in $1"; }; }
not_exists() { [[ ! -e $1 ]] || die "unexpected path: $1"; }
reset() {
  rm -rf "$test_home" "$fixture"; mkdir -p "$test_home" "$fixture" "$fixture/scripts"
  cp "$source_script" "$fixture/scripts/install-linux.sh"
  # Redirect all installer filesystem effects into this temporary test_home and OS fixture.
  sed -i "s|\$HOME|\${TEST_HOME}|g; s|/etc/os-release|\${TEST_OS_RELEASE}|g" "$fixture/scripts/install-linux.sh"
  cat >"$fixture/artha" <<'APP'
#!/bin/sh
if [ -n "${TEST_LAUNCH_MARKER:-}" ]; then
  printf launched >"$TEST_LAUNCH_MARKER"
  exit 0
fi
echo fixture-app
APP
  chmod +x "$fixture/artha" "$fixture/scripts/install-linux.sh"
  mkdir -p "$fixture/lib" "$fixture/data"
  echo library >"$fixture/lib/example.so"; echo data >"$fixture/data/example.dat"
  echo icon >"$fixture/artha.png"
  cat >"$tmp/os-release" <<'OS'
ID=debian
ID_LIKE=
OS
  : >"$tmp/events"
}

cat >"$mocks/uname" <<'MOCK'
#!/usr/bin/env bash
case "${1:-}" in
  -s) echo "${MOCK_OS:-Linux}" ;;
  -m) echo "${MOCK_ARCH:-x86_64}" ;;
esac
MOCK
cat >"$mocks/gh" <<'MOCK'
#!/usr/bin/env bash
printf 'gh %s\n' "$*" >>"$EVENTS"
[[ ${GH_FAIL:-0} == 0 ]] || exit 1
if [[ $1 == release && $2 == list ]]; then echo 'v2.4.0-beta.1'; exit 0; fi
if [[ $1 == release && $2 == download ]]; then
  tag=$3; shift 3
  while (($#)); do
    case "$1" in
      --dir) out=$2; shift 2 ;;
      *) shift ;;
    esac
  done
  ver=${tag#v}; archive="Artha-$ver-linux-x64.tar.gz"
  mkdir -p "$FIXTURE/package/artha-$ver"
  cp -r "$FIXTURE/artha" "$FIXTURE/lib" "$FIXTURE/data" "$FIXTURE/artha.png" "$FIXTURE/package/artha-$ver/"
  cp "$FIXTURE/scripts/install-linux.sh" "$FIXTURE/package/artha-$ver/install.sh"
  tar -czf "$out/$archive" -C "$FIXTURE/package" "artha-$ver"
  hash=$(sha256sum "$out/$archive" | cut -d' ' -f1)
  case "${SUMS_MODE:-good}" in
    good) printf '%s  %s\n' "$hash" "$archive" >"$out/SHA256SUMS.txt" ;;
    bad) printf '%064d  %s\n' 0 "$archive" >"$out/SHA256SUMS.txt" ;;
    missing-entry) printf '%064d  Other.tar.gz\n' 0 >"$out/SHA256SUMS.txt" ;;
    duplicate) printf '%s  %s\n%s  %s\n' "$hash" "$archive" "$hash" "$archive" >"$out/SHA256SUMS.txt" ;;
  esac
  [[ ${ASSET_MODE:-good} == no-sums ]] && rm "$out/SHA256SUMS.txt"
  exit 0
fi
exit 2
MOCK
cat >"$mocks/apt-cache" <<'MOCK'
#!/usr/bin/env bash
[[ ${T64_AVAILABLE:-0} == 1 ]] && echo 'Package: libgtk-3-0t64'
MOCK
cat >"$mocks/dpkg-query" <<'MOCK'
#!/usr/bin/env bash
exit 1
MOCK
cat >"$mocks/apt-get" <<'MOCK'
#!/usr/bin/env bash
printf 'apt-get %s\n' "$*" >>"$EVENTS"
exit 0
MOCK
cat >"$mocks/dnf" <<'MOCK'
#!/usr/bin/env bash
printf 'dnf %s\n' "$*" >>"$EVENTS"
exit 0
MOCK
cat >"$mocks/cp" <<'MOCK'
#!/usr/bin/env bash
if [[ ${CP_FAIL:-0} == 1 && ${1:-} == -a && ${2:-} == */artha ]]; then exit 1; fi
exec /usr/bin/cp "$@"
MOCK
cat >"$mocks/rpm" <<'MOCK'
#!/usr/bin/env bash
exit 1
MOCK
cat >"$mocks/pacman" <<'MOCK'
#!/usr/bin/env bash
if [[ $1 == -Q ]]; then exit 1; fi
printf 'pacman %s\n' "$*" >>"$EVENTS"
MOCK
cat >"$mocks/sudo" <<'MOCK'
#!/usr/bin/env bash
printf 'sudo %s\n' "$*" >>"$EVENTS"
MOCK
cat >"$mocks/omarchy" <<'MOCK'
#!/usr/bin/env bash
printf 'omarchy %s\n' "$*" >>"$EVENTS"
MOCK
cat >"$mocks/update-desktop-database" <<'MOCK'
#!/usr/bin/env bash
exit 0
MOCK
cat >"$mocks/gtk-update-icon-cache" <<'MOCK'
#!/usr/bin/env bash
exit 0
MOCK
chmod +x "$mocks"/*

run() {
  env TEST_HOME="$test_home" TEST_OS_RELEASE="$tmp/os-release" FIXTURE="$fixture" EVENTS="$tmp/events" \
    PATH="$mocks:/usr/bin:/bin" "$fixture/scripts/install-linux.sh" "$@"
}
install_fixture() { run "$@" <<<y >"$tmp/out" 2>"$tmp/err" || { cat "$tmp/out" "$tmp/err" >&2; die 'installer unexpectedly failed'; }; }
assert_fail() { if run "$@" >"$tmp/out" 2>"$tmp/err"; then die "expected failure: $*"; fi; }
dest="$test_home/.local/lib/artha"

# Latest release resolves the prerelease tag while naming the versioned archive correctly.
reset
install_fixture
contains "$tmp/events" 'gh release list --repo sudharamachandranrajeev/artha --exclude-drafts --limit 1 --json tagName'
contains "$tmp/events" 'Artha-2.4.0-beta.1-linux-x64.tar.gz'
[[ -x $dest/artha && -f $dest/lib/example.so && -f $dest/data/example.dat && -f $dest/install.sh ]] || die 'release bundle did not install'
contains "$tmp/out" "$test_home/.local/bin/artha"
contains "$tmp/out" 'keyring must be running and unlocked'
ok 'latest prerelease download and install'

# Upgrade replaces app, uninstall script preserves user data marker.
echo old >"$dest/old-marker"
install_fixture
not_exists "$dest/old-marker"
mkdir -p "$test_home/.local/share/dev.artha.artha" "$test_home/.local/share/keyrings"
echo sqlite-data >"$test_home/.local/share/dev.artha.artha/artha.sqlite"
echo keyring-data >"$test_home/.local/share/keyrings/login.keyring"
env TEST_HOME="$test_home" TEST_OS_RELEASE="$tmp/os-release" "$dest/install.sh" --uninstall >/dev/null
not_exists "$dest"
not_exists "$test_home/.local/bin/artha"
contains "$test_home/.local/share/dev.artha.artha/artha.sqlite" sqlite-data
contains "$test_home/.local/share/keyrings/login.keyring" keyring-data
ok 'upgrade and uninstall preserve sqlite and keyring markers'

for mode in bad missing-entry duplicate; do
  reset
  mkdir -p "$test_home/.local/lib/artha"
  echo old-install >"$test_home/.local/lib/artha/marker"
  export ASSET_MODE=good SUMS_MODE=$mode
  assert_fail
  contains "$test_home/.local/lib/artha/marker" old-install
  unset ASSET_MODE SUMS_MODE
done
ok 'bad, missing and duplicate checksum data leave old install intact'

reset
mkdir -p "$test_home/.local/lib/artha"
echo old-install >"$test_home/.local/lib/artha/marker"
export ASSET_MODE=no-sums
assert_fail
contains "$test_home/.local/lib/artha/marker" old-install
unset ASSET_MODE
ok 'missing checksum file leaves old install intact'

reset
mkdir -p "$test_home/.local/lib/artha"
echo existing >"$test_home/.local/lib/artha/marker"
export GH_FAIL=1
assert_fail
contains "$test_home/.local/lib/artha/marker" existing
unset GH_FAIL
ok 'authentication/download failure keeps existing install'

# Declining dependencies stops before package tools or the app copy.
reset
mkdir -p "$test_home/.local/lib/artha"
echo old-install >"$test_home/.local/lib/artha/marker"
if run <<<n >"$tmp/out" 2>"$tmp/err"; then die 'declining package install should fail'; fi
contains "$tmp/err" 'package installation cancelled'
contains "$test_home/.local/lib/artha/marker" old-install
if grep -Eq 'sudo|omarchy' "$tmp/events"; then die 'decline invoked a package manager'; fi
ok 'dependency prompt decline preserves existing app without package command'

# Runtime package command routing and GTK t64 selection.
rm -f "$mocks/omarchy"
for distro in 'ID=ubuntu' 'ID=fedora' 'ID=arch'; do
  reset
  sed -i 's/command -v omarchy/false/' "$fixture/scripts/install-linux.sh"
  printf '%s\n' "$distro" >"$tmp/os-release"
  [[ $distro != ID=ubuntu ]] || export T64_AVAILABLE=1
  install_fixture
  case "$distro" in
    ID=ubuntu) contains "$tmp/events" 'sudo apt-get install libgtk-3-0t64 libsecret-1-0 gnome-keyring'; unset T64_AVAILABLE ;;
    ID=fedora) contains "$tmp/events" 'sudo dnf install gtk3 libsecret gnome-keyring' ;;
    ID=arch) contains "$tmp/events" 'sudo pacman -S gtk3 libsecret gnome-keyring' ;;
  esac
done
reset
printf 'ID=debian\n' >"$tmp/os-release"
cat >"$mocks/omarchy" <<'MOCK'
#!/usr/bin/env bash
printf 'omarchy %s\n' "$*" >>"$EVENTS"
MOCK
chmod +x "$mocks/omarchy"
install_fixture
contains "$tmp/events" 'omarchy pkg add libgtk-3-0 libsecret-1-0 gnome-keyring'
ok 'apt t64, Fedora, Arch and Omarchy dependency routes'

# Local release bundles skip gh by default; --download bypasses the bundle.
reset
cp -r "$fixture/artha" "$fixture/lib" "$fixture/data" "$fixture/artha.png" "$fixture/scripts/"
install_fixture
if grep -q '^gh ' "$tmp/events"; then die 'local bundle unexpectedly invoked gh'; fi
reset
cp -r "$fixture/artha" "$fixture/lib" "$fixture/data" "$fixture/artha.png" "$fixture/scripts/"
install_fixture --download
contains "$tmp/events" 'gh release list'
ok 'local bundle preference and --download override'

# A held installation lock must fail before contacting gh or changing files.
reset
mkdir -p "$test_home/.local/lib"
(flock -n 9; sleep 3) 9>"$test_home/.local/lib/.artha.install.lock" &
lock_pid=$!
sleep 0.1
assert_fail
contains "$tmp/err" 'another Artha installer is running'
if grep -q '^gh ' "$tmp/events"; then die 'locked installer contacted gh'; fi
kill "$lock_pid" 2>/dev/null || true
wait "$lock_pid" 2>/dev/null || true
ok 'concurrent installer lock rejects second run'

# A copy failure while staging leaves the live install untouched.
reset
mkdir -p "$test_home/.local/lib/artha"
echo old-install >"$test_home/.local/lib/artha/marker"
export CP_FAIL=1
assert_fail
contains "$test_home/.local/lib/artha/marker" old-install
unset CP_FAIL
ok 'staging copy failure keeps existing app'

reset
assert_fail --bad-option
contains "$tmp/err" 'unknown option'
assert_fail --version
contains "$tmp/err" 'requires a tag'
export MOCK_ARCH=aarch64
assert_fail
contains "$tmp/err" 'only x86_64'
unset MOCK_ARCH
export MOCK_OS=Darwin
assert_fail
contains "$tmp/err" 'Linux is required'
unset MOCK_OS
ok 'invalid options and unsupported platforms fail clearly'

# Exercise desktop Exec escaping through GLib without launching a real app.
if command -v gio >/dev/null; then
  reset
  test_home="$tmp"'/space dir/back\slash/"quote/$dollar/`tick/%percent'
  export TEST_LAUNCH_MARKER="$tmp/launcher-ran"
  install_fixture
  gio launch "$test_home/.local/share/applications/dev.artha.artha.desktop"
  for _ in {1..50}; do
    [[ -f $TEST_LAUNCH_MARKER ]] && break
    sleep 0.1
  done
  [[ -f $TEST_LAUNCH_MARKER ]] || die 'gio did not launch app through escaped desktop Exec path'
  unset TEST_LAUNCH_MARKER
  ok 'gio launches correctly from special-character install path'
else
  echo 'skip - gio unavailable for desktop Exec launch check'
fi
