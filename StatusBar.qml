import QtQuick 2.10

Rectangle {
    id: root
    height: 36
    color: "#0d1421"

    property bool badgeConnected: false
    property bool faceConnected:  false

    // Top border
    Rectangle {
        anchors.top: parent.top
        width: parent.width; height: 1
        color: "#1e293b"
    }

    Row {
        anchors.centerIn: parent
        spacing: 20

        // Badge status
        Row {
            spacing: 6
            anchors.verticalCenter: parent.verticalCenter

            Rectangle {
                width: 7; height: 7; radius: 4
                anchors.verticalCenter: parent.verticalCenter
                color: root.badgeConnected ? "#10b981" : "#ef4444"

                SequentialAnimation on opacity {
                    running: root.badgeConnected
                    loops: Animation.Infinite
                    NumberAnimation { from: 1; to: 0.3; duration: 800 }
                    NumberAnimation { from: 0.3; to: 1; duration: 800 }
                }
            }

            Text {
                text: "Badge"
                color: root.badgeConnected ? "#94a3b8" : "#64748b"
                font.pixelSize: 11
                font.letterSpacing: 1
                anchors.verticalCenter: parent.verticalCenter
            }
        }

        Rectangle { width: 1; height: 14; color: "#334155"; anchors.verticalCenter: parent.verticalCenter }

        // Face status
        Row {
            spacing: 6
            anchors.verticalCenter: parent.verticalCenter

            Rectangle {
                width: 7; height: 7; radius: 4
                anchors.verticalCenter: parent.verticalCenter
                color: root.faceConnected ? "#10b981" : "#ef4444"

                SequentialAnimation on opacity {
                    running: root.faceConnected
                    loops: Animation.Infinite
                    NumberAnimation { from: 1; to: 0.3; duration: 800 }
                    NumberAnimation { from: 0.3; to: 1; duration: 800 }
                }
            }

            Text {
                text: "Face ID"
                color: root.faceConnected ? "#94a3b8" : "#64748b"
                font.pixelSize: 11
                font.letterSpacing: 1
                anchors.verticalCenter: parent.verticalCenter
            }
        }

        Rectangle { width: 1; height: 14; color: "#334155"; anchors.verticalCenter: parent.verticalCenter }

        // Clock
        Text {
            id: clock
            color: "#475569"
            font.pixelSize: 11
            font.family: "monospace"
            anchors.verticalCenter: parent.verticalCenter

            Timer {
                interval: 1000; running: true; repeat: true; triggeredOnStart: true
                onTriggered: clock.text = Qt.formatTime(new Date(), "hh:mm:ss")
            }
        }
    }
}
