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
    property bool styleOpen: false
    property bool autoOpen: false
    property string customQuery: ""
    property bool busy: false
    property bool onlineDone: false
    property var localCands: []
    property var onlineCands: []

    property string styleBg: ""
    property string styleLine: ""
    property real styleAlpha: 0.85
    property real styleScale: 1.0
    property real pillW: 760
    property real pillH: 150
    readonly property var bgSwatches: ["", "#0B0B10", "#1B1410", "#16213E", "#1F2A1F", "#2B1B2E", "#3B1F1F", "#2B2B2B", "#FFFFFF"]
    readonly property var lineSwatches: ["", "#FFFFFF", "#E9D5BF", "#FFD166", "#FF8FA3", "#B39DDB", "#80DEEA", "#A5D6A7", "#FFAB91"]
    readonly property var sliderDefs: [
        { key: "alpha", label: "Transparency", min: 0, max: 0.8 },
        { key: "scale", label: "Text size", min: 0.7, max: 1.4 }
    ]

    property var pal: ({})
    function c(name, fallback) {
        return pal[name] !== undefined ? pal[name] : fallback;
    }
    function bgColor() { return styleBg !== "" ? styleBg : c("surface_container", "#1b1410"); }
    function lineHi() { return styleLine !== "" ? styleLine : c("primary", "#E9D5BF"); }
    function lineDim() { return styleLine !== "" ? styleLine : c("on_surface", "#E9D5BF"); }

    FileView {
        path: Quickshell.env("HOME") + "/.local/state/quickshell/user/generated/colors.json"
        watchChanges: true
        onFileChanged: reload()
        onLoaded: {
            try { root.pal = JSON.parse(text()); } catch (e) {}
        }
    }

    FileView {
        path: Quickshell.env("HOME") + "/.config/lyrics-widget/style.json"
        onLoaded: {
            try {
                const s = JSON.parse(text());
                if (s.bg !== undefined) root.styleBg = s.bg;
                if (s.line !== undefined) root.styleLine = s.line;
                if (s.alpha !== undefined) root.styleAlpha = s.alpha;
                if (s.scale !== undefined) root.styleScale = s.scale;
                if (s.w !== undefined) root.pillW = s.w;
                if (s.h !== undefined) root.pillH = s.h;
            } catch (e) {}
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

    Process {
        id: styleSaveProc
        command: ["true"]
    }

    Timer {
        id: styleSaveTimer
        interval: 500
        onTriggered: root.saveStyle()
    }

    function saveStyle() {
        const data = JSON.stringify({ bg: styleBg, line: styleLine, alpha: styleAlpha, scale: styleScale, w: pillW, h: pillH });
        styleSaveProc.running = false;
        styleSaveProc.command = ["sh", "-c", 'mkdir -p "$HOME/.config/lyrics-widget" && printf "%s" "$1" > "$HOME/.config/lyrics-widget/style.json"', "sh", data];
        styleSaveProc.running = true;
    }

    function setStyle(key, v) {
        if (key === "bg") styleBg = v;
        else if (key === "line") styleLine = v;
        else if (key === "alpha") styleAlpha = v;
        else if (key === "scale") styleScale = v;
        styleSaveTimer.restart();
    }

    function resetStyle() {
        styleBg = "";
        styleLine = "";
        styleAlpha = 0.85;
        styleScale = 1.0;
        pillW = 760;
        pillH = 150;
        styleSaveTimer.restart();
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
        if (open) { styleOpen = false; pickerOpen = true; }
    }

    function togglePicker() {
        styleOpen = false;
        pickerOpen = !pickerOpen;
        if (pickerOpen && !onlineDone && !onlineProc.running && title) runOnline();
    }

    function toggleStyle() {
        pickerOpen = false;
        styleOpen = !styleOpen;
    }

    function resetSearch() {
        customQuery = "";
        fetchLyrics(true);
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
        function styleMenu(): void { root.toggleStyle(); }
        function reload(): void { root.fetchLyrics(true); }
        function search(q: string): void {
            root.customQuery = q;
            root.autoOpen = true;
            root.fetchLyrics(true);
        }
        function reset(): void { root.resetSearch(); }
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
                x: popup.x
                y: popup.y
                width: popup.visible ? popup.width : 0
                height: popup.visible ? popup.height : 0
            }
        }
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.namespace: "lyrics"
        WlrLayershell.keyboardFocus: root.pickerOpen ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None

        Rectangle {
            id: pill
            width: root.pillW
            height: root.pillH
            x: (win.width - width) / 2
            y: win.height - height - 60
            radius: 22
            clip: true
            color: Qt.alpha(root.bgColor(), root.styleAlpha)
            opacity: (root.lines.length > 0 || root.status !== "") ? 1 : 0
            Behavior on opacity { NumberAnimation { duration: 250 } }

            Text {
                anchors.centerIn: parent
                width: parent.width - 200
                horizontalAlignment: Text.AlignHCenter
                elide: Text.ElideRight
                visible: root.lines.length === 0
                color: Qt.alpha(root.lineDim(), 0.6)
                font.pixelSize: Math.round(20 * root.styleScale)
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
                preferredHighlightBegin: height / 2 - Math.round(20 * root.styleScale)
                preferredHighlightEnd: height / 2 + Math.round(20 * root.styleScale)
                highlightMoveDuration: 450
                highlightMoveVelocity: -1

                delegate: Item {
                    width: lv.width
                    height: Math.round(40 * root.styleScale)
                    property int dist: Math.abs(index - root.idx)

                    Rectangle {
                        anchors.fill: parent
                        anchors.margins: 2
                        radius: 10
                        color: Qt.alpha(root.lineHi(), rowArea.containsMouse ? 0.12 : 0)
                    }

                    Text {
                        anchors.centerIn: parent
                        width: parent.width
                        horizontalAlignment: Text.AlignHCenter
                        elide: Text.ElideRight
                        text: modelData.text !== "" ? modelData.text : "♪"
                        color: dist === 0 ? root.lineHi() : Qt.alpha(root.lineDim(), 0.5)
                        font.pixelSize: dist === 0 ? Math.round(24 * root.styleScale) : Math.round(17 * root.styleScale)
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
                color: Qt.alpha(root.lineDim(), 0.45)
            }

            Text {
                anchors.bottom: parent.bottom
                anchors.right: parent.right
                anchors.margins: 8
                visible: root.offset !== 0
                text: (root.offset > 0 ? "+" : "") + root.offset.toFixed(1) + "s"
                font.pixelSize: 12
                color: Qt.alpha(root.lineDim(), 0.5)
            }

            Repeater {
                model: ["tl", "tr", "bl", "br"]

                delegate: MouseArea {
                    id: grip
                    readonly property bool onLeft: modelData.charAt(1) === "l"
                    readonly property bool onTop: modelData.charAt(0) === "t"
                    property real sx: 0
                    property real sy: 0
                    property real ox: 0
                    property real oy: 0
                    property real ow: 0
                    property real oh: 0
                    width: 16
                    height: 16
                    x: onLeft ? 0 : pill.width - width
                    y: onTop ? 0 : pill.height - height
                    hoverEnabled: true
                    cursorShape: (onLeft === onTop) ? Qt.SizeFDiagCursor : Qt.SizeBDiagCursor

                    onPressed: (mouse) => {
                        const g = grip.mapToItem(null, mouse.x, mouse.y);
                        sx = g.x;
                        sy = g.y;
                        pill.x = pill.x;
                        pill.y = pill.y;
                        ox = pill.x;
                        oy = pill.y;
                        ow = root.pillW;
                        oh = root.pillH;
                    }

                    onPositionChanged: (mouse) => {
                        if (!pressed) return;
                        const g = grip.mapToItem(null, mouse.x, mouse.y);
                        const dx = g.x - sx;
                        const dy = g.y - sy;
                        const nw = Math.max(420, Math.min(onLeft ? ow - dx : ow + dx, win.width - 20));
                        const nh = Math.max(90, Math.min(onTop ? oh - dy : oh + dy, win.height - 20));
                        root.pillW = nw;
                        root.pillH = nh;
                        pill.x = onLeft ? ox + (ow - nw) : ox;
                        pill.y = onTop ? oy + (oh - nh) : oy;
                    }

                    onReleased: styleSaveTimer.restart()

                    Rectangle {
                        anchors.centerIn: parent
                        width: 8
                        height: 8
                        radius: 4
                        visible: grip.containsMouse || grip.pressed
                        color: Qt.alpha(root.lineDim(), 0.7)
                    }
                }
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
                anchors.topMargin: 6
                anchors.rightMargin: 16

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

            Item {
                id: styleBtn
                width: 36
                height: 28
                anchors.top: parent.top
                anchors.right: reloadBtn.left
                anchors.topMargin: 6
                anchors.rightMargin: 4

                Text {
                    anchors.centerIn: parent
                    text: "Aa"
                    font.pixelSize: 15
                    font.bold: true
                    color: Qt.alpha(root.c("on_surface", "#E9D5BF"),
                                    (styleArea.containsMouse || root.styleOpen) ? 0.95 : 0.4)
                }

                MouseArea {
                    id: styleArea
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.toggleStyle()
                }
            }
        }

        Rectangle {
            id: popup
            visible: root.pickerOpen || root.styleOpen
            width: pill.width
            height: 300
            x: pill.x
            y: (pill.y - height - 10 >= 0) ? pill.y - height - 10 : pill.y + pill.height + 10
            radius: 22
            clip: true
            color: Qt.alpha(root.bgColor(), Math.min(1, root.styleAlpha + 0.1))

            Item {
                id: pickerView
                anchors.fill: parent
                visible: root.pickerOpen

                function submit() {
                    const q = searchInput.text.trim();
                    if (q !== "") {
                        root.customQuery = q;
                        root.autoOpen = true;
                        root.fetchLyrics(true);
                    }
                }

                Connections {
                    target: root
                    function onCustomQueryChanged() {
                        if (root.customQuery === "") searchInput.text = "";
                    }
                }

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

                Rectangle {
                    id: searchBtn
                    width: 76
                    height: 34
                    radius: 17
                    anchors.right: parent.right
                    anchors.rightMargin: 12
                    anchors.top: pickerTitle.bottom
                    anchors.topMargin: 10
                    color: Qt.alpha(root.c("primary", "#E9D5BF"), sbArea.containsMouse ? 0.4 : 0.25)

                    Text {
                        anchors.centerIn: parent
                        text: "Search"
                        font.pixelSize: 13
                        font.bold: true
                        color: root.c("on_surface", "#E9D5BF")
                    }

                    MouseArea {
                        id: sbArea
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: pickerView.submit()
                    }
                }

                Rectangle {
                    id: autoBtn
                    visible: root.customQuery !== ""
                    width: 64
                    height: 34
                    radius: 17
                    anchors.right: searchBtn.left
                    anchors.rightMargin: 6
                    anchors.verticalCenter: searchBtn.verticalCenter
                    color: Qt.alpha(root.c("on_surface", "#E9D5BF"), abArea.containsMouse ? 0.2 : 0.1)

                    Text {
                        anchors.centerIn: parent
                        text: "Auto"
                        font.pixelSize: 13
                        color: root.c("on_surface", "#E9D5BF")
                    }

                    MouseArea {
                        id: abArea
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.resetSearch()
                    }
                }

                Rectangle {
                    id: searchBox
                    height: 34
                    radius: 17
                    anchors.left: parent.left
                    anchors.leftMargin: 12
                    anchors.right: autoBtn.visible ? autoBtn.left : searchBtn.left
                    anchors.rightMargin: 6
                    anchors.verticalCenter: searchBtn.verticalCenter
                    color: Qt.alpha(root.c("on_surface", "#E9D5BF"), 0.08)
                    border.width: 1
                    border.color: Qt.alpha(root.c("primary", "#E9D5BF"), searchInput.activeFocus ? 0.8 : 0.2)

                    TextInput {
                        id: searchInput
                        anchors.fill: parent
                        anchors.leftMargin: 14
                        anchors.rightMargin: 14
                        verticalAlignment: TextInput.AlignVCenter
                        clip: true
                        selectByMouse: true
                        font.pixelSize: 14
                        color: root.c("on_surface", "#E9D5BF")
                        selectionColor: root.c("primary", "#E9D5BF")
                        selectedTextColor: root.c("surface_container", "#1b1410")
                        onAccepted: pickerView.submit()
                        Keys.onEscapePressed: root.pickerOpen = false
                    }

                    Text {
                        anchors.fill: parent
                        anchors.leftMargin: 14
                        verticalAlignment: Text.AlignVCenter
                        visible: searchInput.text === ""
                        text: "Search artist and title, then press Enter"
                        font.pixelSize: 14
                        color: Qt.alpha(root.c("on_surface", "#E9D5BF"), 0.4)
                    }
                }

                Text {
                    anchors.centerIn: plist
                    width: parent.width - 60
                    horizontalAlignment: Text.AlignHCenter
                    wrapMode: Text.WordWrap
                    visible: root.cands.length === 0
                    color: Qt.alpha(root.c("on_surface", "#E9D5BF"), 0.6)
                    font.pixelSize: 14
                    text: root.busy ? "Searching…" : "Nothing found. Try the search box above."
                }

                ListView {
                    id: plist
                    anchors.top: searchBox.bottom
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

            Item {
                id: styleView
                anchors.fill: parent
                visible: root.styleOpen

                Text {
                    id: styleTitle
                    anchors.left: parent.left
                    anchors.top: parent.top
                    anchors.margins: 16
                    text: "Style (saved automatically)"
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
                        color: Qt.alpha(root.c("on_surface", "#E9D5BF"), scloseArea.containsMouse ? 0.95 : 0.4)
                    }

                    MouseArea {
                        id: scloseArea
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.styleOpen = false
                    }
                }

                Column {
                    anchors.top: styleTitle.bottom
                    anchors.topMargin: 14
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.leftMargin: 16
                    anchors.rightMargin: 16
                    spacing: 14

                    Item {
                        width: parent.width
                        height: 30

                        Text {
                            id: bgLabel
                            width: 130
                            anchors.verticalCenter: parent.verticalCenter
                            text: "Background colour"
                            font.pixelSize: 14
                            color: root.c("on_surface", "#E9D5BF")
                        }

                        Row {
                            anchors.left: bgLabel.right
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: 8

                            Repeater {
                                model: root.bgSwatches

                                delegate: Rectangle {
                                    width: 28
                                    height: 28
                                    radius: 14
                                    color: modelData !== "" ? modelData : root.c("surface_container", "#1b1410")
                                    border.width: root.styleBg === modelData ? 2 : 1
                                    border.color: root.styleBg === modelData ? "#FFFFFF" : Qt.rgba(1, 1, 1, 0.3)

                                    Text {
                                        visible: modelData === ""
                                        anchors.centerIn: parent
                                        text: "A"
                                        font.pixelSize: 13
                                        color: root.c("on_surface", "#E9D5BF")
                                    }

                                    MouseArea {
                                        anchors.fill: parent
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: root.setStyle("bg", modelData)
                                    }
                                }
                            }
                        }
                    }

                    Item {
                        width: parent.width
                        height: 30

                        Text {
                            id: lineLabel
                            width: 130
                            anchors.verticalCenter: parent.verticalCenter
                            text: "Line colour"
                            font.pixelSize: 14
                            color: root.c("on_surface", "#E9D5BF")
                        }

                        Row {
                            anchors.left: lineLabel.right
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: 8

                            Repeater {
                                model: root.lineSwatches

                                delegate: Rectangle {
                                    width: 28
                                    height: 28
                                    radius: 14
                                    color: modelData !== "" ? modelData : root.c("primary", "#E9D5BF")
                                    border.width: root.styleLine === modelData ? 2 : 1
                                    border.color: root.styleLine === modelData ? "#FFFFFF" : Qt.rgba(1, 1, 1, 0.3)

                                    Text {
                                        visible: modelData === ""
                                        anchors.centerIn: parent
                                        text: "A"
                                        font.pixelSize: 13
                                        font.bold: true
                                        color: root.c("surface_container", "#1b1410")
                                    }

                                    MouseArea {
                                        anchors.fill: parent
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: root.setStyle("line", modelData)
                                    }
                                }
                            }
                        }
                    }

                    Repeater {
                        model: root.sliderDefs

                        delegate: Item {
                            width: parent.width
                            height: 30
                            property real val: modelData.key === "alpha" ? 1 - root.styleAlpha : root.styleScale
                            property real frac: Math.max(0, Math.min(1, (val - modelData.min) / (modelData.max - modelData.min)))

                            Text {
                                id: sLabel
                                width: 130
                                anchors.verticalCenter: parent.verticalCenter
                                text: modelData.label
                                font.pixelSize: 14
                                color: root.c("on_surface", "#E9D5BF")
                            }

                            Text {
                                id: sVal
                                width: 48
                                anchors.right: parent.right
                                anchors.verticalCenter: parent.verticalCenter
                                horizontalAlignment: Text.AlignRight
                                text: Math.round(val * 100) + "%"
                                font.pixelSize: 13
                                color: Qt.alpha(root.c("on_surface", "#E9D5BF"), 0.7)
                            }

                            Rectangle {
                                id: track
                                anchors.left: sLabel.right
                                anchors.right: sVal.left
                                anchors.rightMargin: 14
                                anchors.verticalCenter: parent.verticalCenter
                                height: 6
                                radius: 3
                                color: Qt.alpha(root.c("on_surface", "#E9D5BF"), 0.2)

                                Rectangle {
                                    width: parent.width * frac
                                    height: parent.height
                                    radius: 3
                                    color: root.c("primary", "#E9D5BF")
                                }

                                Rectangle {
                                    id: knob
                                    width: 18
                                    height: 18
                                    radius: 9
                                    anchors.verticalCenter: parent.verticalCenter
                                    x: (track.width - width) * frac
                                    color: "#FFFFFF"
                                }

                                MouseArea {
                                    anchors.fill: parent
                                    anchors.topMargin: -12
                                    anchors.bottomMargin: -12
                                    cursorShape: Qt.PointingHandCursor

                                    function setFrom(mx) {
                                        const f = Math.max(0, Math.min(1, (mx - knob.width / 2) / (track.width - knob.width)));
                                        const v = modelData.min + f * (modelData.max - modelData.min);
                                        if (modelData.key === "alpha") root.setStyle("alpha", Math.round((1 - v) * 100) / 100);
                                        else root.setStyle("scale", Math.round(v * 100) / 100);
                                    }

                                    onPressed: (mouse) => setFrom(mouse.x)
                                    onPositionChanged: (mouse) => { if (pressed) setFrom(mouse.x) }
                                }
                            }
                        }
                    }

                    Rectangle {
                        width: 90
                        height: 28
                        radius: 14
                        color: Qt.alpha(root.c("on_surface", "#E9D5BF"), rsArea.containsMouse ? 0.2 : 0.1)

                        Text {
                            anchors.centerIn: parent
                            text: "Reset"
                            font.pixelSize: 13
                            color: root.c("on_surface", "#E9D5BF")
                        }

                        MouseArea {
                            id: rsArea
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.resetStyle()
                        }
                    }
                }
            }
        }
    }
}
