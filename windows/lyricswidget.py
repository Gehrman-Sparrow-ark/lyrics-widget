#!/usr/bin/env python3
"""Lyrics widget for Windows.

Same look and options as the Quickshell version: local .lrc folder first, then
LRCLIB / Kugou / NetEase, a picker, click-a-line timing sync, saved offsets.
"""
import asyncio
import bisect
import ctypes
import json
import logging
import os
import re
import subprocess
import sys
import threading
import time
from ctypes import wintypes
from datetime import datetime, timezone
from pathlib import Path

# Software rendering gives reliable per-pixel transparency on Windows.
# Delete this line to try GPU rendering instead.
os.environ.setdefault("QT_QUICK_BACKEND", "software")

from PySide6.QtCore import QDir, QLockFile, QObject, Property, QTimer, QUrl, Signal, Slot
from PySide6.QtGui import QColor, QCursor, QIcon, QPainter, QPixmap
from PySide6.QtCore import Qt
from PySide6.QtQml import QQmlApplicationEngine
from PySide6.QtWidgets import QApplication, QInputDialog, QMenu, QSystemTrayIcon

APP_DIR = Path(__file__).resolve().parent
LYR_DIR = Path.home() / "Music" / "Lyrics"
LYRSEARCH = APP_DIR / "lyrsearch.py"
DISPLAY_LEAD = 0.15
STATE_DIR = Path(os.environ.get("LOCALAPPDATA", str(Path.home()))) / "lyrics-widget"
STATE_DIR.mkdir(parents=True, exist_ok=True)

# Global hotkeys: name -> (modifiers, virtual-key code). Edit freely.
MOD_ALT, MOD_CONTROL, MOD_SHIFT, MOD_WIN, MOD_NOREPEAT = 0x1, 0x2, 0x4, 0x8, 0x4000
HOTKEYS = {
    "toggle": (MOD_CONTROL | MOD_ALT, 0x4C),   # Ctrl+Alt+L
    "picker": (MOD_CONTROL | MOD_ALT, 0x50),   # Ctrl+Alt+P
    "reload": (MOD_CONTROL | MOD_ALT, 0x52),   # Ctrl+Alt+R
    "earlier": (MOD_CONTROL | MOD_ALT, 0xBB),  # Ctrl+Alt+=
    "later": (MOD_CONTROL | MOD_ALT, 0xBD),    # Ctrl+Alt+-
}

logging.basicConfig(
    filename=str(STATE_DIR / "lyrics-widget.log"),
    level=logging.INFO,
    format="%(asctime)s %(levelname)s %(message)s",
    encoding="utf-8",
)
log = logging.getLogger("lyrics-widget")


def _excepthook(t, v, tb):
    log.error("uncaught", exc_info=(t, v, tb))


sys.excepthook = _excepthook
threading.excepthook = lambda a: log.error("thread error", exc_info=(a.exc_type, a.exc_value, a.exc_traceback))


def parse_lrc(text):
    out = []
    off = 0
    tre = re.compile(r"\[(\d+):(\d+(?:[.:]\d+)?)\]")
    for line in text.splitlines():
        om = re.match(r"^\[offset:\s*([+-]?\d+)\s*\]", line, re.I)
        if om:
            off = int(om.group(1))
            continue
        times = []
        last = 0
        for m in tre.finditer(line):
            times.append(int(m.group(1)) * 60 + float(m.group(2).replace(":", ".")))
            last = m.end()
        if not times:
            continue
        txt = line[last:].strip()
        for t in times:
            out.append((t, txt))
    out.sort(key=lambda x: x[0])
    return out, off


