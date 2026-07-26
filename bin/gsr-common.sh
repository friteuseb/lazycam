#!/usr/bin/env bash
#
# gsr-common.sh — réglages et fonctions partagés par gsr-toggle.sh / gsr-pause.sh.
# (sourcé par les deux ; ne s'exécute pas seul)
#
# --- Réglages par défaut (surchargés par la config) -----------------------
OUTDIR="$HOME/Videos"            # dossier de sortie
FPS=30                           # 30 = parfait pour du desktop/tuto
CODEC=h264                       # h264 (compatible partout) | hevc | av1
QUALITY=very_high                # medium | high | very_high | ultra
MIC=""                           # vide = choix auto (voir pick_mic)
DENOISE=0                        # 1 = réduction de bruit
VOICE_FILTER="loudnorm=I=-16:TP=-1.5:LRA=11"   # vide = pas de normalisation
# -------------------------------------------------------------------------

# Ancienne config shell (rétro-compat) : ~/.config/gsr-toggle.conf
CONF="${XDG_CONFIG_HOME:-$HOME/.config}/gsr-toggle.conf"
[ -f "$CONF" ] && . "$CONF"

# --- Config JSON de lazycam (écrite par la GUI), prioritaire si présente ---
LAZY_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/lazycam"
CONFIG_JSON="$LAZY_DIR/config.json"
# jcfg <filtre-jq> <défaut> : valeur scalaire du JSON, sinon défaut.
# NB : pas de "// empty" — il considère le booléen false comme vide.
jcfg() {
    [ -f "$CONFIG_JSON" ] || { printf '%s' "$2"; return; }
    local v; v="$(jq -r "$1" "$CONFIG_JSON" 2>/dev/null)"
    { [ -n "$v" ] && [ "$v" != "null" ]; } && printf '%s' "$v" || printf '%s' "$2"
}
# jarr <filtre-jq-array> : éléments d'un tableau JSON, un par ligne.
jarr() {
    [ -f "$CONFIG_JSON" ] || return
    jq -r "$1 // [] | .[]" "$CONFIG_JSON" 2>/dev/null
}
if [ -f "$CONFIG_JSON" ]; then
    od="$(jcfg '.outdir' "$OUTDIR")"; OUTDIR="${od/#\~/$HOME}"
    FPS="$(jcfg '.fps' "$FPS")"
    CODEC="$(jcfg '.codec' "$CODEC")"
    QUALITY="$(jcfg '.quality' "$QUALITY")"
    [ "$(jcfg '.denoise' false)" = "true" ] && DENOISE=1 || DENOISE=0
    [ "$(jcfg '.normalize' true)" = "true" ] || VOICE_FILTER=""
fi

# Chaîne de filtres voix : réduction de bruit (optionnelle) + normalisation.
AUDIO_CHAIN=""
[ "${DENOISE:-0}" = "1" ] && AUDIO_CHAIN="highpass=f=90,afftdn=nf=-25"
[ -n "$VOICE_FILTER" ] && AUDIO_CHAIN="${AUDIO_CHAIN:+$AUDIO_CHAIN,}$VOICE_FILTER"

APP=com.dec05eba.gpu_screen_recorder
# Invocation du moteur de capture. Ubuntu/Debian n'ont pas de paquet
# gpu-screen-recorder : il n'existe qu'en Flatpak. Arch (AUR) et d'autres
# distributions l'empaquettent nativement, et le binaire est alors dans le PATH.
# GSR_CMD absorbe les deux cas — sans ça, lazycam ne marche que sur les systèmes
# où le moteur est en Flatpak.
if command -v gpu-screen-recorder >/dev/null 2>&1; then
    GSR_CMD=(gpu-screen-recorder)
else
    GSR_CMD=(flatpak run --command=gpu-screen-recorder "$APP")
fi
# Le VRAI process a comm="gpu-screen-reco" (tronqué à 15c). Les wrappers sont
# "bwrap" : il NE FAUT PAS leur envoyer SIGUSR2 (ça tuerait l'enregistrement).
# MATCH générique (-w suivi de n'importe quel mode : portal, un moniteur, region…)
MATCH='gpu-screen-recorder -w '
STATE="${XDG_RUNTIME_DIR:-/tmp}/gsr-toggle.state"
OVPIDFILE="${XDG_RUNTIME_DIR:-/tmp}/lazycam-overlays.pids"

