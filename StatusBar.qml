import QtQuick 2.10

Rectangle {
    id: root
    height: 48
    color: "#0d1421"

    property bool badgeConnected: false
    property bool faceConnected:  false

    // Top border
    Rectangle {
        anchors.top: parent.top
        width: parent.width; height: 1
        color: "#1e293b"
    }

    // ── Left: Badge + Caméra ─────────────────────────────────────────────
    Row {
        anchors.left: parent.left
        anchors.leftMargin: 16
        anchors.verticalCenter: parent.verticalCenter
        spacing: 16

        // Badge pill
        Rectangle {
            width: badgeRow.implicitWidth + 20
            height: 28; radius: 6
            color: "#0f172a"
            border.color: "#1e293b"
            anchors.verticalCenter: parent.verticalCenter

            Row {
                id: badgeRow
                anchors.centerIn: parent
                spacing: 6

                Text {
                    text: "⊡"
                    color: "#64748b"; font.pixelSize: 13
                    anchors.verticalCenter: parent.verticalCenter
                }
                Text {
                    text: "BADGE"
                    color: "#94a3b8"; font.pixelSize: 11
                    font.weight: Font.Medium; font.letterSpacing: 1
                    anchors.verticalCenter: parent.verticalCenter
                }
                Rectangle {
                    width: 7; height: 7; radius: 4
                    anchors.verticalCenter: parent.verticalCenter
                    color: root.badgeConnected ? "#22c55e" : "#ef4444"
                    SequentialAnimation on opacity {
                        running: root.badgeConnected; loops: Animation.Infinite
                        NumberAnimation { from: 1; to: 0.3; duration: 800 }
                        NumberAnimation { from: 0.3; to: 1; duration: 800 }
                    }
                }
                Text {
                    text: root.badgeConnected ? "ACTIF" : "INACTIF"
                    color: root.badgeConnected ? "#22c55e" : "#ef4444"
                    font.pixelSize: 11; font.weight: Font.Bold; font.letterSpacing: 1
                    anchors.verticalCenter: parent.verticalCenter
                }
            }
        }

        // Caméra pill
        Rectangle {
            width: camRow.implicitWidth + 20
            height: 28; radius: 6
            color: "#0f172a"
            border.color: "#1e293b"
            anchors.verticalCenter: parent.verticalCenter

            Row {
                id: camRow
                anchors.centerIn: parent
                spacing: 6

                Text {
                    text: "◉"
                    color: "#64748b"; font.pixelSize: 13
                    anchors.verticalCenter: parent.verticalCenter
                }
                Text {
                    text: "CAMÉRA"
                    color: "#94a3b8"; font.pixelSize: 11
                    font.weight: Font.Medium; font.letterSpacing: 1
                    anchors.verticalCenter: parent.verticalCenter
                }
                Rectangle {
                    width: 7; height: 7; radius: 4
                    anchors.verticalCenter: parent.verticalCenter
                    color: root.faceConnected ? "#22c55e" : "#ef4444"
                    SequentialAnimation on opacity {
                        running: root.faceConnected; loops: Animation.Infinite
                        NumberAnimation { from: 1; to: 0.3; duration: 800 }
                        NumberAnimation { from: 0.3; to: 1; duration: 800 }
                    }
                }
                Text {
                    text: root.faceConnected ? "ACTIF" : "INACTIF"
                    color: root.faceConnected ? "#22c55e" : "#ef4444"
                    font.pixelSize: 11; font.weight: Font.Bold; font.letterSpacing: 1
                    anchors.verticalCenter: parent.verticalCenter
                }
            }
        }
    }

    // ── Right: date + time ────────────────────────────────────────────────
    Row {
        anchors.right: parent.right
        anchors.rightMargin: 16
        anchors.verticalCenter: parent.verticalCenter
        spacing: 12

        Text {
            id: dateText
            color: "#475569"; font.pixelSize: 12
            anchors.verticalCenter: parent.verticalCenter
        }

        Rectangle { width: 1; height: 18; color: "#1e293b"; anchors.verticalCenter: parent.verticalCenter }

        Text {
            id: timeText
            color: "#94a3b8"; font.pixelSize: 18
            font.weight: Font.Medium; font.family: "monospace"
            anchors.verticalCenter: parent.verticalCenter
        }

        Timer {
            interval: 1000; running: true; repeat: true; triggeredOnStart: true
            onTriggered: {
                var now = new Date()
                timeText.text = Qt.formatTime(now, "hh:mm:ss")
                dateText.text = Qt.formatDate(now, "dd MMM yyyy")
            }
        }
    }
}