def save_lrc(artist, title, off_ms, path, lrc):
    lrc = re.sub(r"^\[offset:[^\]]*\][ \t]*\r?\n?", "", lrc, flags=re.M | re.I)
    if off_ms:
        lrc = "[offset:%d]\n%s" % (off_ms, lrc)
    LYR_DIR.mkdir(parents=True, exist_ok=True)
    base = LYR_DIR.resolve()
    dest = None
    if path:
        p = Path(path)
        try:
            if p.suffix.lower() == ".lrc" and base in p.resolve().parents:
                dest = p
        except OSError:
            pass
    if dest is None:
        raw = ("%s - %s" % (artist, title)) if artist else title
        name = re.sub(r'[\\/:*?"<>|\x00-\x1f]', " ", raw)
        name = re.sub(r"\s+", " ", name).strip(" .") or "untitled"
        while len(name.encode("utf-8")) > 200:
            name = name[:-1]
        dest = LYR_DIR / (name + ".lrc")
    tmp = dest.parent / (dest.name + ".tmp")
    tmp.write_text(lrc, encoding="utf-8")
    os.replace(tmp, dest)


def load_palette():
    for p in (STATE_DIR / "colors.json", APP_DIR / "colors.json"):
        try:
            return json.loads(p.read_text(encoding="utf-8"))
        except Exception:
            continue
    return {}


STYLE_DEFAULT = {"bg": "", "line": "", "alpha": 0.85, "scale": 1.0, "w": 760.0, "h": 150.0}


def load_style():
    style = dict(STYLE_DEFAULT)
    try:
        data = json.loads((STATE_DIR / "style.json").read_text(encoding="utf-8"))
        for k in ("bg", "line", "alpha", "scale", "w", "h"):
            if k in data:
                style[k] = data[k]
    except Exception:
        pass
    return style


def _prop(name):
    def getter(self):
        return getattr(self, "_" + name)

    def setter(self, value):
        if getattr(self, "_" + name) != value:
            setattr(self, "_" + name, value)
            getattr(self, name + "Changed").emit()

    return getter, setter


