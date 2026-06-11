#!/usr/bin/env python3
"""
lazycam — interface de configuration (GTK4 / libadwaita).

Édite ~/.config/lazycam/config.json : ordre de préférence des micros et des
écrans, mode de capture, réglages d'enregistrement, aides tuto. Permet de
tester un micro (niveau + VU-mètre live) et de lancer/arrêter l'enregistrement.

Le moteur reste les scripts bash (gsr-toggle.sh) ; cette fenêtre ne fait
qu'écrire la config et déclencher.
"""
import os
import sys
import threading
import struct
import subprocess

import gi
gi.require_version("Gtk", "4.0")
gi.require_version("Adw", "1")
from gi.repository import Gtk, Adw, GLib, Gio  # noqa: E402

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import lazycam_backend as B  # noqa: E402


# ───────────────────────── VU-mètre micro (live) ─────────────────────────
class MicMeter:
    """Lit en continu le niveau d'un micro via pw-record (s16 mono) et appelle
    on_level(0..1) dans le thread GTK. Tout est gardé : échoue en silence."""

    def __init__(self, on_level):
        self.on_level = on_level
        self.proc = None
        self.thread = None
        self.stop_flag = threading.Event()

    def start(self, target):
        self.stop()
        self.stop_flag.clear()
        cmd = ["pw-record", "--rate", "16000", "--channels", "1",
               "--format", "s16", "--latency", "50ms"]
        if target:
            cmd += ["--target", target]
        cmd += ["-"]
        try:
            self.proc = subprocess.Popen(cmd, stdout=subprocess.PIPE,
                                         stderr=subprocess.DEVNULL, bufsize=0)
        except Exception:
            self.proc = None
            return
        self.thread = threading.Thread(target=self._loop, daemon=True)
        self.thread.start()

    def _loop(self):
        chunk = 1024
        while not self.stop_flag.is_set() and self.proc and self.proc.stdout:
            data = self.proc.stdout.read(chunk * 2)
            if not data:
                break
            n = len(data) // 2
            if n == 0:
                continue
            samples = struct.unpack("<%dh" % n, data[:n * 2])
            peak = max((abs(s) for s in samples), default=0) / 32768.0
            GLib.idle_add(self.on_level, min(1.0, peak))
        GLib.idle_add(self.on_level, 0.0)

    def stop(self):
        self.stop_flag.set()
        if self.proc:
            try:
                self.proc.terminate()
            except Exception:
                pass
            self.proc = None


