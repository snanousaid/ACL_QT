import QtQuick 2.10
import ACL 1.0

Item {
    id: root
    property string mjpegUrl: ""
    property bool streamPaused: false

    // Camera MJPEG feed (full screen)
    MjpegItem {
        anchors.fill: parent
        source: root.mjpegUrl
        active: !root.streamPaused
    }

    // Dark veil
    Rectangle {
        anchors.fill: parent
        color: "#090e17"
        opacity: 0.30
    }

    // Grid background
    Canvas {
        anchors.fill: parent
        opacity: 0.15
        onPaint: {
            var ctx = getContext("2d")
            ctx.clearRect(0, 0, width, height)
            ctx.strokeStyle = "rgba(255,255,255,0.12)"
            ctx.lineWidth = 0.8
            var step = 40
            for (var x = 0; x <= width; x += step) {
                ctx.beginPath(); ctx.moveTo(x, 0); ctx.lineTo(x, height); ctx.stroke()
            }
            for (var y = 0; y <= height; y += step) {
                ctx.beginPath(); ctx.moveTo(0, y); ctx.lineTo(width, y); ctx.stroke()
            }
        }
    }

    // Top card — title
    Rectangle {
        anchors.top: parent.top
        anchors.topMargin: 40
        anchors.horizontalCenter: parent.horizontalCenter
        width: titleCol.implicitWidth + 80
        height: titleCol.implicitHeight + 32
        radius: 16
        color: "#40000000"
        border.color: "#4d64748b"

        Column {
            id: titleCol
            anchors.centerIn: parent
            spacing: 4

            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: "🛡"
                font.pixelSize: 32
            }

            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: "CONTRÔLE D'ACCÈS"
                color: "#94a3b8"
                font.pixelSize: 11
                font.letterSpacing: 4
                font.capitalization: Font.AllUppercase
            }

            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: "SYSTÈME <b><font color='#3b82f6'>SÉCURISÉ</font></b>"
                color: "white"
                font.pixelSize: 22
                font.weight: Font.Light
                textFormat: Text.RichText
            }
        }
    }

    // Bottom pill — instructions
    Rectangle {
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 40
        anchors.horizontalCenter: parent.horizontalCenter
        width: bottomCol.implicitWidth + 64
        height: bottomCol.implicitHeight + 32
        radius: 40
        color: "#99162032"
        border.color: "#4d475569"

        Column {
            id: bottomCol
            anchors.centerIn: parent
            spacing: 8

            Row {
                anchors.horizontalCenter: parent.horizontalCenter
                spacing: 12
                Text { text: "◉"; color: "#22d3ee"; font.pixelSize: 22 }
                Text {
                    text: "PLACEZ VOTRE VISAGE DANS LE CADRE"
                    color: "white"
                    font.pixelSize: 16
                    font.weight: Font.DemiBold
                    font.letterSpacing: 1
                }
            }

            Row {
                anchors.horizontalCenter: parent.horizontalCenter
                spacing: 12
                Rectangle { width: 40; height: 1; color: "#4d64748b"; anchors.verticalCenter: parent.verticalCenter }
                Text { text: "▭  ou présentez votre badge"; color: "#94a3b8"; font.pixelSize: 12 }
                Rectangle { width: 40; height: 1; color: "#4d64748b"; anchors.verticalCenter: parent.verticalCenter }
            }
        }
    }
}
