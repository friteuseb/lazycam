#!/usr/bin/env bash
#
# gsr-pause.sh — met en PAUSE / REPREND l'enregistrement en cours (même touche).
# Raccourci : Super+Shift+R (Super+P est pris par le changement d'affichage GNOME).
#
# La vidéo se met en pause via SIGUSR2 (gpu-screen-recorder retire le temps de
# pause du flux). L'audio (pw-record) n'a pas de pause : on coupe le segment en
# cours à la pause et on en démarre un nouveau à la reprise ; gsr-toggle.sh
# recolle les segments à l'arrêt. Tout reste synchro.
#
set -u
DIR="$(cd "$(dirname "$0")" && pwd)"
. "$DIR/gsr-common.sh"

if ! gsr_running || [ ! -f "$STATE" ]; then
    notify-send -i dialog-information "Enregistrement" "Aucun enregistrement en cours."
    exit 0
fi

VIDEO=""; FINAL=""; APREFIX=""; SEG=0; RECPID=""; PAUSED=0; MIC=""
. "$STATE"

if [ "$PAUSED" = "0" ]; then
    # --- PAUSE ---
    gsr_signal -USR2                                # met la vidéo en pause
    [ -n "$RECPID" ] && kill -INT "$RECPID" 2>/dev/null   # clôt le segment audio
    PAUSED=1
    write_state
    notify-send -i media-playback-pause "Enregistrement" "⏸  En pause"
else
    # --- REPRISE ---
    gsr_signal -USR2                                # reprend la vidéo
    SEG=$((SEG + 1))
    start_audio                                     # nouveau segment audio
    PAUSED=0
    write_state
    notify-send -i media-record "Enregistrement" "▶  Reprise"
fi