gsr_running() { pgrep -f "$MATCH" >/dev/null; }
# signale uniquement le vrai gsr (pas bwrap, pas ce script) : gsr_signal -USR2 | -INT
gsr_signal()  { pkill "$1" -x gpu-screen-reco 2>/dev/null; }

# --- Choix de l'écran capturé ---------------------------------------------
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
        printf '%s\t%s' "$TOKEN_DIR/laptop.token" "écran du portable"
    fi
}

# Arguments "-w …" passés à gpu-screen-recorder, selon la config :
#   capture_mode = portal  (défaut) : sélection par le portail (token selon dock)
#                  monitor          : 1er moniteur présent selon screen_order
#                  focused          : fenêtre active
#                  region           : rectangle .region (WxH+X+Y)
video_capture_args() {
    local mode region mons order pat hit vt
    mode="$(jcfg '.capture_mode' portal)"
    case "$mode" in
        focused) printf -- '-w focused'; return ;;
        region)
            region="$(jcfg '.region' '')"
            [ -n "$region" ] && { printf -- '-w region -region %s' "$region"; return; } ;;
        monitor)
            mons="$("${GSR_CMD[@]}" --list-monitors 2>/dev/null | cut -d'|' -f1)"
            order="$(jarr '.screen_order')"
            [ -z "$order" ] && order=$'DP\nHDMI\neDP'
            while IFS= read -r pat; do
                [ -z "$pat" ] && continue
                hit="$(printf '%s\n' "$mons" | grep -iE "$pat" | head -1)"
                [ -n "$hit" ] && { printf -- '-w %s' "$hit"; return; }
            done <<< "$order" ;;
    esac
    # défaut / fallback : portal (token selon dock — comportement historique)
    IFS=$'\t' read -r vt _ < <(video_token)
    printf -- '-w portal -restore-portal-session yes -portal-session-token-filepath %s' "$vt"
}

# Choix auto du micro : 1er appareil présent selon l'ordre de préférence.
# L'ordre vient de la config (.mic_order) ; à défaut, l'ordre historique :
#   USB Amazon › webcam Creative › micro interne analogique.
# Les éléments sont des motifs grep -iE testés sur node.name.
pick_mic() {
    local src order pat hit
    src="$(pw-dump 2>/dev/null | jq -r '.[]|select(.info.props["media.class"]=="Audio/Source")|.info.props["node.name"]' 2>/dev/null)"
    order="$(jarr '.mic_order')"
    [ -z "$order" ] && order=$'Amazon_USB_Streaming_Mic\nCam_Sync|Creative\nalsa_input\\.pci.*analog'
    while IFS= read -r pat; do
        [ -z "$pat" ] && continue
        hit="$(printf '%s\n' "$src" | grep -iE "$pat" | head -1)"
        [ -n "$hit" ] && { printf '%s' "$hit"; return; }
    done <<< "$order"
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

# --- Aides tuto (overlays) -------------------------------------------------
# show_keys : affiche les touches pressées via showmethekey (Wayland-friendly).
# show_clicks : nécessite une extension GNOME Shell (cf. README) — non géré ici.
start_overlays() {
    : > "$OVPIDFILE"
    if [ "$(jcfg '.show_keys' false)" = "true" ]; then
        if command -v showmethekey-gtk >/dev/null 2>&1; then
            showmethekey-gtk >/dev/null 2>&1 & echo $! >> "$OVPIDFILE"
        elif flatpak info one.alynx.showmethekey >/dev/null 2>&1; then
            flatpak run one.alynx.showmethekey >/dev/null 2>&1 & echo $! >> "$OVPIDFILE"
        fi
    fi
}
stop_overlays() {
    [ -f "$OVPIDFILE" ] || return 0
    while read -r p; do [ -n "$p" ] && kill "$p" 2>/dev/null; done < "$OVPIDFILE"
    rm -f "$OVPIDFILE"
}

# écrit l'état partagé (lu au prochain appui pause/arrêt).
write_state() {
    printf 'VIDEO=%q\nFINAL=%q\nAPREFIX=%q\nSEG=%q\nRECPID=%q\nPAUSED=%q\nMIC=%q\n' \
        "$VIDEO" "$FINAL" "$APREFIX" "$SEG" "$RECPID" "$PAUSED" "$MIC" > "$STATE"
}
