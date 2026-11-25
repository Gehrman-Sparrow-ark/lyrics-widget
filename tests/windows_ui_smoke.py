#!/usr/bin/env python3
"""Run Windows backend/QML smoke checks without WinRT, Windows hotkeys or network.

From the project root, run: python tests/windows_ui_smoke.py
Requires PySide6. Qt activation eligibility is checked offscreen; Windows
foreground-window and global-hotkey behavior still needs a native check.
"""

import json
import logging
import math
import os
import sys
import tempfile
from pathlib import Path

os.environ.setdefault("QT_QPA_PLATFORM", "offscreen")
os.environ.setdefault("QT_QUICK_BACKEND", "software")
sys.dont_write_bytecode = True

from PySide6.QtCore import QMetaObject, QObject, QTimer, Qt, QUrl, qInstallMessageHandler
from PySide6.QtQml import QQmlApplicationEngine
from PySide6.QtQuick import QQuickItem
from PySide6.QtTest import QTest
from PySide6.QtWidgets import QApplication
from shiboken6 import delete

WINDOWS = Path(__file__).resolve().parents[1] / "windows"
sys.path.insert(0, str(WINDOWS))


def run(root):
    os.environ["LOCALAPPDATA"] = str(root)
    import lyricswidget as widget
    sys.excepthook = sys.__excepthook__

    widget.LYR_DIR = root / "Lyrics"
    app = QApplication([])
    app.setQuitOnLastWindowClosed(False)
    warnings = []
    previous_handler = qInstallMessageHandler(lambda mode, context, message: warnings.append(message))

    backend = widget.Backend()
    jobs = []
    backend.spawn = lambda mode, generation: jobs.append((mode, generation, backend.searchQuery))
    engine = QQmlApplicationEngine()
    engine.rootContext().setContextProperty("backend", backend)
    engine.load(QUrl.fromLocalFile(str(WINDOWS / "main.qml")))
    assert engine.rootObjects(), warnings
    win = engine.rootObjects()[0]
    editor = win.findChild(QObject, "lyricsSearchInput")
    assert editor is not None
    no_focus = Qt.WindowType.WindowDoesNotAcceptFocus

    backend.searchText("cold search")
    backend.onHotkey("picker")
    assert not backend.pickerOpen and not jobs and win.flags() & no_focus

    backend.onMedia(True, "First track", "An artist", 10.0, 120.0, False)
    initial = backend.gen
    backend.setStyleSize(420, 155)
    assert win.width() == 420
    assert QMetaObject.invokeMethod(win, "toggleStyle")
    QTest.qWait(20)
    y = win.y()
    for name in ("backgroundSwatches", "lineSwatches"):
        row = win.findChild(QQuickItem, name)
        assert row is not None
        assert 24 <= row.property("chipSize") <= 28
        assert row.property("width") <= row.property("available")
        assert len([child for child in row.childItems() if child.property("width") == row.property("chipSize")]) == 9

    # Opening from the backend exercises the same route as the tray/global hotkey.
    backend.onHotkey("picker")
    QTest.qWait(20)
    assert backend.pickerOpen and not win.property("styleOpen")
    assert not win.flags() & no_focus
    assert editor.property("focus") and editor.property("activeFocus"), warnings
    assert win.y() == y
    assert len(jobs) == 1, jobs  # Online runs only once the local pass has returned.
    backend.onLocal(initial, {"candidates": []})
    assert jobs[-1] == ("--online-only", initial, "")

    # Closing by selecting Aa allows a pending search to finish but never reopens it.
    backend.searchText("  manual artist title  ")
    manual = backend.gen
    assert backend.pickerOpen and editor.property("text") == "manual artist title"
    assert jobs[-1] == ("--local-only", manual, "manual artist title")
    assert QMetaObject.invokeMethod(win, "toggleStyle")
    backend.onLocal(manual, {"candidates": []})
    backend.onOnline(manual, {"candidates": []})
    QTest.qWait(20)
    assert not backend.pickerOpen and win.property("styleOpen")
    assert win.flags() & no_focus and win.y() == y

    # Reload is a fresh lookup using the actual track; stale responses are ignored.
    backend.reload()
    automatic = backend.gen
    assert backend.searchQuery == "" and editor.property("text") == ""
    assert jobs[-1] == ("--local-only", automatic, "")
    backend.onOnline(manual, {"candidates": [{"title": "stale"}]})
    assert backend.cands == [] and not backend.pickerOpen

    backend.searchText("second manual query")
    stale = backend.gen
    backend.onMedia(True, "Second track", "An artist", 10.0, 120.0, False)
    assert backend.gen > stale and backend.searchQuery == "" and editor.property("text") == ""
    backend.onOnline(stale, {"candidates": []})
    assert not backend.pickerOpen

    # Verify the selected line is active, not the one 200 ms later.
    lrc = "[00:10.000]First\n[00:10.200]Second\n[00:11.000]Third\n"
    backend.onLocal(backend.gen, {"candidates": [{"source": "local", "lrc": lrc}]})
    backend.tick()
    assert backend.idx == 0  # The normal +150 ms display lead remains.
    backend.syncTo(0)
    backend.tick()
    assert backend.idx == 0 and math.isclose(backend.offset, -0.15)

    # Replacing a candidate after a click flushes the previous candidate's timing.
    old_path = widget.LYR_DIR / "old.lrc"
    old_path.parent.mkdir()
    old_path.write_text(lrc, encoding="utf-8")
    backend.curPath = str(old_path)
    backend.cands = [{"source": "local", "lrc": lrc.replace("First", "Replacement")}]
    backend.pick(0)
    assert old_path.read_text(encoding="utf-8").startswith("[offset:-150]\n")
    assert "Replacement" in backend.rawLrc and not backend.saveTimer.isActive()

    # The normal quit hook flushes both timers before they have time to fire.
    backend.syncTo(0)
    backend.setStyleSize(455, 160)
    app.aboutToQuit.connect(backend.flushPendingSaves)
    QTimer.singleShot(0, app.quit)
    app.exec()
    assert not backend.saveTimer.isActive() and not backend.styleTimer.isActive()
    assert (widget.LYR_DIR / "An artist - Second track.lrc").read_text(encoding="utf-8").startswith("[offset:-150]\n")
    style = json.loads((widget.STATE_DIR / "style.json").read_text(encoding="utf-8"))
    assert style["w"] == 455 and style["h"] == 160
    assert widget.load_style()["w"] == 455
    win.hide()
    delete(engine)
    qInstallMessageHandler(previous_handler)
    assert not [warning for warning in warnings if any(fragment in warning for fragment in ("WindowDoesNotAcceptFocus", "ReferenceError", "TypeError", "Binding loop"))], warnings


if __name__ == "__main__":
    with tempfile.TemporaryDirectory(prefix="lyrics-widget-test-") as d:
        try:
            run(Path(d))
        finally:
            logging.shutdown()
    print("Windows backend and offscreen QML smoke checks passed.")
