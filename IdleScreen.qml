import QtQuick 2.10
import ACL 1.0

Item {
    id: root
    property string mjpegUrl: ""
    property bool streamPaused: false

    // Dérivé de mjpegUrl : "http://host:5050/video_feed" → ".../status.json"
    property string _statusUrl: mjpegUrl.replace("/video_feed", "/status.json")
    property bool   _inFlight:  false

    // ── État ROI reçu du backend ─────────────────────────────────────────────
    QtObject {
        id: roiStatus
        property bool   face:   false
        property bool   inRoi:  false
        property string access: ""   // "" | "granted" | "denied"
    }

    // États : idle | in | granted | denied | out
    property string _roiState: {
        if (roiStatus.access === "granted") return "granted"
        if (roiStatus.access === "denied")  return "denied"
        if (!roiStatus.face)                return "idle"
        if (!roiStatus.inRoi)               return "out"
        return "in"
    }

    property color _roiColor: {
        if (_roiState === "granted") return "#22c55e"
        if (_roiState === "denied")  return "#ef4444"
        if (_roiState === "out")     return "#64748b"
        return "#22d3ee"   // idle / in
    }

    // Opacité du cadre : pulse en idle, plein sinon
    property real _frameOpacity: 1.0
    SequentialAnimation {
        running: root._roiState === "idle"
        loops:   Animation.Infinite
        NumberAnimation { target: root; property: "_frameOpacity"; from: 1.0; to: 0.45; duration: 1200; easing.type: Easing.InOutSine }
        NumberAnimation { target: root; property: "_frameOpacity"; from: 0.45; to: 1.0; duration: 1200; easing.type: Easing.InOutSine }
        onRunningChanged: { if (!running) root._frameOpacity = 1.0 }
    }

    // ── Polling /status.json (300 ms) ────────────────────────────────────────
    Timer {
        interval: 300
        repeat:   true
        running:  !root.streamPaused && root._statusUrl.length > 0
        onTriggered: {
            if (root._inFlight) return
            root._inFlight = true
            var xhr = new XMLHttpRequest()
            xhr.open("GET", root._statusUrl)
            xhr.onreadystatechange = function() {
                if (xhr.readyState !== 4) return
                root._inFlight = false
                if (xhr.status === 200) {
                    try {
                        var d = JSON.parse(xhr.responseText)
                        roiStatus.face   = d.face   === true
                        roiStatus.inRoi  = d.in_roi === true
                        roiStatus.access = (typeof d.access === "string") ? d.access : ""
                    } catch(e) {}
                }
            }
            xhr.send()
        }
    }

    // ── Flux MJPEG ───────────────────────────────────────────────────────────
    MjpegItem {
        anchors.fill: parent
        source: root.mjpegUrl
        active: !root.streamPaused
    }

    // ── Voile sombre ─────────────────────────────────────────────────────────
    Rectangle {
        anchors.fill: parent
        color: "#090e17"
        opacity: 0.25
    }

    // ── Grille tech (40×40 px, 15% opacité) ─────────────────────────────────
    Canvas {
        anchors.fill: parent
        opacity: 0.15
        Component.onCompleted: requestPaint()
        onPaint: {
            var ctx  = getContext("2d")
            var step = 40
            ctx.clearRect(0, 0, width, height)
            ctx.strokeStyle = "#ffffff"
            ctx.lineWidth   = 0.6
            ctx.beginPath()
            for (var x = 0; x <= width;  x += step) { ctx.moveTo(x, 0);     ctx.lineTo(x, height) }
            for (var y = 0; y <= height; y += step) { ctx.moveTo(0, y);     ctx.lineTo(width, y)  }
            ctx.stroke()
        }
    }

    // ── Carte titre ──────────────────────────────────────────────────────────
    Rectangle {
        id: titleCard
        anchors.top: parent.top
        anchors.topMargin: 32
        anchors.horizontalCenter: parent.horizontalCenter
        width:  titleCol.implicitWidth + 80
        height: titleCol.implicitHeight + 28
        radius: 16
        color:  "#55111827"
        border.color: "#556b7280"
        border.width: 1

        Rectangle {
            anchors.fill: parent
            radius: parent.radius
            color:  "#25ffffff"
        }

        Column {
            id: titleCol
            anchors.centerIn: parent
            spacing: 6

            Canvas {
                anchors.horizontalCenter: parent.horizontalCenter
                width: 32; height: 32
                onPaint: {
                    var ctx = getContext("2d")
                    ctx.clearRect(0, 0, width, height)
                    ctx.strokeStyle = "#60a5fa"
                    ctx.lineWidth   = 2
                    ctx.lineJoin    = "round"
                    ctx.beginPath()
                    ctx.moveTo(16, 2)
                    ctx.lineTo(28, 7)
                    ctx.lineTo(28, 16)
                    ctx.quadraticCurveTo(28, 26, 16, 30)
                    ctx.quadraticCurveTo(4,  26,  4, 16)
                    ctx.lineTo(4, 7)
                    ctx.closePath()
                    ctx.stroke()
                    ctx.beginPath()
                    ctx.moveTo(10, 16); ctx.lineTo(14, 20); ctx.lineTo(22, 12)
                    ctx.stroke()
                }
            }

            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text:  "CONTRÔLE D'ACCÈS"
                color: "#94a3b8"
                font.pixelSize:     11
                font.letterSpacing: 4
            }
            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text:       "SYSTÈME  <font color='#60a5fa'><b>SÉCURISÉ</b></font>"
                color:      "white"
                font.pixelSize: 22
                font.weight:    Font.Light
                textFormat:     Text.RichText
                font.letterSpacing: 2
            }
        }
    }

    // ── Cadre ROI dynamique ──────────────────────────────────────────────────
    Item {
        id: roiFrame
        anchors.centerIn: parent
        width:   parent.width  * 0.76
        height:  parent.height * 0.42
        opacity: root._frameOpacity
        clip:    true

        readonly property int   arm:   28
        readonly property int   thick: 3
        readonly property color c:     root._roiColor

        // Coins — top-left
        Rectangle { x: 0;                                y: 0;                                width: roiFrame.arm;   height: roiFrame.thick; color: roiFrame.c }
        Rectangle { x: 0;                                y: 0;                                width: roiFrame.thick; height: roiFrame.arm;   color: roiFrame.c }
        // top-right
        Rectangle { x: roiFrame.width  - roiFrame.arm;  y: 0;                                width: roiFrame.arm;   height: roiFrame.thick; color: roiFrame.c }
        Rectangle { x: roiFrame.width  - roiFrame.thick; y: 0;                               width: roiFrame.thick; height: roiFrame.arm;   color: roiFrame.c }
        // bottom-left
        Rectangle { x: 0;                                y: roiFrame.height - roiFrame.thick; width: roiFrame.arm;   height: roiFrame.thick; color: roiFrame.c }
        Rectangle { x: 0;                                y: roiFrame.height - roiFrame.arm;   width: roiFrame.thick; height: roiFrame.arm;   color: roiFrame.c }
        // bottom-right
        Rectangle { x: roiFrame.width  - roiFrame.arm;  y: roiFrame.height - roiFrame.thick; width: roiFrame.arm;   height: roiFrame.thick; color: roiFrame.c }
        Rectangle { x: roiFrame.width  - roiFrame.thick; y: roiFrame.height - roiFrame.arm;  width: roiFrame.thick; height: roiFrame.arm;   color: roiFrame.c }

        // Ligne de scan (haut → bas, 2.8 s, boucle)
        Rectangle {
            id: scanLine
            anchors { left: parent.left; right: parent.right }
            height: 2
            color:  roiFrame.c
            y: 0; opacity: 0

            SequentialAnimation on y {
                loops: Animation.Infinite; running: true
                NumberAnimation { from: 0; to: roiFrame.height; duration: 2800; easing.type: Easing.Linear }
                PauseAnimation  { duration: 200 }
            }
            SequentialAnimation on opacity {
                loops: Animation.Infinite; running: true
                NumberAnimation { from: 0;   to: 0.7; duration: 280  }
                PauseAnimation  { duration: 2240 }
                NumberAnimation { from: 0.7; to: 0;   duration: 280  }
            }
        }

        // Flash (accordé / refusé)
        Rectangle {
            anchors.fill: parent
            color:   roiFrame.c
            opacity: 0

            SequentialAnimation on opacity {
                loops:   Animation.Infinite
                running: root._roiState === "granted" || root._roiState === "denied"
                NumberAnimation { from: 0.04; to: 0.28; duration: 700; easing.type: Easing.InOutSine }
                NumberAnimation { from: 0.28; to: 0.04; duration: 700; easing.type: Easing.InOutSine }
            }
        }
    }

    // ── Pilule bas ───────────────────────────────────────────────────────────
    Rectangle {
        anchors.bottom:           parent.bottom
        anchors.bottomMargin:     32
        anchors.horizontalCenter: parent.horizontalCenter
        width:  pillCol.implicitWidth + 64
        height: pillCol.implicitHeight + 28
        radius: 40
        color:  "#cc0f172a"
        border.color: "#4d475569"
        border.width: 1

        Column {
            id: pillCol
            anchors.centerIn: parent
            spacing: 10

            Row {
                anchors.horizontalCenter: parent.horizontalCenter
                spacing: 10

                Canvas {
                    width: 22; height: 22
                    anchors.verticalCenter: parent.verticalCenter
                    onPaint: {
                        var ctx = getContext("2d")
                        ctx.clearRect(0, 0, width, height)
                        ctx.strokeStyle = "#22d3ee"
                        ctx.lineWidth   = 1.8
                        ctx.beginPath(); ctx.arc(11, 11, 9,   0, Math.PI * 2); ctx.stroke()
                        ctx.beginPath(); ctx.arc(8,  9,  1.2, 0, Math.PI * 2); ctx.stroke()
                        ctx.beginPath(); ctx.arc(14, 9,  1.2, 0, Math.PI * 2); ctx.stroke()
                        ctx.beginPath(); ctx.arc(11, 12, 3.5, 0, Math.PI);     ctx.stroke()
                    }
                }

                Text {
                    text:  "PLACEZ VOTRE VISAGE DANS LE CADRE"
                    color: "white"
                    font.pixelSize:     15
                    font.weight:        Font.DemiBold
                    font.letterSpacing: 1
                    anchors.verticalCenter: parent.verticalCenter
                }
            }

            Row {
                anchors.horizontalCenter: parent.horizontalCenter
                spacing: 10

                Rectangle {
                    width: 36; height: 1
                    color: "#4d64748b"
                    anchors.verticalCenter: parent.verticalCenter
                }
                Text {
                    text:  "⊡  ou présentez votre badge"
                    color: "#64748b"
                    font.pixelSize: 12
                    anchors.verticalCenter: parent.verticalCenter
                }
                Rectangle {
                    width: 36; height: 1
                    color: "#4d64748b"
                    anchors.verticalCenter: parent.verticalCenter
                }
            }
        }
    }
}
