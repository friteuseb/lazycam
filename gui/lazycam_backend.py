"""
lazycam_backend — logique pure (sans GTK) : config, détection des appareils,
test micro, pilotage de l'enregistrement. Importable et testable seul.
"""
from __future__ import annotations
import json
import os
import re
import shutil
import subprocess
import tempfile
from pathlib import Path

APP_ID = "com.dec05eba.gpu_screen_recorder"

CONFIG_DIR = Path(os.environ.get("XDG_CONFIG_HOME", str(Path.home() / ".config"))) / "lazycam"
CONFIG_PATH = CONFIG_DIR / "config.json"

# Recherche des scripts gsr-* : install utilisateur, système (.deb), puis repo.
def _scripts_dir() -> Path:
    candidates = [
        Path.home() / ".local" / "bin",          # install.sh (utilisateur)
        Path("/usr/bin"),                          # paquet .deb
        Path("/usr/local/bin"),                    # install manuel système
        Path(__file__).resolve().parent.parent / "bin",  # dépôt cloné
    ]
    for d in candidates:
        if (d / "gsr-toggle.sh").exists():
            return d
    return candidates[0]

SCRIPTS_DIR = _scripts_dir()

DEFAULTS = {
    "mic_order": ["Amazon_USB_Streaming_Mic", "Cam_Sync|Creative", r"alsa_input\.pci.*analog"],
    "capture_mode": "portal",          # portal | monitor | focused | region
    "screen_order": ["DP", "HDMI", "eDP"],
    "region": "",
    "fps": 30,
    "codec": "h264",                   # h264 | hevc | av1
    "quality": "very_high",            # medium | high | very_high | ultra
    "outdir": "~/Videos",
    "denoise": False,
    "normalize": True,
    "show_keys": False,
    "show_clicks": False,
}

CODECS = ["h264", "hevc", "av1"]
QUALITIES = ["medium", "high", "very_high", "ultra"]
CAPTURE_MODES = ["portal", "monitor", "focused", "region"]
CAPTURE_LABELS = {
    "portal": "Portail (choix à l'écran)",
    "monitor": "Moniteur (par ordre de préférence)",
    "focused": "Fenêtre active",
    "region": "Région personnalisée",
}


# ───────────────────────────── Config ─────────────────────────────
def load_config() -> dict:
    cfg = dict(DEFAULTS)
    try:
        if CONFIG_PATH.exists():
            cfg.update(json.loads(CONFIG_PATH.read_text()))
    except Exception:
        pass
    # complète les clés manquantes par les défauts
    for k, v in DEFAULTS.items():
        cfg.setdefault(k, v)
    return cfg


def save_config(cfg: dict) -> None:
    CONFIG_DIR.mkdir(parents=True, exist_ok=True)
    tmp = CONFIG_PATH.with_suffix(".json.tmp")
    tmp.write_text(json.dumps(cfg, indent=2, ensure_ascii=False) + "\n")
    tmp.replace(CONFIG_PATH)


# ──────────────────────── Détection appareils ────────────────────
def list_mics() -> list[dict]:
    """Sources audio réelles via pw-dump : [{name, desc}] (toutes présentes)."""
    try:
        out = subprocess.run(["pw-dump"], capture_output=True, text=True, timeout=5).stdout
        data = json.loads(out)
    except Exception:
        return []
    mics = []
    for node in data:
        props = (node.get("info") or {}).get("props") or {}
        if props.get("media.class") != "Audio/Source":
            continue
        name = props.get("node.name")
        if not name:
            continue
        desc = props.get("node.description") or props.get("node.nick") or name
        mics.append({"name": name, "desc": desc})
    return mics


def gsr_cmd() -> list[str]:
    """Invocation du moteur de capture : binaire natif si présent, sinon Flatpak.

    Ubuntu/Debian n'empaquettent pas gpu-screen-recorder (Flatpak uniquement) ;
    Arch et d'autres l'ont en natif. Doit rester aligné sur GSR_CMD dans
    bin/gsr-common.sh.
    """
    if shutil.which("gpu-screen-recorder"):
        return ["gpu-screen-recorder"]
    return ["flatpak", "run", "--command=gpu-screen-recorder", APP_ID]


