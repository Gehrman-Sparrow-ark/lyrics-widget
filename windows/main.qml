import QtQuick
import QtQuick.Window

Window {
    id: win

    readonly property int pillH: 150
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

    function togglePicker() {
        if (styleOpen) styleOpen = false;
        backend.togglePicker();
    }

    function toggleStyle() {
        if (backend.pickerOpen) backend.togglePicker();
        styleOpen = !styleOpen;
    }

    title: "Lyrics"
    flags: Qt.FramelessWindowHint | Qt.WindowStaysOnTopHint | Qt.Tool | Qt.WindowDoesNotAcceptFocus
    color: "transparent"
    visible: backend.shown && backend.hasPlayer
    width: 760
    height: pillH
    x: (Screen.width - width) / 2
    y: Screen.desktopAvailableHeight - height - 60

    onPopupOpenChanged: {
        const bottom = win.y + win.height;
        if (popupOpen) {
            win.height = win.pillH + win.gap + win.popupH;
            win.y = Math.max(0, bottom - win.height);
        } else {
            win.height = win.pillH;
            win.y = bottom - win.height;
        }
    }

    Connections {
        target: backend
        function onPickerOpenChanged() { backend.setFocusable(backend.pickerOpen); }
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
            anchors.margins: 6

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
                onClicked: win.togglePicker()
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

            Connections {
                target: backend
                function onCandsChanged() { }
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
                id: searchBox
                height: 34
                radius: 17
                anchors.left: parent.left
                anchors.leftMargin: 12
                anchors.right: searchBtn.left
                anchors.rightMargin: 6
                anchors.verticalCenter: searchBtn.verticalCenter
                color: Qt.alpha(win.c("on_surface", "#E9D5BF"), 0.08)
                border.width: 1
                border.color: Qt.alpha(win.c("primary", "#E9D5BF"), searchInput.activeFocus ? 0.8 : 0.2)

                TextInput {
                    id: searchInput
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
            visible: win.styleOpen

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
                        anchors.left: bgLabel.right
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 8

                        Repeater {
                            model: win.bgSwatches

                            delegate: Rectangle {
                                width: 28
                                height: 28
                                radius: 14
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
                        anchors.left: lineLabel.right
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 8

                        Repeater {
                            model: win.lineSwatches

                            delegate: Rectangle {
                                width: 28
                                height: 28
                                radius: 14
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
