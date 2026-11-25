"""Exercise the actual Linux QML with Qt 6 and isolated Quickshell/MPRIS stubs."""
import json
import os
from pathlib import Path
import subprocess
import tempfile
from unittest.mock import patch

os.environ.setdefault("QT_QPA_PLATFORM", "offscreen")

from PySide6.QtCore import QPointF, Qt, QUrl
from PySide6.QtGui import QGuiApplication
from PySide6.QtQml import QQmlComponent, QQmlEngine
from PySide6.QtQuick import QQuickItem  # register item wrappers in PySide
from PySide6.QtTest import QTest
from shiboken6 import delete


ROOT = Path(__file__).resolve().parents[1]
SOURCE = (ROOT / "shell.qml").read_text(encoding="utf-8")
SOURCE = "\n".join(
    line for line in SOURCE.splitlines()
    if "WlrLayershell." not in line
    and line != "import Quickshell.Wayland"
    and "anchors { top: true; bottom: true; left: true; right: true }" not in line
).replace("exclusionMode: ExclusionMode.Ignore", "exclusionMode: 0")
SOURCE = SOURCE[:SOURCE.rfind("}")] + """
    readonly property QtObject fixtureWindow: win
    readonly property QtObject fixturePill: pill
    readonly property QtObject fixturePopup: popup
    readonly property QtObject fixtureBgRow: bgRow
    readonly property QtObject fixtureLineRow: lineRow
    readonly property var fixtureSaveCommand: saveProc.command
    property QtObject fixturePlayer: QtObject {
        property string trackTitle: "Track A"
        property string trackArtist: "Fixture Artist"
        property string dbusName: "fixture"
        property bool isPlaying: true
        property real position: 0
        property real length: 60
    }

    function startFixture() { Mpris.players.values = [fixturePlayer]; }
    function selectFixture(title, lyric) {
        fixturePlayer.trackTitle = title;
        cands = [{lrc: lyric, path: "/fixture/Music/Lyrics/" + title + ".lrc", source: "local", score: 1}];
        applyCand(0, false);
    }
    function submitFixture() {
        searchInput.text = "Fixture query";
        pickerView.submit();
    }
    function finishOnlineFixture() { handleOnline({candidates: []}); }
    function finishSaveFixture() { saveProc.running = false; }
}
"""

MODS = {
    "Quickshell": {
        "entries": ("ShellRoot 1.0 ShellRoot.qml\nPanelWindow 1.0 PanelWindow.qml\n"
                    "Region 1.0 Region.qml\nsingleton Quickshell 1.0 Quickshell.qml"),
        "ShellRoot": "QtObject { default property list<QtObject> children }",
        "PanelWindow": "Window { width: 1920; height: 1080; property int exclusionMode; property QtObject mask }",
        "Region": ("QtObject { default property list<QtObject> regions; property real x; property real y; "
                   "property real width; property real height }"),
        "Quickshell": 'pragma Singleton\nimport QtQuick\nQtObject { function env(k) { return "/fixture" } }',
    },
    "Quickshell/Services/Mpris": {
        "entries": "singleton Mpris 1.0 Mpris.qml",
        "Mpris": ("pragma Singleton\nimport QtQuick\nQtObject { "
                  "property QtObject players: QtObject { property var values: [] } }"),
    },
    "Quickshell/Io": {
        "entries": ("Process 1.0 Process.qml\nStdioCollector 1.0 StdioCollector.qml\n"
                    "FileView 1.0 FileView.qml\nIpcHandler 1.0 IpcHandler.qml"),
        "Process": "QtObject { property bool running; property var command; property QtObject stdout }",
        "StdioCollector": "QtObject { property string text; signal streamFinished() }",
        "FileView": ('QtObject { property string path; property bool watchChanges; signal loaded(); '
                     'signal fileChanged(); function reload() {} function text() { return "{}" } }'),
        "IpcHandler": "QtObject { property string target }",
    },
}


def drag(window, sx, sy, ex, ey):
    QTest.mousePress(window, Qt.LeftButton, Qt.NoModifier, QPointF(sx, sy).toPoint())
    QTest.mouseMove(window, QPointF(ex, ey).toPoint())
    QTest.mouseRelease(window, Qt.LeftButton, Qt.NoModifier, QPointF(ex, ey).toPoint())
    QTest.qWait(25)


