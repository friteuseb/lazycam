#!/usr/bin/env bash
# make-demo.sh — turn a lazycam recording into the demo assets used by the
# website and the README.
#
#   ./packaging/make-demo.sh ~/Videos/tuto_20260726_101500.mp4 --start 3 --duration 15
#
# Produces, in docs/ by default:
#   demo.mp4         web-optimised, silent, loopable (used by the landing page)
#   demo-poster.png  first frame (poster= attribute, shown before autoplay kicks in)
#   demo.gif         downscaled GIF (used by the README, which cannot play video)
#
# The --key option draws a "Super + R" badge over a time range. It exists
# because showmethekey — the key overlay lazycam supports at record time — has
# no Flathub or apt package on Ubuntu (source build only), so the keypress is
# usually easier to add here in post.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

START=0
DURATION=15
WIDTH=960
GIF_WIDTH=720
GIF_FPS=12
OUTDIR="$ROOT/docs"
FONT=/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf
KEY_RANGES=()
ENDCARD=""
ENDCARD_DUR=2

usage() {
    sed -n '2,17p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
    cat <<'EOF'

Options:
  --start SEC        where to start in the source file   (default 0)
  --duration SEC     length of the clip                  (default 15)
  --width PX         width of demo.mp4                   (default 960)
  --gif-width PX     width of demo.gif                   (default 720)
  --gif-fps N        frame rate of demo.gif              (default 12)
  --key START:END    draw a "Super + R" badge between these two times,
                     in seconds and relative to the trimmed clip.
                     Repeatable: --key 0.5:2 --key 12:13.5
  --endcard "A|B"    append a closing card with A as the headline and B under
                     it. A self-recorded demo stops before lazycam finishes
                     writing the file, so the payoff — "and here is the MP4" —
                     cannot be in the footage. This states it instead of
                     faking a screenshot of it.
  --endcard-dur SEC  how long the closing card lasts     (default 2)
  --outdir DIR       where to write the assets           (default docs/)
  -h, --help         this help
EOF
}

# escape a string for use inside a drawtext text= option
dt_escape() { printf '%s' "$1" | sed -e 's/\\/\\\\/g' -e "s/'/\\\\'/g" -e 's/:/\\:/g' -e 's/%/\\%/g'; }

[ $# -ge 1 ] || { usage; exit 1; }
SRC="$1"; shift

while [ $# -gt 0 ]; do
    case "$1" in
        --start)     START="$2";     shift 2 ;;
        --duration)  DURATION="$2";  shift 2 ;;
        --width)     WIDTH="$2";     shift 2 ;;
        --gif-width) GIF_WIDTH="$2"; shift 2 ;;
        --gif-fps)   GIF_FPS="$2";   shift 2 ;;
        --outdir)    OUTDIR="$2";    shift 2 ;;
        --key)       KEY_RANGES+=("$2"); shift 2 ;;
        --endcard)     ENDCARD="$2";     shift 2 ;;
        --endcard-dur) ENDCARD_DUR="$2"; shift 2 ;;
        -h|--help)   usage; exit 0 ;;
        *) echo "Unknown option: $1" >&2; usage; exit 1 ;;
    esac
done

command -v ffmpeg >/dev/null || { echo "ffmpeg is required (sudo apt install ffmpeg)" >&2; exit 1; }
[ -f "$SRC" ] || { echo "No such file: $SRC" >&2; exit 1; }
mkdir -p "$OUTDIR"

# --- video filter chain ----------------------------------------------------
# `badges` holds only the drawtext overlays; the scale filter is prepended per
# branch below, because the closing card needs an explicit height to concat.
badges=""

