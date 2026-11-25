import QtQuick
import QtQuick.Window

Window {
    id: win

    property int curW: 760
    property int curH: 150
    property int shift: 0
    readonly property int minW: 420
    readonly property int pillH: curH
    readonly property int popupH: 300
    readonly property int gap: 10
    readonly property var st: backend.style
    property bool styleOpen: false
    readonly property bool popupOpen: backend.pickerOpen || styleOpen
    readonly property var bgSwatches: ["", "#0B0B10", "#1B1410", "#16213E", "#1F2A1F", "#2B1B2E", "#3B1F1F", "#2B2B2B", "#FFFFFF"]
    readonly property var lineSwatches: ["", "#FFFFFF", "#E9D5BF", "#FFD166", "#FF8FA3", "#B39DDB", "#80DEEA", "#A5D6A7", "#FFAB91"]
    readonly property var sliderDefs: [
        { key: "alpha", label: "Transparency", min: 0, max: 0.8 },
        { key: "scale", label: "Text size", min: 0.7, max: 1.4 }
    ]

    function c(name, fallback) {
        const v = backend.palette[name];
        return v !== undefined ? v : fallback;
    }
    function bgColor() { return st.bg !== "" ? st.bg : c("surface_container", "#1b1410"); }
    function lineHi() { return st.line !== "" ? st.line : c("primary", "#E9D5BF"); }
    function lineDim() { return st.line !== "" ? st.line : c("on_surface", "#E9D5BF"); }

    function fmtDur(s) {
        if (!s) return "";
        const m = Math.floor(s / 60);
        const r = Math.round(s % 60);
        return m + ":" + (r < 10 ? "0" : "") + r;
    }

    function toggleStyle() {
        // Set the replacement panel first so switching doesn't move the window twice.
        styleOpen = !styleOpen;
        if (styleOpen && backend.pickerOpen) backend.togglePicker();
    }

    function activatePicker() {
        if (visible && backend.pickerOpen) {
            searchInput.forceActiveFocus(Qt.OtherFocusReason);
            requestActivate();
        }
    }

    function applySavedSize() {
        curW = Math.max(minW, Math.round(st.w || 760));
        curH = Math.max(90, Math.round(st.h || 150));
    }

    title: "Lyrics"
    flags: Qt.FramelessWindowHint | Qt.WindowStaysOnTopHint | Qt.Tool
           | (backend.pickerOpen ? 0 : Qt.WindowDoesNotAcceptFocus)
    color: "transparent"
    visible: backend.shown && backend.hasPlayer
    onVisibleChanged: if (visible && backend.pickerOpen) Qt.callLater(win.activatePicker)
    width: curW
    height: curH + (popupOpen ? gap + popupH : 0)
    x: (Screen.width - width) / 2
    y: Screen.desktopAvailableHeight - height - 60

    onPopupOpenChanged: {
        const extra = win.gap + win.popupH;
        if (popupOpen) {
            // Select the display containing the compact pill, not the expanded window.
            const area = backend.screenWorkArea(
                Math.round(win.x + win.width / 2), Math.round(win.y + win.pillH / 2));
            const desiredTop = win.y - extra;
            const fullHeight = win.pillH + extra;
            const ny = area.height > 0
                ? Math.max(area.top, Math.min(desiredTop, area.top + area.height - fullHeight))
                : desiredTop;
            win.shift = win.y - ny;
            win.y = ny;
        } else {
            win.y = win.y + win.shift;
            win.shift = 0;
        }
    }

    Component.onCompleted: applySavedSize()

    Connections {
        target: backend
        function onStyleChanged() { win.applySavedSize(); }
        function onPickerOpenChanged() {
            if (backend.pickerOpen) {
                win.styleOpen = false;
                searchInput.text = backend.searchQuery;
                Qt.callLater(win.activatePicker);
            } else {
                searchInput.focus = false;
            }
        }
        function onSearchQueryChanged() {
            if (searchInput.text !== backend.searchQuery)
                searchInput.text = backend.searchQuery;
        }
    }

    Rectangle {
        id: pill
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        height: win.pillH
        radius: 22
        clip: true
        color: Qt.alpha(win.bgColor(), win.st.alpha)
        opacity: (backend.lines.length > 0 || backend.status !== "") ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: 250 } }

        Text {
            anchors.centerIn: parent
            width: parent.width - 200
            horizontalAlignment: Text.AlignHCenter
            elide: Text.ElideRight
            visible: backend.lines.length === 0
            color: Qt.alpha(win.lineDim(), 0.6)
            font.pixelSize: Math.round(20 * win.st.scale)
            text: backend.status !== "" ? backend.status : "♪"
        }

        ListView {
            id: lv
            anchors.fill: parent
            anchors.leftMargin: 24
            anchors.rightMargin: 24
            interactive: false
            model: backend.lines
            currentIndex: Math.max(0, backend.idx)
            highlightRangeMode: ListView.StrictlyEnforceRange
            preferredHighlightBegin: height / 2 - Math.round(20 * win.st.scale)
            preferredHighlightEnd: height / 2 + Math.round(20 * win.st.scale)
            highlightMoveDuration: 450
            highlightMoveVelocity: -1

            delegate: Item {
                width: lv.width
                height: Math.round(40 * win.st.scale)
                property int dist: Math.abs(index - backend.idx)

                Rectangle {
                    anchors.fill: parent
                    anchors.margins: 2
                    radius: 10
                    color: Qt.alpha(win.lineHi(), rowArea.containsMouse ? 0.12 : 0)
                }

                Text {
                    anchors.centerIn: parent
                    width: parent.width
                    horizontalAlignment: Text.AlignHCenter
                    elide: Text.ElideRight
                    text: modelData.text !== "" ? modelData.text : "♪"
                    color: dist === 0 ? win.lineHi() : Qt.alpha(win.lineDim(), 0.5)
                    font.pixelSize: dist === 0 ? Math.round(24 * win.st.scale) : Math.round(17 * win.st.scale)
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
                    onClicked: backend.syncTo(index)
                }
            }
        }

        Text {
            anchors.bottom: parent.bottom
            anchors.left: parent.left
            anchors.margins: 8
            visible: backend.srcLabel !== ""
            text: backend.srcLabel
            font.pixelSize: 12
            color: Qt.alpha(win.lineDim(), 0.45)
        }

        Text {
            anchors.bottom: parent.bottom
            anchors.right: parent.right
            anchors.margins: 8
            visible: backend.offset !== 0
            text: (backend.offset > 0 ? "+" : "") + backend.offset.toFixed(1) + "s"
            font.pixelSize: 12
            color: Qt.alpha(win.lineDim(), 0.5)
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
                enabled: !win.popupOpen
                width: 16
                height: 16
                x: onLeft ? 0 : pill.width - width
                y: onTop ? 0 : pill.height - height
                hoverEnabled: true
                cursorShape: (onLeft === onTop) ? Qt.SizeFDiagCursor : Qt.SizeBDiagCursor

                onPressed: {
                    const p = backend.cursorPos();
                    sx = p.x;
                    sy = p.y;
                    ox = win.x;
                    oy = win.y;
                    ow = win.curW;
                    oh = win.curH;
                }

                onPositionChanged: {
                    if (!pressed) return;
                    const p = backend.cursorPos();
                    const dx = p.x - sx;
                    const dy = p.y - sy;
                    const nw = Math.max(win.minW, Math.min(onLeft ? ow - dx : ow + dx, win.screen.width - 20));
                    const nh = Math.max(90, Math.min(onTop ? oh - dy : oh + dy, win.screen.height - 40));
                    win.curW = nw;
                    win.curH = nh;
                    win.x = onLeft ? ox + (ow - nw) : ox;
                    win.y = onTop ? oy + (oh - nh) : oy;
                }

                onReleased: backend.setStyleSize(win.curW, win.curH)

                Rectangle {
                    anchors.centerIn: parent
                    width: 8
                    height: 8
                    radius: 4
                    visible: grip.containsMouse || grip.pressed
                    color: Qt.alpha(win.lineDim(), 0.7)
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
                color: Qt.alpha(win.c("on_surface", "#E9D5BF"),
                                (dragArea.containsMouse || dragArea.pressed) ? 0.7 : 0.25)
            }

            MouseArea {
                id: dragArea
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: pressed ? Qt.ClosedHandCursor : Qt.OpenHandCursor
                property real px: 0
                property real py: 0
                property real wx: 0
                property real wy: 0
                onPressed: {
                    const p = backend.cursorPos();
                    px = p.x; py = p.y; wx = win.x; wy = win.y;
                }
                onPositionChanged: {
                    if (!pressed) return;
                    const p = backend.cursorPos();
                    win.x = wx + p.x - px;
                    win.y = wy + p.y - py;
                }
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
                color: Qt.alpha(win.c("on_surface", "#E9D5BF"), closeArea.containsMouse ? 0.95 : 0.4)
            }

            MouseArea {
                id: closeArea
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: backend.shown = false
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
                color: Qt.alpha(win.c("on_surface", "#E9D5BF"),
                                (listArea.containsMouse || backend.pickerOpen) ? 0.95 : 0.4)
            }

            MouseArea {
                id: listArea
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: backend.togglePicker()
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
                color: Qt.alpha(win.c("on_surface", "#E9D5BF"),
                                (reloadArea.containsMouse || backend.busy) ? 0.95 : 0.4)
            }

            MouseArea {
                id: reloadArea
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: backend.reload()
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
                color: Qt.alpha(win.c("on_surface", "#E9D5BF"),
                                (styleArea.containsMouse || win.styleOpen) ? 0.95 : 0.4)
            }

            MouseArea {
                id: styleArea
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: win.toggleStyle()
            }
        }
    }

    Rectangle {
        id: popup
        visible: win.popupOpen
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        height: win.popupH
        radius: 22
        clip: true
        color: Qt.alpha(win.bgColor(), Math.min(1, win.st.alpha + 0.1))

        Item {
            id: pickerView
            anchors.fill: parent
            visible: backend.pickerOpen

            function submit() {
                backend.searchText(searchInput.text);
            }

            Text {
                id: pickerTitle
                anchors.left: parent.left
                anchors.top: parent.top
                anchors.margins: 16
                text: "Choose lyrics (your pick is saved to Music\\Lyrics)"
                font.pixelSize: 14
                color: Qt.alpha(win.c("on_surface", "#E9D5BF"), 0.7)
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
                    color: Qt.alpha(win.c("on_surface", "#E9D5BF"), pcloseArea.containsMouse ? 0.95 : 0.4)
                }

                MouseArea {
                    id: pcloseArea
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: backend.togglePicker()
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
                color: Qt.alpha(win.c("primary", "#E9D5BF"), sbArea.containsMouse ? 0.4 : 0.25)

                Text {
                    anchors.centerIn: parent
                    text: "Search"
                    font.pixelSize: 13
                    font.bold: true
                    color: win.c("on_surface", "#E9D5BF")
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
                objectName: "lyricsAutoButton"
                visible: backend.searchQuery !== ""
                width: 64
                height: 34
                radius: 17
                anchors.right: searchBtn.left
                anchors.rightMargin: 6
                anchors.verticalCenter: searchBtn.verticalCenter
                color: Qt.alpha(win.c("on_surface", "#E9D5BF"), abArea.containsMouse ? 0.2 : 0.1)

                Text {
                    anchors.centerIn: parent
                    text: "Auto"
                    font.pixelSize: 13
                    color: win.c("on_surface", "#E9D5BF")
                }

                MouseArea {
                    id: abArea
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: backend.autoSearch()
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
                color: Qt.alpha(win.c("on_surface", "#E9D5BF"), 0.08)
                border.width: 1
                border.color: Qt.alpha(win.c("primary", "#E9D5BF"), searchInput.activeFocus ? 0.8 : 0.2)

                TextInput {
                    id: searchInput
                    objectName: "lyricsSearchInput"
                    anchors.fill: parent
                    anchors.leftMargin: 14
                    anchors.rightMargin: 14
                    verticalAlignment: TextInput.AlignVCenter
                    clip: true
                    selectByMouse: true
                    font.pixelSize: 14
                    color: win.c("on_surface", "#E9D5BF")
                    selectionColor: win.c("primary", "#E9D5BF")
                    selectedTextColor: win.c("surface_container", "#1b1410")
                    onAccepted: pickerView.submit()
                    Keys.onEscapePressed: backend.togglePicker()
                }

                Text {
                    anchors.fill: parent
                    anchors.leftMargin: 14
                    verticalAlignment: Text.AlignVCenter
                    visible: searchInput.text === ""
                    text: "Search artist and title, then press Enter"
                    font.pixelSize: 14
                    color: Qt.alpha(win.c("on_surface", "#E9D5BF"), 0.4)
                }
            }

            Text {
                anchors.centerIn: plist
                width: parent.width - 60
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.WordWrap
                visible: backend.cands.length === 0
                color: Qt.alpha(win.c("on_surface", "#E9D5BF"), 0.6)
                font.pixelSize: 14
                text: backend.busy ? "Searching…" : "Nothing found. Try the search box above."
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
                model: backend.cands

                delegate: Rectangle {
                    width: plist.width
                    height: 42
                    radius: 10
                    color: index === backend.curIndex
                        ? Qt.alpha(win.c("primary", "#E9D5BF"), 0.22)
                        : Qt.alpha(win.c("on_surface", "#E9D5BF"), prowArea.containsMouse ? 0.12 : 0.05)

                    Text {
                        id: badge
                        anchors.left: parent.left
                        anchors.leftMargin: 12
                        anchors.verticalCenter: parent.verticalCenter
                        width: 64
                        text: modelData.source
                        font.pixelSize: 12
                        font.bold: true
                        color: win.c("primary", "#E9D5BF")
                    }

                    Text {
                        anchors.left: badge.right
                        anchors.right: meta.left
                        anchors.rightMargin: 8
                        anchors.verticalCenter: parent.verticalCenter
                        elide: Text.ElideRight
                        font.pixelSize: 14
                        color: win.c("on_surface", "#E9D5BF")
                        text: (modelData.artist ? modelData.artist + " - " : "") + modelData.title
                    }

                    Text {
                        id: meta
                        anchors.right: parent.right
                        anchors.rightMargin: 12
                        anchors.verticalCenter: parent.verticalCenter
                        font.pixelSize: 12
                        color: Qt.alpha(win.c("on_surface", "#E9D5BF"), 0.6)
                        text: win.fmtDur(modelData.duration)
                              + (modelData.source === "local" ? "" : "  " + Math.round(modelData.score * 100) + "%")
                    }

                    MouseArea {
                        id: prowArea
                        anchors.fill: parent
                        hoverEnabled: true
                        onClicked: backend.pick(index)
                    }
                }
            }
        }

        Item {
            id: styleView
            anchors.fill: parent
            visible: win.styleOpen && !backend.pickerOpen

            Text {
                id: styleTitle
                anchors.left: parent.left
                anchors.top: parent.top
                anchors.margins: 16
                text: "Style (saved automatically)"
                font.pixelSize: 14
                color: Qt.alpha(win.c("on_surface", "#E9D5BF"), 0.7)
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
                    color: Qt.alpha(win.c("on_surface", "#E9D5BF"), scloseArea.containsMouse ? 0.95 : 0.4)
                }

                MouseArea {
                    id: scloseArea
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: win.styleOpen = false
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
                        color: win.c("on_surface", "#E9D5BF")
                    }

                    Row {
                        id: bgRow
                        objectName: "backgroundSwatches"
                        readonly property int count: win.bgSwatches.length
                        readonly property real available: parent.width - bgLabel.width
                        readonly property int chipSize: Math.min(28, Math.floor((available - spacing * (count - 1)) / count))
                        anchors.left: bgLabel.right
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: Math.max(4, Math.min(8, (available - 28 * count) / (count - 1)))

                        Repeater {
                            model: win.bgSwatches

                            delegate: Rectangle {
                                width: bgRow.chipSize
                                height: width
                                radius: width / 2
                                color: modelData !== "" ? modelData : win.c("surface_container", "#1b1410")
                                border.width: win.st.bg === modelData ? 2 : 1
                                border.color: win.st.bg === modelData ? "#FFFFFF" : Qt.rgba(1, 1, 1, 0.3)

                                Text {
                                    visible: modelData === ""
                                    anchors.centerIn: parent
                                    text: "A"
                                    font.pixelSize: 13
                                    color: win.c("on_surface", "#E9D5BF")
                                }

                                MouseArea {
                                    anchors.fill: parent
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: backend.setStyleColor("bg", modelData)
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
                        color: win.c("on_surface", "#E9D5BF")
                    }

                    Row {
                        id: lineRow
                        objectName: "lineSwatches"
                        readonly property int count: win.lineSwatches.length
                        readonly property real available: parent.width - lineLabel.width
                        readonly property int chipSize: Math.min(28, Math.floor((available - spacing * (count - 1)) / count))
                        anchors.left: lineLabel.right
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: Math.max(4, Math.min(8, (available - 28 * count) / (count - 1)))

                        Repeater {
                            model: win.lineSwatches

                            delegate: Rectangle {
                                width: lineRow.chipSize
                                height: width
                                radius: width / 2
                                color: modelData !== "" ? modelData : win.c("primary", "#E9D5BF")
                                border.width: win.st.line === modelData ? 2 : 1
                                border.color: win.st.line === modelData ? "#FFFFFF" : Qt.rgba(1, 1, 1, 0.3)

                                Text {
                                    visible: modelData === ""
                                    anchors.centerIn: parent
                                    text: "A"
                                    font.pixelSize: 13
                                    font.bold: true
                                    color: win.c("surface_container", "#1b1410")
                                }

                                MouseArea {
                                    anchors.fill: parent
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: backend.setStyleColor("line", modelData)
                                }
                            }
                        }
                    }
                }

                Repeater {
                    model: win.sliderDefs

                    delegate: Item {
                        width: parent.width
                        height: 30
                        property real val: modelData.key === "alpha" ? 1 - win.st.alpha : win.st.scale
                        property real frac: Math.max(0, Math.min(1, (val - modelData.min) / (modelData.max - modelData.min)))

                        Text {
                            id: sLabel
                            width: 130
                            anchors.verticalCenter: parent.verticalCenter
                            text: modelData.label
                            font.pixelSize: 14
                            color: win.c("on_surface", "#E9D5BF")
                        }

                        Text {
                            id: sVal
                            width: 48
                            anchors.right: parent.right
                            anchors.verticalCenter: parent.verticalCenter
                            horizontalAlignment: Text.AlignRight
                            text: Math.round(val * 100) + "%"
                            font.pixelSize: 13
                            color: Qt.alpha(win.c("on_surface", "#E9D5BF"), 0.7)
                        }

                        Rectangle {
                            id: track
                            anchors.left: sLabel.right
                            anchors.right: sVal.left
                            anchors.rightMargin: 14
                            anchors.verticalCenter: parent.verticalCenter
                            height: 6
                            radius: 3
                            color: Qt.alpha(win.c("on_surface", "#E9D5BF"), 0.2)

                            Rectangle {
                                width: parent.width * frac
                                height: parent.height
                                radius: 3
                                color: win.c("primary", "#E9D5BF")
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
                                    if (modelData.key === "alpha") backend.setStyleNumber("alpha", Math.round((1 - v) * 100) / 100);
                                    else backend.setStyleNumber("scale", Math.round(v * 100) / 100);
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
                    color: Qt.alpha(win.c("on_surface", "#E9D5BF"), rsArea.containsMouse ? 0.2 : 0.1)

                    Text {
                        anchors.centerIn: parent
                        text: "Reset"
                        font.pixelSize: 13
                        color: win.c("on_surface", "#E9D5BF")
                    }

                    MouseArea {
                        id: rsArea
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: backend.resetStyle()
                    }
                }
            }
        }
    }
}
