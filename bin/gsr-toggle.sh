#!/usr/bin/env bash
#
# gsr-toggle.sh — démarre / arrête l'enregistrement écran + voix (micro).
# Raccourci : 1er appui = démarre, 2e appui = arrête + fusionne + sauve.
# Pause/reprise : voir gsr-pause.sh (Super+Shift+R).
#
# Pourquoi deux process ?
#   gpu-screen-recorder (flatpak) ne capte PAS le micro (le sandbox PipeWire ne
#   laisse passer que les sorties/monitors). On capte donc la voix séparément
#   avec pw-record, par SEGMENTS (un par période active, pour gérer la pause),
#   et on recolle le tout dans la vidéo au moment de l'arrêt.
#
set -u
DIR="$(cd "$(dirname "$0")" && pwd)"
. "$DIR/gsr-common.sh"

if gsr_running; then
    # ======================= ARRÊT =======================
    VIDEO=""; FINAL=""; APREFIX=""; SEG=0; RECPID=""; PAUSED=0; MIC=""
    [ -f "$STATE" ] && . "$STATE"

    gsr_signal -INT                                 # finalise la vidéo (vrai process)
    [ -n "$RECPID" ] && kill -INT "$RECPID" 2>/dev/null
    pkill -INT -x pw-record 2>/dev/null             # filet de sécurité
    stop_overlays                                   # coupe les overlays tuto
    notify-send -i media-record "Enregistrement" "Arrêt en cours, fusion…"

    for _ in $(seq 1 80); do gsr_running || break; sleep 0.1; done
    # attendre la finalisation des segments audio : tant que pw-record tourne,
    # le FLAC du dernier segment n'est pas refermé (concat l'ignorerait).
    [ -n "$RECPID" ] && for _ in $(seq 1 50); do kill -0 "$RECPID" 2>/dev/null || break; sleep 0.1; done
    for _ in $(seq 1 50); do pgrep -x pw-record >/dev/null || break; sleep 0.1; done
    sleep 0.4

    [ -z "$FINAL" ] && FINAL="$OUTDIR/tuto_$(date +%Y%m%d_%H%M%S).mp4"

    # rassembler les segments audio dans l'ordre (0..SEG)
    segs=()
    if [ -n "$APREFIX" ]; then
        for i in $(seq 0 "$SEG"); do
            [ -f "${APREFIX}.${i}.flac" ] && segs+=("${APREFIX}.${i}.flac")
        done
    fi

    if [ -n "$VIDEO" ] && [ -f "$VIDEO" ] && [ "${#segs[@]}" -ge 1 ]; then
        # fusion vidéo + voix en UNE passe : on recolle les segments audio avec
        # le filtre concat (le concat -c copy casse sur du FLAC), puis filtres voix.
        inputs=(-i "$VIDEO"); for f in "${segs[@]}"; do inputs+=(-i "$f"); done
        n="${#segs[@]}"
        fc=""; for ((k=0; k<n; k++)); do fc+="[$((k+1)):a]"; done
        if [ -n "$AUDIO_CHAIN" ]; then
            fc+="concat=n=$n:v=0:a=1[ac];[ac]$AUDIO_CHAIN[a]"
        else
            fc+="concat=n=$n:v=0:a=1[a]"
        fi
        if ffmpeg -hide_banner -loglevel error -y \
               "${inputs[@]}" -filter_complex "$fc" \
               -map 0:v -map '[a]' -c:v copy -c:a aac -b:a 192k -shortest \
               "$FINAL"; then
            rm -f "$VIDEO" "${segs[@]}"
            notify-send -i media-record "Enregistrement" "Terminé ✓  $(basename "$FINAL")"
        else
            notify-send -i dialog-error "Enregistrement" \
                "Fusion échouée — fichiers bruts conservés dans $OUTDIR"
        fi
    elif [ -n "$VIDEO" ] && [ -f "$VIDEO" ]; then
        mv -f "$VIDEO" "$FINAL"
        notify-send -i dialog-warning "Enregistrement" \
            "Terminé SANS voix ✓  $(basename "$FINAL")"
    else
        notify-send -i dialog-error "Enregistrement" "Aucun fichier vidéo trouvé."
    fi
    rm -f "$STATE"
else
    # ======================= DÉMARRAGE =======================
    mkdir -p "$OUTDIR"
    STAMP="$(date +%Y%m%d_%H%M%S)"
    VIDEO="$OUTDIR/.rec_${STAMP}.video.mp4"
    APREFIX="$OUTDIR/.rec_${STAMP}.mic"
    FINAL="$OUTDIR/tuto_${STAMP}.mp4"
    SEG=0; PAUSED=0

    # écran capturé : arguments -w … selon la config (portal par défaut)
    read -ra VARGS <<< "$(video_capture_args)"

    # 1) vidéo (gsr, SANS audio)
    "${GSR_CMD[@]}" \
        "${VARGS[@]}" \
        -f "$FPS" -k "$CODEC" -q "$QUALITY" \
        -o "$VIDEO" >/dev/null 2>&1 &

    # 2) voix (pw-record). MIC vide => choix auto selon l'ordre de préférence.
    [ -z "$MIC" ] && MIC="$(pick_mic)"
    start_audio

    # 3) overlays tuto éventuels (touches pressées)
    start_overlays

    write_state
    notify-send -i media-record "Enregistrement" "Démarré ●  écran + voix  →  $(basename "$FINAL")"
fi
