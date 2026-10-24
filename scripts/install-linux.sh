#!/usr/bin/env bash
# User-local Artha installer. Release bundles can run this same script directly.
set -euo pipefail

app_id=dev.artha.artha
dest="$HOME/.local/lib/artha"
bin="$HOME/.local/bin/artha"
desktop="$HOME/.local/share/applications/$app_id.desktop"
icon="$HOME/.local/share/icons/hicolor/512x512/apps/$app_id.png"
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
version=
force_download=0

usage() {
  cat <<'USAGE'
Usage: install-linux.sh [--version TAG] [--download] [--uninstall] [--help]

Install Artha for the current user. With no local release bundle or build,
downloads the latest Linux x64 release (requires authenticated GitHub CLI `gh`).
--version TAG  Download that release tag
--download    Download latest release even when a local build is available
--uninstall   Remove Artha; keep your data and keyring entry
USAGE
}
fail() { echo "install-linux: $*" >&2; exit 1; }

while (($#)); do
  case "$1" in
    --help|-h) usage; exit 0 ;;
    --uninstall) [[ -z ${version:-} && $force_download == 0 ]] || fail "--uninstall cannot be combined with download options"; uninstall=1 ;;
    --download) force_download=1 ;;
    --version) (($# >= 2)) || fail "--version requires a tag"; version=$2; shift ;;
    --*) fail "unknown option: $1" ;;
    *) fail "unexpected argument: $1" ;;
  esac
  shift
done
[[ ${uninstall:-0} == 0 || ( $force_download == 0 && -z $version ) ]] || fail "--uninstall cannot be combined with download options"
[[ $(uname -s) == Linux ]] || fail "Linux is required"
[[ $(uname -m) == x86_64 ]] || fail "only x86_64 Linux is supported"
(( EUID != 0 )) || fail "run as your regular user; Artha installs without root"

# Serialize updates and removal so two installers cannot replace each other's files.
command -v flock >/dev/null || fail "flock is required (install util-linux)"
mkdir -p "$(dirname "$dest")"
exec 9>"$(dirname "$dest")/.artha.install.lock"
flock -n 9 || fail "another Artha installer is running"

if [[ ${uninstall:-0} == 1 ]]; then
  rm -rf "$dest"
  rm -f "$bin" "$desktop" "$icon"
  command -v update-desktop-database >/dev/null && update-desktop-database -q "$(dirname "$desktop")" || true
  echo "Artha removed. Your data is still in ~/.local/share/$app_id."
  exit 0
fi

# Prefer a release bundle next to this script, then a checkout build, unless a
# download was explicitly requested. A version always means a release download.
bundle=
png=
if [[ $force_download == 0 && -z $version ]]; then
  if [[ -x $here/artha && -d $here/lib && -d $here/data ]]; then
    bundle=$here; png=$here/artha.png
  else
    root="$(cd "$here/.." && pwd)"
    if [[ -x $root/build/linux/x64/release/bundle/artha ]]; then
      bundle="$root/build/linux/x64/release/bundle"; png="$root/branding/artha-512.png"
    fi
  fi
fi

temp=
cleanup() { [[ -z $temp ]] || rm -rf "$temp"; }
trap cleanup EXIT
if [[ -z $bundle ]]; then
  command -v gh >/dev/null || fail "GitHub CLI (gh) is required to download a release"
  command -v tar >/dev/null || fail "tar is required"
  temp="$(mktemp -d)"
  repo=sudharamachandranrajeev/artha
  if [[ -z $version ]]; then
    version="$(gh release list --repo "$repo" --exclude-drafts --limit 1 --json tagName --jq '.[0].tagName')" || fail "could not find a release; sign in with gh auth login"
    [[ -n $version && $version != null ]] || fail "no published release found"
  fi
  [[ $version =~ ^v[0-9]+\.[0-9]+\.[0-9]+([-+][0-9A-Za-z.-]+)?$ ]] || fail "use a release tag such as v0.2.0-beta.1"
  asset_version=${version#v}
  archive="Artha-${asset_version}-linux-x64.tar.gz"
  gh release download "$version" --repo "$repo" --pattern "$archive" --pattern SHA256SUMS.txt --dir "$temp" || fail "could not download release assets; check gh authentication and release tag"
  [[ -f $temp/$archive && -f $temp/SHA256SUMS.txt ]] || fail "release is missing the Linux archive or SHA256SUMS.txt"
  expected="$(awk -v name="$archive" '$2 == name || $2 == "*" name {print $1}' "$temp/SHA256SUMS.txt")"
  [[ $expected =~ ^[[:xdigit:]]{64}$ ]] || fail "no unique valid checksum for $archive"
  actual="$(sha256sum "$temp/$archive" | awk '{print $1}')"
  [[ ${actual,,} == ${expected,,} ]] || fail "checksum mismatch for $archive"
  mkdir "$temp/unpacked"
  tar -xzf "$temp/$archive" -C "$temp/unpacked"
  # Release archive contains its own installer alongside the bundle.
  found="$(find "$temp/unpacked" -type f -name artha -perm /111 -print -quit)"
  [[ -n $found ]] || fail "release archive does not contain the Artha executable"
  bundle="$(dirname "$found")"
  [[ -d $bundle/lib && -d $bundle/data ]] || fail "release archive has an incomplete bundle"
  png="$bundle/artha.png"
fi
[[ -x $bundle/artha && -d $bundle/lib && -d $bundle/data ]] || fail "no usable Linux bundle found; run flutter build linux --release"

# Determine only missing runtime packages. Never run package management unless
# packages are missing, and leave confirmation to the package manager/user.
source /etc/os-release 2>/dev/null || true
ids=" ${ID:-} ${ID_LIKE:-} "
manager=; packages=()
case "$ids" in
  *" ubuntu "*|*" debian "*)
    manager=apt-get
    gtk=libgtk-3-0
    if command -v apt-cache >/dev/null; then
      t64_info="$(apt-cache show libgtk-3-0t64 2>/dev/null || true)"
      if [[ $t64_info == *$'Package: libgtk-3-0t64'* ]]; then gtk=libgtk-3-0t64; fi
    fi
    packages=("$gtk" libsecret-1-0 gnome-keyring)
    ;;
  *" fedora "*) manager=dnf; packages=(gtk3 libsecret gnome-keyring) ;;
  *" arch "*|*" manjaro "*) manager=pacman; packages=(gtk3 libsecret gnome-keyring) ;;