class Backend(QObject):
    shownChanged = Signal()
    hasPlayerChanged = Signal()
    statusChanged = Signal()
    linesChanged = Signal()
    idxChanged = Signal()
    offsetChanged = Signal()
    srcLabelChanged = Signal()
    candsChanged = Signal()
    curIndexChanged = Signal()
    pickerOpenChanged = Signal()
    searchQueryChanged = Signal()
    busyChanged = Signal()
    paletteChanged = Signal()
    styleChanged = Signal()

    sigMedia = Signal(bool, str, str, float, float, bool)
    sigLocal = Signal(int, object)
    sigOnline = Signal(int, object)
    sigHotkey = Signal(str)

    shown = Property(bool, *_prop("shown"), notify=shownChanged)
    hasPlayer = Property(bool, *_prop("hasPlayer"), notify=hasPlayerChanged)
    status = Property(str, *_prop("status"), notify=statusChanged)
    lines = Property("QVariantList", *_prop("lines"), notify=linesChanged)
    idx = Property(int, *_prop("idx"), notify=idxChanged)
    offset = Property(float, *_prop("offset"), notify=offsetChanged)
    srcLabel = Property(str, *_prop("srcLabel"), notify=srcLabelChanged)
    cands = Property("QVariantList", *_prop("cands"), notify=candsChanged)
    curIndex = Property(int, *_prop("curIndex"), notify=curIndexChanged)
    pickerOpen = Property(bool, *_prop("pickerOpen"), notify=pickerOpenChanged)
    searchQuery = Property(str, *_prop("searchQuery"), notify=searchQueryChanged)
    busy = Property(bool, *_prop("busy"), notify=busyChanged)
    palette = Property("QVariantMap", *_prop("palette"), notify=paletteChanged)
    style = Property("QVariantMap", *_prop("style"), notify=styleChanged)

    def __init__(self):
        super().__init__()
        self._shown = True
        self._hasPlayer = False
        self._status = ""
        self._lines = []
        self._idx = -1
        self._offset = 0.0
        self._srcLabel = ""
        self._cands = []
        self._curIndex = -1
        self._pickerOpen = False
        self._searchQuery = ""
        self._busy = False
        self._palette = load_palette()
        self._style = load_style()

        self.title = ""
        self.artist = ""
        self.lyrArtist = ""
        self.lyrTitle = ""
        self.length = 0.0
        self.playing = False
        self.posRef = 0.0
        self.posAt = time.monotonic()
        self.loadedKey = ""
        self.rawLrc = ""
        self.curPath = ""
        self.localRunning = False
        self.localCands = []
        self.onlineCands = []
        self.onlineFinished = False
        self.onlineRunning = False
        self.times = []
        self.gen = 0

        self.sigMedia.connect(self.onMedia)
        self.sigLocal.connect(self.onLocal)
        self.sigOnline.connect(self.onOnline)
        self.sigHotkey.connect(self.onHotkey)

        self.tickTimer = QTimer(self)
        self.tickTimer.setInterval(200)
        self.tickTimer.timeout.connect(self.tick)
        self.tickTimer.start()

        self.saveTimer = QTimer(self)
        self.saveTimer.setSingleShot(True)
        self.saveTimer.setInterval(700)
        self.saveTimer.timeout.connect(self.saveCurrent)

        self.styleTimer = QTimer(self)
        self.styleTimer.setSingleShot(True)
        self.styleTimer.setInterval(500)
        self.styleTimer.timeout.connect(self.saveStyle)

    # ---- timing ----
    def curPos(self):
        return self.posRef + ((time.monotonic() - self.posAt) if self.playing else 0.0)

    def tick(self):
        if not self.times:
            return
        p = self.curPos() + DISPLAY_LEAD + self._offset
        # Exact click-to-sync can land one floating-point step before the line.
        self.idx = bisect.bisect_right(self.times, p + 1e-8) - 1

    # ---- media updates (from the poller thread) ----
    @Slot(bool, str, str, float, float, bool)
    def onMedia(self, has, title, artist, pos, length, playing):
        self.hasPlayer = has
        self.posRef = pos
        self.posAt = time.monotonic()
        self.length = length
        self.playing = playing
        if has and (title != self.title or artist != self.artist):
            self.title = title
            self.artist = artist
            self.fetchLyrics(False)

    # ---- searching ----
    def fetchLyrics(self, force, query=""):
        if not self.title:
            return
        key = self.artist + "|" + self.title
        if not force and key == self.loadedKey:
            return
        if not force:
            self.pickerOpen = False
        self.flushPendingLyrics()
        self.searchQuery = query
        self.lyrArtist = self.artist
        self.lyrTitle = self.title
        self.loadedKey = key
        self.gen += 1
        gen = self.gen
        self.lines = []
        self.idx = -1
        self.times = []
        self.localCands = []
        self.onlineCands = []
        self.cands = []
        self.curIndex = -1
        self.rawLrc = ""
        self.curPath = ""
        self.srcLabel = ""
        self.offset = 0.0
        self.localRunning = True
        self.onlineFinished = False
        self.onlineRunning = False
        self.busy = True
        self.status = "checking local files…"
        if query:
            self.pickerOpen = True
        self.spawn("--local-only", gen)
        QTimer.singleShot(30000, lambda g=gen: self.watchdog(g))

    def watchdog(self, gen):
        if gen != self.gen or not self._busy:
            return
        self.gen += 1
        self.localRunning = False
        self.onlineRunning = False
        self.busy = False
        if not self._lines:
            self.status = "search timed out, press ↻ to retry"

    def spawn(self, mode, gen):
        args = (mode, self.title, self.artist, self.length, self._searchQuery, gen)
        threading.Thread(target=self.runSearch, args=args, daemon=True).start()

    def runSearch(self, mode, title, artist, length, query, gen):
        res = None
        try:
            py = Path(sys.executable)
            exe = py.with_name("python.exe")
            cmd = [
                str(exe if exe.exists() else py), str(LYRSEARCH), mode,
                "--title=" + title, "--artist=" + artist, "--length=" + str(length or 0),
            ]
            if query:
                cmd.append("--query=" + query)
            proc = subprocess.Popen(
                cmd, stdin=subprocess.DEVNULL, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL,
                creationflags=getattr(subprocess, "CREATE_NO_WINDOW", 0),
            )
            try:
                out, _ = proc.communicate(timeout=40)
            except subprocess.TimeoutExpired:
                proc.kill()
                out = b""
            if out.strip():
                res = json.loads(out.decode("utf-8", "replace"))
        except Exception:
            log.exception("search failed")
        if mode == "--local-only":
            self.sigLocal.emit(gen, res)
        else:
            self.sigOnline.emit(gen, res)

    def runOnline(self):
        if self.localRunning or self.onlineRunning or self.onlineFinished or not self.title:
            return
        self.onlineRunning = True
        self.busy = True
        if not self._lines:
            self.status = "searching online…"
        self.spawn("--online-only", self.gen)

    def rebuild(self):
        self.cands = self.localCands + self.onlineCands

    @Slot(int, object)
    def onLocal(self, gen, res):
        if gen != self.gen:
            return
        self.localRunning = False
        self.localCands = (res or {}).get("candidates", [])
        self.rebuild()
        if self.localCands and not self._searchQuery:
            self.applyCandidate(0, False)
            self.busy = self.onlineRunning
            if self._pickerOpen:
                self.runOnline()
            return
        self.runOnline()

    @Slot(int, object)
    def onOnline(self, gen, res):
        if gen != self.gen:
            return
        self.onlineRunning = False
        self.onlineCands = (res or {}).get("candidates", [])
        self.rebuild()
        self.onlineFinished = True
        self.busy = False
        if not self._lines:
            if not self._cands:
                if not res or res.get("error"):
                    self.status = "search failed, press ↻ to retry"
                elif res.get("net_errors", 0) > 0:
                    self.status = "couldn't reach the lyric sources, press ↻ to retry"
                else:
                    self.status = "no lyrics found, press ↻ to retry"
            elif not self._searchQuery and self._cands[0].get("score", 0) >= 0.55:
                self.applyCandidate(0, False)
            else:
                self.status = "%d possible matches, ☰ to choose" % len(self._cands)

    def applyCandidate(self, i, save):
        if i < 0 or i >= len(self._cands):
            return False
        cd = self._cands[i]
        parsed, off_ms = parse_lrc(cd.get("lrc", ""))
        if not parsed:
            self.status = "that file has no timestamps"
            return False
        self.flushPendingLyrics()
        self.curIndex = i
        self.times = [t for t, _ in parsed]
        self.lines = [{"t": t, "text": x} for t, x in parsed]
        self.rawLrc = cd["lrc"]
        self.curPath = cd.get("path") or ""
        self.offset = off_ms / 1000.0
        src = cd.get("source", "")
        self.srcLabel = "local" if src == "local" else "%s · %d%%" % (src, round(cd.get("score", 0) * 100))
        self.status = ""
        self.idx = -1
        if save:
            self.saveCurrent()
        return True

    def saveCurrent(self):
        if not self.rawLrc or not self.lyrTitle:
            return
        try:
            save_lrc(self.lyrArtist, self.lyrTitle, int(round(self._offset * 1000)), self.curPath, self.rawLrc)
        except Exception:
            log.exception("saving lyrics failed")

    def flushPendingLyrics(self):
        if self.saveTimer.isActive():
            self.saveTimer.stop()
            self.saveCurrent()

    @Slot()
    def flushPendingSaves(self):
        self.flushPendingLyrics()
        if self.styleTimer.isActive():
            self.styleTimer.stop()
            self.saveStyle()

    # ---- slots used by the QML ----
    @Slot()
    def reload(self):
        if self._hasPlayer:
            self.fetchLyrics(True)

    @Slot()
    def togglePicker(self):
        if not self._pickerOpen and not self._hasPlayer:
            return
        self.pickerOpen = not self._pickerOpen
        if self._pickerOpen:
            self.runOnline()

    @Slot(int)
    def pick(self, i):
        if self.applyCandidate(i, True):
            self.pickerOpen = False

    @Slot(int)
    def syncTo(self, i):
        if i < 0 or i >= len(self._lines):
            return
        self.offset = self._lines[i]["t"] - (self.curPos() + DISPLAY_LEAD)
        self.idx = i
        self.saveTimer.start()

    def nudge(self, delta):
        self.offset = round(self._offset + delta, 3)
        self.saveTimer.start()

    def search(self, query):
        query = query.strip()
        if not query:
            # An empty box means "go back to automatic matching".
            if self._searchQuery:
                self.autoSearch()
            return
        if self._hasPlayer and self.title:
            self.fetchLyrics(True, query)

    @Slot()
    def autoSearch(self):
        if self._hasPlayer:
            self.fetchLyrics(True)


    @Slot(float, float)
    def setStyleSize(self, w, h):
        s = dict(self._style)
        s["w"] = float(w)
        s["h"] = float(h)
        self.style = s
        self.styleTimer.start()


    def saveStyle(self):
        try:
            (STATE_DIR / "style.json").write_text(json.dumps(self._style), encoding="utf-8")
        except Exception:
            log.exception("saving style failed")

    @Slot(str, str)
    def setStyleColor(self, key, value):
        s = dict(self._style)
        s[key] = value
        self.style = s
        self.styleTimer.start()

    @Slot(str, float)
    def setStyleNumber(self, key, value):
        s = dict(self._style)
        s[key] = float(value)
        self.style = s
        self.styleTimer.start()

    @Slot()
    def resetStyle(self):
        self.style = dict(STYLE_DEFAULT)
        self.styleTimer.start()

    @Slot(str)
    def searchText(self, query):
        self.search(query)

    @Slot(result="QVariant")
    def cursorPos(self):
        p = QCursor.pos()
        return {"x": p.x(), "y": p.y()}

    @Slot(str)
    def onHotkey(self, name):
        if name == "toggle":
            self.shown = not self._shown
        elif name == "picker":
            self.shown = True
            self.togglePicker()
        elif name == "reload":
            self.reload()
        elif name == "earlier":
            self.nudge(0.5)
        elif name == "later":
            self.nudge(-0.5)