# ────────────────────────────── Fenêtre ──────────────────────────────────
class LazycamWindow(Adw.ApplicationWindow):
    def __init__(self, app):
        super().__init__(application=app, title="lazycam")
        self.set_default_size(560, 760)
        self.cfg = B.load_config()
        self.mics = B.list_mics()
        self.monitors = B.list_monitors()
        self.meter = MicMeter(self._on_meter_level)
        self._meter_bar = None  # LevelBar actuellement alimenté

        toolbar = Adw.ToolbarView()
        header = Adw.HeaderBar()

        self.rec_btn = Gtk.Button()
        self.rec_btn.add_css_class("destructive-action")
        self.rec_btn.connect("clicked", self.on_toggle_rec)
        header.pack_start(self.rec_btn)

        save_btn = Gtk.Button(label="Enregistrer")
        save_btn.add_css_class("suggested-action")
        save_btn.connect("clicked", lambda *_: self.save())
        header.pack_end(save_btn)

        refresh_btn = Gtk.Button(icon_name="view-refresh-symbolic")
        refresh_btn.set_tooltip_text("Re-détecter les appareils")
        refresh_btn.connect("clicked", self.on_refresh)
        header.pack_end(refresh_btn)

        toolbar.add_top_bar(header)

        self.toasts = Adw.ToastOverlay()
        self.page = Adw.PreferencesPage()
        self.toasts.set_child(self.page)
        toolbar.set_content(self.toasts)
        self.set_content(toolbar)

        self._build_video_group()
        self._build_audio_group()
        self._build_rec_group()
        self._build_tuto_group()

        self._update_rec_btn()
        GLib.timeout_add_seconds(2, self._poll_rec)

    # ----- groupe Source vidéo -----
    def _build_video_group(self):
        g = Adw.PreferencesGroup(title="Source vidéo",
                                 description="Le 1er écran disponible (selon l'ordre) est filmé.")
        self.page.add(g)

        self.mode_row = self._combo(
            "Mode de capture",
            [B.CAPTURE_LABELS[m] for m in B.CAPTURE_MODES],
            B.CAPTURE_MODES.index(self.cfg.get("capture_mode", "portal")),
            self._on_mode_changed)
        g.add(self.mode_row)

        self.screen_group = Adw.PreferencesGroup(
            title="Ordre des écrans",
            description="Glisse avec ↑ ↓. Utilisé en mode « Moniteur ».")
        self.page.add(self.screen_group)
        self._screen_rows_box = self.screen_group
        self._rebuild_screen_rows()

        self.region_row = Adw.EntryRow(title="Région (LxH+X+Y, ex. 1280x720+0+0)")
        self.region_row.set_text(self.cfg.get("region", ""))
        self.region_row.connect("changed", lambda r: self._set("region", r.get_text()))
        fill = Gtk.Button(icon_name="view-fullscreen-symbolic", valign=Gtk.Align.CENTER)
        fill.set_tooltip_text("Pré-remplir avec le 1er écran")
        fill.connect("clicked", self._prefill_region)
        self.region_row.add_suffix(fill)
        self.screen_group.add(self.region_row)
        self._sync_mode_visibility()

    def _rebuild_screen_rows(self):
        for r in getattr(self, "_screen_rows", []):
            self.screen_group.remove(r)
        self._screen_rows = []
        order = self.cfg.get("screen_order", [])
        for i, pat in enumerate(order):
            hit = B.match_present(pat, self.monitors)
            sub = (f"● {hit['name']} {hit['res']}" if hit else "○ aucun écran correspondant")
            row = Adw.ActionRow(title=pat, subtitle=sub)
            self._add_order_controls(row, "screen_order", i)
            self.screen_group.add(row)
            self._screen_rows.append(row)
        add = Adw.ActionRow(title="＋ Ajouter un écran détecté")
        btn = Gtk.Button(icon_name="list-add-symbolic", valign=Gtk.Align.CENTER)
        btn.connect("clicked", lambda *_: self._add_detected("screen"))
        add.add_suffix(btn)
        add.set_activatable_widget(btn)
        self.screen_group.add(add)
        self._screen_rows.append(add)

    # ----- groupe Entrée audio -----
    def _build_audio_group(self):
        self.audio_group = Adw.PreferencesGroup(
            title="Entrée audio",
            description="Ordre de préférence des micros. ▶ teste, 🎙 écoute le niveau en direct.")
        self.page.add(self.audio_group)
        self._rebuild_mic_rows()

        opts = Adw.PreferencesGroup()
        self.page.add(opts)
        self.denoise_row = Adw.SwitchRow(title="Réduction de bruit",
                                         subtitle="Filtre les bruits de fond constants")
        self.denoise_row.set_active(bool(self.cfg.get("denoise")))
        self.denoise_row.connect("notify::active",
                                 lambda r, _: self._set("denoise", r.get_active()))
        opts.add(self.denoise_row)
        self.norm_row = Adw.SwitchRow(title="Normaliser la voix",
                                      subtitle="Volume homogène (loudnorm)")
        self.norm_row.set_active(bool(self.cfg.get("normalize")))
        self.norm_row.connect("notify::active",
                              lambda r, _: self._set("normalize", r.get_active()))
        opts.add(self.norm_row)

    def _rebuild_mic_rows(self):
        for r in getattr(self, "_mic_rows", []):
            self.audio_group.remove(r)
        self._mic_rows = []
        order = self.cfg.get("mic_order", [])
        for i, pat in enumerate(order):
            hit = B.match_present(pat, self.mics)
            title = hit["desc"] if hit else pat
            sub = (f"● présent · {hit['name']}" if hit else f"○ absent · motif : {pat}")
            row = Adw.ActionRow(title=title, subtitle=sub)

            bar = Gtk.LevelBar(min_value=0, max_value=1, valign=Gtk.Align.CENTER,
                               hexpand=False, width_request=70)
            row.add_suffix(bar)

            listen = Gtk.ToggleButton(icon_name="audio-input-microphone-symbolic",
                                      valign=Gtk.Align.CENTER)
            listen.set_tooltip_text("Écouter le niveau en direct")
            listen.set_sensitive(hit is not None)
            listen.connect("toggled", self._on_listen, hit["name"] if hit else None, bar)
            row.add_suffix(listen)

            test = Gtk.Button(icon_name="media-playback-start-symbolic",
                              valign=Gtk.Align.CENTER)
            test.set_tooltip_text("Test 4 s : niveau + réécoute")
            test.set_sensitive(hit is not None)
            test.connect("clicked", self._on_test, hit["name"] if hit else None, row)
            row.add_suffix(test)

            self._add_order_controls(row, "mic_order", i)
            self.audio_group.add(row)
            self._mic_rows.append(row)

        add = Adw.ActionRow(title="＋ Ajouter un micro détecté")
        btn = Gtk.Button(icon_name="list-add-symbolic", valign=Gtk.Align.CENTER)
        btn.connect("clicked", lambda *_: self._add_detected("mic"))
        add.add_suffix(btn)
        add.set_activatable_widget(btn)
        self.audio_group.add(add)
        self._mic_rows.append(add)

    # ----- groupe Enregistrement -----
    def _build_rec_group(self):
        g = Adw.PreferencesGroup(title="Enregistrement")
        self.page.add(g)
        fps_vals = ["24", "30", "60"]
        cur_fps = str(self.cfg.get("fps", 30))
        g.add(self._combo("Images / seconde", fps_vals,
                          fps_vals.index(cur_fps) if cur_fps in fps_vals else 1,
                          lambda i: self._set("fps", int(fps_vals[i]))))
        g.add(self._combo("Codec", [c.upper() for c in B.CODECS],
                          B.CODECS.index(self.cfg.get("codec", "h264")),
                          lambda i: self._set("codec", B.CODECS[i])))
        g.add(self._combo("Qualité", B.QUALITIES,
                          B.QUALITIES.index(self.cfg.get("quality", "very_high")),
                          lambda i: self._set("quality", B.QUALITIES[i])))
        self.out_row = Adw.EntryRow(title="Dossier de sortie")
        self.out_row.set_text(self.cfg.get("outdir", "~/Videos"))
        self.out_row.connect("changed", lambda r: self._set("outdir", r.get_text()))
        folder = Gtk.Button(icon_name="folder-open-symbolic", valign=Gtk.Align.CENTER)
        folder.connect("clicked", self._pick_folder)
        self.out_row.add_suffix(folder)
        g.add(self.out_row)

    # ----- groupe Aides tuto -----
    def _build_tuto_group(self):
        g = Adw.PreferencesGroup(
            title="Aides tuto",
            description="Surcouches utiles pour les tutoriels.")
        self.page.add(g)
        keys = Adw.SwitchRow(title="Afficher les touches pressées")
        if not B.have_showmethekey():
            keys.set_subtitle("Nécessite : flatpak install flathub one.alynx.showmethekey")
        keys.set_active(bool(self.cfg.get("show_keys")))
        keys.connect("notify::active", lambda r, _: self._set("show_keys", r.get_active()))
        g.add(keys)
        clicks = Adw.SwitchRow(title="Mettre les clics en évidence",
                               subtitle="À venir : nécessite une extension GNOME Shell")
        clicks.set_active(bool(self.cfg.get("show_clicks")))
        clicks.set_sensitive(False)
        g.add(clicks)

    # ───────────────────────── helpers UI ─────────────────────────
    def _combo(self, title, options, active, on_change):
        row = Adw.ComboRow(title=title)
        row.set_model(Gtk.StringList.new(options))
        row.set_selected(max(0, active))
        row.connect("notify::selected", lambda r, _: on_change(r.get_selected()))
        return row

    def _add_order_controls(self, row, key, idx):
        up = Gtk.Button(icon_name="go-up-symbolic", valign=Gtk.Align.CENTER)
        up.set_tooltip_text("Monter")
        up.connect("clicked", lambda *_: self._move(key, idx, -1))
        down = Gtk.Button(icon_name="go-down-symbolic", valign=Gtk.Align.CENTER)
        down.set_tooltip_text("Descendre")
        down.connect("clicked", lambda *_: self._move(key, idx, +1))
        rm = Gtk.Button(icon_name="user-trash-symbolic", valign=Gtk.Align.CENTER)
        rm.set_tooltip_text("Retirer")
        rm.connect("clicked", lambda *_: self._remove(key, idx))
        for b in (up, down, rm):
            b.add_css_class("flat")
            row.add_suffix(b)

    def _move(self, key, idx, delta):
        lst = self.cfg.get(key, [])
        j = idx + delta
        if 0 <= j < len(lst):
            lst[idx], lst[j] = lst[j], lst[idx]
            self._set(key, lst)
            self._rebuild(key)

    def _remove(self, key, idx):
        lst = self.cfg.get(key, [])
        if 0 <= idx < len(lst):
            lst.pop(idx)
            self._set(key, lst)
            self._rebuild(key)

    def _add_detected(self, kind):
        if kind == "mic":
            present = {p for p in self.cfg["mic_order"]}
            choices = [m for m in self.mics
                       if not any(B.match_present(p, [m]) for p in present)]
            self._choose_dialog("Ajouter un micro", choices, "desc", "name", "mic_order")
        else:
            present = {p for p in self.cfg["screen_order"]}
            choices = [m for m in self.monitors
                       if not any(B.match_present(p, [m]) for p in present)]
            self._choose_dialog("Ajouter un écran", choices, "name", "name", "screen_order")

    def _choose_dialog(self, title, choices, label_key, val_key, cfg_key):
        if not choices:
            self._toast("Tous les appareils détectés sont déjà dans la liste.")
            return
        dlg = Adw.MessageDialog(transient_for=self, heading=title)
        box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=6)
        group = None
        self._radio_map = {}
        for c in choices:
            btn = Gtk.CheckButton(label=c[label_key])
            if group is None:
                group = btn
                btn.set_active(True)
            else:
                btn.set_group(group)
            self._radio_map[btn] = c[val_key]
            box.append(btn)
        dlg.set_extra_child(box)
        dlg.add_response("cancel", "Annuler")
        dlg.add_response("add", "Ajouter")
        dlg.set_response_appearance("add", Adw.ResponseAppearance.SUGGESTED)

        def on_resp(d, resp):
            if resp == "add":
                for btn, val in self._radio_map.items():
                    if btn.get_active():
                        self.cfg[cfg_key].append(val)
                        self._set(cfg_key, self.cfg[cfg_key])
                        self._rebuild(cfg_key)
                        break
            d.destroy()
        dlg.connect("response", on_resp)
        dlg.present()

    def _rebuild(self, key):
        if key == "mic_order":
            self._rebuild_mic_rows()
        else:
            self._rebuild_screen_rows()

    # ───────────────────────── actions ─────────────────────────
    def _on_mode_changed(self, idx):
        self._set("capture_mode", B.CAPTURE_MODES[idx])
        self._sync_mode_visibility()

    def _sync_mode_visibility(self):
        mode = self.cfg.get("capture_mode", "portal")
        self.screen_group.set_visible(mode in ("monitor", "region"))
        self.region_row.set_visible(mode == "region")

    def _prefill_region(self, *_):
        if self.monitors:
            self.region_row.set_text(self.monitors[0]["res"] + "+0+0")

    def _on_listen(self, btn, target, bar):
        if btn.get_active():
            if self._meter_bar and self._meter_bar is not bar:
                self._meter_bar.set_value(0)
            self._meter_bar = bar
            self.meter.start(target)
        else:
            self.meter.stop()
            bar.set_value(0)
            self._meter_bar = None

    def _on_meter_level(self, level):
        if self._meter_bar:
            self._meter_bar.set_value(level)
        return False

    def _on_test(self, btn, target, row):
        btn.set_sensitive(False)
        self._toast("🎙 Parle… (4 s)")

        def work():
            res = B.mic_test(target, 4)
            try:
                if res.get("path"):
                    subprocess.run(["pw-play", res["path"]], timeout=8)
                    os.unlink(res["path"])
            except Exception:
                pass
            GLib.idle_add(done, res)

        def done(res):
            mean, mx = res.get("mean"), res.get("max")
            if mean is None:
                row.set_subtitle("test : échec de la capture")
            else:
                row.set_subtitle(f"test : moyenne {mean:.0f} dB · crête {mx:.0f} dB "
                                 f"({'bon' if mean > -30 else 'faible'})")
            btn.set_sensitive(True)
            return False
        threading.Thread(target=work, daemon=True).start()

    def on_toggle_rec(self, *_):
        B.toggle_recording()
        GLib.timeout_add(800, self._update_rec_btn)

    def on_refresh(self, *_):
        self.mics = B.list_mics()
        self.monitors = B.list_monitors()
        self._rebuild_mic_rows()
        self._rebuild_screen_rows()
        self._toast("Appareils re-détectés.")

    def _poll_rec(self):
        self._update_rec_btn()
        return True

    def _update_rec_btn(self):
        if B.is_recording():
            self.rec_btn.set_label("⏹ Arrêter")
            self.rec_btn.remove_css_class("suggested-action")
            self.rec_btn.add_css_class("destructive-action")
        else:
            self.rec_btn.set_label("● Enregistrer")
            self.rec_btn.remove_css_class("destructive-action")
            self.rec_btn.add_css_class("suggested-action")
        return False

    def _pick_folder(self, *_):
        dlg = Gtk.FileDialog(title="Dossier de sortie")
        dlg.select_folder(self, None, self._folder_picked)

    def _folder_picked(self, dlg, res):
        try:
            f = dlg.select_folder_finish(res)
            if f:
                self.out_row.set_text(f.get_path())
        except Exception:
            pass

    def _set(self, key, value):
        self.cfg[key] = value

    def save(self):
        B.save_config(self.cfg)
        self._toast("Réglages enregistrés ✓")

    def _toast(self, msg):
        self.toasts.add_toast(Adw.Toast.new(msg))

    def do_close_request(self):
        self.meter.stop()
        return False


class LazycamApp(Adw.Application):
    def __init__(self):
        super().__init__(application_id="org.friteuseb.lazycam",
                         flags=Gio.ApplicationFlags.DEFAULT_FLAGS)

    def do_activate(self):
        win = self.props.active_window or LazycamWindow(self)
        win.present()


if __name__ == "__main__":
    sys.exit(LazycamApp().run(sys.argv))
