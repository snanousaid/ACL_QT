import QtQuick 2.10

// Spinner rotatif (Canvas + RotationAnimator) — réutilisable.
// Usage : Spinner { size: 18; color: "#cbd5e1" }
Item {
    id: root
    property int    size:  20
    property color  color: "#cbd5e1"

    width:  size
    height: size

    Canvas {
        id: spinnerCanvas
        anchors.fill: parent
        onPaint: {
            var ctx = getContext("2d")
            ctx.clearRect(0, 0, width, height)
            ctx.lineWidth   = Math.max(1.5, width / 10)
            ctx.lineCap     = "round"
            ctx.strokeStyle = root.color
            // Arc de 270° (laisse une ouverture pour donner l'impression de rotation)
            ctx.beginPath()
            ctx.arc(width / 2, height / 2,
                    width / 2 - ctx.lineWidth,
                    -Math.PI / 2,
                    -Math.PI / 2 + Math.PI * 1.5)
            ctx.stroke()
        }
    }

    RotationAnimator on rotation {
        running: root.visible
        from:    0
        to:      360
        duration: 900
        loops:    Animation.Infinite
    }
}
