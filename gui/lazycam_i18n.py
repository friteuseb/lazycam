"""Minimal translation layer for the lazycam GUI.

English is the source language: every user-facing string in the code is English
and doubles as the lookup key. Translations live in TRANSLATIONS below.

Deliberately not gettext. lazycam ships through four packaging paths (.deb, the
APT repo, the Launchpad PPA and the AUR), and gettext would add a msgfmt build
step plus .mo installation to each of them for two languages and ~60 strings.
A dict costs one more .py file.

Usage:
    import lazycam_i18n as I
    I.set_language("auto")      # or "en" / "fr"
    I._("Apply")
"""
from __future__ import annotations
import os

# "auto" resolves from the environment; the others force a language.
# Language names are endonyms and stay as-is in every locale, so only the "auto"
# label has a translation below — _() passes the other two through unchanged.
LANGUAGES = ["auto", "en", "fr"]
LANGUAGE_LABELS = {
    "auto": "Automatic (system)",
    "en": "English",
    "fr": "Français",
}

TRANSLATIONS = {
    "fr": {
        # ── header bar ──
        "Start / stop recording (Super+R)": "Démarrer / arrêter l'enregistrement (Super+R)",
        "Apply": "Appliquer",
        "Save the settings (config.json)": "Sauvegarder les réglages (config.json)",
        "Re-detect devices": "Re-détecter les appareils",
        "Record": "Filmer",
        "Stop": "Arrêter",

        # ── video source ──
        "Video source": "Source vidéo",
        "The first available monitor, in order, is recorded.":
            "Le 1er écran disponible (selon l'ordre) est filmé.",
        "Capture mode": "Mode de capture",
        "Portal (pick on screen)": "Portail (choix à l'écran)",
        "Monitor (by preference order)": "Moniteur (par ordre de préférence)",
        "Active window": "Fenêtre active",
        "Custom region": "Région personnalisée",
        "Monitor order": "Ordre des écrans",
        "Reorder with ↑ ↓. Used in “Monitor” mode.":
            "Réordonne avec ↑ ↓. Utilisé en mode « Moniteur ».",
        "Region (WxH+X+Y, e.g. 1280x720+0+0)": "Région (LxH+X+Y, ex. 1280x720+0+0)",
        "Prefill with the first monitor": "Pré-remplir avec le 1er écran",
        "○ no matching monitor": "○ aucun écran correspondant",
        "＋ Add a detected monitor": "＋ Ajouter un écran détecté",
        "Add a monitor": "Ajouter un écran",

        # ── audio input ──
        "Audio input": "Entrée audio",
        "Microphone preference order. ▶ tests, 🎙 monitors the live level.":
            "Ordre de préférence des micros. ▶ teste, 🎙 écoute le niveau en direct.",
        "● present · {name}": "● présent · {name}",
        "○ absent · pattern: {pattern}": "○ absent · motif : {pattern}",
        "Monitor the live level": "Écouter le niveau en direct",
        "4 s test: level + playback": "Test 4 s : niveau + réécoute",
        "＋ Add a detected microphone": "＋ Ajouter un micro détecté",
        "Add a microphone": "Ajouter un micro",
        "Noise reduction": "Réduction de bruit",
        "Filters out constant background noise": "Filtre les bruits de fond constants",
        "Normalise the voice": "Normaliser la voix",
        "Even volume (loudnorm)": "Volume homogène (loudnorm)",
        "🎙 Speak… (4 s)": "🎙 Parle… (4 s)",
        "test: capture failed": "test : échec de la capture",
        "test: mean {mean} dB · peak {peak} dB ({verdict})":
            "test : moyenne {mean} dB · crête {peak} dB ({verdict})",
        "good": "bon",
        "low": "faible",

        # ── recording ──
        "Recording": "Enregistrement",
        "Frames per second": "Images / seconde",
        "Quality": "Qualité",
        "Medium": "Moyenne",
        "High": "Haute",
        "Very high": "Très haute",
        "Ultra": "Ultra",
        "Output folder": "Dossier de sortie",

        # ── tutorial helpers ──
        "Tutorial helpers": "Aides tuto",
        "Overlays that help when recording tutorials.":
            "Surcouches utiles pour les tutoriels.",
        "Show pressed keys": "Afficher les touches pressées",
        "Needs showmethekey — no Ubuntu package, has to be built from source "
        "(see the README)":
            "Nécessite showmethekey — aucun paquet Ubuntu, à compiler depuis les "
            "sources (voir le README)",
        "Highlight mouse clicks": "Mettre les clics en évidence",
        "Coming later: needs a GNOME Shell extension":
            "À venir : nécessite une extension GNOME Shell",

        # ── shortcuts ──
        "Keyboard shortcuts": "Raccourcis clavier",
        "Start/stop · Pause/resume": "Démarrer/arrêter · Pause/reprise",
        "Enabled · Start/stop · Pause/resume": "Actifs · Démarrer/arrêter · Pause/reprise",
        "Disabled — click to register them": "Inactifs — clique pour les poser",
        "Enable": "Activer",
        "Disable": "Désactiver",
        "Shortcuts enabled ✓": "Raccourcis activés ✓",
        "Shortcuts disabled.": "Raccourcis désactivés.",
        "Failed: run “lazycam-shortcuts” in a terminal.":
            "Échec : lance « lazycam-shortcuts » en terminal.",

        # ── interface ──
        "Interface": "Interface",
        "Language": "Langue",
        "Applies immediately; saved with Apply like the other settings.":
            "S'applique tout de suite ; enregistré avec Appliquer comme le reste.",
        "Automatic (system)": "Automatique (système)",

        # ── generic ──
        "Move up": "Monter",
        "Move down": "Descendre",
        "Remove": "Retirer",
        "Cancel": "Annuler",
        "Add": "Ajouter",
        "Every detected device is already in the list.":
            "Tous les appareils détectés sont déjà dans la liste.",
        "Devices re-detected.": "Appareils re-détectés.",
        "Settings saved ✓": "Réglages enregistrés ✓",
    },
}

_current = "en"


def detect_language() -> str:
    """Language implied by the environment, falling back to English."""
    for var in ("LC_ALL", "LC_MESSAGES", "LANG", "LANGUAGE"):
        val = os.environ.get(var)
        if val:
            code = val.split(":")[0].split(".")[0].split("_")[0].lower()
            if code in TRANSLATIONS:
                return code
            if code:
                return "en"
    return "en"


def set_language(lang: str) -> str:
    """Select the active language. 'auto' resolves from the environment."""
    global _current
    _current = detect_language() if lang == "auto" else (
        lang if lang in TRANSLATIONS or lang == "en" else "en")
    return _current


def current_language() -> str:
    return _current


def _(text: str) -> str:
    """Translate a source string; unknown strings pass through unchanged."""
    return TRANSLATIONS.get(_current, {}).get(text, text)