class MediaPoller(threading.Thread):
    """Reads the current song from Windows' media controls (SMTC)."""

    def __init__(self, backend):
        super().__init__(daemon=True)
        self.backend = backend
        self.seen = set()

    def log_once(self, e):
        key = repr(e)
        if key not in self.seen:
            self.seen.add(key)
            log.exception("media poll error")

    def run(self):
        try:
            asyncio.run(self.loop())
        except Exception:
            log.exception("media poller stopped")

    async def loop(self):
        from winrt.windows.media.control import (
            GlobalSystemMediaTransportControlsSessionManager as Manager,
            GlobalSystemMediaTransportControlsSessionPlaybackStatus as PStatus,
        )
        mgr = await Manager.request_async()
        while True:
            best = None
            try:
                for s in list(mgr.get_sessions()):
                    try:
                        props = await s.try_get_media_properties_async()
                        title = props.title or ""
                        if not title:
                            continue
                        playing = s.get_playback_info().playback_status == PStatus.PLAYING
                        tl = s.get_timeline_properties()
                        pos = tl.position.total_seconds()
                        length = (tl.end_time - tl.start_time).total_seconds()
                        if playing:
                            last = tl.last_updated_time
                            if last.tzinfo is None:
                                last = last.replace(tzinfo=timezone.utc)
                            dt = (datetime.now(timezone.utc) - last).total_seconds()
                            if 0 < dt < 86400:
                                pos += dt
                        if length > 0:
                            pos = min(pos, length)
                        item = (playing, title, props.artist or "", max(0.0, pos), max(0.0, length))
                        if best is None or (item[0] and not best[0]):
                            best = item
                    except Exception as e:
                        self.log_once(e)
            except Exception as e:
                self.log_once(e)
            if best:
                self.backend.sigMedia.emit(True, best[1], best[2], best[3], best[4], best[0])
            else:
                self.backend.sigMedia.emit(False, "", "", 0.0, 0.0, False)
            await asyncio.sleep(0.5)