if [ ${#KEY_RANGES[@]} -gt 0 ]; then
    if [ ! -f "$FONT" ]; then
        echo "Font not found: $FONT — install fonts-dejavu-core, or edit FONT in this script." >&2
        exit 1
    fi
    for range in "${KEY_RANGES[@]}"; do
        from="${range%%:*}"; to="${range##*:}"
        if [ "$from" = "$range" ] || [ -z "$to" ]; then
            echo "Malformed --key '$range' — expected START:END, e.g. 0.5:2" >&2
            exit 1
        fi
        badges+=",drawtext=fontfile='${FONT}':text='Super + R'"
        badges+=":fontcolor=white:fontsize=h/22:box=1:boxcolor=0x1e1e2e@0.82:boxborderw=20"
        badges+=":x=(w-text_w)/2:y=h-text_h-h/12"
        badges+=":enable='between(t\,${from}\,${to})'"
    done
fi

echo "▶ source   : $SRC"
echo "▶ clip     : ${DURATION}s from ${START}s"
echo "▶ output   : $OUTDIR"
[ ${#KEY_RANGES[@]} -gt 0 ] && echo "▶ key badge: ${KEY_RANGES[*]}"
echo

# --- 1) demo.mp4 -----------------------------------------------------------
echo "[1/3] demo.mp4"
X264=(-c:v libx264 -preset slow -crf 28 -pix_fmt yuv420p -movflags +faststart)

if [ -z "$ENDCARD" ]; then
    ffmpeg -hide_banner -loglevel error -y \
        -ss "$START" -i "$SRC" -t "$DURATION" \
        -vf "scale=${WIDTH}:-2:flags=lanczos${badges}" \
        -an "${X264[@]}" "$OUTDIR/demo.mp4"
else
    [ -f "$FONT" ] || { echo "Font not found: $FONT" >&2; exit 1; }
    # Match the card to the scaled clip exactly, otherwise concat refuses.
    IFS=, read -r SW SH < <(ffprobe -v error -select_streams v:0 \
        -show_entries stream=width,height -of csv=p=0 "$SRC")
    CH=$(( (SH * WIDTH / SW + 1) / 2 * 2 ))
    FPS_OUT=30

    head="${ENDCARD%%|*}"
    sub=""
    [ "$ENDCARD" != "$head" ] && sub="${ENDCARD#*|}"

    card="drawtext=fontfile='${FONT}':text='$(dt_escape "$head")'"
    card+=":fontcolor=0xcdd6f4:fontsize=h/16:x=(w-text_w)/2"
    card+=":y=(h-text_h)/2-$([ -n "$sub" ] && echo 'h/22' || echo '0')"
    if [ -n "$sub" ]; then
        card+=",drawtext=fontfile='${FONT}':text='$(dt_escape "$sub")'"
        card+=":fontcolor=0x7f849c:fontsize=h/28:x=(w-text_w)/2:y=(h+text_h)/2+h/28"
    fi

    # -t must precede -i here: after it, ffmpeg would attach it to the *next*
    # input (the colour card) instead of trimming the source.
    ffmpeg -hide_banner -loglevel error -y \
        -ss "$START" -t "$DURATION" -i "$SRC" \
        -f lavfi -t "$ENDCARD_DUR" -i "color=c=0x1e1e2e:s=${WIDTH}x${CH}:r=${FPS_OUT}" \
        -filter_complex \
          "[0:v]scale=${WIDTH}:${CH}:flags=lanczos${badges},fps=${FPS_OUT},setsar=1[main];\
           [1:v]${card},fps=${FPS_OUT},setsar=1[card];\
           [main][card]concat=n=2:v=1:a=0[out]" \
        -map "[out]" -an "${X264[@]}" "$OUTDIR/demo.mp4"
fi

# --- 2) demo-poster.png ----------------------------------------------------
echo "[2/3] demo-poster.png"
ffmpeg -hide_banner -loglevel error -y \
    -i "$OUTDIR/demo.mp4" -frames:v 1 "$OUTDIR/demo-poster.png"

# --- 3) demo.gif (two-pass palette, much smaller than a naive one-pass) -----
echo "[3/3] demo.gif"
palette="$(mktemp --suffix=.png)"
trap 'rm -f "$palette"' EXIT
gif_filters="fps=${GIF_FPS},scale=${GIF_WIDTH}:-1:flags=lanczos"
ffmpeg -hide_banner -loglevel error -y -i "$OUTDIR/demo.mp4" \
    -vf "${gif_filters},palettegen=stats_mode=diff" "$palette"
ffmpeg -hide_banner -loglevel error -y -i "$OUTDIR/demo.mp4" -i "$palette" \
    -lavfi "${gif_filters}[x];[x][1:v]paletteuse=dither=bayer:bayer_scale=5:diff_mode=rectangle" \
    "$OUTDIR/demo.gif"

# --- report ----------------------------------------------------------------
echo
for f in demo.mp4 demo-poster.png demo.gif; do
    printf '  %-16s %s\n' "$f" "$(du -h "$OUTDIR/$f" | cut -f1)"
done

gif_bytes=$(stat -c%s "$OUTDIR/demo.gif")
if [ "$gif_bytes" -gt 5000000 ]; then
    echo
    echo "⚠  demo.gif is over 5 MB — GitHub will be slow to render it in the README."
    echo "   Try: --gif-width 600 --gif-fps 10, or a shorter --duration."
fi

cat <<EOF

Next: uncomment the demo blocks that reference these files.
  docs/index.html      (hero section)
  docs/fr/index.html   (hero section)
  README.md            (below the badges)
  README.fr.md         (below the badges)
EOF
