import QtQuick
import QtQuick.Window

Window {
    id: win

    readonly property int pillH: 150
    readonly property int pickerH: 290
    readonly property int gap: 10

    function c(name, fallback) {
        const v = backend.palette[name];
        return v !== undefined ? v : fallback;
    }

    function fmtDur(s) {
        if (!s) return "";
        const m = Math.floor(s / 60);
        const r = Math.round(s % 60);
        return m + ":" + (r < 10 ? "0" : "") + r;
    }

    title: "Lyrics"
    flags: Qt.FramelessWindowHint | Qt.WindowStaysOnTopHint | Qt.Tool | Qt.WindowDoesNotAcceptFocus
    color: "transparent"
    visible: backend.shown && backend.hasPlayer
    width: 760
    height: pillH
    x: (Screen.width - width) / 2
    y: Screen.desktopAvailableHeight - height - 60

    Connections {
        target: backend
        function onPickerOpenChanged() {
            const bottom = win.y + win.height;
            if (backend.pickerOpen) {
                win.height = win.pillH + win.gap + win.pickerH;
                win.y = Math.max(0, bottom - win.height);
            } else {
                win.height = win.pillH;
                win.y = bottom - win.height;
            }
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
        color: Qt.alpha(win.c("surface_container", "#1b1410"), 0.85)
        opacity: (backend.lines.length > 0 || backend.status !== "") ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: 250 } }

        Text {
            anchors.centerIn: parent
            width: parent.width - 160
            horizontalAlignment: Text.AlignHCenter
            elide: Text.ElideRight
            visible: backend.lines.length === 0
            color: Qt.alpha(win.c("on_surface", "#E9D5BF"), 0.6)
            font.pixelSize: 20
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
            preferredHighlightBegin: height / 2 - 20
            preferredHighlightEnd: height / 2 + 20
            highlightMoveDuration: 450
            highlightMoveVelocity: -1

            delegate: Item {
                width: lv.width
                height: 40
                property int dist: Math.abs(index - backend.idx)

                Rectangle {
                    anchors.fill: parent
                    anchors.margins: 2
                    radius: 10
                    color: Qt.alpha(win.c("primary", "#E9D5BF"), rowArea.containsMouse ? 0.12 : 0)
                }

                Text {
                    anchors.centerIn: parent
                    width: parent.width
                    horizontalAlignment: Text.AlignHCenter
                    elide: Text.ElideRight
                    text: modelData.text !== "" ? modelData.text : "♪"
                    color: dist === 0
                        ? win.c("primary", "#E9D5BF")
                        : Qt.alpha(win.c("on_surface", "#E9D5BF"), 0.5)
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
            color: Qt.alpha(win.c("on_surface", "#E9D5BF"), 0.45)
        }

        Text {
            anchors.bottom: parent.bottom
            anchors.right: parent.right
            anchors.margins: 8
            visible: backend.offset !== 0
            text: (backend.offset > 0 ? "+" : "") + backend.offset.toFixed(1) + "s"
            font.pixelSize: 12
            color: Qt.alpha(win.c("on_surface", "#E9D5BF"), 0.5)
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
    }

    Rectangle {
        id: picker
        visible: backend.pickerOpen
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        height: win.pickerH
        radius: 22
        clip: true
        color: Qt.alpha(win.c("surface_container", "#1b1410"), 0.95)

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

        Text {
            anchors.centerIn: parent
            width: parent.width - 60
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.WordWrap
            visible: backend.cands.length === 0
            color: Qt.alpha(win.c("on_surface", "#E9D5BF"), 0.6)
            font.pixelSize: 14
            text: backend.busy ? "Searching…" : "Nothing found. Right-click the tray icon, then Search by hand…"
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
}
