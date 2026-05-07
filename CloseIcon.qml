import QtQuick 2.10

// Bouton fermer réutilisable — X dessiné en Canvas (rendu net)
// Usage : CloseIcon { onClicked: ... }
Rectangle {
    id: root
    width: 36; height: 36; radius: 18
    color: closeMA.pressed ? "#7f1d1d" : "#1e293b"
    border.color: closeMA.pressed ? "#ef4444" : "#334155"
    border.width: 1.5

    signal clicked()

    Canvas {
        anchors.centerIn: parent
        width: 14; height: 14
        property bool pressed: closeMA.pressed
        onPressedChanged: requestPaint()
        onPaint: {
            var ctx = getContext("2d")
            ctx.clearRect(0, 0, width, height)
            ctx.strokeStyle = pressed ? "#fca5a5" : "#cbd5e1"
            ctx.lineWidth   = 2.4
            ctx.lineCap     = "round"
            ctx.beginPath()
            ctx.moveTo(2, 2);  ctx.lineTo(12, 12)
            ctx.moveTo(12, 2); ctx.lineTo(2, 12)
            ctx.stroke()
        }
    }

    MouseArea {
        id: closeMA
        anchors.fill: parent
        onClicked: root.clicked()
    }
}
