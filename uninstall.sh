#!/usr/bin/env bash
#
# uninstall.sh — retire les raccourcis GNOME de lazycam et (optionnellement)
# les scripts de ~/.local/bin. Ne touche pas à ta config micro ni à tes vidéos.
#
set -u
BIN_DIR="$HOME/.local/bin"
SCHEMA=org.gnome.settings-daemon.plugins.media-keys
LISTKEY=custom-keybindings

c_ok()  { printf '  \033[32m✓\033[0m %s\n' "$1"; }
title() { printf '\n\033[1m%s\033[0m\n' "$1"; }

title "Retrait des raccourcis GNOME lazycam"
raw="$(gsettings get "$SCHEMA" "$LISTKEY")"
existing=()
if [ "$raw" != "@as []" ] && [ "$raw" != "[]" ]; then
    tmp="${raw#[}"; tmp="${tmp%]}"
    IFS=',' read -ra parts <<< "$tmp"
    for p in "${parts[@]}"; do p="${p//\'/}"; p="${p// /}"; [ -n "$p" ] && existing+=("$p"); done
fi
kept=()
for p in ${existing[@]+"${existing[@]}"}; do
    rs="$SCHEMA.custom-keybinding:$p"
    cmd="$(gsettings get "$rs" command 2>/dev/null)"
    case "$cmd" in
        *"/gsr-toggle.sh'"|*"/gsr-pause.sh'")
            gsettings reset-recursively "$rs" 2>/dev/null
            c_ok "raccourci retiré : $cmd" ;;
        *) kept+=("$p") ;;
    esac
done
arr="["; n="${#kept[@]}"
for idx in "${!kept[@]}"; do arr+="'${kept[$idx]}'"; [ "$idx" -lt "$((n-1))" ] && arr+=", "; done
arr+="]"
gsettings set "$SCHEMA" "$LISTKEY" "$arr"

title "Scripts"
read -rp "  Supprimer aussi les scripts de $BIN_DIR ? [o/N] " ans
case "${ans:-N}" in
    [oO]*)
        for f in gsr-common.sh gsr-toggle.sh gsr-pause.sh gsr-config.sh lazycam-config; do
            rm -f "$BIN_DIR/$f" && c_ok "supprimé : $f"
        done ;;
    *) c_ok "scripts conservés" ;;
esac

title "Interface graphique"
APPID=org.friteuseb.lazycam
rm -rf "$HOME/.local/share/lazycam" && c_ok "lib GUI retirée"
rm -f "$HOME/.local/share/applications/$APPID.desktop" \
      "$HOME/.local/share/applications/lazycam-config.desktop" \
      "$HOME/.local/share/icons/hicolor/scalable/apps/$APPID.svg" \
      "$HOME/.local/share/icons/hicolor/scalable/apps/lazycam.svg"
command -v update-desktop-database >/dev/null && \
    update-desktop-database "$HOME/.local/share/applications" 2>/dev/null
c_ok "entrée de menu + icône retirées"

title "Désinstallé ✓"
echo "  Config (~/.config/lazycam, ~/.config/gsr-toggle.conf) et vidéos (~/Videos) conservées."
