#!/usr/bin/env python3
"""Windows typed-search checks: the Auto button, and an empty box returning to automatic matching.

From the project root, run: python tests/windows_search_auto_smoke.py
Requires PySide6. Runs offscreen; no network, no WinRT.
"""

import os
import sys
import tempfile
from pathlib import Path

os.environ.setdefault("QT_QPA_PLATFORM", "offscreen")
os.environ.setdefault("QT_QUICK_BACKEND", "software")
sys.dont_write_bytecode = True

from PySide6.QtCore import QObject, QPoint, QPointF, Qt, QUrl, qInstallMessageHandler
from PySide6.QtQml import QQmlApplicationEngine
from PySide6.QtQuick import QQuickItem
from PySide6.QtTest import QTest
from PySide6.QtWidgets import QApplication

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
    qInstallMessageHandler(lambda mode, context, message: warnings.append(message))

    backend = widget.Backend()
    jobs = []
    backend.spawn = lambda mode, generation: jobs.append((mode, backend.searchQuery))
    engine = QQmlApplicationEngine()
    engine.rootContext().setContextProperty("backend", backend)
    engine.load(QUrl.fromLocalFile(str(WINDOWS / "main.qml")))
    assert engine.rootObjects(), warnings
    win = engine.rootObjects()[0]

    backend.onMedia(True, "Where's My Love", "SYML", 10.0, 190.0, False)
    QTest.qWait(20)
    auto = win.findChild(QQuickItem, "lyricsAutoButton")
    assert auto is not None, "Auto button missing from the QML"
    assert not auto.isVisible(), "Auto must be hidden while matching is automatic"

    # A typed search shows Auto.
    jobs.clear()
    backend.searchText("smashing pumpkins 1979")
    QTest.qWait(30)
    assert backend.searchQuery == "smashing pumpkins 1979" and backend.pickerOpen
    assert auto.isVisible(), "Auto must appear after a typed search"
    assert jobs and jobs[0][1] == "smashing pumpkins 1979", jobs

    # Clicking Auto goes back to automatic matching.
    jobs.clear()
    point = auto.mapToScene(QPointF(auto.width() / 2, auto.height() / 2))
    QTest.mouseClick(win, Qt.MouseButton.LeftButton, Qt.KeyboardModifier.NoModifier, QPoint(int(point.x()), int(point.y())))
    QTest.qWait(30)
    assert backend.searchQuery == "", "clicking Auto did not clear the typed search"
    assert not auto.isVisible(), "Auto must hide again"
    assert jobs and jobs[0][1] == "", jobs
    editor = win.findChild(QObject, "lyricsSearchInput")
    assert editor.property("text") == "", "the box still shows the old search"

    # Clearing the box and pressing Enter also goes back to automatic.
    backend.searchText("another search")
    QTest.qWait(30)
    assert backend.searchQuery == "another search"
    jobs.clear()
    backend.searchText("   ")
    QTest.qWait(30)
    assert backend.searchQuery == "" and jobs and jobs[0][1] == "", (backend.searchQuery, jobs)

    # An empty Enter while already automatic does nothing.
    jobs.clear()
    backend.searchText("")
    QTest.qWait(30)
    assert not jobs, jobs

    # Reload is a fresh automatic lookup too.
    backend.searchText("yet another")
    QTest.qWait(30)
    backend.reload()
    QTest.qWait(30)
    assert backend.searchQuery == ""

    # A new song also leaves the typed search.
    backend.searchText("sticky")
    QTest.qWait(30)
    backend.onMedia(True, "Second song", "Someone", 0.0, 200.0, False)
    QTest.qWait(30)
    assert backend.searchQuery == ""

    backend.flushPendingSaves()
    real = [w for w in warnings if "Binding loop" in w or "TypeError" in w or "ReferenceError" in w or "is not defined" in w]
    assert not real, real
    print("PASS: Windows Auto button, empty search, reload and song change")


with tempfile.TemporaryDirectory() as tmp:
    run(Path(tmp))
