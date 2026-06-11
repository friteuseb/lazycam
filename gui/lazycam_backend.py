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

# Recherche des scripts : version déployée d'abord, sinon le repo voisin.
def _scripts_dir() -> Path:
    deployed = Path.home() / ".local" / "bin"
    if (deployed / "gsr-toggle.sh").exists():
        return deployed
    return Path(__file__).resolve().parent.parent / "bin"

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


def list_monitors() -> list[dict]:
    """Moniteurs vus par le moteur : [{name, res}]."""
    try:
        out = subprocess.run(
            ["flatpak", "run", "--command=gpu-screen-recorder", APP_ID, "--list-monitors"],
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


def have_showmethekey() -> bool:
    if shutil.which("showmethekey-gtk"):
        return True
    try:
        subprocess.run(["flatpak", "info", "one.alynx.showmethekey"], check=True,
                       capture_output=True)
        return True
    except Exception:
        return False