esac
missing=()
if [[ -n $manager ]]; then
  for pkg in "${packages[@]}"; do
    case $manager in
      apt-get) dpkg-query -W -f='${Status}' "$pkg" 2>/dev/null | grep -q 'install ok installed' || missing+=("$pkg") ;;
      dnf) rpm -q "$pkg" >/dev/null 2>&1 || missing+=("$pkg") ;;
      pacman) pacman -Q "$pkg" >/dev/null 2>&1 || missing+=("$pkg") ;;
    esac
  done
  if ((${#missing[@]})); then
    echo "Artha needs runtime packages: ${missing[*]}"
    read -r -p "Install these packages now? Your system may ask for your password. [y/N] " answer || fail "package installation needs confirmation in a terminal"
    [[ $answer == [yY] || $answer == [yY][eE][sS] ]] || fail "package installation cancelled; no app files were changed"
    if command -v omarchy >/dev/null; then
      omarchy pkg add "${missing[@]}"
    else
      command -v sudo >/dev/null || fail "sudo is required to install missing packages: ${missing[*]}"
      case $manager in
        apt-get) sudo apt-get install "${missing[@]}" ;;
        dnf) sudo dnf install "${missing[@]}" ;;
        pacman) sudo pacman -S "${missing[@]}" ;;
      esac
    fi
  fi
else
  echo "Could not identify a supported package manager; ensure GTK 3, libsecret and GNOME Keyring are installed." >&2
fi

# Copy to a sibling directory and retain the old installation until the new
# copy is complete. Restore it if the final rename fails.
mkdir -p "$(dirname "$dest")"
staging="$(mktemp -d "$(dirname "$dest")/.artha.new.XXXXXX")"
backup="$(dirname "$dest")/.artha.old.$$"
restore() {
  rm -rf "$staging"
  if [[ -e $backup && ! -e $dest ]]; then mv "$backup" "$dest"; fi
}
trap 'restore; cleanup' EXIT
cp -a "$bundle/artha" "$bundle/lib" "$bundle/data" "$staging/"
cp "${BASH_SOURCE[0]}" "$staging/install.sh"
[[ -f $png ]] && cp "$png" "$staging/artha.png"
rm -rf "$backup"
[[ ! -e $dest ]] || mv "$dest" "$backup"
mv "$staging" "$dest"
rm -rf "$backup"
trap cleanup EXIT

mkdir -p "$(dirname "$bin")" "$(dirname "$desktop")" "$(dirname "$icon")"
ln -sf "$dest/artha" "$bin"
[[ ! -f $dest/artha.png ]] || cp "$dest/artha.png" "$icon"
# Desktop Entry quoting differs from shell quoting, including a second backslash pass.
exec_path=${dest//\\/\\\\}
exec_path=${exec_path//\"/\\\"}
exec_path=${exec_path//\$/\\\$}
exec_path=${exec_path//\`/\\\`}
exec_path=${exec_path//%/%%}
exec_path=${exec_path//\\/\\\\}
# Use a fixed executable so launchers do not test a percent-escaped app path
# before expanding Desktop Entry field codes in its argument.
cat >"$desktop" <<DESKTOP
[Desktop Entry]
Type=Application
Name=Artha
GenericName=Personal finance
Comment=Accounts, spending, investments and reports in one private ledger
Exec=/usr/bin/env "$exec_path/artha"
Icon=$app_id
Terminal=false
Categories=Office;Finance;
Keywords=money;budget;accounts;ledger;investments;
StartupWMClass=$app_id
DESKTOP
command -v update-desktop-database >/dev/null && update-desktop-database -q "$(dirname "$desktop")" || true
command -v gtk-update-icon-cache >/dev/null && gtk-update-icon-cache -q "$HOME/.local/share/icons/hicolor" 2>/dev/null || true

if [[ ":$PATH:" != *":$(dirname "$bin"):"* ]]; then
  echo "Artha installed. Start it from your app menu or run: $bin"
else
  echo "Artha installed. Start it from your app menu or run: artha"
fi
echo "The desktop keyring must be running and unlocked when Artha starts."
echo "Update later: bash \"$dest/install.sh\" --download"
echo "Remove the app, keeping data: bash \"$dest/install.sh\" --uninstall"
