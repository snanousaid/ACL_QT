import QtQuick 2.10
import ACL 1.0

Item {
    id: root
    property string mjpegUrl: ""
    property bool streamPaused: false

    // ── Camera MJPEG feed ─────────────────────────────────────────────────
    MjpegItem {
        anchors.fill: parent
        source: root.mjpegUrl
        active: !root.streamPaused
    }

    // ── Dark veil ─────────────────────────────────────────────────────────
    Rectangle {
        anchors.fill: parent
        color: "#090e17"
        opacity: 0.25
    }

    // ── Top title card ────────────────────────────────────────────────────
    Rectangle {
        id: titleCard
        anchors.top: parent.top
        anchors.topMargin: 32
        anchors.horizontalCenter: parent.horizontalCenter
        width: titleCol.implicitWidth + 80
        height: titleCol.implicitHeight + 28
        radius: 16
        color: "#55111827"
        border.color: "#556b7280"
        border.width: 1

        // blur effect via layered semi-transparent rectangles
        Rectangle {
            anchors.fill: parent
            radius: parent.radius
            color: "#25ffffff"
        }

        Column {
            id: titleCol
            anchors.centerIn: parent
            spacing: 6

            // Shield icon drawn with Canvas
            Canvas {
                anchors.horizontalCenter: parent.horizontalCenter
                width: 32; height: 32
                onPaint: {
                    var ctx = getContext("2d")
                    ctx.clearRect(0, 0, width, height)
                    ctx.strokeStyle = "#60a5fa"
                    ctx.lineWidth = 2
                    ctx.lineJoin = "round"
                    ctx.beginPath()
                    ctx.moveTo(16, 2)
                    ctx.lineTo(28, 7)
                    ctx.lineTo(28, 16)
                    ctx.quadraticCurveTo(28, 26, 16, 30)
                    ctx.quadraticCurveTo(4, 26, 4, 16)
                    ctx.lineTo(4, 7)
                    ctx.closePath()
                    ctx.stroke()
                    // check mark
                    ctx.strokeStyle = "#60a5fa"
                    ctx.lineWidth = 2
                    ctx.beginPath()
                    ctx.moveTo(10, 16); ctx.lineTo(14, 20); ctx.lineTo(22, 12)
                    ctx.stroke()
                }
            }

            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: "CONTRÔLE D'ACCÈS"
                color: "#94a3b8"
                font.pixelSize: 11
                font.letterSpacing: 4
            }

            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: "SYSTÈME  <font color='#60a5fa'><b>SÉCURISÉ</b></font>"
                color: "white"
                font.pixelSize: 22
                font.weight: Font.Light
                textFormat: Text.RichText
                font.letterSpacing: 2
            }
        }
    }

    // ── ROI frame — corner brackets only ─────────────────────────────────
    Item {
        id: roiFrame
        anchors.centerIn: parent
        width: parent.width * 0.76
        height: parent.height * 0.42

        readonly property color c: "#22d3ee"
        readonly property int arm: 28
        readonly property int thick: 3

        // Top-left
        Rectangle { x: 0; y: 0; width: roiFrame.arm; height: roiFrame.thick; color: roiFrame.c }
        Rectangle { x: 0; y: 0; width: roiFrame.thick; height: roiFrame.arm; color: roiFrame.c }
        // Top-right
        Rectangle { x: roiFrame.width - roiFrame.arm; y: 0; width: roiFrame.arm; height: roiFrame.thick; color: roiFrame.c }
        Rectangle { x: roiFrame.width - roiFrame.thick; y: 0; width: roiFrame.thick; height: roiFrame.arm; color: roiFrame.c }
        // Bottom-left
        Rectangle { x: 0; y: roiFrame.height - roiFrame.thick; width: roiFrame.arm; height: roiFrame.thick; color: roiFrame.c }
        Rectangle { x: 0; y: roiFrame.height - roiFrame.arm; width: roiFrame.thick; height: roiFrame.arm; color: roiFrame.c }
        // Bottom-right
        Rectangle { x: roiFrame.width - roiFrame.arm; y: roiFrame.height - roiFrame.thick; width: roiFrame.arm; height: roiFrame.thick; color: roiFrame.c }
        Rectangle { x: roiFrame.width - roiFrame.thick; y: roiFrame.height - roiFrame.arm; width: roiFrame.thick; height: roiFrame.arm; color: roiFrame.c }

        // Pulsing opacity
        SequentialAnimation on opacity {
            loops: Animation.Infinite
            NumberAnimation { from: 1.0; to: 0.5; duration: 1200; easing.type: Easing.InOutSine }
            NumberAnimation { from: 0.5; to: 1.0; duration: 1200; easing.type: Easing.InOutSine }
        }
    }

    // ── Bottom pill ───────────────────────────────────────────────────────
    Rectangle {
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 32
        anchors.horizontalCenter: parent.horizontalCenter
        width: pillCol.implicitWidth + 64
        height: pillCol.implicitHeight + 28
        radius: 40
        color: "#cc0f172a"
        border.color: "#4d475569"
        border.width: 1

        Column {
            id: pillCol
            anchors.centerIn: parent
            spacing: 10

            Row {
                anchors.horizontalCenter: parent.horizontalCenter
                spacing: 10

                // Face scan icon
                Canvas {
                    width: 22; height: 22
                    anchors.verticalCenter: parent.verticalCenter
                    onPaint: {
                        var ctx = getContext("2d")
                        ctx.clearRect(0, 0, width, height)
                        ctx.strokeStyle = "#22d3ee"
                        ctx.lineWidth = 1.8
                        // outer circle
                        ctx.beginPath(); ctx.arc(11, 11, 9, 0, Math.PI * 2); ctx.stroke()
                        // face features
                        ctx.beginPath(); ctx.arc(8,  9, 1.2, 0, Math.PI * 2); ctx.stroke()
                        ctx.beginPath(); ctx.arc(14, 9, 1.2, 0, Math.PI * 2); ctx.stroke()
                        ctx.beginPath()
                        ctx.arc(11, 12, 3.5, 0, Math.PI)
                        ctx.stroke()
                    }
                }

                Text {
                    text: "PLACEZ VOTRE VISAGE DANS LE CADRE"
                    color: "white"
                    font.pixelSize: 15
                    font.weight: Font.DemiBold
                    font.letterSpacing: 1
                    anchors.verticalCenter: parent.verticalCenter
                }
            }

            Row {
                anchors.horizontalCenter: parent.horizontalCenter
                spacing: 10

                Rectangle {
                    width: 36; height: 1; color: "#4d64748b"
                    anchors.verticalCenter: parent.verticalCenter
                }
                Text {
                    text: "⊡  ou présentez votre badge"
                    color: "#64748b"
                    font.pixelSize: 12
                    anchors.verticalCenter: parent.verticalCenter
                }
                Rectangle {
                    width: 36; height: 1; color: "#4d64748b"
                    anchors.verticalCenter: parent.verticalCenter
                }
            }
        }
    }
}
