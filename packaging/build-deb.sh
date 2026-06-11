#!/usr/bin/env bash
#
# build-deb.sh — construit le paquet Debian/Ubuntu lazycam dans dist/.
# Usage : ./packaging/build-deb.sh [version]   (défaut : 0.1.0)
#
set -eu

VERSION="${1:-0.1.0}"
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
for f in gsr-common.sh gsr-toggle.sh gsr-pause.sh gsr-config.sh lazycam-shortcuts; do
    install -m 0755 "$ROOT/bin/$f" "$STAGE/usr/bin/$f"
done

# GUI (lib) + lanceur
install -m 0644 "$ROOT/gui/lazycam_backend.py" "$STAGE/usr/share/lazycam/lazycam_backend.py"
install -m 0644 "$ROOT/gui/lazycam-gui.py"     "$STAGE/usr/share/lazycam/lazycam-gui.py"
cat > "$STAGE/usr/bin/lazycam-config" <<'EOF'
#!/usr/bin/env bash
exec python3 /usr/share/lazycam/lazycam-gui.py "$@"
EOF
chmod 0755 "$STAGE/usr/bin/lazycam-config"

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
Depends: python3, python3-gi, gir1.2-gtk-4.0, gir1.2-adw-1, jq, ffmpeg, pipewire-bin, wireplumber, libnotify-bin, libglib2.0-bin
Recommends: flatpak
Section: video
Priority: optional
Homepage: https://github.com/friteuseb/lazycam
Description: Enregistreur d'écran « une touche » pour GNOME
 lazycam filme l'écran et la voix d'un seul raccourci (Super+R), choisit
 automatiquement le micro et l'écran selon un ordre de préférence, gère la
 pause/reprise et monte automatiquement la vidéo à l'arrêt.
 .
 Surcouche au moteur GPU Screen Recorder (à installer via Flatpak).
 Inclut une interface de configuration GTK4 (lazycam-config).
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
    echo "lazycam installé. Deux étapes côté utilisateur :"
    echo "  1) Moteur de capture (une fois) :"
    echo "       flatpak install -y flathub com.dec05eba.gpu_screen_recorder"
    echo "  2) Activer le raccourci Super+R :"
    echo "       lazycam-shortcuts        (ou via lazycam-config)"
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
