#!/usr/bin/env bash
#
# build-deb.sh — construit le paquet Debian/Ubuntu lazycam dans dist/.
# Usage : ./packaging/build-deb.sh [version]   (défaut : 0.2.0)
#
set -eu

VERSION="${1:-0.2.0}"
ARCH=all
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PKG="lazycam"
STAGE="$(mktemp -d)"
OUT="$ROOT/dist"
DEB="$OUT/${PKG}_${VERSION}_${ARCH}.deb"

trap 'rm -rf "$STAGE"' EXIT
mkdir -p "$OUT"
chmod 0755 "$STAGE"          # racine du paquet en 755 (pas 700 hérité de mktemp)

# ── arborescence installée ────────────────────────────────────────────────
install -d "$STAGE/usr/bin" \
           "$STAGE/usr/share/lazycam" \
           "$STAGE/usr/share/applications" \
           "$STAGE/usr/share/icons/hicolor/scalable/apps" \
           "$STAGE/usr/share/doc/lazycam" \
           "$STAGE/DEBIAN"

# scripts moteur + raccourcis
# glob sur bin/ : un nouveau script est empaqueté sans toucher à une liste.
for f in "$ROOT"/bin/*; do
    [ -f "$f" ] || continue
    install -m 0755 "$f" "$STAGE/usr/bin/$(basename "$f")"
done

# GUI (lib) + lanceur
install -m 0644 "$ROOT"/gui/*.py "$STAGE/usr/share/lazycam/"
install -m 0755 "$ROOT/packaging/lazycam-config" "$STAGE/usr/bin/lazycam-config"

# entrée de menu + icône (nommées d'après l'app-id)
install -m 0644 "$ROOT/data/org.friteuseb.lazycam.desktop" \
    "$STAGE/usr/share/applications/org.friteuseb.lazycam.desktop"
install -m 0644 "$ROOT/data/icon.svg" \
    "$STAGE/usr/share/icons/hicolor/scalable/apps/org.friteuseb.lazycam.svg"

# doc + copyright + changelog (réduit le bruit lintian)
install -m 0644 "$ROOT/README.md" "$STAGE/usr/share/doc/lazycam/README.md"
cat > "$STAGE/usr/share/doc/lazycam/copyright" <<EOF
Format: https://www.debian.org/doc/packaging-manuals/copyright-format/1.0/
Upstream-Name: lazycam
Source: https://github.com/friteuseb/lazycam

Files: *
Copyright: $(date +%Y) Cyril Wolfangel <cyril.wolfangel@gmail.com>
License: GPL-3.0+
EOF
: | gzip -9n > "$STAGE/usr/share/doc/lazycam/changelog.Debian.gz"
{ echo "lazycam ($VERSION) unstable; urgency=low"; echo;
  echo "  * Paquet initial."; echo;
  echo " -- Cyril Wolfangel <cyril.wolfangel@gmail.com>  $(date -R)"; } \
  | gzip -9n > "$STAGE/usr/share/doc/lazycam/changelog.Debian.gz"

# ── métadonnées du paquet ─────────────────────────────────────────────────
INSTALLED_KB="$(du -sk "$STAGE/usr" | cut -f1)"
cat > "$STAGE/DEBIAN/control" <<EOF
Package: $PKG
Version: $VERSION
Architecture: $ARCH
Maintainer: Cyril Wolfangel <cyril.wolfangel@gmail.com>
Installed-Size: $INSTALLED_KB
Depends: python3, python3-gi, gir1.2-gtk-4.0, gir1.2-adw-1 (>= 1.4), jq, ffmpeg, pipewire-bin, wireplumber, libnotify-bin, libglib2.0-bin
Recommends: flatpak
Section: video
Priority: optional
Homepage: https://github.com/friteuseb/lazycam
Description: one-key screen recorder for GNOME on Wayland
 lazycam records your screen and your voice from a single shortcut (Super+R),
 picks the microphone and the monitor automatically from a preference order,
 handles pause/resume, and edits the video automatically when you stop.
 .
 A thin layer on top of the GPU Screen Recorder engine (installed via Flatpak).
 Includes a GTK4 configuration interface (lazycam-config).
EOF

# postinst : caches système + rappels (les raccourcis sont par-utilisateur).
cat > "$STAGE/DEBIAN/postinst" <<'EOF'
#!/bin/sh
set -e
if [ "$1" = "configure" ]; then
    command -v update-desktop-database >/dev/null 2>&1 && \
        update-desktop-database -q /usr/share/applications 2>/dev/null || true
    command -v gtk-update-icon-cache >/dev/null 2>&1 && \
        gtk-update-icon-cache -qtf /usr/share/icons/hicolor 2>/dev/null || true
    echo ""
    echo "lazycam installed. Two steps remain on your side:"
    echo "  1) Capture engine (once):"
    echo "       flatpak install -y flathub com.dec05eba.gpu_screen_recorder"
    echo "  2) Enable the Super+R shortcut:"
    echo "       lazycam-shortcuts        (or from lazycam-config)"
    echo ""
fi
exit 0
EOF
chmod 0755 "$STAGE/DEBIAN/postinst"

# postrm : rafraîchit les caches après suppression.
cat > "$STAGE/DEBIAN/postrm" <<'EOF'
#!/bin/sh
set -e
if [ "$1" = "remove" ] || [ "$1" = "purge" ]; then
    command -v update-desktop-database >/dev/null 2>&1 && \
        update-desktop-database -q /usr/share/applications 2>/dev/null || true
    command -v gtk-update-icon-cache >/dev/null 2>&1 && \
        gtk-update-icon-cache -qtf /usr/share/icons/hicolor 2>/dev/null || true
fi
exit 0
EOF
chmod 0755 "$STAGE/DEBIAN/postrm"

# ── build ─────────────────────────────────────────────────────────────────
fakeroot dpkg-deb --build --root-owner-group "$STAGE" "$DEB" >/dev/null
echo "✓ Paquet construit : $DEB"
echo "  Installer :  sudo apt install $DEB"
echo "  Contenu   :  dpkg -c $DEB"
