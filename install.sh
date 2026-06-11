#!/usr/bin/env bash
#
# install.sh — installe lazycam : copie les scripts dans ~/.local/bin et pose
# les raccourcis GNOME (Super+R = start/stop, Super+Shift+R = pause/reprise).
#
# Idempotent : relançable sans créer de doublons. Ne touche pas aux raccourcis
# GNOME existants autres que ceux de lazycam.
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

c_ok()   { printf '  \033[32m✓\033[0m %s\n' "$1"; }
c_warn() { printf '  \033[33m!\033[0m %s\n' "$1"; }
c_err()  { printf '  \033[31m✗\033[0m %s\n' "$1"; }
title()  { printf '\n\033[1m%s\033[0m\n' "$1"; }

# ───────────────────────── 1. Dépendances système ─────────────────────────
title "1/5  Vérification des dépendances"
missing=()
declare -A PKG=(
    [pw-record]=pipewire-bin [pw-dump]=pipewire-bin [wpctl]=wireplumber
    [jq]=jq [ffmpeg]=ffmpeg [notify-send]=libnotify-bin
    [gsettings]=libglib2.0-bin [gdbus]=libglib2.0-bin [flatpak]=flatpak
)
for cmd in pw-record pw-dump wpctl jq ffmpeg notify-send gsettings gdbus flatpak; do
    if command -v "$cmd" >/dev/null; then c_ok "$cmd"; else
        c_err "$cmd manquant (paquet : ${PKG[$cmd]})"; missing+=("${PKG[$cmd]}")
    fi
done
if [ "${#missing[@]}" -gt 0 ]; then
    uniq_pkgs="$(printf '%s\n' "${missing[@]}" | sort -u | tr '\n' ' ')"
    c_warn "Installe les paquets manquants puis relance :"
    printf '      sudo apt install %s\n' "$uniq_pkgs"
    exit 1
fi

# ───────────────────────── 2. Moteur GPU Screen Recorder ──────────────────
title "2/5  Moteur GPU Screen Recorder (flatpak)"
if flatpak info "$GSR_APP" >/dev/null 2>&1; then
    c_ok "$GSR_APP déjà installé"
else
    c_warn "$GSR_APP absent."
    read -rp "  Installer depuis Flathub maintenant ? [O/n] " ans
    case "${ans:-O}" in
        [nN]*) c_warn "Ignoré — lazycam ne pourra pas enregistrer sans ce moteur." ;;
        *) flatpak install -y flathub "$GSR_APP" \
             && c_ok "Moteur installé" || { c_err "Échec de l'installation"; exit 1; } ;;
    esac
fi

# ───────────────────────── 3. Copie des scripts ───────────────────────────
title "3/5  Installation des scripts → $BIN_DIR"
mkdir -p "$BIN_DIR"
for f in gsr-common.sh gsr-toggle.sh gsr-pause.sh gsr-config.sh; do
    install -m 0755 "$SRC_DIR/$f" "$BIN_DIR/$f" && c_ok "$f"
done

# ───────────────────────── 4. Interface graphique ─────────────────────────
title "4/5  Interface de configuration (GTK)"
if python3 -c 'import gi; gi.require_version("Gtk","4.0"); gi.require_version("Adw","1")' 2>/dev/null; then
    mkdir -p "$LIB_DIR" "$APPS_DIR" "$ICON_DIR"
    install -m 0644 "$GUI_DIR/lazycam_backend.py" "$LIB_DIR/lazycam_backend.py"
    install -m 0644 "$GUI_DIR/lazycam-gui.py"     "$LIB_DIR/lazycam-gui.py"
    c_ok "GUI → $LIB_DIR"
    # commande de lancement
    cat > "$BIN_DIR/lazycam-config" <<EOF
#!/usr/bin/env bash
exec python3 "$LIB_DIR/lazycam-gui.py" "\$@"
EOF
    chmod +x "$BIN_DIR/lazycam-config"
    c_ok "commande : lazycam-config"
    # icône + entrée de menu
    install -m 0644 "$DATA_DIR/icon.svg" "$ICON_DIR/lazycam.svg"
    install -m 0644 "$DATA_DIR/lazycam-config.desktop" "$APPS_DIR/lazycam-config.desktop"
    command -v update-desktop-database >/dev/null && update-desktop-database "$APPS_DIR" 2>/dev/null
    c_ok "entrée de menu « lazycam » + icône"
else
    c_warn "PyGObject/GTK4/libadwaita absent — GUI non installée."
    c_warn "Pour l'activer : sudo apt install python3-gi gir1.2-gtk-4.0 gir1.2-adw-1"
fi

# ───────────────────────── 5. Raccourcis GNOME ────────────────────────────
title "5/5  Raccourcis clavier GNOME"
SCHEMA=org.gnome.settings-daemon.plugins.media-keys
LISTKEY=custom-keybindings
BASE=/org/gnome/settings-daemon/plugins/media-keys/custom-keybindings

# tableau des chemins de raccourcis custom existants
raw="$(gsettings get "$SCHEMA" "$LISTKEY")"
existing=()
if [ "$raw" != "@as []" ] && [ "$raw" != "[]" ]; then
    tmp="${raw#[}"; tmp="${tmp%]}"
    IFS=',' read -ra parts <<< "$tmp"
    for p in "${parts[@]}"; do
        p="${p//\'/}"; p="${p// /}"; [ -n "$p" ] && existing+=("$p")
    done
fi

# ensure_kb <nom> <commande> <binding> : réutilise le slot si la commande
# existe déjà, sinon en crée un nouveau. Ne crée jamais de doublon.
ensure_kb() {
    local name="$1" cmd="$2" bind="$3" path="" p rs i=0
    for p in ${existing[@]+"${existing[@]}"}; do
        rs="$SCHEMA.custom-keybinding:$p"
        if [ "$(gsettings get "$rs" command 2>/dev/null)" = "'$cmd'" ]; then path="$p"; break; fi
    done
    if [ -z "$path" ]; then
        while printf '%s\n' ${existing[@]+"${existing[@]}"} | grep -q "/custom$i/\$"; do i=$((i+1)); done
        path="$BASE/custom$i/"; existing+=("$path")
    fi
    rs="$SCHEMA.custom-keybinding:$path"
    gsettings set "$rs" name "$name"
    gsettings set "$rs" command "$cmd"
    gsettings set "$rs" binding "$bind"
    c_ok "$bind → $name"
}

ensure_kb "lazycam : enregistrer (start/stop)" "$BIN_DIR/gsr-toggle.sh" "<Super>r"
ensure_kb "lazycam : pause / reprise"          "$BIN_DIR/gsr-pause.sh"  "<Super><Shift>r"

# réécrit le tableau des chemins
arr="["; n="${#existing[@]}"
for idx in "${!existing[@]}"; do
    arr+="'${existing[$idx]}'"; [ "$idx" -lt "$((n-1))" ] && arr+=", "
done
arr+="]"
gsettings set "$SCHEMA" "$LISTKEY" "$arr"

title "Terminé ✓"
cat <<EOF
  lazycam est installé.

    • Super + R          démarre / arrête l'enregistrement (écran + voix)
    • Super + Shift + R  met en pause / reprend
    • lazycam-config     interface de réglages (ordre micros/écrans, qualité…)

  Sorties dans ~/Videos. Le micro et l'écran sont choisis automatiquement
  selon ton ordre de préférence. Bon enregistrement !
EOF
