<div align="center">

# 🎥 lazycam

**Enregistreur d'écran « une touche » pour Ubuntu / GNOME Wayland.**
*Tu appuies sur une touche, ça filme l'écran et ta voix. Tu réappuies, c'est monté.*

Construit au-dessus de [GPU Screen Recorder](https://git.dec05eba.com/gpu-screen-recorder/)
(NVENC / VAAPI, très faible impact CPU).

</div>

---

## Pourquoi lazycam ?

Les bons enregistreurs Linux existent (OBS, Kooha, GPU Screen Recorder…), mais
aucun ne fait *exactement* le bon geste pour faire des tutos vite fait :

- **Une seule touche** pour démarrer **et** arrêter (`Super+R`). Pas de fenêtre à viser.
- **Micro choisi automatiquement** : micro USB dédié (ex. Amazon Streaming Mic) ›
  webcam › micro interne. Tu branches ton bon micro, il est pris, point.
- **Écran choisi selon le dock** : sur station d'accueil → écran externe ;
  en déplacement → écran du portable. Mémorisé, plus aucune question.
- **Pause / reprise** (`Super+Shift+R`) sans casser la synchro audio.
- **Montage automatique** à l'arrêt : la voix est recollée et normalisée dans le MP4.

Sortie propre dans `~/Videos/tuto_AAAAMMJJ_HHMMSS.mp4`, prête à publier.

## Installation

```bash
git clone https://github.com/friteuseb/lazycam.git
cd lazycam
./install.sh
```

L'installeur :
1. vérifie les dépendances système,
2. propose d'installer le moteur GPU Screen Recorder (Flathub) s'il manque,
3. copie les scripts dans `~/.local/bin`,
4. pose les raccourcis GNOME **sans toucher** à tes raccourcis existants.

Relançable à volonté (idempotent).

### Dépendances

| Outil | Paquet Ubuntu |
|-------|---------------|
| `flatpak` + GPU Screen Recorder | `flatpak` + Flathub |
| `pw-record`, `pw-dump` | `pipewire-bin` |
| `wpctl` | `wireplumber` |
| `ffmpeg` | `ffmpeg` |
| `jq` | `jq` |
| `notify-send` | `libnotify-bin` |
| `gsettings`, `gdbus` | `libglib2.0-bin` |

## Utilisation

| Raccourci | Action |
|-----------|--------|
| `Super + R` | Démarrer / arrêter (puis montage auto) |
| `Super + Shift + R` | Pause / reprise |

Choisir et **tester** le micro (niveau, réécoute, réduction de bruit) :

```bash
gsr-config.sh
```

La sélection auto reste active tant que tu ne forces pas un micro précis.

## Comment ça marche

GPU Screen Recorder (sandbox flatpak) ne capte que l'écran. lazycam capte donc la
**voix séparément** avec `pw-record`, par segments (pour gérer la pause), puis
**recolle tout** dans la vidéo via `ffmpeg` au moment de l'arrêt. Les deux flux
restent synchronisés. Détails dans les en-têtes des scripts (`bin/`).

| Script | Rôle |
|--------|------|
| `gsr-toggle.sh` | start / stop + montage |
| `gsr-pause.sh` | pause / reprise |
| `gsr-common.sh` | réglages & fonctions partagés (choix micro, écran, état) |
| `gsr-config.sh` | assistant terminal : choisir & tester le micro |

Réglages par défaut (FPS, codec, qualité, dossier) en haut de `gsr-common.sh`.

## Désinstallation

```bash
./uninstall.sh
```

Retire les raccourcis et, au choix, les scripts. Garde ta config micro et tes vidéos.

## Licence

[GPL-3.0](LICENSE) — cohérent avec GPU Screen Recorder, le moteur sous-jacent.
Merci à [dec05eba](https://git.dec05eba.com/gpu-screen-recorder/) pour ce moteur.
