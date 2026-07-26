#!/usr/bin/env bash
#
# install.sh — installe lazycam : copie les scripts dans ~/.local/bin et pose
# les raccourcis GNOME (Super+R = start/stop, Super+Shift+R = pause/reprise).
#
# Idempotent : relançable sans créer de doublons. Ne touche pas aux raccourcis
# GNOME existants autres que ceux de lazycam.
#
# Les chaînes affichées passent par msg() / say() (voir bin/lazycam-lang.sh) :
# anglais par défaut, français si la config ou la locale le demande.
#
set -u

ROOT_DIR="$(cd "$(dirname "$0")" && pwd)"
SRC_DIR="$ROOT_DIR/bin"
GUI_DIR="$ROOT_DIR/gui"
DATA_DIR="$ROOT_DIR/data"
BIN_DIR="$HOME/.local/bin"
LIB_DIR="$HOME/.local/share/lazycam"
APPS_DIR="$HOME/.local/share/applications"
ICON_DIR="$HOME/.local/share/icons/hicolor/scalable/apps"
GSR_APP="com.dec05eba.gpu_screen_recorder"

. "$SRC_DIR/lazycam-lang.sh"

c_ok()   { printf '  \033[32m✓\033[0m %s\n' "$1"; }
c_warn() { printf '  \033[33m!\033[0m %s\n' "$1"; }
c_err()  { printf '  \033[31m✗\033[0m %s\n' "$1"; }
title()  { printf '\n\033[1m%s\033[0m\n' "$1"; }

# ───────────────────────── 1. Dépendances système ─────────────────────────
title "$(msg '1/5  Checking dependencies' '1/5  Vérification des dépendances')"
missing=()
declare -A PKG=(
    [pw-record]=pipewire-bin [pw-dump]=pipewire-bin [wpctl]=wireplumber
    [jq]=jq [ffmpeg]=ffmpeg [notify-send]=libnotify-bin
    [gsettings]=libglib2.0-bin [gdbus]=libglib2.0-bin [flatpak]=flatpak
)
for cmd in pw-record pw-dump wpctl jq ffmpeg notify-send gsettings gdbus flatpak; do
    if command -v "$cmd" >/dev/null; then c_ok "$cmd"; else
        c_err "$cmd $(msg "missing (package: ${PKG[$cmd]})" "manquant (paquet : ${PKG[$cmd]})")"
        missing+=("${PKG[$cmd]}")
    fi
done
if [ "${#missing[@]}" -gt 0 ]; then
    uniq_pkgs="$(printf '%s\n' "${missing[@]}" | sort -u | tr '\n' ' ')"
    c_warn "$(msg 'Install the missing packages, then run this again:' \
                  'Installe les paquets manquants puis relance :')"
    printf '      sudo apt install %s\n' "$uniq_pkgs"
    exit 1
fi

# ───────────────────────── 2. Moteur GPU Screen Recorder ──────────────────
title "$(msg '2/5  GPU Screen Recorder engine (flatpak)' \
             '2/5  Moteur GPU Screen Recorder (flatpak)')"
if flatpak info "$GSR_APP" >/dev/null 2>&1; then
    c_ok "$GSR_APP $(msg 'already installed' 'déjà installé')"
else
    c_warn "$GSR_APP $(msg 'not found.' 'absent.')"
    read -rp "$(msg '  Install it from Flathub now? [Y/n] ' \
                    '  Installer depuis Flathub maintenant ? [O/n] ')" ans
    case "${ans:-y}" in
        [nN]*) c_warn "$(msg 'Skipped — lazycam cannot record without this engine.' \
                             'Ignoré — lazycam ne pourra pas enregistrer sans ce moteur.')" ;;
        *) flatpak install -y flathub "$GSR_APP" \
             && c_ok "$(msg 'Engine installed' 'Moteur installé')" \
             || { c_err "$(msg 'Installation failed' 'Échec de l'\''installation')"; exit 1; } ;;
    esac
fi

