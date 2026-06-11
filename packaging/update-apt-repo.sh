#!/usr/bin/env bash
#
# update-apt-repo.sh — (re)génère le dépôt APT signé dans docs/apt/.
#   À relancer après chaque nouveau .deb construit dans dist/.
#
# La clé privée de signature vit dans $GNUPGHOME (hors du dépôt git) et n'est
# JAMAIS commitée. Sauvegarde ce dossier : sans lui, tu ne peux plus signer.
#
set -eu

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APT="$ROOT/docs/apt"
DIST_DEBS="$ROOT/dist"
GNUPGHOME="${LAZYCAM_GNUPGHOME:-$HOME/.lazycam-apt-gnupg}"
export GNUPGHOME

KEY_NAME="lazycam apt repository"
KEY_EMAIL="lazycam@coconweb.fr"
ORIGIN="lazycam"
SUITE="stable"
COMPONENT="main"
ARCHES="amd64 arm64"

c(){ printf '\033[1m%s\033[0m\n' "$1"; }

# ── 1. clé de signature (créée au 1er passage) ────────────────────────────
mkdir -p "$GNUPGHOME"; chmod 700 "$GNUPGHOME"
if ! gpg --list-secret-keys "$KEY_EMAIL" >/dev/null 2>&1; then
    c "Génération de la clé de signature (une fois)…"
    gpg --batch --gen-key <<EOF
%no-protection
Key-Type: RSA
Key-Length: 4096
Name-Real: $KEY_NAME
Name-Email: $KEY_EMAIL
Expire-Date: 0
%commit
EOF
fi

# ── 2. arborescence + pool ────────────────────────────────────────────────
c "Construction de l'arborescence du dépôt…"
rm -rf "$APT/dists"
mkdir -p "$APT/pool/main/l/lazycam"
for a in $ARCHES; do mkdir -p "$APT/dists/$SUITE/$COMPONENT/binary-$a"; done

shopt -s nullglob
debs=("$DIST_DEBS"/*.deb)
[ "${#debs[@]}" -gt 0 ] || { echo "Aucun .deb dans $DIST_DEBS (lance build-deb.sh d'abord)" >&2; exit 1; }
cp -f "${debs[@]}" "$APT/pool/main/l/lazycam/"

# ── 3. index Packages par architecture ────────────────────────────────────
c "Index Packages…"
cd "$APT"
for a in $ARCHES; do
    dpkg-scanpackages --arch "$a" pool /dev/null \
        > "dists/$SUITE/$COMPONENT/binary-$a/Packages" 2>/dev/null
    gzip -9kf "dists/$SUITE/$COMPONENT/binary-$a/Packages"
done

# ── 4. Release (checksums des Packages) ───────────────────────────────────
c "Fichier Release…"
cd "$APT/dists/$SUITE"
apt-ftparchive \
    -o APT::FTPArchive::Release::Origin="$ORIGIN" \
    -o APT::FTPArchive::Release::Label="$ORIGIN" \
    -o APT::FTPArchive::Release::Suite="$SUITE" \
    -o APT::FTPArchive::Release::Codename="$SUITE" \
    -o APT::FTPArchive::Release::Architectures="$ARCHES" \
    -o APT::FTPArchive::Release::Components="$COMPONENT" \
    -o APT::FTPArchive::Release::Description="Dépôt APT lazycam" \
    release . > Release

# ── 5. signatures (InRelease inline + Release.gpg détachée) ────────────────
c "Signature GPG…"
gpg --batch --yes --clearsign -o InRelease Release
gpg --batch --yes -abs -o Release.gpg Release

# ── 6. clé publique publiée (binaire pour /etc/apt/keyrings + armurée) ─────
gpg --export  "$KEY_EMAIL" > "$APT/lazycam.gpg"
gpg --armor --export "$KEY_EMAIL" > "$APT/lazycam.asc"

c "✓ Dépôt APT régénéré dans docs/apt/"
echo "  Clé publique : docs/apt/lazycam.gpg"
echo "  Pense à : git add docs/apt && git commit && git push"
echo "  Sauvegarde la clé privée : $GNUPGHOME (NON commitée)"
