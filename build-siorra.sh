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
BASED_ON="Debian GNU/Linux 13"   # shown in system information

apt-get update
apt-get install -y live-build debootstrap squashfs-tools xorriso \
    isolinux syslinux-common grub-pc-bin grub-efi-amd64-bin mtools dosfstools

mkdir -p siorra && cd siorra
# keep cache/ so reruns don't redownload everything (plain `lb clean`, not --purge)
# (CONFIG_ONLY=1 skips it so an existing chroot survives; see quick-test.sh)
[ "${CONFIG_ONLY:-}" = 1 ] || lb clean 2>/dev/null || true

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
    --iso-preparer "Siorra Linux" \
    --image-name "siorra-linux" \
    --security true --updates true \
    --apt-recommends false \
    ${http_proxy:+--apt-http-proxy "$http_proxy"}

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
user-setup
locales
keyboard-configuration
iproute2
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
PRETTY_NAME="Siorra Linux ${VERSION} (${CODENAME}), based on ${BASED_ON}"
NAME="Siorra Linux"
VERSION_ID="${VERSION}"
VERSION="${VERSION} (${CODENAME})"
VERSION_CODENAME=${CODENAME,,}
ID=siorra
ID_LIKE=debian
ANSI_COLOR="38;2;216;90;48"
LOGO=siorra-logo
HOME_URL="https://example.com/siorra"
SUPPORT_URL="https://example.com/siorra/support"
BUG_REPORT_URL="https://example.com/siorra/bugs"
OSR
# quoted heredocs: dash's echo would turn the \n of agetty's issue escapes into a newline
cat > /etc/issue <<'ISS'
Siorra Linux ${VERSION} \n \l
Based on ${BASED_ON}

ISS
cat > /etc/issue.net <<'ISS'
Siorra Linux ${VERSION} (based on ${BASED_ON})
ISS
cat > /etc/motd <<'MOTD'

Siorra Linux ${VERSION}, based on ${BASED_ON}.

The programs included with the Siorra Linux system are free software;
the exact distribution terms for each program are described in the
individual files in /usr/share/doc/*/copyright.

Siorra Linux comes with ABSOLUTELY NO WARRANTY, to the extent
permitted by applicable law.
MOTD
echo "siorra" > /etc/hostname
EOF
chmod +x config/hooks/normal/0100-siorra-branding.hook.chroot

# ---------- Live user: siorra / siorra ----------
# user-setup (a mere Recommends of live-config) MUST be installed or live-config
# never creates the user; it is in the package list above.
mkdir -p config/includes.chroot/etc/live/config.conf.d
cat > config/includes.chroot/etc/live/config.conf.d/siorra.conf <<'EOF'
LIVE_USERNAME="siorra"
LIVE_USER_FULLNAME="Siorra Live User"
LIVE_USER_DEFAULT_GROUPS="audio cdrom dip floppy video plugdev netdev sudo"
EOF

# Custom live-config component, runs at boot right after 0030-user-setup:
# sets the live password and enables LightDM autologin (live session only, so
# the installed system is not affected). Debian's stock lightdm.conf has no
# "#autologin-user=" lines, so live-config's own lightdm component does nothing.
mkdir -p config/includes.chroot/usr/lib/live/config
cat > config/includes.chroot/usr/lib/live/config/0031-siorra-live <<'EOF'
#!/bin/sh

. /usr/lib/live/config.sh

Cmdline ()
{
	for _PARAMETER in ${LIVE_CONFIG_CMDLINE}
	do
		case "${_PARAMETER}" in
			live-config.noautologin|noautologin|live-config.nox11autologin|nox11autologin)
				LIVE_CONFIG_NOAUTOLOGIN="true"
				;;
			live-config.username=*|username=*)
				LIVE_USERNAME="${_PARAMETER#*username=}"
				;;
		esac
	done
}

Init ()
{
	if component_was_executed "siorra-live"
	then
		exit 0
	fi

	echo -n " siorra-live"
}

Config ()
{
	if grep -q "^${LIVE_USERNAME}:" /etc/passwd
	then
		echo "${LIVE_USERNAME}:siorra" | chpasswd
	fi

	if [ "${LIVE_CONFIG_NOAUTOLOGIN}" != "true" ] && [ -d /etc/lightdm ]
	then
		mkdir -p /etc/lightdm/lightdm.conf.d
		cat > /etc/lightdm/lightdm.conf.d/50-siorra-autologin.conf << EOT
[Seat:*]
autologin-user=${LIVE_USERNAME}
autologin-user-timeout=0
autologin-session=xfce
EOT
	fi

	touch /var/lib/live/config/siorra-live
}

Cmdline
Init
Config
EOF
chmod +x config/includes.chroot/usr/lib/live/config/0031-siorra-live

# ---------- Branding ----------
bash ../apply-branding.sh

# ---------- Build ----------
if [ "${CONFIG_ONLY:-}" = 1 ]; then echo "Config generated (CONFIG_ONLY=1), not building."; exit 0; fi
lb build 2>&1 | tee build.log

ls -lh ./*.iso
echo "Done. Test with: qemu-system-x86_64 -m 4G -enable-kvm -cdrom siorra/siorra-linux-amd64.hybrid.iso"
