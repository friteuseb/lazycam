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
  --outdir DIR       where to write the assets           (default docs/)
  -h, --help         this help
EOF
}

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
        -h|--help)   usage; exit 0 ;;
        *) echo "Unknown option: $1" >&2; usage; exit 1 ;;
    esac
done

command -v ffmpeg >/dev/null || { echo "ffmpeg is required (sudo apt install ffmpeg)" >&2; exit 1; }
[ -f "$SRC" ] || { echo "No such file: $SRC" >&2; exit 1; }
mkdir -p "$OUTDIR"

# --- video filter chain ----------------------------------------------------
filters="scale=${WIDTH}:-2:flags=lanczos"

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
        filters+=",drawtext=fontfile='${FONT}':text='Super + R'"
        filters+=":fontcolor=white:fontsize=h/22:box=1:boxcolor=0x1e1e2e@0.82:boxborderw=20"
        filters+=":x=(w-text_w)/2:y=h-text_h-h/12"
        filters+=":enable='between(t\,${from}\,${to})'"
    done
fi

echo "▶ source   : $SRC"
echo "▶ clip     : ${DURATION}s from ${START}s"
echo "▶ output   : $OUTDIR"
[ ${#KEY_RANGES[@]} -gt 0 ] && echo "▶ key badge: ${KEY_RANGES[*]}"
echo

# --- 1) demo.mp4 -----------------------------------------------------------
echo "[1/3] demo.mp4"
ffmpeg -hide_banner -loglevel error -y \
    -ss "$START" -i "$SRC" -t "$DURATION" \
    -vf "$filters" \
    -an -c:v libx264 -preset slow -crf 28 -pix_fmt yuv420p -movflags +faststart \
    "$OUTDIR/demo.mp4"

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
