#!/usr/bin/env bash
#
# lazycam-lang.sh — langue de l'interface, partagée par tous les scripts.
# (sourcé ; ne s'exécute pas seul)
#
# Sourcé par gsr-common.sh, gsr-config.sh, lazycam-shortcuts, install.sh et
# uninstall.sh, pour que la fenêtre GTK, les notifications et les scripts ne
# soient jamais dans deux langues différentes.
#
# Règle, identique à gui/lazycam_i18n.py :
#   1. clé "lang" de ~/.config/lazycam/config.json  (auto | en | fr)
#   2. si "auto" : LC_ALL, puis LC_MESSAGES, puis LANG
#   3. à défaut : anglais
#
# jq est une dépendance de lazycam, mais install.sh source ce fichier AVANT
# d'avoir vérifié les dépendances : l'absence de jq doit donc rester sans
# conséquence (on retombe simplement sur la locale).

_lazycam_cfg="${XDG_CONFIG_HOME:-$HOME/.config}/lazycam/config.json"
UI_LANG=auto
if [ -f "$_lazycam_cfg" ] && command -v jq >/dev/null 2>&1; then
    UI_LANG="$(jq -r '.lang // "auto"' "$_lazycam_cfg" 2>/dev/null)"
    case "$UI_LANG" in ""|null) UI_LANG=auto ;; esac
fi
if [ "$UI_LANG" = "auto" ]; then
    case "${LC_ALL:-${LC_MESSAGES:-${LANG:-}}}" in
        fr*) UI_LANG=fr ;;
        *)   UI_LANG=en ;;
    esac
fi
unset _lazycam_cfg

# msg <anglais> <français> : la chaîne dans la langue retenue.
msg() { [ "$UI_LANG" = "fr" ] && printf '%s' "$2" || printf '%s' "$1"; }

# say <anglais> <français> : idem, suivi d'un saut de ligne.
say() { printf '%s\n' "$(msg "$1" "$2")"; }
