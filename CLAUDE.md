# Siorra Linux - project handoff

Put this file in the repo root (`CLAUDE.md`) so Claude Code reads it automatically.

## Goal
Build **Siorra Linux**, a Debian-based distro (Debian 13 "trixie", XFCE, LightDM, Calamares installer), with its own branding. The logo is **option C**: a coral (#D85A30) hexagon with a white blocky "S". The dark background is #1c1b19.

## Repo and environment
- GitHub (private): `daler-sodikov/siorra-linux`.
- Local path: `~/Desktop/Siorra/siorra-linux-build`.
- Host: Arch Linux, zsh, Docker. The owner is Daler, who prefers concise answers and honest disclosure of limitations.
- Network quirk: the laptop only has internet through the **NetShare** Android app, which is an HTTP proxy at `http://192.168.49.1:8282`. There is no real network interface sharing.
  - `systemd-resolved` is not running, so `resolvectl` fails.
  - Docker needs the proxy on its daemon only for `docker pull`.
  - Inside the container the proxy is passed with `-e http_proxy=... -e https_proxy=...`.
  - USB tethering would be more reliable.

## Files
- `build-siorra.sh`: installs live-build in the container, runs `lb config`, writes the package list, os-release branding hook and live-user config, calls `../apply-branding.sh`, then `lb build`.
- `apply-branding.sh`: run from inside `siorra/` after `lb config`. It adds the logo/icons, wallpaper, LightDM greeter config, XFCE wallpaper XML, Plymouth theme, bootloader splash replacement, Calamares branding and the chroot hook `0200-siorra-theme.hook.chroot`.
- `brand/`: the logo SVG, PNGs from 16 to 512 px, the 1920x1080 wallpaper and the 640x480 boot splash.

## Build command (from repo root)
```
docker run --rm -it --privileged -v "$PWD":/work -w /work \
  -e http_proxy=http://192.168.49.1:8282 -e https_proxy=http://192.168.49.1:8282 \
  debian:trixie bash build-siorra.sh
```
The ISO appears in `siorra/`. The exact filename has not been confirmed, so check `ls siorra/*.iso`. Test with `qemu-system-x86_64 -m 4G -enable-kvm -vga virtio -cdrom siorra/*.iso`.

## Status
- The full ISO build **succeeded** and the ISO boots in QEMU.
- The branded LightDM greeter appears (logo, "Siorra Linux" text, dark background), so greeter/wallpaper branding works.
- The first build took about 1 hour over the proxy.

## Known issues (fixed in source, need a rebuild to confirm)
1. **Login.** Root cause: `user-setup` was never installed (`--apt-recommends false`; it is only a Recommends of `live-config`), so live-config never created any user. Fixed by adding `user-setup` (plus `locales`, `keyboard-configuration`, `iproute2`) to the package list. Live user/password is now **`siorra` / `siorra`**, set by a custom live-config component `0031-siorra-live` (runs after user-setup). That component also writes `/etc/lightdm/lightdm.conf.d/50-siorra-autologin.conf` at boot (live session only), because Debian's lightdm.conf has no `#autologin-user=` lines for live-config's own component to uncomment. `config.conf.d/siorra.conf` IS read (via `init-config.sh`). Boot with `noautologin` to get the greeter.
2. **Wallpaper logo overlap.** Logo and text moved to the top of `brand/siorra-wallpaper.png`; greeter dialog pinned at `position=50%,center 60%,center`.
3. **Cache.** `lb clean --purge` replaced by `lb clean`.
4. **Proxy line.** `${http_proxy:+--apt-http-proxy "$http_proxy"}` is in `build-siorra.sh` and committed.
5. **Password comment** corrected.
- Open: Calamares has no `removeuser` module, so the installed system keeps the `siorra` user.

## Debian de-branding (in source, unverified until rebuilt)
- os-release `PRETTY_NAME="Siorra Linux 0.1 (Aurora), based on Debian GNU/Linux 13"` (+ `ID_LIKE=debian`), `/etc/issue`, `/etc/issue.net`, `/etc/motd` all say Siorra / based on Debian. `BASED_ON` var in `build-siorra.sh`. The old `/etc/issue` was broken (dash `echo` expanded `\n`); now written with a quoted heredoc.
- Hook `0300-siorra-debrand` (in `apply-branding.sh`): Calamares launcher ("Install Siorra Linux"), removes `calamares/branding/debian`, renames Xfce "Debian Sensible Browser/X Terminal Emulator", Xfce vendorinfo, `debian-logo.png`, dpkg vendor `siorra` (Parent: Debian). Also `GRUB_DISTRIBUTOR=Siorra` for installed systems and Siorra titles in syslinux/GRUB themes.
- Intentionally still Debian: apt sources, `/etc/debian_version`, package names, kernel version string (`6.12.x+deb13`), `Exec=calamares-install-debian`, GRUB live entry names ("Live system (amd64)") which live-build generates.

## Not yet verified
- Plymouth boot splash.
- GRUB/syslinux splash images: live-build bootloader template paths may differ, and the script replaces every `splash.png` it finds.
- XFCE wallpaper after login: monitor names in the XML are guesses.
- Calamares branding and the installer itself. Calamares uses a minimal logo-only slideshow.
- Whether `os-release` and `/etc/issue` branding applies in the running system.

## Suggested next steps
1. Fix issues 1 to 5 and rebuild.
2. Boot, log in, and verify each unverified item above.
3. Add a README and a GitHub Actions workflow to build the ISO.
4. Later: a Siorra GTK/icon theme, a custom apt repo, and real project URLs (the ones in `os-release` and Calamares are placeholders: `example.com/siorra`). The version codename "Aurora" is a placeholder too.