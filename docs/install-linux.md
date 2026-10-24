# Install Artha on Linux

Artha runs on Intel/AMD 64-bit Linux desktops. Use Ubuntu 22.04 or newer, Debian 12 or newer,
or a current Fedora, Arch or Omarchy desktop. The installer handles missing packages on
these distribution families. ARM Linux and Alpine Linux are not supported by
the published desktop build. Ubuntu, Fedora and Arch also have release startup tests;
Omarchy uses the Arch build and its own package-install command.

## Install with one script

You need access to Artha's private GitHub repository. A GitHub login is only for downloading
the app; you do not need an Artha sync account to use it.

1. Install GitHub CLI if `gh --version` does not work. Use the command for your system:

   | System | Command |
   | --- | --- |
   | Omarchy | `omarchy pkg add github-cli` |
   | Arch | `sudo pacman -S --needed github-cli` |
   | Fedora | `sudo dnf install gh` |
   | Ubuntu / Debian | `sudo apt update && sudo apt install gh` |

2. Sign in once, choosing **GitHub.com** and **Login with a web browser**:

   ```sh
   gh auth login
   ```

3. Download the installer, then run it:

   ```sh
   gh api 'repos/sudharamachandranrajeev/artha/contents/scripts/install-linux.sh?ref=main' \
     -H 'Accept: application/vnd.github.raw+json' > install-artha.sh &&
   bash install-artha.sh --download
   ```

   This uses the newest published release, including beta releases. The script checks the
   Linux archive against that release's `SHA256SUMS.txt` before unpacking it. If desktop
   libraries are missing, it lists them and asks before installing them. Your system may
   ask for your password for those packages. Do not run the whole installer with `sudo`.

4. Open **Artha** from your application launcher. On Omarchy, search for **Artha** in the
   application launcher. You can also run:

   ```sh
   ~/.local/bin/artha
   ```

If you already have this source checkout, step 3 is simply
`bash scripts/install-linux.sh --download`. Flutter is not needed to install a release.

To choose a particular release, use `bash install-artha.sh --version v0.2.0-beta.1`.
You can inspect the script before running it. `bash install-artha.sh --help` lists its options.

## Prefer downloading in your browser?

Sign in to GitHub and open the [release downloads](https://github.com/sudharamachandranrajeev/artha/releases).
Download the Linux `.tar.gz` file and `SHA256SUMS.txt` from the same release into an otherwise
empty folder. In a terminal in that folder, run:

```sh
sha256sum --check --ignore-missing SHA256SUMS.txt
```

Continue only if your Linux archive is reported **OK** and the command succeeds. Extract
the archive, open its folder in a terminal, then run `bash install.sh`. Bundled installers
from older releases may only warn about missing libraries; use the current standalone
installer above if you want automatic dependency setup.

## First launch and the keyring

Artha keeps its encryption key in your desktop's secret service, such as GNOME Keyring.
If prompted, unlock the **login keyring** with your keyring password, usually your login
password. If the installer added GNOME Keyring for the first time, log out and back in.
On a minimal Arch desktop, the desktop session also needs D-Bus and a configured secret
service; installing the library alone does not unlock a keyring.

If Artha reports a missing key, do not delete or reset the keyring to get past the message.
Restore access to the original keyring; an existing database needs its original key.
For normal use, continue with the [quick start](quick-start.md).

## Update or remove Artha

Close Artha before updating. After installation with the new script, run:

```sh
bash ~/.local/lib/artha/install.sh --download
```

To remove the application:

```sh
bash ~/.local/lib/artha/install.sh --uninstall
```

Both commands preserve your encrypted ledger and keyring entry. If upgrading from an older
installer without the saved script, download `install-artha.sh` again and use its options.

The application is stored in `~/.local/lib/artha`; its launcher is `~/.local/bin/artha`.
Your ledger is separate, in `~/.local/share/dev.artha.artha`. Uninstalling is not a data wipe.

## Common problems

| Message or symptom | What to do |
| --- | --- |
| GitHub reports 404 or a download fails | Run `gh auth status` and check that this GitHub account can open the private repository. |
| `artha: command not found` | Open Artha from the menu or run `~/.local/bin/artha`. |
| Package download fails | Update your distribution using its normal update process, then retry. The installer does not perform a full system upgrade. |
| Checksum mismatch | Delete that download and try again. Do not bypass the check. |
| Another installer is running | Wait for that installation or removal to finish, then retry. |
| Keyring is locked | Unlock the existing login keyring. Logging out and back in may start your configured secret service. |
