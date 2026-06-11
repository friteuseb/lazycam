#!/usr/bin/env bash
#
# gsr-common.sh — réglages et fonctions partagés par gsr-toggle.sh / gsr-pause.sh.
# (sourcé par les deux ; ne s'exécute pas seul)
#
# --- Réglages par défaut (surchargés par ~/.config/gsr-toggle.conf) -------
OUTDIR="$HOME/Videos"            # dossier de sortie
FPS=30                           # 30 = parfait pour du desktop/tuto
CODEC=h264                       # h264 (compatible partout) | hevc | av1
QUALITY=very_high                # medium | high | very_high | ultra
# Micro : vide = AUTO (webcam si branchée, sinon micro interne du Vivobook).
MIC=""
# Réduction de bruit (1 = active). Désactivée par défaut : rendu plus naturel.
DENOISE=0
# Normalisation de la voix (loudnorm). Vide = aucun traitement.
VOICE_FILTER="loudnorm=I=-16:TP=-1.5:LRA=11"
# -------------------------------------------------------------------------

CONF="${XDG_CONFIG_HOME:-$HOME/.config}/gsr-toggle.conf"
[ -f "$CONF" ] && . "$CONF"

# Chaîne de filtres voix : réduction de bruit (optionnelle) + normalisation.
AUDIO_CHAIN=""
[ "${DENOISE:-0}" = "1" ] && AUDIO_CHAIN="highpass=f=90,afftdn=nf=-25"
[ -n "$VOICE_FILTER" ] && AUDIO_CHAIN="${AUDIO_CHAIN:+$AUDIO_CHAIN,}$VOICE_FILTER"

APP=com.dec05eba.gpu_screen_recorder
# Le VRAI process a comm="gpu-screen-reco" (tronqué à 15c). Les wrappers sont
# "bwrap" : il NE FAUT PAS leur envoyer SIGUSR2 (ça tuerait l'enregistrement).
MATCH='gpu-screen-recorder -w portal'
STATE="${XDG_RUNTIME_DIR:-/tmp}/gsr-toggle.state"

gsr_running() { pgrep -f "$MATCH" >/dev/null; }
# signale uniquement le vrai gsr (pas bwrap, pas ce script) : gsr_signal -USR2 | -INT
gsr_signal()  { pkill "$1" -x gpu-screen-reco 2>/dev/null; }

# --- Choix de l'écran capturé selon l'état du dock (CalDigit) -------------
# GNOME Wayland n'autorise QUE la capture via portal (pas de "-w DP-2" direct).
# Astuce : on garde un token de restauration portal DIFFÉRENT selon que la
# station est branchée ou non. Au 1er usage de chaque état, le portail demande
# quel écran partager (tu choisis l'écran 2 quand c'est docké, l'écran du
# Vivobook sinon) ; ensuite c'est mémorisé et 100 % silencieux.
TOKEN_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/gsr-tokens"

# vrai si un écran externe (≠ panneau interne eDP) est connecté = station branchée
dock_connected() {
    gdbus call --session \
        --dest org.gnome.Mutter.DisplayConfig \
        --object-path /org/gnome/Mutter/DisplayConfig \
        --method org.gnome.Mutter.DisplayConfig.GetCurrentState 2>/dev/null \
        | grep -qE "'(DP|HDMI|DVI|VGA|DisplayPort)-"
}

# renvoie "<filepath>\t<libellé>" : token portal à utiliser + écran décrit
video_token() {
    mkdir -p "$TOKEN_DIR"
    if dock_connected; then
        printf '%s\t%s' "$TOKEN_DIR/docked.token" "écran 2 (station)"
    else
        printf '%s\t%s' "$TOKEN_DIR/laptop.token" "écran du Vivobook"
    fi
}

# Choix auto du micro, par ordre de préférence :
#   1) micro USB dédié (Amazon USB Streaming Mic) — meilleure qualité, prioritaire
#   2) webcam (Creative Cam Sync) si branchée
#   3) micro interne (entrée analogique)
# Vide si rien -> pw-record prend le défaut système.
pick_mic() {
    local src usb cam
    src="$(pw-dump 2>/dev/null | jq -r '.[]|select(.info.props["media.class"]=="Audio/Source")|.info.props["node.name"]' 2>/dev/null)"
    usb="$(printf '%s\n' "$src" | grep -i 'Amazon_USB_Streaming_Mic' | head -1)"
    [ -n "$usb" ] && { printf '%s' "$usb"; return; }
    cam="$(printf '%s\n' "$src" | grep -i 'Cam_Sync\|Creative' | head -1)"
    [ -n "$cam" ] && { printf '%s' "$cam"; return; }
    printf '%s' "$(printf '%s\n' "$src" | grep -iE 'alsa_input\.pci.*analog' | head -1)"
}

# démute le micro choisi (un micro mute n'enregistre QUE du silence).
unmute_mic() {
    [ -n "${1:-}" ] || return 0
    local id
    id="$(pw-dump 2>/dev/null | jq -r --arg n "$1" '.[]|select(.info.props["node.name"]==$n)|.id' 2>/dev/null | head -1)"
    [ -n "$id" ] && wpctl set-mute "$id" 0 2>/dev/null
}

# démarre l'enregistrement du segment audio courant (${APREFIX}.${SEG}.flac).
# Renseigne RECPID. Le process survit à la fin du script (reparenté à init).
start_audio() {
    local out="${APREFIX}.${SEG}.flac"
    unmute_mic "$MIC"
    if [ -n "$MIC" ]; then
        pw-record --target "$MIC" "$out" >/dev/null 2>&1 &
    else
        pw-record "$out" >/dev/null 2>&1 &
    fi
    RECPID=$!
}

# écrit l'état partagé (lu au prochain appui pause/arrêt).
write_state() {
    printf 'VIDEO=%q\nFINAL=%q\nAPREFIX=%q\nSEG=%q\nRECPID=%q\nPAUSED=%q\nMIC=%q\n' \
        "$VIDEO" "$FINAL" "$APREFIX" "$SEG" "$RECPID" "$PAUSED" "$MIC" > "$STATE"
}
