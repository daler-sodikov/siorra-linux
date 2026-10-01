#!/usr/bin/env bash
# Siorra Linux - ISO builder (Debian 13 "trixie" base, XFCE desktop, Calamares installer)
#
# On Arch (host), run inside a Debian container:
#   docker run --rm -it --privileged -v "$PWD":/work -w /work debian:trixie bash build-siorra.sh
# On Debian/Ubuntu: run as root.
# Result: ./siorra/siorra-linux-amd64.iso
set -euo pipefail

VERSION="0.1"
CODENAME="Aurora"

apt-get update
apt-get install -y live-build debootstrap squashfs-tools xorriso \
    isolinux syslinux-common grub-pc-bin grub-efi-amd64-bin mtools dosfstools

mkdir -p siorra && cd siorra
lb clean --purge 2>/dev/null || true

lb config \
    --distribution trixie \
    --architectures amd64 \
    --archive-areas "main contrib non-free-firmware" \
    --mode debian \
    --binary-images iso-hybrid \
    --bootloaders "grub-efi,syslinux" \
    --bootappend-live "boot=live components quiet splash username=siorra hostname=siorra" \
    --iso-application "Siorra Linux" \
    --iso-volume "SIORRA_${VERSION}" \
    --iso-publisher "Bitsoft" \
    --image-name "siorra-linux" \
    --security true --updates true \
    --apt-recommends false

# ---------- Packages ----------
mkdir -p config/package-lists
cat > config/package-lists/siorra.list.chroot <<'EOF'
# kernel + firmware
linux-image-amd64
firmware-linux
firmware-iwlwifi
firmware-realtek
firmware-misc-nonfree
# live system
live-boot
live-config
live-config-systemd
# desktop
xfce4
xfce4-goodies
lightdm
lightdm-gtk-greeter
xserver-xorg
pipewire-audio
network-manager-gnome
# installer
calamares
calamares-settings-debian
# apps
firefox-esr
thunar
xfce4-terminal
git
curl
wget
vim
htop
sudo
EOF

# ---------- Branding hook (runs inside the chroot) ----------
mkdir -p config/hooks/normal
cat > config/hooks/normal/0100-siorra-branding.hook.chroot <<EOF
#!/bin/sh
set -e
cat > /usr/lib/os-release <<'OSR'
PRETTY_NAME="Siorra Linux ${VERSION} (${CODENAME})"
NAME="Siorra Linux"
VERSION_ID="${VERSION}"
VERSION="${VERSION} (${CODENAME})"
VERSION_CODENAME=${CODENAME,,}
ID=siorra
ID_LIKE=debian
HOME_URL="https://example.com/siorra"
SUPPORT_URL="https://example.com/siorra/support"
BUG_REPORT_URL="https://example.com/siorra/bugs"
OSR
echo "Siorra Linux ${VERSION} \n \l" > /etc/issue
echo "Siorra Linux ${VERSION}" > /etc/issue.net
echo "siorra" > /etc/hostname
EOF
chmod +x config/hooks/normal/0100-siorra-branding.hook.chroot

# ---------- Live user: siorra / siorra (change it!) ----------
mkdir -p config/includes.chroot/etc/live/config.conf.d
cat > config/includes.chroot/etc/live/config.conf.d/siorra.conf <<'EOF'
LIVE_USERNAME="siorra"
LIVE_USER_FULLNAME="Siorra Live User"
LIVE_USER_DEFAULT_GROUPS="audio cdrom dip floppy video plugdev netdev sudo"
EOF

# ---------- Branding ----------
bash ../apply-branding.sh

# ---------- Build ----------
lb build 2>&1 | tee build.log

ls -lh ./*.iso
echo "Done. Test with: qemu-system-x86_64 -m 4G -enable-kvm -cdrom siorra/siorra-linux-amd64.hybrid.iso"