def list_monitors() -> list[dict]:
    """Moniteurs vus par le moteur : [{name, res}]."""
    try:
        out = subprocess.run(
            gsr_cmd() + ["--list-monitors"],
            capture_output=True, text=True, timeout=15).stdout
    except Exception:
        return []
    mons = []
    for line in out.splitlines():
        line = line.strip()
        if not line or "|" not in line:
            continue
        name, _, res = line.partition("|")
        mons.append({"name": name, "res": res})
    return mons


def match_present(pattern: str, devices: list[dict], key: str = "name") -> dict | None:
    """1er appareil présent dont le champ <key> matche le motif (grep -iE)."""
    try:
        rx = re.compile(pattern, re.IGNORECASE)
    except re.error:
        rx = re.compile(re.escape(pattern), re.IGNORECASE)
    for d in devices:
        if rx.search(d.get(key, "")):
            return d
    return None


# ─────────────────────────── Test micro ──────────────────────────
def mic_test(target: str | None, seconds: int = 4) -> dict:
    """Enregistre <seconds> s et renvoie {mean, max, path}. path à réécouter/supprimer."""
    tmp = tempfile.NamedTemporaryFile(suffix=".flac", delete=False).name
    cmd = ["pw-record"]
    if target:
        cmd += ["--target", target]
    cmd += [tmp]
    try:
        subprocess.run(cmd, timeout=seconds + 2)
    except subprocess.TimeoutExpired:
        pass
    except Exception:
        return {"mean": None, "max": None, "path": tmp}
    mean = _vol(tmp, "mean_volume")
    mx = _vol(tmp, "max_volume")
    return {"mean": mean, "max": mx, "path": tmp}


def _vol(path: str, field: str):
    try:
        out = subprocess.run(
            ["ffmpeg", "-hide_banner", "-i", path, "-af", "volumedetect", "-f", "null", "/dev/null"],
            capture_output=True, text=True, timeout=15).stderr
        for line in out.splitlines():
            if field in line:
                return float(line.split(":")[-1].replace("dB", "").strip())
    except Exception:
        pass
    return None


# ───────────────────────── Enregistrement ────────────────────────
def is_recording() -> bool:
    try:
        subprocess.run(["pgrep", "-f", "gpu-screen-recorder -w "], check=True,
                       capture_output=True)
        return True
    except Exception:
        return False


def toggle_recording() -> None:
    subprocess.Popen([str(SCRIPTS_DIR / "gsr-toggle.sh")],
                     start_new_session=True)


_MEDIA_SCHEMA = "org.gnome.settings-daemon.plugins.media-keys"


def shortcuts_active() -> bool:
    """Vrai si le raccourci Super+R (gsr-toggle) est déjà posé."""
    try:
        base = subprocess.run(
            ["gsettings", "get", _MEDIA_SCHEMA, "custom-keybindings"],
            capture_output=True, text=True, timeout=5).stdout.strip()
        for p in re.findall(r"'([^']+)'", base):
            cmd = subprocess.run(
                ["gsettings", "get", f"{_MEDIA_SCHEMA}.custom-keybinding:{p}", "command"],
                capture_output=True, text=True, timeout=5).stdout
            if "gsr-toggle.sh" in cmd:
                return True
    except Exception:
        pass
    return False


def set_shortcuts(remove: bool = False) -> None:
    """Pose ou retire les raccourcis via la commande lazycam-shortcuts."""
    exe = SCRIPTS_DIR / "lazycam-shortcuts"
    base = [str(exe)] if exe.exists() else ["lazycam-shortcuts"]
    subprocess.run(base + (["--remove"] if remove else []), timeout=15)


def have_showmethekey() -> bool:
    if shutil.which("showmethekey-gtk"):
        return True
    try:
        subprocess.run(["flatpak", "info", "one.alynx.showmethekey"], check=True,
                       capture_output=True)
        return True
    except Exception:
        return False
