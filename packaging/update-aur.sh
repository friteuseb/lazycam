#!/usr/bin/env bash
# update-aur.sh — refresh packaging/aur/PKGBUILD and .SRCINFO for a released tag.
#
#   ./packaging/update-aur.sh 0.2.0
#   ./packaging/update-aur.sh 0.2.0 --offline   # regenerate .SRCINFO only
#
# Sets pkgver, downloads the GitHub tag tarball, computes its sha256 and writes
# both files. .SRCINFO is generated here rather than with `makepkg --printsrcinfo`
# so this works from Ubuntu, where makepkg does not exist.
#
# Publishing (once, needs an AUR account with your SSH key registered):
#   git clone ssh://aur@aur.archlinux.org/lazycam.git aur-lazycam
#   cp packaging/aur/PKGBUILD packaging/aur/.SRCINFO aur-lazycam/
#   cd aur-lazycam && git add -A && git commit -m "lazycam 0.2.0" && git push
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
AUR="$ROOT/packaging/aur"
PKGBUILD="$AUR/PKGBUILD"
SRCINFO="$AUR/.SRCINFO"

[ $# -ge 1 ] || { echo "Usage: $0 <version> [--offline]" >&2; exit 1; }
VERSION="$1"
OFFLINE=0
[ "${2:-}" = "--offline" ] && OFFLINE=1

[ -f "$PKGBUILD" ] || { echo "Not found: $PKGBUILD" >&2; exit 1; }

sed -i "s/^pkgver=.*/pkgver=$VERSION/" "$PKGBUILD"

if [ "$OFFLINE" -eq 0 ]; then
    url="https://github.com/friteuseb/lazycam/archive/refs/tags/v${VERSION}.tar.gz"
    tmp="$(mktemp)"
    trap 'rm -f "$tmp"' EXIT
    echo "▶ fetching $url"
    if ! curl -fsSL -o "$tmp" "$url"; then
        echo "Could not download the tarball. Is the tag v$VERSION pushed to GitHub?" >&2
        echo "Push it first, or re-run with --offline to only regenerate .SRCINFO." >&2
        exit 1
    fi
    sum="$(sha256sum "$tmp" | cut -d' ' -f1)"
    echo "▶ sha256 $sum"
    sed -i "s/^sha256sums=.*/sha256sums=('$sum')/" "$PKGBUILD"
else
    echo "▶ offline: leaving sha256sums untouched"
fi

# --- .SRCINFO, generated from the PKGBUILD itself --------------------------
# Sourcing only defines variables and the package() function; nothing is run.
# shellcheck disable=SC1090
(
    source "$PKGBUILD"
    {
        printf 'pkgbase = %s\n' "$pkgname"
        printf '\tpkgdesc = %s\n' "$pkgdesc"
        printf '\tpkgver = %s\n'  "$pkgver"
        printf '\tpkgrel = %s\n'  "$pkgrel"
        printf '\turl = %s\n'     "$url"
        for a in "${arch[@]}";       do printf '\tarch = %s\n' "$a"; done
        for l in "${license[@]}";    do printf '\tlicense = %s\n' "$l"; done
        for d in "${depends[@]}";    do printf '\tdepends = %s\n' "$d"; done
        for o in "${optdepends[@]}"; do printf '\toptdepends = %s\n' "$o"; done
        for s in "${source[@]}";     do printf '\tsource = %s\n' "$s"; done
        for c in "${sha256sums[@]}"; do printf '\tsha256sums = %s\n' "$c"; done
        printf '\n'
        printf 'pkgname = %s\n' "$pkgname"
    } > "$SRCINFO"
)

echo "✓ $PKGBUILD"
echo "✓ $SRCINFO"

if grep -q REPLACE_ME "$PKGBUILD"; then
    echo
    echo "⚠  sha256sums is still a placeholder — do not publish this to the AUR."
    echo "   Tag and push v$VERSION, then re-run without --offline."
fi
