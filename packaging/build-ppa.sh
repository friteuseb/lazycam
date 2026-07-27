#!/usr/bin/env bash
# build-ppa.sh — build signed Debian *source* packages for the Launchpad PPA.
#
#   ./packaging/build-ppa.sh 0.2.0 noble jammy
#
# Launchpad builds the binaries itself, so it only accepts source uploads, one
# per Ubuntu series, each with its own version. This script rewrites
# debian/changelog per series, builds into a temporary directory (so nothing
# lands next to the repository), and prints the dput commands.
#
# Prerequisites, none of which this script installs for you:
#   sudo apt install devscripts debhelper dput
#   a GPG key registered on your Launchpad account, and the Ubuntu Code of
#   Conduct signed (Launchpad refuses uploads otherwise)
#
# The key is NOT the APT repository key in ~/.lazycam-apt-gnupg — that one is a
# passphrase-less key made for signing the self-hosted repo. Launchpad needs a
# key attached to your Launchpad identity. Select it with:
#   export LAZYCAM_PPA_KEY=<keyid>
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PPA="${LAZYCAM_PPA:-ppa:cyril-wolfangel/lazycam}"
OUT="$ROOT/dist/ppa"

[ $# -ge 2 ] || {
    echo "Usage: $0 <version> <series> [series...]" >&2
    echo "   e.g. $0 0.2.0 noble jammy" >&2
    exit 1
}
VERSION="$1"; shift
SERIES=("$@")

missing=()
for c in dpkg-buildpackage dpkg-source debuild dh; do
    command -v "$c" >/dev/null || missing+=("$c")
done
if [ ${#missing[@]} -gt 0 ]; then
    echo "Missing tools: ${missing[*]}" >&2
    echo "Install them with: sudo apt install devscripts debhelper dput" >&2
    exit 1
fi

if [ -n "${LAZYCAM_PPA_KEY:-}" ]; then
    SIGN=(-k"$LAZYCAM_PPA_KEY")
else
    echo "⚠  LAZYCAM_PPA_KEY is not set — building UNSIGNED packages."
    echo "   Launchpad rejects unsigned uploads; this is only good for a local check."
    echo
    SIGN=(-us -uc)
fi

mkdir -p "$OUT"
ORIG_CHANGELOG="$(cat "$ROOT/debian/changelog")"
restore() { printf '%s' "$ORIG_CHANGELOG" > "$ROOT/debian/changelog"; }
trap restore EXIT

DATE="$(date -R)"

for series in "${SERIES[@]}"; do
    full="${VERSION}~${series}1"
    echo "── ${series} → lazycam ${full} ─────────────────────────────"

    cat > "$ROOT/debian/changelog" <<EOF
lazycam ($full) $series; urgency=low

  * Release $VERSION for $series.

 -- Cyril Wolfangel <cyril.wolfangel@gmail.com>  $DATE
EOF

    build="$(mktemp -d)"
    cp -a "$ROOT" "$build/lazycam-$full"
    rm -rf "$build/lazycam-$full/.git" "$build/lazycam-$full/dist"
    ( cd "$build/lazycam-$full" && debuild -S -sa "${SIGN[@]}" )

    find "$build" -maxdepth 1 -type f \
        \( -name '*.dsc' -o -name '*.tar.*' -o -name '*.changes' -o -name '*.buildinfo' \) \
        -exec mv -t "$OUT" {} +
    rm -rf "$build"
    echo
done

restore
trap - EXIT

echo "✓ Source packages in $OUT:"
ls -1 "$OUT"/*.changes 2>/dev/null | sed 's/^/    /'
echo
echo "Upload them with:"
for series in "${SERIES[@]}"; do
    echo "    dput $PPA $OUT/lazycam_${VERSION}~${series}1_source.changes"
done
echo
echo "Launchpad then builds the binaries and emails you the result."
echo "Users install with:"
echo "    sudo add-apt-repository $PPA && sudo apt update && sudo apt install lazycam"
