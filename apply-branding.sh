#!/usr/bin/env bash
# Run from inside the live-build dir (siorra/) after `lb config`, before `lb build`.
# Usage: bash ../apply-branding.sh   (expects ../brand/)
set -euo pipefail
B="$(cd "$(dirname "$0")" && pwd)/brand"
C=config/includes.chroot

# logos + icons
mkdir -p $C/usr/share/pixmaps $C/usr/share/icons/hicolor/scalable/apps
cp "$B/siorra-logo-256.png" $C/usr/share/pixmaps/siorra-logo.png
cp "$B/siorra-logo.svg" $C/usr/share/icons/hicolor/scalable/apps/siorra-logo.svg
for s in 16 32 48 64 128 256 512; do
  mkdir -p $C/usr/share/icons/hicolor/${s}x${s}/apps
  cp "$B/siorra-logo-$s.png" $C/usr/share/icons/hicolor/${s}x${s}/apps/siorra-logo.png
done

# wallpaper
mkdir -p $C/usr/share/backgrounds/siorra
cp "$B/siorra-wallpaper.png" $C/usr/share/backgrounds/siorra/siorra-wallpaper.png

# LightDM greeter
mkdir -p $C/etc/lightdm/lightdm-gtk-greeter.conf.d
cat > $C/etc/lightdm/lightdm-gtk-greeter.conf.d/50-siorra.conf <<'EOF'
[greeter]
background=/usr/share/backgrounds/siorra/siorra-wallpaper.png
default-user-image=/usr/share/pixmaps/siorra-logo.png
EOF

# XFCE default wallpaper (common monitor names; verify on first boot)
mkdir -p $C/etc/xdg/xfce4/xfconf/xfce-perchannel-xml
{
echo '<?xml version="1.0" encoding="UTF-8"?>'
echo '<channel name="xfce4-desktop" version="1.0"><property name="backdrop" type="empty"><property name="screen0" type="empty">'
for m in monitorVirtual1 monitorVirtual-1 monitorLVDS1 monitoreDP1 monitoreDP-1 monitorHDMI-1 monitor0; do
  echo "<property name=\"$m\" type=\"empty\"><property name=\"workspace0\" type=\"empty\"><property name=\"image-style\" type=\"int\" value=\"5\"/><property name=\"last-image\" type=\"string\" value=\"/usr/share/backgrounds/siorra/siorra-wallpaper.png\"/></property></property>"
done
echo '</property></property></channel>'
} > $C/etc/xdg/xfce4/xfconf/xfce-perchannel-xml/xfce4-desktop.xml

# Plymouth theme
P=$C/usr/share/plymouth/themes/siorra
mkdir -p $P
cp "$B/siorra-logo-256.png" $P/logo.png
cat > $P/siorra.plymouth <<'EOF'
[Plymouth Theme]
Name=Siorra
Description=Siorra Linux boot splash
ModuleName=script

[script]
ImageDir=/usr/share/plymouth/themes/siorra
ScriptFile=/usr/share/plymouth/themes/siorra/siorra.script
EOF
cat > $P/siorra.script <<'EOF'
Window.SetBackgroundTopColor(0.11, 0.106, 0.1);
Window.SetBackgroundBottomColor(0.11, 0.106, 0.1);
logo.image = Image("logo.png");
logo.sprite = Sprite(logo.image);
logo.sprite.SetX(Window.GetWidth() / 2 - logo.image.GetWidth() / 2);
logo.sprite.SetY(Window.GetHeight() / 2 - logo.image.GetHeight() / 2);
EOF
printf 'plymouth\nplymouth-themes\n' >> config/package-lists/siorra.list.chroot

# GRUB / syslinux splash: copy live-build templates, swap splash images
mkdir -p config/bootloaders
cp -rn /usr/share/live/build/bootloaders/* config/bootloaders/ 2>/dev/null || true
find config/bootloaders -name 'splash.png' -exec cp "$B/boot-splash-640x480.png" {} \;

# Calamares branding
K=$C/etc/calamares/branding/siorra
mkdir -p $K
cp "$B/siorra-logo-128.png" $K/logo.png
cat > $K/branding.desc <<'EOF'
---
componentName: siorra
welcomeStyleCalamares: true
strings:
  productName: Siorra Linux
  shortProductName: Siorra
  version: 0.1
  shortVersion: 0.1
  versionedName: Siorra Linux 0.1
  shortVersionedName: Siorra 0.1
  bootloaderEntryName: Siorra
  productUrl: https://example.com/siorra
  supportUrl: https://example.com/siorra/support
  knownIssuesUrl: https://example.com/siorra/bugs
  releaseNotesUrl: https://example.com/siorra/notes
images:
  productLogo: "logo.png"
  productIcon: "logo.png"
slideshow: "show.qml"
style:
  sidebarBackground: "#1c1b19"
  sidebarText: "#FFFFFF"
  sidebarTextSelect: "#D85A30"
EOF
cat > $K/show.qml <<'EOF'
import QtQuick 2.0;
import calamares.slideshow 1.0;
Presentation {
    id: presentation
    Slide {
        Image { source: "logo.png"; anchors.centerIn: parent }
    }
}
EOF

# Chroot hook: activate theme + Calamares branding
cat > config/hooks/normal/0200-siorra-theme.hook.chroot <<'EOF'
#!/bin/sh
set -e
plymouth-set-default-theme siorra || true
sed -i 's/^branding:.*/branding: siorra/' /etc/calamares/settings.conf || true
gtk-update-icon-cache -f /usr/share/icons/hicolor 2>/dev/null || true
update-initramfs -u -k all
EOF
chmod +x config/hooks/normal/0200-siorra-theme.hook.chroot
echo "Siorra branding applied."
