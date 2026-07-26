<div align="center">

# 🎥 lazycam

**Enregistreur d'écran « une touche » pour Ubuntu / GNOME Wayland.**

*Tu appuies sur une touche, ça filme l'écran et ta voix. Tu réappuies, c'est monté.*

Surcouche à [GPU Screen Recorder](https://git.dec05eba.com/gpu-screen-recorder/) (NVENC / VAAPI, très faible impact CPU).

[![Téléchargements](https://img.shields.io/github/downloads/friteuseb/lazycam/total?label=t%C3%A9l%C3%A9chargements&color=cba6f7)](https://github.com/friteuseb/lazycam/releases)
[![Dernière version](https://img.shields.io/github/v/release/friteuseb/lazycam?label=version&color=f38ba8)](https://github.com/friteuseb/lazycam/releases/latest)
[![Licence GPL-3.0](https://img.shields.io/badge/licence-GPL--3.0-89b4fa)](LICENSE)

</div>

---

## Sommaire

- [Pourquoi lazycam ?](#pourquoi-lazycam-)
- [Installation](#installation)
- [Démarrage rapide](#démarrage-rapide)
- [Utilisation](#utilisation)
- [Configuration](#configuration)
  - [L'interface graphique](#linterface-graphique-lazycam-config)
  - [Le fichier `config.json`](#le-fichier-configjson)
  - [Logique de choix du micro et de l'écran](#logique-de-choix-du-micro-et-de-lécran)
- [Comment ça marche](#comment-ça-marche)
- [Aides tuto](#aides-tuto)
- [Fichiers & emplacements](#fichiers--emplacements)
- [Dépannage](#dépannage)
- [Désinstallation](#désinstallation)
- [Développement](#développement)
- [Licence](#licence)

---

## Pourquoi lazycam ?

Je voulais juste filmer mon écran pour des tutos. Étonnamment compliqué sous Linux :
**OBS Studio** est un studio de production complet — formidable pour streamer,
démesuré pour appuyer sur un bouton et filmer trois minutes ; les **autres outils**
demandent presque tous de viser une fenêtre et de cliquer, et
**Bandicam** — dont j'adorais la simplicité « j'appuie, ça filme » — n'existe que
sous Windows. Alors j'ai construit celui qui me manquait : la simplicité de
Bandicam, sur Linux, qui marche vraiment sous Wayland.

Concrètement, aucun des bons enregistreurs (OBS, Kooha, GPU Screen Recorder…) ne
fait *exactement* le bon geste pour faire des tutos vite fait :

- **Une seule touche** pour démarrer **et** arrêter (`Super+R`). Pas de fenêtre à viser.
- **Micro choisi automatiquement** selon un **ordre de préférence** : micro USB
  dédié › webcam › micro interne. Tu branches ton bon micro, il est pris, point.
- **Écran choisi automatiquement** : par défaut le portail GNOME (qui mémorise ton
  choix), ou par **ordre de préférence de moniteurs** si tu préfères.
- **Pause / reprise** (`Super+Shift+R`) sans casser la synchro audio.
- **Montage automatique** à l'arrêt : la voix est recollée et normalisée dans le MP4.

Sortie propre dans `~/Videos/tuto_AAAAMMJJ_HHMMSS.mp4`, prête à publier.

---

## Installation

lazycam est un **outil d'intégration système** (il pilote d'autres programmes et
pose des raccourcis GNOME) : il s'installe donc sur l'hôte, pas en bac à sable.

### Option A — dépôt APT *(recommandé)*

Ajoute le dépôt une fois, puis `apt install` et les mises à jour suivent avec
`apt upgrade` :

```bash
sudo install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://lazycam.coconweb.fr/apt/lazycam.gpg | sudo tee /etc/apt/keyrings/lazycam.gpg >/dev/null
echo "deb [arch=amd64,arm64 signed-by=/etc/apt/keyrings/lazycam.gpg] https://lazycam.coconweb.fr/apt stable main" | sudo tee /etc/apt/sources.list.d/lazycam.list >/dev/null
sudo apt update && sudo apt install lazycam
```

### Option B — paquet `.deb` direct

[Télécharge le `.deb`](https://github.com/friteuseb/lazycam/releases/latest) puis :

```bash
sudo apt install ./lazycam_0.1.0_all.deb
```

### Après l'installation (Option A ou B)

`apt` tire toutes les dépendances système. Restent **deux gestes côté
utilisateur** (un paquet tourne en root et ne peut pas les faire) :

```bash
flatpak install -y flathub com.dec05eba.gpu_screen_recorder   # 1) le moteur de capture
lazycam-shortcuts                                             # 2) activer Super+R
```

> **Pourquoi `lazycam-shortcuts` à part ?** Les raccourcis clavier sont stockés
> dans dconf **par-utilisateur**. Le `postinst` d'un paquet s'exécute en root et
> ne peut donc pas écrire dans *ta* session. La commande `lazycam-shortcuts`
> (ou le bouton **« Activer »** dans `lazycam-config`) les pose dans ta session.

### Option C — depuis les sources (git)

```bash
git clone https://github.com/friteuseb/lazycam.git
cd lazycam
./install.sh
```

`install.sh` est **idempotent** (relançable sans rien casser) et fait tout d'un
coup : vérifie les dépendances, propose d'installer le moteur, copie les scripts
dans `~/.local/bin`, installe la GUI, puis pose les raccourcis Super+R **sans
toucher** à tes autres raccourcis GNOME.

### Dépendances

| Outil | Paquet Ubuntu | Rôle |
|-------|---------------|------|
| GPU Screen Recorder | `flatpak` + Flathub | moteur de capture vidéo |
| `pw-record`, `pw-dump` | `pipewire-bin` | capture & détection audio |
| `wpctl` | `wireplumber` | démuter le micro |
| `ffmpeg` | `ffmpeg` | montage / filtres voix |
| `jq` | `jq` | lecture de la config JSON |
| `notify-send` | `libnotify-bin` | notifications |
| `gsettings`, `gdbus` | `libglib2.0-bin` | raccourcis & détection écran |
| GTK 4 + libadwaita | `python3-gi gir1.2-gtk-4.0 gir1.2-adw-1` | interface graphique |

> Le moteur **gpu-screen-recorder** n'est pas un paquet apt : il s'installe via
> Flatpak (commande ci-dessus). C'est volontaire — c'est sa distribution officielle.

---

## Démarrage rapide

```bash
lazycam-config        # ouvre les réglages, branche ton micro, vérifie le niveau
```
Puis, n'importe où :

- **`Super + R`** → l'enregistrement démarre (notification « ● Démarré »).
- Parle, montre ce que tu veux.
- **`Super + R`** → stop : la vidéo et la voix sont montées, tu obtiens un MP4.

---

## Utilisation

| Raccourci | Action |
|-----------|--------|
| `Super + R` | Démarrer / arrêter (puis montage automatique) |
| `Super + Shift + R` | Pause / reprise |

| Commande | Rôle |
|----------|------|
| `lazycam-config` | interface graphique de réglages |
| `lazycam-shortcuts` | poser / retirer les raccourcis (`--remove`) |
| `gsr-config.sh` | assistant **terminal** : choisir & tester le micro |

---

## Configuration

Toute la configuration vit dans un seul fichier :
`~/.config/lazycam/config.json`. Tu l'édites via l'interface graphique (conseillé)
ou à la main.

### L'interface graphique (`lazycam-config`)

Fenêtre GTK4 / libadwaita, lancée par la commande `lazycam-config` ou depuis le
menu d'applications (**« lazycam »**). Barre du haut :

- **⏺ Filmer / ⏹ Arrêter** (à gauche) — démarre ou arrête l'enregistrement.
- **💾 Appliquer** (à droite) — **sauvegarde** les réglages dans `config.json`.

> ⚠️ Les changements ne sont écrits que quand tu cliques **Appliquer**.

Sections :

| Section | Ce que tu règles |
|---------|------------------|
| **Source vidéo** | Mode de capture, et l'ordre de préférence des écrans (mode Moniteur). |
| **Entrée audio** | Ordre de préférence des micros (↑ ↓), test ▶ (4 s + réécoute), 🎙 niveau en direct, réduction de bruit, normalisation. |
| **Enregistrement** | FPS, codec, qualité, dossier de sortie. |
| **Aides tuto** | Afficher les touches pressées (clics : à venir). |
| **Raccourcis clavier** | Activer / désactiver Super+R et Super+Shift+R. |

Pour réordonner une liste : les flèches **↑ ↓** de chaque ligne. Pour en retirer
un : 🗑. Pour en ajouter un détecté : **＋**.

### Le fichier `config.json`

```jsonc
{
  // Ordre de préférence des micros : motifs (grep -iE) testés sur le nom PipeWire.
  // Le 1er micro présent qui correspond est utilisé.
  "mic_order": ["Amazon_USB_Streaming_Mic", "Cam_Sync|Creative", "alsa_input\\.pci.*analog"],

  // Mode de capture vidéo : "portal" | "monitor" | "focused" | "region"
  "capture_mode": "portal",

  // Ordre de préférence des écrans (mode "monitor") : motifs testés sur le nom du moniteur.
  "screen_order": ["DP", "HDMI", "eDP"],

  // Rectangle pour le mode "region" (largeurxhauteur+X+Y). Vide sinon.
  "region": "",

  "fps": 30,                 // 24 | 30 | 60
  "codec": "h264",           // h264 (compatible partout) | hevc | av1
  "quality": "very_high",    // medium | high | very_high | ultra
  "outdir": "~/Videos",      // dossier de sortie

  "denoise": false,          // réduction de bruit (highpass + afftdn)
  "normalize": true,         // normalisation du volume (loudnorm)

  "show_keys": false,        // afficher les touches pressées (showmethekey)
  "show_clicks": false       // (à venir : nécessite une extension GNOME)
}
```

**Sans fichier de config**, lazycam applique des valeurs par défaut identiques à
ce tableau → comportement « sans surprise », mode Portail.

#### Modes de capture vidéo

| Mode | Comportement | Remarque |
|------|--------------|----------|
| `portal` *(défaut)* | Le portail GNOME demande quel écran/fenêtre partager au 1er usage, puis **mémorise** (un jeton par état dock branché / débranché). | Le plus fiable sur GNOME Wayland. |
| `monitor` | Filme le **1er moniteur présent** selon `screen_order` (capture directe `-w <nom>`). | Pas de pop-up. Choisit tout seul l'écran de la station si branchée. |
| `focused` | Filme la **fenêtre active**. | |
| `region` | Filme le rectangle `region` (`LxH+X+Y`). | Saisie manuelle (la sélection à la souris n'est pas encore implémentée). |

#### Filtres voix

- `denoise: true` ajoute `highpass=f=90,afftdn=nf=-25` (coupe les graves parasites
  + débruitage spectral).
- `normalize: true` ajoute `loudnorm=I=-16:TP=-1.5:LRA=11` (volume homogène, niveau
  broadcast). Les deux se cumulent si activés.

### Logique de choix du micro et de l'écran

C'est le cœur de lazycam. Au démarrage d'un enregistrement :

```
Micro :  pour chaque motif de mic_order (dans l'ordre)
           → existe-t-il une source audio PipeWire dont le nom matche ?
             oui → on prend celle-là, on s'arrête.
         aucun ne matche → micro par défaut du système.

Écran :  mode "monitor" → pour chaque motif de screen_order (dans l'ordre)
                            → un moniteur présent matche-t-il ? oui → on le filme.
         mode "portal"  → jeton mémorisé selon dock branché ou non.
```

Les motifs sont des **expressions régulières** (`grep -iE`, insensible à la casse)
testées sur le `node.name` PipeWire du micro ou le nom du moniteur (`eDP-1`,
`DP-2`…). Exemple : `Cam_Sync|Creative` capte la webcam quel que soit son libellé
exact ; `alsa_input\.pci.*analog` capte l'entrée analogique interne.

**Conséquence pratique** : tu listes tes appareils du plus voulu au moins voulu,
et lazycam prend toujours le meilleur **disponible** à l'instant T. Tu débranches
le micro USB → il bascule sur la webcam, puis sur l'interne. Zéro réglage à refaire.

---

## Comment ça marche

GPU Screen Recorder (sandbox Flatpak) ne capte **que l'écran** : son bac à sable
PipeWire ne laisse passer que les sorties. lazycam capte donc la **voix
séparément** et recolle tout au montage.

```
  Super+R (start)
        │
        ├─► gpu-screen-recorder  ──►  .rec_<stamp>.video.mp4   (écran, sans audio)
        │
        └─► pw-record (micro)    ──►  .rec_<stamp>.mic.0.flac  (voix, segment 0)
                                       (pause → ferme le segment ; reprise → segment 1, 2…)

  Super+R (stop)
        │
        └─► ffmpeg : concat des segments audio  +  filtres voix (denoise/loudnorm)
                     muxés avec la vidéo  ──►  ~/Videos/tuto_<stamp>.mp4
```

Pourquoi des **segments audio** ? Parce que `pw-record` ne sait pas se mettre en
pause : à chaque pause on **clôt** le segment courant, à la reprise on en **ouvre**
un nouveau. Au stop, `ffmpeg` les recolle dans l'ordre — la vidéo, elle, gère sa
propre pause via `SIGUSR2`. Les deux flux restent synchronisés.

| Script | Rôle |
|--------|------|
| `gsr-toggle.sh` | start / stop + montage final |
| `gsr-pause.sh` | pause / reprise (vidéo via signal, audio par segments) |
| `gsr-common.sh` | réglages & fonctions partagés : lecture de la config, choix micro (`pick_mic`), choix écran (`video_capture_args`), état |
| `gsr-config.sh` | assistant terminal pour choisir & tester le micro |
| `lazycam-shortcuts` | pose / retire les raccourcis GNOME (idempotent) |

---

## Aides tuto

- **Touches pressées** : active *« Afficher les touches pressées »* dans
  `lazycam-config`. Nécessite [showmethekey](https://github.com/AlynxZhou/showmethekey) :
  `flatpak install -y flathub one.alynx.showmethekey`. lazycam le lance au
  démarrage de l'enregistrement et le coupe à l'arrêt.
- **Mise en évidence des clics** : pas encore disponible — sous Wayland ça
  demande une extension GNOME Shell, non livrée pour l'instant.

> Sous Wayland, la capture clavier globale est volontairement verrouillée pour la
> sécurité : c'est pour ça qu'on délègue à un outil dédié plutôt que de l'implémenter.

---

## Fichiers & emplacements

| Chemin | Contenu |
|--------|---------|
| `~/.config/lazycam/config.json` | ta configuration |
| `~/.config/gsr-tokens/` | jetons portail (mode `portal`) |
| `~/Videos/tuto_*.mp4` | tes enregistrements |
| `$XDG_RUNTIME_DIR/gsr-toggle.state` | état de l'enregistrement en cours |
| **Installé via `.deb`** | `/usr/bin/` (scripts), `/usr/share/lazycam/` (GUI) |
| **Installé via `install.sh`** | `~/.local/bin/` (scripts), `~/.local/share/lazycam/` (GUI) |

---

## Dépannage

| Symptôme | Cause probable / solution |
|----------|---------------------------|
| **Pas de son dans la vidéo** | Mauvais micro choisi ou micro muet. Ouvre `lazycam-config`, teste (▶) le micro voulu, vérifie son ordre. lazycam démute automatiquement le micro choisi. |
| **`Super+R` ne fait rien** | Raccourcis non posés. Lance `lazycam-shortcuts` (ou bouton « Activer » dans la GUI). Vérifie qu'aucun autre logiciel ne capte `Super+R`. |
| **Le mauvais micro est pris** | Réordonne `mic_order` (le 1er présent gagne). Branché trop tard ? Clique **« Re-détecter »** dans la GUI. |
| **Pop-up de partage d'écran à chaque fois** | Tu es en mode `portal` et le jeton n'a pas été mémorisé, ou tu as changé d'écran. Refais le choix une fois, ou passe en mode `monitor`. |
| **La GUI ne s'ouvre pas** | GTK4/libadwaita manquant : `sudo apt install python3-gi gir1.2-gtk-4.0 gir1.2-adw-1`. |
| **Doublons de raccourcis** | Tu as lancé `lazycam-shortcuts` depuis un autre dossier que celui des scripts. `lazycam-shortcuts --remove` puis relance la **bonne** copie (celle installée). |

---

## Désinstallation

- **Paquet `.deb`** : `sudo apt remove lazycam`
- **Sources** : `./uninstall.sh` (retire raccourcis, GUI, icône ; te demande pour
  les scripts ; **garde** ta config et tes vidéos).

---

## Développement

```
bin/        scripts moteur (bash) + lazycam-shortcuts
gui/        lazycam-gui.py (GTK4) + lazycam_backend.py (logique pure, testable)
data/       icône + fichier .desktop
packaging/  build-deb.sh + update-apt-repo.sh
docs/       site web (GitHub Pages) + docs/apt/ (dépôt APT)
install.sh / uninstall.sh
```

`gui/lazycam_backend.py` n'importe pas GTK : tu peux le tester seul (détection des
appareils, lecture de la config, test micro) sans environnement graphique.

### Publier une nouvelle version

```bash
# 1. construire le paquet
./packaging/build-deb.sh 0.2.0           # → dist/lazycam_0.2.0_all.deb

# 2. régénérer + resigner le dépôt APT
./packaging/update-apt-repo.sh           # → docs/apt/ (signé)

# 3. publier
git add docs/apt && git commit -m "release 0.2.0" && git push   # GitHub Pages sert le dépôt
gh release create v0.2.0 dist/lazycam_0.2.0_all.deb --title "lazycam v0.2.0"
```

> 🔑 **Clé de signature du dépôt** : la clé privée vit dans `~/.lazycam-apt-gnupg`
> (hors du dépôt git, **jamais commitée**). **Sauvegarde ce dossier** : sans lui,
> tu ne peux plus signer de mise à jour et les utilisateurs devront ré-importer
> une nouvelle clé. La clé publique distribuée est `docs/apt/lazycam.gpg`.

---

## Licence

[GPL-3.0](LICENSE) — cohérent avec GPU Screen Recorder, le moteur sous-jacent.
Merci à [dec05eba](https://git.dec05eba.com/gpu-screen-recorder/) pour ce moteur.
