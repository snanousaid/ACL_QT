import QtQuick 2.10

// Carte d'information avec icône + label + valeur + badge optionnel à droite.
// Usage : InfoCard { iconType: "wifi"; label: "wlan0"; value: "192.168.10.132"
//                    valueColor: "#22c55e"; valueMono: true; badge: "IPv4" }
Rectangle {
    id: root
    height: subValue.length > 0 ? 64 : 58
    Behavior on height { NumberAnimation { duration: 120 } }
    radius: 12
    color: "#1e293b"
    border.color: "#334155"
    border.width: 1

    property string iconType:   ""        // "monitor" | "wifi" | "ethernet" | "mac"
    property string iconColor:  "#60a5fa"
    property string label:      ""
    property string value:      ""
    property color  valueColor: "white"
    property bool   valueMono:  false
    property string subValue:   ""        // sous-ligne optionnelle (ex: mode "DHCP (auto)")
    property color  subValueColor: "#94a3b8"
    property string badge:      ""        // ex: "IPv4", "IPv6", ""
    property string badgeColor: "#1e293b"

    Row {
        anchors { left: parent.left; leftMargin: 14; verticalCenter: parent.verticalCenter }
        spacing: 12

        // Icône Canvas selon iconType
        Rectangle {
            width: 32; height: 32; radius: 8
            color: Qt.rgba(0, 0, 0, 0)
            anchors.verticalCenter: parent.verticalCenter

            Canvas {
                anchors.fill: parent
                onPaint: {
                    var ctx = getContext("2d")
                    ctx.clearRect(0, 0, width, height)
                    ctx.strokeStyle = root.iconColor
                    ctx.fillStyle   = root.iconColor
                    ctx.lineWidth   = 1.6
                    ctx.lineCap     = "round"
                    ctx.lineJoin    = "round"

                    if (root.iconType === "monitor") {
                        // Écran : rectangle + pied
                        ctx.strokeRect(width*0.20, height*0.25, width*0.60, height*0.40)
                        ctx.beginPath()
                        ctx.moveTo(width*0.40, height*0.65)
                        ctx.lineTo(width*0.40, height*0.78)
                        ctx.lineTo(width*0.60, height*0.78)
                        ctx.lineTo(width*0.60, height*0.65)
                        ctx.stroke()
                        ctx.beginPath()
                        ctx.moveTo(width*0.32, height*0.78)
                        ctx.lineTo(width*0.68, height*0.78)
                        ctx.stroke()
                    } else if (root.iconType === "wifi") {
                        // 3 arcs WiFi
                        var wcx = width / 2, wcy = height * 0.78
                        ctx.lineWidth = 2
                        ctx.beginPath(); ctx.arc(wcx, wcy, width*0.42, Math.PI*1.20, Math.PI*1.80); ctx.stroke()
                        ctx.beginPath(); ctx.arc(wcx, wcy, width*0.28, Math.PI*1.20, Math.PI*1.80); ctx.stroke()
                        ctx.beginPath(); ctx.arc(wcx, wcy, 2, 0, Math.PI*2); ctx.fill()
                    } else if (root.iconType === "ethernet") {
                        // Port RJ45
                        ctx.beginPath()
                        ctx.moveTo(width*0.25, height*0.30)
                        ctx.lineTo(width*0.75, height*0.30)
                        ctx.lineTo(width*0.75, height*0.55)
                        ctx.lineTo(width*0.65, height*0.72)
                        ctx.lineTo(width*0.35, height*0.72)
                        ctx.lineTo(width*0.25, height*0.55)
                        ctx.closePath()
                        ctx.stroke()
                        for (var i = 0; i < 4; i++) {
                            var px = width * (0.36 + i * 0.10)
                            ctx.fillRect(px, height*0.40, 1.4, height*0.20)
                        }
                    } else if (root.iconType === "mac") {
                        // Carte / chip
                        ctx.strokeRect(width*0.22, height*0.30, width*0.56, height*0.40)
                        ctx.beginPath()
                        ctx.moveTo(width*0.22, height*0.42); ctx.lineTo(width*0.78, height*0.42)
                        ctx.stroke()
                        ctx.fillRect(width*0.30, height*0.50, width*0.12, 2)
                        ctx.fillRect(width*0.46, height*0.50, width*0.12, 2)
                        ctx.fillRect(width*0.62, height*0.50, width*0.10, 2)
                        ctx.fillRect(width*0.30, height*0.58, width*0.20, 2)
                        ctx.fillRect(width*0.54, height*0.58, width*0.20, 2)
                    }
                }
            }
        }

        Column {
            anchors.verticalCenter: parent.verticalCenter
            spacing: 2
            Text {
                text: root.label
                color: "#64748b"; font.pixelSize: 10; font.letterSpacing: 1
            }
            Text {
                text: root.value
                color: root.valueColor
                font.pixelSize: 14
                font.weight: Font.DemiBold
                font.family: root.valueMono ? "monospace" : "Sans"
            }
            Text {
                visible: root.subValue.length > 0
                text: root.subValue
                color: root.subValueColor
                font.pixelSize: 10
                font.weight: Font.DemiBold
            }
        }
    }

    // Badge à droite (IPv4, IPv6, etc.)
    Rectangle {
        visible: root.badge.length > 0
        anchors { right: parent.right; rightMargin: 12; verticalCenter: parent.verticalCenter }
        width: badgeText.implicitWidth + 14; height: 22; radius: 6
        color: root.badgeColor; border.color: "#475569"; border.width: 1
        Text {
            id: badgeText
            anchors.centerIn: parent
            text: root.badge
            color: "#cbd5e1"; font.pixelSize: 10; font.weight: Font.DemiBold
        }
    }
}
