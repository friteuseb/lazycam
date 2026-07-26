#!/usr/bin/env python3
"""
lazycam — interface de configuration (GTK4 / libadwaita).

Édite ~/.config/lazycam/config.json : ordre de préférence des micros et des
écrans, mode de capture, réglages d'enregistrement, aides tuto. Permet de
tester un micro (niveau + VU-mètre live) et de lancer/arrêter l'enregistrement.

Le moteur reste les scripts bash (gsr-toggle.sh) ; cette fenêtre ne fait
qu'écrire la config et déclencher.

Les chaînes affichées sont en anglais (langue source) et passent par
lazycam_i18n._() ; la traduction française y vit. Voir la clé « lang » de la
config et le sélecteur du groupe Interface.
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
import lazycam_i18n as I  # noqa: E402
from lazycam_i18n import _  # noqa: E402


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
    def __init__(self, app, cfg=None):
        super().__init__(application=app, title="lazycam")
        self.set_default_size(560, 760)
        # cfg est passé lors d'un changement de langue : la fenêtre est
        # reconstruite, mais les réglages en cours d'édition ne sont pas perdus
        # et ne sont pas écrits non plus (Appliquer reste seul maître).
        self.cfg = cfg if cfg is not None else B.load_config()
        I.set_language(self.cfg.get("lang", "auto"))
        self.mics = B.list_mics()
        self.monitors = B.list_monitors()
        self.meter = MicMeter(self._on_meter_level)
        self._meter_bar = None  # LevelBar actuellement alimenté

        toolbar = Adw.ToolbarView()
        header = Adw.HeaderBar()

        self.rec_content = Adw.ButtonContent()
        self.rec_btn = Gtk.Button(child=self.rec_content)
        self.rec_btn.add_css_class("destructive-action")
        self.rec_btn.set_tooltip_text(_("Start / stop recording (Super+R)"))
        self.rec_btn.connect("clicked", self.on_toggle_rec)
        header.pack_start(self.rec_btn)

        save_btn = Gtk.Button(child=Adw.ButtonContent(
            icon_name="document-save-symbolic", label=_("Apply")))
        save_btn.add_css_class("suggested-action")
        save_btn.set_tooltip_text(_("Save the settings (config.json)"))
        save_btn.connect("clicked", lambda *_a: self.save())
        header.pack_end(save_btn)

        refresh_btn = Gtk.Button(icon_name="view-refresh-symbolic")
        refresh_btn.set_tooltip_text(_("Re-detect devices"))
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
        self._build_shortcuts_group()
        self._build_interface_group()

        self._update_rec_btn()
        GLib.timeout_add_seconds(2, self._poll_rec)

    # ----- groupe Source vidéo -----
    def _build_video_group(self):
        g = Adw.PreferencesGroup(
            title=_("Video source"),
            description=_("The first available monitor, in order, is recorded."))
        self.page.add(g)

        self.mode_row = self._combo(
            _("Capture mode"),
            [_(B.CAPTURE_LABELS[m]) for m in B.CAPTURE_MODES],
            B.CAPTURE_MODES.index(self.cfg.get("capture_mode", "portal")),
            self._on_mode_changed)
        g.add(self.mode_row)

        self.screen_group = Adw.PreferencesGroup(
            title=_("Monitor order"),
            description=_("Reorder with ↑ ↓. Used in “Monitor” mode."))
        self.page.add(self.screen_group)
        self._screen_rows_box = self.screen_group
        self._rebuild_screen_rows()

        self.region_row = Adw.EntryRow(title=_("Region (WxH+X+Y, e.g. 1280x720+0+0)"))
        self.region_row.set_text(self.cfg.get("region", ""))
        self.region_row.connect("changed", lambda r: self._set("region", r.get_text()))
        fill = Gtk.Button(icon_name="view-fullscreen-symbolic", valign=Gtk.Align.CENTER)
        fill.set_tooltip_text(_("Prefill with the first monitor"))
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
            sub = (f"● {hit['name']} {hit['res']}" if hit
                   else _("○ no matching monitor"))
            row = Adw.ActionRow(title=pat, subtitle=sub)
            self._add_order_controls(row, "screen_order", i)
            self.screen_group.add(row)
            self._screen_rows.append(row)
        add = Adw.ActionRow(title=_("＋ Add a detected monitor"))
        btn = Gtk.Button(icon_name="list-add-symbolic", valign=Gtk.Align.CENTER)
        btn.connect("clicked", lambda *_a: self._add_detected("screen"))
        add.add_suffix(btn)
        add.set_activatable_widget(btn)
        self.screen_group.add(add)
        self._screen_rows.append(add)

    # ----- groupe Entrée audio -----
    def _build_audio_group(self):
        self.audio_group = Adw.PreferencesGroup(
            title=_("Audio input"),
            description=_("Microphone preference order. ▶ tests, 🎙 monitors the live level."))
        self.page.add(self.audio_group)
        self._rebuild_mic_rows()

        opts = Adw.PreferencesGroup()
        self.page.add(opts)
        self.denoise_row = Adw.SwitchRow(
            title=_("Noise reduction"),
            subtitle=_("Filters out constant background noise"))
        self.denoise_row.set_active(bool(self.cfg.get("denoise")))
        self.denoise_row.connect("notify::active",
                                 lambda r, _p: self._set("denoise", r.get_active()))
        opts.add(self.denoise_row)
        self.norm_row = Adw.SwitchRow(
            title=_("Normalise the voice"),
            subtitle=_("Even volume (loudnorm)"))
        self.norm_row.set_active(bool(self.cfg.get("normalize")))
        self.norm_row.connect("notify::active",
                              lambda r, _p: self._set("normalize", r.get_active()))
        opts.add(self.norm_row)

    def _rebuild_mic_rows(self):
        for r in getattr(self, "_mic_rows", []):
            self.audio_group.remove(r)
        self._mic_rows = []
        order = self.cfg.get("mic_order", [])
        for i, pat in enumerate(order):
            hit = B.match_present(pat, self.mics)
            title = hit["desc"] if hit else pat
            sub = (_("● present · {name}").format(name=hit["name"]) if hit
                   else _("○ absent · pattern: {pattern}").format(pattern=pat))
            row = Adw.ActionRow(title=title, subtitle=sub)

            bar = Gtk.LevelBar(min_value=0, max_value=1, valign=Gtk.Align.CENTER,
                               hexpand=False, width_request=70)
            row.add_suffix(bar)

            listen = Gtk.ToggleButton(icon_name="audio-input-microphone-symbolic",
                                      valign=Gtk.Align.CENTER)
            listen.set_tooltip_text(_("Monitor the live level"))
            listen.set_sensitive(hit is not None)
            listen.connect("toggled", self._on_listen, hit["name"] if hit else None, bar)
            row.add_suffix(listen)

            test = Gtk.Button(icon_name="media-playback-start-symbolic",
                              valign=Gtk.Align.CENTER)
            test.set_tooltip_text(_("4 s test: level + playback"))
            test.set_sensitive(hit is not None)
            test.connect("clicked", self._on_test, hit["name"] if hit else None, row)
            row.add_suffix(test)

            self._add_order_controls(row, "mic_order", i)
            self.audio_group.add(row)
            self._mic_rows.append(row)

        add = Adw.ActionRow(title=_("＋ Add a detected microphone"))
        btn = Gtk.Button(icon_name="list-add-symbolic", valign=Gtk.Align.CENTER)
        btn.connect("clicked", lambda *_a: self._add_detected("mic"))
        add.add_suffix(btn)
        add.set_activatable_widget(btn)
        self.audio_group.add(add)
        self._mic_rows.append(add)

    # ----- groupe Enregistrement -----
    def _build_rec_group(self):
        g = Adw.PreferencesGroup(title=_("Recording"))
        self.page.add(g)
        fps_vals = ["24", "30", "60"]
        cur_fps = str(self.cfg.get("fps", 30))
        g.add(self._combo(_("Frames per second"), fps_vals,
                          fps_vals.index(cur_fps) if cur_fps in fps_vals else 1,
                          lambda i: self._set("fps", int(fps_vals[i]))))
        g.add(self._combo("Codec", [c.upper() for c in B.CODECS],
                          B.CODECS.index(self.cfg.get("codec", "h264")),
                          lambda i: self._set("codec", B.CODECS[i])))
        g.add(self._combo(_("Quality"), [_(B.QUALITY_LABELS[q]) for q in B.QUALITIES],
                          B.QUALITIES.index(self.cfg.get("quality", "very_high")),
                          lambda i: self._set("quality", B.QUALITIES[i])))
        self.out_row = Adw.EntryRow(title=_("Output folder"))
        self.out_row.set_text(self.cfg.get("outdir", "~/Videos"))
        self.out_row.connect("changed", lambda r: self._set("outdir", r.get_text()))
        folder = Gtk.Button(icon_name="folder-open-symbolic", valign=Gtk.Align.CENTER)
        folder.connect("clicked", self._pick_folder)
        self.out_row.add_suffix(folder)
        g.add(self.out_row)

    # ----- groupe Aides tuto -----
    def _build_tuto_group(self):
        g = Adw.PreferencesGroup(
            title=_("Tutorial helpers"),
            description=_("Overlays that help when recording tutorials."))
        self.page.add(g)
        keys = Adw.SwitchRow(title=_("Show pressed keys"))
        if not B.have_showmethekey():
            keys.set_subtitle(_("Needs showmethekey — no Ubuntu package, has to be "
                                "built from source (see the README)"))
        keys.set_active(bool(self.cfg.get("show_keys")))
        keys.connect("notify::active", lambda r, _p: self._set("show_keys", r.get_active()))
        g.add(keys)
        clicks = Adw.SwitchRow(title=_("Highlight mouse clicks"),
                               subtitle=_("Coming later: needs a GNOME Shell extension"))
        clicks.set_active(bool(self.cfg.get("show_clicks")))
        clicks.set_sensitive(False)
        g.add(clicks)

    # ----- groupe Raccourcis clavier -----
    def _build_shortcuts_group(self):
        g = Adw.PreferencesGroup(title=_("Keyboard shortcuts"))
        self.page.add(g)
        self.sc_row = Adw.ActionRow(
            title="Super + R  ·  Super + Shift + R",
            subtitle=_("Start/stop · Pause/resume"))
        self.sc_btn = Gtk.Button(valign=Gtk.Align.CENTER)
        self.sc_btn.connect("clicked", self._on_shortcuts)
        self.sc_row.add_suffix(self.sc_btn)
        g.add(self.sc_row)
        self._update_sc_btn()

    # ----- groupe Interface (langue) -----
    def _build_interface_group(self):
        g = Adw.PreferencesGroup(title=_("Interface"))
        self.page.add(g)
        cur = self.cfg.get("lang", "auto")
        row = self._combo(
            _("Language"),
            [_(I.LANGUAGE_LABELS[code]) for code in I.LANGUAGES],
            I.LANGUAGES.index(cur) if cur in I.LANGUAGES else 0,
            self._on_lang_changed)
        row.set_subtitle(_("Applies immediately; saved with Apply like the other settings."))
        g.add(row)

    def _on_lang_changed(self, idx):
        lang = I.LANGUAGES[idx]
        if lang == self.cfg.get("lang", "auto"):
            return
        self._set("lang", lang)
        # Les libellés sont posés à la construction : on reconstruit la fenêtre
        # en lui repassant self.cfg, pour ne perdre ni les réglages en cours
        # d'édition ni la règle « rien n'est écrit avant Appliquer ».
        self.meter.stop()
        app = self.get_application()
        GLib.idle_add(app.rebuild_window, self.cfg, self)

    def _update_sc_btn(self):
        if B.shortcuts_active():
            self.sc_btn.set_label(_("Disable"))
            self.sc_btn.remove_css_class("suggested-action")
            self.sc_row.set_subtitle(_("Enabled · Start/stop · Pause/resume"))
        else:
            self.sc_btn.set_label(_("Enable"))
            self.sc_btn.add_css_class("suggested-action")
            self.sc_row.set_subtitle(_("Disabled — click to register them"))

    def _on_shortcuts(self, btn):
        active = B.shortcuts_active()
        try:
            B.set_shortcuts(remove=active)
            self._toast(_("Shortcuts disabled.") if active else _("Shortcuts enabled ✓"))
        except Exception:
            self._toast(_("Failed: run “lazycam-shortcuts” in a terminal."))
        self._update_sc_btn()

    # ───────────────────────── helpers UI ─────────────────────────
    def _combo(self, title, options, active, on_change):
        row = Adw.ComboRow(title=title)
        row.set_model(Gtk.StringList.new(options))
        row.set_selected(max(0, active))
        row.connect("notify::selected", lambda r, _p: on_change(r.get_selected()))
        return row

    def _add_order_controls(self, row, key, idx):
        up = Gtk.Button(icon_name="go-up-symbolic", valign=Gtk.Align.CENTER)
        up.set_tooltip_text(_("Move up"))
        up.connect("clicked", lambda *_a: self._move(key, idx, -1))
        down = Gtk.Button(icon_name="go-down-symbolic", valign=Gtk.Align.CENTER)
        down.set_tooltip_text(_("Move down"))
        down.connect("clicked", lambda *_a: self._move(key, idx, +1))
        rm = Gtk.Button(icon_name="user-trash-symbolic", valign=Gtk.Align.CENTER)
        rm.set_tooltip_text(_("Remove"))
        rm.connect("clicked", lambda *_a: self._remove(key, idx))
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
            self._choose_dialog(_("Add a microphone"), choices, "desc", "name", "mic_order")
        else:
            present = {p for p in self.cfg["screen_order"]}
            choices = [m for m in self.monitors
                       if not any(B.match_present(p, [m]) for p in present)]
            self._choose_dialog(_("Add a monitor"), choices, "name", "name", "screen_order")

    def _choose_dialog(self, title, choices, label_key, val_key, cfg_key):
        if not choices:
            self._toast(_("Every detected device is already in the list."))
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
        dlg.add_response("cancel", _("Cancel"))
        dlg.add_response("add", _("Add"))
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

    def _prefill_region(self, *_a):
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
        self._toast(_("🎙 Speak… (4 s)"))

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
                row.set_subtitle(_("test: capture failed"))
            else:
                row.set_subtitle(
                    _("test: mean {mean} dB · peak {peak} dB ({verdict})").format(
                        mean=f"{mean:.0f}", peak=f"{mx:.0f}",
                        verdict=_("good") if mean > -30 else _("low")))
            btn.set_sensitive(True)
            return False
        threading.Thread(target=work, daemon=True).start()

    def on_toggle_rec(self, *_a):
        B.toggle_recording()
        GLib.timeout_add(800, self._update_rec_btn)

    def on_refresh(self, *_a):
        self.mics = B.list_mics()
        self.monitors = B.list_monitors()
        self._rebuild_mic_rows()
        self._rebuild_screen_rows()
        self._toast(_("Devices re-detected."))

    def _poll_rec(self):
        self._update_rec_btn()
        return True

    def _update_rec_btn(self):
        if B.is_recording():
            self.rec_content.set_icon_name("media-playback-stop-symbolic")
            self.rec_content.set_label(_("Stop"))
        else:
            self.rec_content.set_icon_name("media-record-symbolic")
            self.rec_content.set_label(_("Record"))
        return False

    def _pick_folder(self, *_a):
        dlg = Gtk.FileDialog(title=_("Output folder"))
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
        self._toast(_("Settings saved ✓"))

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

    def rebuild_window(self, cfg, old):
        """Recrée la fenêtre après un changement de langue, cfg conservé tel quel."""
        LazycamWindow(self, cfg=cfg).present()
        if old is not None:
            old.destroy()
        return False


if __name__ == "__main__":
    sys.exit(LazycamApp().run(sys.argv))
