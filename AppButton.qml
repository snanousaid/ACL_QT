import QtQuick 2.10
import QtQuick.Controls 2.5

// ─────────────────────────────────────────────────────────────────────────────
// AppButton — wrapper QtQuick.Controls Button avec notre theme dark.
//
// Usage :
//   AppButton {
//       variant: "primary"  // primary | secondary | danger | success | ghost
//       text:    "Valider"
//       onClicked: { ... }
//   }
//
// Pourquoi : sur A133 evdev, MouseArea.onPressed + visible=false perd le
// release tactile. Button.onClicked fire APRES le release → safe.
// ─────────────────────────────────────────────────────────────────────────────

Button {
    id: root

    property string variant:    "primary"
    property int    fontSize:   13
    property bool   bold:       true
    property color  customBg:   "transparent"   // si non transparent, override variant
    property color  customFg:   "transparent"
    property color  customBorder: "transparent"

    // Schemes par variant
    readonly property var _schemes: ({
        "primary":   { bg: "#2563eb", bgPressed: "#1d4ed8", fg: "white",   border: "#3b82f6", borderW: 0 },
        "secondary": { bg: "#1e293b", bgPressed: "#0f172a", fg: "#cbd5e1", border: "#475569", borderW: 1 },
        "danger":    { bg: "#dc2626", bgPressed: "#7f1d1d", fg: "white",   border: "#7f1d1d", borderW: 0 },
        "success":   { bg: "#16a34a", bgPressed: "#14532d", fg: "white",   border: "#22c55e", borderW: 0 },
        "ghost":     { bg: "transparent", bgPressed: "#1e293b", fg: "#94a3b8", border: "#334155", borderW: 1 }
    })

    readonly property var _s: _schemes[variant] || _schemes.primary

    // Style override par defaut Qt
    background: Rectangle {
        radius: 10
        color: customBg.a > 0 ? customBg
                              : (root.pressed ? root._s.bgPressed : root._s.bg)
        border.color: customBorder.a > 0 ? customBorder : root._s.border
        border.width: root._s.borderW
        opacity: root.enabled ? 1.0 : 0.5
        Behavior on color { ColorAnimation { duration: 120 } }
    }

    contentItem: Text {
        text: root.text
        color: customFg.a > 0 ? customFg : root._s.fg
        font.pixelSize: root.fontSize
        font.weight: root.bold ? Font.Bold : Font.DemiBold
        horizontalAlignment: Text.AlignHCenter
        verticalAlignment:   Text.AlignVCenter
        elide: Text.ElideRight
    }

    // Pas de focus ring (UI tactile, garde clean)
    focusPolicy: Qt.NoFocus

    // Hauteur par defaut alignee sur nos modals
    implicitHeight: 40
}