# ───────────────────────── 3. Copie des scripts ───────────────────────────
title "$(msg "3/5  Installing the scripts → $BIN_DIR" \
             "3/5  Installation des scripts → $BIN_DIR")"
mkdir -p "$BIN_DIR"
# glob sur bin/ : un nouveau script est installé sans toucher à cette liste.
for f in "$SRC_DIR"/*; do
    [ -f "$f" ] || continue
    install -m 0755 "$f" "$BIN_DIR/$(basename "$f")" && c_ok "$(basename "$f")"
done

# ───────────────────────── 4. Interface graphique ─────────────────────────
title "$(msg '4/5  Configuration interface (GTK)' '4/5  Interface de configuration (GTK)')"
if python3 -c 'import gi; gi.require_version("Gtk","4.0"); gi.require_version("Adw","1")' 2>/dev/null; then
    mkdir -p "$LIB_DIR" "$APPS_DIR" "$ICON_DIR"
    install -m 0644 "$GUI_DIR"/*.py "$LIB_DIR/"
    c_ok "GUI → $LIB_DIR"
    # commande de lancement
    cat > "$BIN_DIR/lazycam-config" <<EOF
#!/usr/bin/env bash
exec python3 "$LIB_DIR/lazycam-gui.py" "\$@"
EOF
    chmod +x "$BIN_DIR/lazycam-config"
    c_ok "$(msg 'command: lazycam-config' 'commande : lazycam-config')"
    # icône + entrée de menu — nommées d'après l'app-id pour que la fenêtre
    # Wayland (app_id = org.friteuseb.lazycam) s'associe à son icône.
    APPID=org.friteuseb.lazycam
    rm -f "$APPS_DIR/lazycam-config.desktop" "$ICON_DIR/lazycam.svg"   # anciens noms
    install -m 0644 "$DATA_DIR/icon.svg" "$ICON_DIR/$APPID.svg"
    install -m 0644 "$DATA_DIR/$APPID.desktop" "$APPS_DIR/$APPID.desktop"
    command -v update-desktop-database >/dev/null && update-desktop-database "$APPS_DIR" 2>/dev/null
    command -v gtk-update-icon-cache >/dev/null && \
        gtk-update-icon-cache -qtf "$HOME/.local/share/icons/hicolor" 2>/dev/null
    c_ok "$(msg "“lazycam” menu entry + icon ($APPID)" \
                "entrée de menu « lazycam » + icône ($APPID)")"
else
    c_warn "$(msg 'PyGObject/GTK4/libadwaita missing — GUI not installed.' \
                  'PyGObject/GTK4/libadwaita absent — GUI non installée.')"
    c_warn "$(msg 'To enable it: sudo apt install python3-gi gir1.2-gtk-4.0 gir1.2-adw-1' \
                  "Pour l'activer : sudo apt install python3-gi gir1.2-gtk-4.0 gir1.2-adw-1")"
fi

# ───────────────────────── 5. Raccourcis GNOME ────────────────────────────
title "$(msg '5/5  GNOME keyboard shortcuts' '5/5  Raccourcis clavier GNOME')"
"$BIN_DIR/lazycam-shortcuts" | sed 's/^/  /'

title "$(msg 'Done ✓' 'Terminé ✓')"
if [ "$UI_LANG" = "fr" ]; then
cat <<'EOF'
  lazycam est installé.

    • Super + R          démarre / arrête l'enregistrement (écran + voix)
    • Super + Shift + R  met en pause / reprend
    • lazycam-config     interface de réglages (ordre micros/écrans, qualité…)

  Sorties dans ~/Videos. Le micro et l'écran sont choisis automatiquement
  selon ton ordre de préférence. Bon enregistrement !
EOF
else
cat <<'EOF'
  lazycam is installed.

    • Super + R          starts / stops the recording (screen + voice)
    • Super + Shift + R  pauses / resumes
    • lazycam-config     settings window (mic/monitor order, quality…)

  Output lands in ~/Videos. The microphone and the monitor are picked
  automatically from your preference order. Happy recording!
EOF
fi
