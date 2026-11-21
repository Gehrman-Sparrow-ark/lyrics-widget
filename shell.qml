import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Services.Mpris

ShellRoot {
    id: root

    readonly property string home: Quickshell.env("HOME")

    property bool shown: true
    property var lines: []
    property int idx: -1
    property string status: ""
    property string loadedKey: ""
    property real offset: 0
    property string rawLrc: ""
    property string curPath: ""
    property string srcLabel: ""
    property var cands: []
    property int curIndex: -1
    property bool pickerOpen: false
    property bool autoOpen: false
    property string customQuery: ""
    property bool busy: false
    property bool onlineDone: false
    property var localCands: []
    property var onlineCands: []

    property var pal: ({})
    function c(name, fallback) {
        return pal[name] !== undefined ? pal[name] : fallback;
    }
    FileView {
        path: Quickshell.env("HOME") + "/.local/state/quickshell/user/generated/colors.json"
        watchChanges: true
        onFileChanged: reload()
        onLoaded: {
            try { root.pal = JSON.parse(text()); } catch (e) {}
        }
    }

    property var player: {
        const all = Mpris.players.values;
        const list = [];
        for (let i = 0; i < all.length; i++) {
            const n = (all[i].dbusName || "") + " " + (all[i].identity || "");
            if (n.indexOf("plasma-browser-integration") < 0) list.push(all[i]);
        }
        for (let i = 0; i < list.length; i++)
            if (list[i].isPlaying) return list[i];
        return list.length > 0 ? list[0] : null;
    }

    readonly property string title: player ? player.trackTitle : ""
    readonly property string artist: player ? player.trackArtist : ""

    onTitleChanged: fetchLyrics(false)
    onArtistChanged: fetchLyrics(false)
    Component.onCompleted: fetchLyrics(false)

    function fmtDur(s) {
        if (!s) return "";
        const m = Math.floor(s / 60);
        const r = Math.round(s % 60);
        return m + ":" + (r < 10 ? "0" : "") + r;
    }

    function parseLrc(text) {
        const out = [];
        let off = 0;
        const tre = /\[(\d+):(\d+(?:[.:]\d+)?)\]/g;
        text.split(/\r?\n/).forEach(function(l) {
            const om = l.match(/^\[offset:\s*([+-]?\d+)\s*\]/i);
            if (om) { off = parseInt(om[1]); return; }
            const times = [];
            let last = 0;
            let m;
            tre.lastIndex = 0;
            while ((m = tre.exec(l)) !== null) {
                times.push(parseInt(m[1]) * 60 + parseFloat(m[2].replace(":", ".")));
                last = tre.lastIndex;
            }
            if (times.length === 0) return;
            const txt = l.substring(last).trim();
            times.forEach(function(t) { out.push({ t: t, text: txt }); });
        });
        out.sort(function(a, b) { return a.t - b.t; });
        return { lines: out, offsetMs: off };
    }

    Process {
        id: localProc
        property string key: ""
        command: ["true"]
        stdout: StdioCollector {
            onStreamFinished: {
                if (text.trim() === "" || localProc.key !== root.loadedKey) return;
                let res = null;
                try { res = JSON.parse(text); } catch (e) {}
                root.handleLocal(res);
            }
        }
    }

    Process {
        id: onlineProc
        property string key: ""
        command: ["true"]
        stdout: StdioCollector {
            onStreamFinished: {
                if (text.trim() === "" || onlineProc.key !== root.loadedKey) return;
                let res = null;
                try { res = JSON.parse(text); } catch (e) {}
                root.handleOnline(res);
            }
        }
    }

    Timer {
        id: watchdog
        interval: 30000
        onTriggered: {
            if (!root.busy) return;
            localProc.running = false;
            onlineProc.running = false;
            root.busy = false;
            if (root.lines.length === 0) root.status = "search timed out, press ↻ to retry";
        }
    }

    Process {
        id: saveProc
        command: ["true"]
    }

    Timer {
        id: saveTimer
        interval: 700
        onTriggered: root.saveCurrent()
    }

    function argsFor(mode) {
        const len = (player && player.length > 0) ? player.length : 0;
        const cmd = [home + "/.local/bin/lyrsearch", mode, "--title", title, "--artist", artist, "--length", String(len)];
        if (customQuery !== "") { cmd.push("--query"); cmd.push(customQuery); }
        return cmd;
    }

    function rebuild() {
        cands = localCands.concat(onlineCands);
    }

    function fetchLyrics(force) {
        if (!title) return;
        const key = artist + "|" + title;
        if (!force && key === loadedKey) return;
        if (!force) { customQuery = ""; pickerOpen = false; }
        loadedKey = key;
        lines = [];
        idx = -1;
        localCands = [];
        onlineCands = [];
        cands = [];
        curIndex = -1;
        rawLrc = "";
        curPath = "";
        srcLabel = "";
        offset = 0;
        onlineDone = false;
        busy = true;
        status = "checking local files…";
        localProc.running = false;
        onlineProc.running = false;
        localProc.key = key;
        localProc.command = argsFor("--local-only");
        localProc.running = true;
        watchdog.restart();
    }

    function runOnline() {
        if (onlineProc.running || !title) return;
        busy = true;
        if (lines.length === 0) status = "searching online…";
        onlineProc.key = loadedKey;
        onlineProc.command = argsFor("--online-only");
        onlineProc.running = true;
        watchdog.restart();
    }

    function handleLocal(res) {
        localCands = (res && res.candidates) ? res.candidates : [];
        rebuild();
        if (localCands.length > 0 && customQuery === "") {
            applyCand(0, false);
            busy = onlineProc.running;
            if (!busy) watchdog.stop();
            if (autoOpen) runOnline();
            return;
        }
        runOnline();
    }

    function handleOnline(res) {
        onlineCands = (res && res.candidates) ? res.candidates : [];
        rebuild();
        const open = autoOpen;
        autoOpen = false;
        onlineDone = true;
        busy = false;
        watchdog.stop();
        if (lines.length === 0) {
            if (cands.length === 0) {
                if (!res || res.error) status = "search failed, press ↻ to retry";
                else if (res.net_errors > 0) status = "couldn't reach the lyric sources, press ↻ to retry";
                else status = "no lyrics found, press ↻ to retry";
            } else if (customQuery === "" && cands[0].score >= 0.55) {
                applyCand(0, false);
            } else {
                status = cands.length + " possible matches, ☰ to choose";
            }
        }
        if (open) pickerOpen = true;
    }

    function togglePicker() {
        pickerOpen = !pickerOpen;
        if (pickerOpen && !onlineDone && !onlineProc.running && title) runOnline();
    }

    function applyCand(i, save) {
        const cd = cands[i];
        if (!cd) return;
        const parsed = parseLrc(cd.lrc);
        if (parsed.lines.length === 0) { status = "that file has no timestamps"; return; }
        curIndex = i;
        lines = parsed.lines;
        rawLrc = cd.lrc;
        curPath = cd.path || "";
        offset = parsed.offsetMs / 1000;
        srcLabel = cd.source === "local" ? "local" : cd.source + " · " + Math.round(cd.score * 100) + "%";
        status = "";
        idx = -1;
        if (save) saveCurrent();
    }

    function saveCurrent() {
        if (rawLrc === "" || !title) return;
        saveProc.running = false;
        saveProc.command = [home + "/.local/bin/lyrsave", artist, title,
                            String(Math.round(offset * 1000)), curPath, rawLrc];
        saveProc.running = true;
    }

    function syncTo(i) {
        if (!player || i < 0 || i >= lines.length) return;
        player.positionChanged();
        offset = lines[i].t - player.position + 0.15;
        idx = i;
        saveTimer.restart();
    }

    Timer {
        interval: 200
        repeat: true
        running: root.player !== null
        onTriggered: {
            root.player.positionChanged();
            const p = root.player.position + 0.15 + root.offset;
            let n = -1;
            for (let i = 0; i < root.lines.length; i++) {
                if (root.lines[i].t <= p) n = i; else break;
            }
            if (n !== root.idx) root.idx = n;
        }
    }

    IpcHandler {
        target: "lyrics"
        function toggle(): void { root.shown = !root.shown; }
        function nudge(s: string): void {
            root.offset = root.offset + parseFloat(s);
            saveTimer.restart();
        }
        function pick(): void { root.togglePicker(); }
        function reload(): void { root.fetchLyrics(true); }
        function search(q: string): void {
            root.customQuery = q;
            root.autoOpen = true;
            root.fetchLyrics(true);
        }
        function reset(): void {
            root.customQuery = "";
            root.fetchLyrics(true);
        }
    }

    PanelWindow {
        id: win
        visible: root.shown && root.player !== null
        color: "transparent"
        anchors { top: true; bottom: true; left: true; right: true }
        exclusionMode: ExclusionMode.Ignore
        mask: Region {
            x: pill.x
            y: pill.y
            width: pill.width
            height: pill.height
            Region {
                x: picker.x
                y: picker.y
                width: root.pickerOpen ? picker.width : 0
                height: root.pickerOpen ? picker.height : 0
            }
        }
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.namespace: "lyrics"

        Rectangle {
            id: pill
            width: 760
            height: 150
            x: (win.width - width) / 2
            y: win.height - height - 60
            radius: 22
            clip: true
            color: Qt.alpha(root.c("surface_container", "#1b1410"), 0.85)
            opacity: (root.lines.length > 0 || root.status !== "") ? 1 : 0
            Behavior on opacity { NumberAnimation { duration: 250 } }

            Text {
                anchors.centerIn: parent
                width: parent.width - 120
                horizontalAlignment: Text.AlignHCenter
                elide: Text.ElideRight
                visible: root.lines.length === 0
                color: Qt.alpha(root.c("on_surface", "#E9D5BF"), 0.6)
                font.pixelSize: 20
                text: root.status !== "" ? root.status : "♪"
            }

            ListView {
                id: lv
                anchors.fill: parent
                anchors.leftMargin: 24
                anchors.rightMargin: 24
                interactive: false
                model: root.lines
                currentIndex: Math.max(0, root.idx)
                highlightRangeMode: ListView.StrictlyEnforceRange
                preferredHighlightBegin: height / 2 - 20
                preferredHighlightEnd: height / 2 + 20
                highlightMoveDuration: 450
                highlightMoveVelocity: -1

                delegate: Item {
                    width: lv.width
                    height: 40
                    property int dist: Math.abs(index - root.idx)

                    Rectangle {
                        anchors.fill: parent
                        anchors.margins: 2
                        radius: 10
                        color: Qt.alpha(root.c("primary", "#E9D5BF"), rowArea.containsMouse ? 0.12 : 0)
                    }

                    Text {
                        anchors.centerIn: parent
                        width: parent.width
                        horizontalAlignment: Text.AlignHCenter
                        elide: Text.ElideRight
                        text: modelData.text !== "" ? modelData.text : "♪"
                        color: dist === 0
                            ? root.c("primary", "#E9D5BF")
                            : Qt.alpha(root.c("on_surface", "#E9D5BF"), 0.5)
                        font.pixelSize: dist === 0 ? 24 : 17
                        font.bold: dist === 0
                        opacity: dist === 0 ? 1 : (dist === 1 ? 0.6 : 0.25)
                        Behavior on opacity { NumberAnimation { duration: 350 } }
                        Behavior on font.pixelSize { NumberAnimation { duration: 350 } }
                        Behavior on color { ColorAnimation { duration: 350 } }
                    }

                    MouseArea {
                        id: rowArea
                        anchors.fill: parent
                        hoverEnabled: true
                        onClicked: root.syncTo(index)
                    }
                }
            }

            Text {
                anchors.bottom: parent.bottom
                anchors.left: parent.left
                anchors.margins: 8
                visible: root.srcLabel !== ""
                text: root.srcLabel
                font.pixelSize: 12
                color: Qt.alpha(root.c("on_surface", "#E9D5BF"), 0.45)
            }

            Text {
                anchors.bottom: parent.bottom
                anchors.right: parent.right
                anchors.margins: 8
                visible: root.offset !== 0
                text: (root.offset > 0 ? "+" : "") + root.offset.toFixed(1) + "s"
                font.pixelSize: 12
                color: Qt.alpha(root.c("on_surface", "#E9D5BF"), 0.5)
            }

            Item {
                id: handle
                width: 160
                height: 28
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.top: parent.top

                Rectangle {
                    width: 44
                    height: 4
                    radius: 2
                    anchors.centerIn: parent
                    color: Qt.alpha(root.c("on_surface", "#E9D5BF"),
                                    (dragArea.containsMouse || dragArea.pressed) ? 0.7 : 0.25)
                }

                MouseArea {
                    id: dragArea
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: pressed ? Qt.ClosedHandCursor : Qt.OpenHandCursor
                    drag.target: pill
                    drag.axis: Drag.XAndYAxis
                    drag.minimumX: 0
                    drag.maximumX: win.width - pill.width
                    drag.minimumY: 0
                    drag.maximumY: win.height - pill.height
                }
            }

            Item {
                id: closeBtn
                width: 32
                height: 28
                anchors.top: parent.top
                anchors.right: parent.right
                anchors.margins: 6

                Text {
                    anchors.centerIn: parent
                    text: "✕"
                    font.pixelSize: 15
                    color: Qt.alpha(root.c("on_surface", "#E9D5BF"), closeArea.containsMouse ? 0.95 : 0.4)
                }

                MouseArea {
                    id: closeArea
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.shown = false
                }
            }

            Item {
                id: listBtn
                width: 32
                height: 28
                anchors.top: parent.top
                anchors.right: closeBtn.left
                anchors.topMargin: 6
                anchors.rightMargin: 4

                Text {
                    anchors.centerIn: parent
                    text: "☰"
                    font.pixelSize: 16
                    color: Qt.alpha(root.c("on_surface", "#E9D5BF"),
                                    (listArea.containsMouse || root.pickerOpen) ? 0.95 : 0.4)
                }

                MouseArea {
                    id: listArea
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.togglePicker()
                }
            }

            Item {
                id: reloadBtn
                width: 32
                height: 28
                anchors.top: parent.top
                anchors.right: listBtn.left
                anchors.topMargin: 6
                anchors.rightMargin: 4

                Text {
                    anchors.centerIn: parent
                    text: "↻"
                    font.pixelSize: 17
                    color: Qt.alpha(root.c("on_surface", "#E9D5BF"),
                                    (reloadArea.containsMouse || root.busy) ? 0.95 : 0.4)
                }

                MouseArea {
                    id: reloadArea
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.fetchLyrics(true)
                }
            }
        }

        Rectangle {
            id: picker
            visible: root.pickerOpen
            width: pill.width
            height: 290
            x: pill.x
            y: (pill.y - height - 10 >= 0) ? pill.y - height - 10 : pill.y + pill.height + 10
            radius: 22
            clip: true
            color: Qt.alpha(root.c("surface_container", "#1b1410"), 0.95)

            Text {
                id: pickerTitle
                anchors.left: parent.left
                anchors.top: parent.top
                anchors.margins: 16
                text: "Choose lyrics (your pick is saved to ~/Music/Lyrics)"
                font.pixelSize: 14
                color: Qt.alpha(root.c("on_surface", "#E9D5BF"), 0.7)
            }

            Item {
                width: 32
                height: 28
                anchors.top: parent.top
                anchors.right: parent.right
                anchors.margins: 8

                Text {
                    anchors.centerIn: parent
                    text: "✕"
                    font.pixelSize: 15
                    color: Qt.alpha(root.c("on_surface", "#E9D5BF"), pcloseArea.containsMouse ? 0.95 : 0.4)
                }

                MouseArea {
                    id: pcloseArea
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.pickerOpen = false
                }
            }

            Text {
                anchors.centerIn: parent
                width: parent.width - 60
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.WordWrap
                visible: root.cands.length === 0
                color: Qt.alpha(root.c("on_surface", "#E9D5BF"), 0.6)
                font.pixelSize: 14
                text: "Nothing found. Search by hand in a terminal:\nqs -c lyrics ipc call lyrics search \"artist title\""
            }

            ListView {
                id: plist
                anchors.top: pickerTitle.bottom
                anchors.topMargin: 10
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                anchors.margins: 12
                clip: true
                spacing: 4
                model: root.cands

                delegate: Rectangle {
                    width: plist.width
                    height: 42
                    radius: 10
                    color: index === root.curIndex
                        ? Qt.alpha(root.c("primary", "#E9D5BF"), 0.22)
                        : Qt.alpha(root.c("on_surface", "#E9D5BF"), prowArea.containsMouse ? 0.12 : 0.05)

                    Text {
                        id: badge
                        anchors.left: parent.left
                        anchors.leftMargin: 12
                        anchors.verticalCenter: parent.verticalCenter
                        width: 64
                        text: modelData.source
                        font.pixelSize: 12
                        font.bold: true
                        color: root.c("primary", "#E9D5BF")
                    }

                    Text {
                        anchors.left: badge.right
                        anchors.right: meta.left
                        anchors.rightMargin: 8
                        anchors.verticalCenter: parent.verticalCenter
                        elide: Text.ElideRight
                        font.pixelSize: 14
                        color: root.c("on_surface", "#E9D5BF")
                        text: (modelData.artist ? modelData.artist + " - " : "") + modelData.title
                    }

                    Text {
                        id: meta
                        anchors.right: parent.right
                        anchors.rightMargin: 12
                        anchors.verticalCenter: parent.verticalCenter
                        font.pixelSize: 12
                        color: Qt.alpha(root.c("on_surface", "#E9D5BF"), 0.6)
                        text: root.fmtDur(modelData.duration)
                              + (modelData.source === "local" ? "" : "  " + Math.round(modelData.score * 100) + "%")
                    }

                    MouseArea {
                        id: prowArea
                        anchors.fill: parent
                        hoverEnabled: true
                        onClicked: {
                            root.applyCand(index, true);
                            root.pickerOpen = false;
                        }
                    }
                }
            }
        }
    }
}
