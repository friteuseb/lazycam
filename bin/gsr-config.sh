#!/usr/bin/env bash
#
# gsr-config.sh — choisir et tester le micro utilisé par gsr-toggle.sh.
# Écrit la config dans ~/.config/gsr-toggle.conf (lue par gsr-toggle.sh).
#
set -u

CONF="${XDG_CONFIG_HOME:-$HOME/.config}/gsr-toggle.conf"
mkdir -p "$(dirname "$CONF")"

# valeurs par défaut, surchargées par la config existante
MIC=""
DENOISE=0
[ -f "$CONF" ] && . "$CONF"

for dep in pw-dump jq pw-record pw-play ffmpeg; do
    command -v "$dep" >/dev/null || { echo "Dépendance manquante : $dep" >&2; exit 1; }
done

# --- liste des micros réels (Audio/Source, pas les monitors) -------------
load_mics() {
    NAMES=(); DESCS=()
    while IFS=$'\t' read -r name desc; do
        [ -z "$name" ] && continue
        NAMES+=("$name"); DESCS+=("$desc")
    done < <(pw-dump 2>/dev/null | jq -r '
        .[] | select(.info.props["media.class"]=="Audio/Source")
        | "\(.info.props["node.name"])\t\(.info.props["node.description"] // .info.props["node.nick"] // "micro")"')
}

current_label() {
    [ -z "$MIC" ] && { echo "(micro par défaut du système)"; return; }
    local i
    for i in "${!NAMES[@]}"; do
        [ "${NAMES[$i]}" = "$MIC" ] && { echo "${DESCS[$i]}"; return; }
    done
    echo "$MIC"
}

# --- test : enregistre 4 s, mesure le niveau, réécoute -------------------
test_mic() {
    local target="$1" tmp
    tmp="$(mktemp --suffix=.flac)"
    echo
    echo "🎙  Enregistrement 4 s — PARLE NORMALEMENT maintenant…"
    if [ -n "$target" ]; then
        timeout 4 pw-record --target "$target" "$tmp" 2>/dev/null
    else
        timeout 4 pw-record "$tmp" 2>/dev/null
    fi
    local mean max
    mean="$(ffmpeg -hide_banner -i "$tmp" -af volumedetect -f null /dev/null 2>&1 | grep mean_volume | sed 's/.*: //')"
    max="$(ffmpeg -hide_banner -i "$tmp" -af volumedetect -f null /dev/null 2>&1 | grep max_volume | sed 's/.*: //')"
    echo "   Niveau moyen : ${mean:-?}   |   crête : ${max:-?}"
    echo "   (repère : voix correcte ≈ -25 à -15 dB de moyenne ; bruit de fond plus bas = mieux)"
    echo "▶  Réécoute du test…"
    pw-play "$tmp" 2>/dev/null
    rm -f "$tmp"
    echo
}

# ------------------------------- menu ------------------------------------
while true; do
    load_mics
    clear
    echo "════════════════════════════════════════════════════════"
    echo "  Configuration micro — gsr-toggle (enregistrement écran)"
    echo "════════════════════════════════════════════════════════"
    echo "  Micro actuel    : $(current_label)"
    echo "  Réduction bruit : $([ "${DENOISE:-0}" = 1 ] && echo "ACTIVÉE" || echo "désactivée")"
    echo "────────────────────────────────────────────────────────"
    echo "  Micros disponibles :"
    for i in "${!NAMES[@]}"; do
        mark="  "; [ "${NAMES[$i]}" = "$MIC" ] && mark="→ "
        printf "   %s%d) %s\n" "$mark" "$((i+1))" "${DESCS[$i]}"
    done
    echo
    echo "   0) Micro par défaut du système"
    echo "   t) Tester le micro actuellement sélectionné"
    echo "   d) Activer / désactiver la réduction de bruit"
    echo "   s) Sauvegarder et quitter"
    echo "   q) Quitter sans sauvegarder"
    echo "────────────────────────────────────────────────────────"
    read -rp "  Choix (un numéro pour sélectionner + tester) : " choice

    case "$choice" in
        0) MIC=""; test_mic "" ; read -rp "  [Entrée pour continuer]" _ ;;
        t|T) test_mic "$MIC" ; read -rp "  [Entrée pour continuer]" _ ;;
        d|D) DENOISE=$([ "${DENOISE:-0}" = 1 ] && echo 0 || echo 1) ;;
        s|S)
            printf '# Généré par gsr-config.sh\nMIC=%q\nDENOISE=%q\n' "$MIC" "$DENOISE" > "$CONF"
            echo; echo "✓ Config enregistrée dans $CONF"
            echo "  Micro : $(current_label) | Bruit : $([ "$DENOISE" = 1 ] && echo ON || echo OFF)"
            exit 0 ;;
        q|Q) echo "Quitté sans sauvegarder."; exit 0 ;;
        ''|*[!0-9]*) ;;  # ignore
        *)
            idx=$((choice-1))
            if [ "$idx" -ge 0 ] && [ "$idx" -lt "${#NAMES[@]}" ]; then
                MIC="${NAMES[$idx]}"
                test_mic "$MIC"
                read -rp "  [Entrée pour continuer]" _
            fi ;;
    esac
done
