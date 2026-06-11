#!/usr/bin/env bash
#
# install.sh — installe lazycam : copie les scripts dans ~/.local/bin et pose
# les raccourcis GNOME (Super+R = start/stop, Super+Shift+R = pause/reprise).
#
# Idempotent : relançable sans créer de doublons. Ne touche pas aux raccourcis
# GNOME existants autres que ceux de lazycam.
#
set -u

SRC_DIR="$(cd "$(dirname "$0")" && pwd)/bin"
BIN_DIR="$HOME/.local/bin"
GSR_APP="com.dec05eba.gpu_screen_recorder"

c_ok()   { printf '  \033[32m✓\033[0m %s\n' "$1"; }
c_warn() { printf '  \033[33m!\033[0m %s\n' "$1"; }
c_err()  { printf '  \033[31m✗\033[0m %s\n' "$1"; }
title()  { printf '\n\033[1m%s\033[0m\n' "$1"; }

# ───────────────────────── 1. Dépendances système ─────────────────────────
title "1/4  Vérification des dépendances"
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
title "2/4  Moteur GPU Screen Recorder (flatpak)"
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
title "3/4  Installation des scripts → $BIN_DIR"
mkdir -p "$BIN_DIR"
for f in gsr-common.sh gsr-toggle.sh gsr-pause.sh gsr-config.sh; do
    install -m 0755 "$SRC_DIR/$f" "$BIN_DIR/$f" && c_ok "$f"
done

# ───────────────────────── 4. Raccourcis GNOME ────────────────────────────
title "4/4  Raccourcis clavier GNOME"
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
    • gsr-config.sh      choisir & tester le micro (terminal)

  Sorties dans ~/Videos. Le micro est choisi automatiquement :
  USB (Amazon) › webcam › micro interne. Bon enregistrement !
EOF