def main():
    with tempfile.TemporaryDirectory(prefix="lyrics-qt-smoke-") as tmp, patch.dict(
        os.environ, {"HOME": tmp, "XDG_CACHE_HOME": tmp}
    ):
        for module, contents in MODS.items():
            folder = Path(tmp, module)
            folder.mkdir(parents=True)
            (folder / "qmldir").write_text(
                "module " + module.replace("/", ".") + "\n" + contents["entries"] + "\n"
            )
            for name, body in contents.items():
                if name != "entries":
                    (folder / (name + ".qml")).write_text(
                        body if body.startswith("pragma") else "import QtQuick\n" + body
                    )
        app = QGuiApplication([])
        engine = QQmlEngine()
        engine.addImportPath(tmp)
        component = QQmlComponent(engine)
        component.setData(SOURCE.encode("utf-8"), QUrl.fromLocalFile(str(Path(tmp, "Fixture.qml"))))
        q = component.create()
        assert q, [error.toString() for error in component.errors()]
        q.startFixture()
        window = q.property("fixtureWindow")
        pill = q.property("fixturePill")
        popup = q.property("fixturePopup")
        try:
            q.selectFixture("Track A", "[00:01]A")
            q.syncTo(0)
            assert abs(q.property("offset") - 0.85) < 1e-8
            # The ordinary playback lead still marks the selected line.
            QTest.qWait(250)
            assert q.property("idx") == 0
            q.selectFixture("Track B", "[offset:-250]\n[00:02]B")
            assert q.property("fixtureSaveCommand").toVariant()[2:] == [
                "Track A", "850", "/fixture/Music/Lyrics/Track A.lrc", "[00:01]A"
            ]
            # Selecting/saving B quickly must not terminate the outgoing A write.
            q.saveCurrent()
            assert q.property("fixtureSaveCommand").toVariant()[2] == "Track A"
            q.finishSaveFixture()
            QTest.qWait(25)
            assert q.property("fixtureSaveCommand").toVariant()[2:5] == [
                "Track B", "-250", "/fixture/Music/Lyrics/Track B.lrc"
            ]
            q.finishSaveFixture()

            q.togglePicker()
            q.submitFixture()
            q.toggleStyle()
            q.finishOnlineFixture()
            assert q.property("styleOpen") and not q.property("pickerOpen")
            # A preexisting pending IPC request also must not override choosing Aa.
            q.togglePicker()
            q.setProperty("autoOpen", True)
            q.toggleStyle()
            q.finishOnlineFixture()
            assert q.property("styleOpen") and not q.property("pickerOpen")
            q.toggleStyle()

            q.setProperty("customQuery", "-M-")
            args = q.argsFor("--local-only").toVariant()
            assert "--query=-M-" in args and "--query" not in args
            out = subprocess.check_output([str(ROOT / "lyrsearch"), *args[1:]], text=True)
            assert isinstance(json.loads(out)["candidates"], list)

            # Existing drag handle and corner now keep QML geometry bindings intact.
            x, y = int(pill.x()), int(pill.y())
            drag(window, x + int(pill.width() / 2), y + 14,
                 x + int(pill.width() / 2) + 100, y + 14)
            assert pill.x() == x + 100, (pill.x(), x)
            x, y = int(pill.x()), int(pill.y())
            drag(window, x + 8, y + 2, x + 8, 202)
            assert pill.y() == 200 and pill.height() == 820
            q.toggleStyle()
            assert popup.y() == 0 and popup.height() == 300
            assert popup.y() + popup.height() <= window.height()

            q.setProperty("pillW", 420)
            q.setProperty("pillX", 1500)
            q.setProperty("pillY", 500)
            QTest.qWait(25)
            for row_name, count in (("fixtureBgRow", 9), ("fixtureLineRow", 10)):
                row = q.property(row_name)
                swatches = [c for c in row.childItems() if c.width() and c.height()]
                assert len(swatches) == count, (row_name, len(swatches))
                assert all(c.x() + c.width() <= row.width() for c in swatches)
            q.resetStyle()
            assert pill.width() == 760 and pill.x() + pill.width() == window.width()

            window.resize(360, 200)
            QTest.qWait(25)
            assert pill.width() <= window.width()
            assert popup.height() <= window.height() and popup.y() == 0
        finally:
            window.close()
            delete(q)
            delete(component)
            delete(engine)
            app.processEvents()
            delete(app)
    print("PASS: Linux QML timing, serialized saves, picker, argv, drag, popup, reset and swatches")


if __name__ == "__main__":
    main()
