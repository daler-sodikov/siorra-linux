#!/usr/bin/env bash
# Fast check of config/hook/live-config changes WITHOUT rebuilding the ISO.
# Needs a previous full build (siorra/chroot). Run from the repo root as your normal user:
#   bash quick-test.sh            # regenerate config in docker, apply to chroot, run checks
#   bash quick-test.sh --no-gen   # skip the docker step (config already regenerated)
# The chroot is modified in place; it is a disposable build artifact (`lb clean` wipes it).
set -euo pipefail
cd "$(dirname "$0")"
PROXY="${http_proxy:-http://192.168.49.1:8282}"

if [ "${1:-}" != "--no-gen" ]; then
  docker run --rm --privileged -v "$PWD":/work -w /work -e CONFIG_ONLY=1 \
    -e http_proxy="$PROXY" -e https_proxy="$PROXY" debian:trixie bash build-siorra.sh
fi

[ -d siorra/chroot/etc ] || { echo "No siorra/chroot - do a full build first."; exit 1; }
NSPAWN="sudo systemd-nspawn -q -D siorra/chroot"

echo "== copy includes.chroot + hooks into chroot"
sudo rsync -a siorra/config/includes.chroot/ siorra/chroot/
sudo mkdir -p siorra/chroot/var/tmp/hooks
# only our own hooks (regular files); live-build's stock ones are symlinks that dangle on the host
find siorra/config/hooks/normal -maxdepth 1 -type f -name '*.hook.chroot' -exec sudo cp {} siorra/chroot/var/tmp/hooks/ \;

echo "== ensure user-setup is installed (old chroot predates the fix)"
$NSPAWN --setenv=http_proxy="$PROXY" --setenv=https_proxy="$PROXY" bash -c \
  'dpkg -s user-setup >/dev/null 2>&1 || { apt-get update -qq && apt-get install -y --no-install-recommends user-setup; }'

echo "== run branding hooks (0200 skipped: it rebuilds the initramfs)"
for h in 0100-siorra-branding 0300-siorra-debrand; do
  $NSPAWN sh /var/tmp/hooks/$h.hook.chroot
done

echo "== run live-config components as at boot"
$NSPAWN bash -c '
  rm -f /var/lib/live/config/user-setup /var/lib/live/config/siorra-live
  userdel -r siorra 2>/dev/null || true
  export LIVE_CONFIG_CMDLINE="boot=live username=siorra"
  set -a; . /usr/lib/live/init-config.sh; set +a
  /usr/lib/live/config/0030-user-setup
  /usr/lib/live/config/0031-siorra-live
  echo "--- passwd:"; getent passwd siorra
  echo "--- autologin conf:"; cat /etc/lightdm/lightdm.conf.d/50-siorra-autologin.conf
  echo "--- password check (expects: siorra OK):"
  python3 - <<PY
import ctypes
c = ctypes.CDLL("libcrypt.so.1"); c.crypt.restype = ctypes.c_char_p
h = [l.split(":")[1] for l in open("/etc/shadow") if l.startswith("siorra:")][0]
for pw in (b"siorra", b"live"):
    print(pw.decode(), "OK" if c.crypt(pw, h.encode()) == h.encode() else "no")
PY
'

echo "== branding"
$NSPAWN bash -c '
  cat /etc/os-release; cat /etc/issue; cat /etc/motd
  echo "--- user-visible Debian in launchers (binary names like Exec=...debian are expected):"
  grep -iE "^(Name|GenericName|Comment)(\[.*\])?=.*debian" /usr/share/applications/calamares-install-debian.desktop /usr/share/xfce4/helpers/*.desktop || echo none
  echo "--- vendorinfo:"; cat /usr/share/xfce4/vendorinfo
  ls /etc/calamares/branding; readlink /etc/dpkg/origins/default /etc/os-release'