class HotkeyThread(threading.Thread):
    WM_HOTKEY = 0x0312

    def __init__(self, backend, keys):
        super().__init__(daemon=True)
        self.backend = backend
        self.keys = keys

    def run(self):
        user32 = ctypes.windll.user32
        ids = {}
        for i, (name, (mods, vk)) in enumerate(self.keys.items(), 1):
            flags = mods if name in ("earlier", "later") else mods | MOD_NOREPEAT
            if user32.RegisterHotKey(None, i, flags, vk):
                ids[i] = name
            else:
                log.warning("hotkey '%s' is unavailable (already used by another program)", name)
        msg = wintypes.MSG()
        while user32.GetMessageW(ctypes.byref(msg), None, 0, 0) != 0:
            if msg.message == self.WM_HOTKEY and msg.wParam in ids:
                self.backend.sigHotkey.emit(ids[msg.wParam])


def make_icon():
    pm = QPixmap(64, 64)
    pm.fill(Qt.transparent)
    p = QPainter(pm)
    p.setRenderHint(QPainter.Antialiasing)
    p.setPen(Qt.NoPen)
    p.setBrush(QColor("#1b1410"))
    p.drawEllipse(2, 2, 60, 60)
    p.setPen(QColor("#E9D5BF"))
    f = p.font()
    f.setPixelSize(38)
    p.setFont(f)
    p.drawText(pm.rect(), Qt.AlignCenter, "♪")
    p.end()
    return QIcon(pm)


