import QtQuick 2.10

// Bouton fermer reutilisable - X dessine en Canvas.
// Base sur AppButton (Button QtQuick.Controls) au lieu de MouseArea pour
// fiabilite tactile A133 evdev (cf bug settingsBtn fix).
// Usage : CloseIcon { onClicked: ... }
AppButton {
    id: root
    width: 36; height: 36
    text: ""

    background: Rectangle {
        radius: 18
        color: root.pressed ? "#7f1d1d" : "#1e293b"
        border.color: root.pressed ? "#ef4444" : "#334155"
        border.width: 1.5
        Behavior on color { ColorAnimation { duration: 100 } }
    }

    contentItem: Canvas {
        width: 14; height: 14
        property bool isPressed: root.pressed
        onIsPressedChanged: requestPaint()
        onPaint: {
            var ctx = getContext("2d")
            ctx.clearRect(0, 0, width, height)
            ctx.strokeStyle = isPressed ? "#fca5a5" : "#cbd5e1"
            ctx.lineWidth   = 2.4
            ctx.lineCap     = "round"
            ctx.beginPath()
            ctx.moveTo(2, 2);  ctx.lineTo(12, 12)
            ctx.moveTo(12, 2); ctx.lineTo(2, 12)
            ctx.stroke()
        }
    }
}