def main():
    app = QApplication(sys.argv)
    app.setApplicationName("Lyrics Widget")
    app.setQuitOnLastWindowClosed(False)

    lock = QLockFile(QDir.temp().filePath("lyrics-widget.lock"))
    if not lock.tryLock(100):
        return 0  # already running

    backend = Backend()
    engine = QQmlApplicationEngine()
    engine.warnings.connect(lambda ws: [log.warning("QML: %s", w.toString()) for w in ws])
    engine.rootContext().setContextProperty("backend", backend)
    engine.load(QUrl.fromLocalFile(str(APP_DIR / "main.qml")))
    if not engine.rootObjects():
        log.error("main.qml failed to load")
        return 1
    app.aboutToQuit.connect(backend.flushPendingSaves)

    tray = QSystemTrayIcon(make_icon(), app)
    tray.setToolTip("Lyrics Widget")
    menu = QMenu()

    def add(label, fn):
        menu.addAction(label).triggered.connect(lambda *_: fn())

    def search_by_hand():
        if not backend.hasPlayer:
            tray.showMessage("Lyrics Widget", "Play a song before looking up lyrics.",
                             QSystemTrayIcon.MessageIcon.Information, 3000)
            return
        text, ok = QInputDialog.getText(None, "Search lyrics", "Artist and title:")
        if ok and text.strip():
            backend.shown = True
            backend.search(text.strip())

    def open_folder():
        LYR_DIR.mkdir(parents=True, exist_ok=True)
        os.startfile(str(LYR_DIR))

    add("Show / hide lyrics", lambda: setattr(backend, "shown", not backend.shown))
    add("Choose lyrics…", lambda: (setattr(backend, "shown", True), backend.togglePicker()))
    add("Reload lyrics", backend.reload)
    add("Search by hand…", search_by_hand)
    add("Open lyrics folder", open_folder)
    menu.addSeparator()
    add("Quit", app.quit)
    tray.setContextMenu(menu)
    tray.activated.connect(
        lambda reason: setattr(backend, "shown", not backend.shown) if reason == QSystemTrayIcon.Trigger else None
    )
    tray.show()

    MediaPoller(backend).start()
    HotkeyThread(backend, HOTKEYS).start()
    log.info("started")
    exit_code = app.exec()
    # Destroy QML bindings before their Python backend goes away.
    del engine
    return exit_code


if __name__ == "__main__":
    sys.exit(main())
