import QtQuick 2.10

Rectangle {
    id: root
    anchors.fill: parent
    visible: false
    color: "#b3000000"
    z: 45

    signal openNetwork()
    signal openFace()
    signal closed()

    function open()  { visible = true  }
    function close() { visible = false; closed() }

    // Backdrop tap = close (onClicked → release deja livre, safe)
    MouseArea { anchors.fill: parent; onClicked: root.close() }

    // ── Card ─────────────────────────────────────────────────────────────────
    Rectangle {
        anchors.centerIn: parent
        width: 420; height: card.implicitHeight + 48
        radius: 20
        color: "#0f172a"
        border.color: "#334155"

        MouseArea { anchors.fill: parent; onClicked: {} }  // absorb backdrop tap

        Column {
            id: card
            anchors {
                top: parent.top; left: parent.left; right: parent.right
                topMargin: 28; leftMargin: 24; rightMargin: 24
            }
            spacing: 0

            Text {
                text: "Configuration"
                color: "white"; font.pixelSize: 18; font.weight: Font.Bold
            }
            Item { width: 1; height: 4 }
            Text {
                text: "Choisissez la section à configurer"
                color: "#64748b"; font.pixelSize: 12
            }
            Item { width: 1; height: 20 }

            // ── 2-column grid ─────────────────────────────────────────────────
            Row {
                width: parent.width
                spacing: 12

                // Réseau button — AppButton variant secondary avec contenu custom
                AppButton {
                    width: (parent.width - 12) / 2
                    height: 110
                    variant: "secondary"
                    text: ""   // contenu custom via contentItem
                    onClicked: { root.visible = false; root.openNetwork() }

                    contentItem: Column {
                        spacing: 8
                        Canvas {
                            width: 32; height: 32
                            anchors.horizontalCenter: parent.horizontalCenter
                            onPaint: {
                                var ctx = getContext("2d")
                                ctx.clearRect(0,0,32,32)
                                ctx.strokeStyle = "#60a5fa"
                                ctx.lineWidth   = 2.5
                                ctx.lineCap     = "round"
                                ctx.fillStyle = "#60a5fa"
                                ctx.beginPath(); ctx.arc(16,26,2.5,0,Math.PI*2); ctx.fill()
                                ctx.beginPath(); ctx.arc(16,26,6,Math.PI*1.2,Math.PI*1.8,false); ctx.stroke()
                                ctx.beginPath(); ctx.arc(16,26,12,Math.PI*1.2,Math.PI*1.8,false); ctx.stroke()
                                ctx.beginPath(); ctx.arc(16,26,18,Math.PI*1.2,Math.PI*1.8,false); ctx.stroke()
                            }
                        }
                        Text {
                            text: "Réseau"
                            color: "white"; font.pixelSize: 14; font.weight: Font.DemiBold
                            anchors.horizontalCenter: parent.horizontalCenter
                        }
                        Text {
                            text: "Wi-Fi / Ethernet"
                            color: "#64748b"; font.pixelSize: 10
                            anchors.horizontalCenter: parent.horizontalCenter
                        }
                    }
                }

                // Face ID button
                AppButton {
                    width: (parent.width - 12) / 2
                    height: 110
                    variant: "secondary"
                    text: ""
                    onClicked: { root.visible = false; root.openFace() }

                    contentItem: Column {
                        spacing: 8
                        Canvas {
                            width: 32; height: 32
                            anchors.horizontalCenter: parent.horizontalCenter
                            onPaint: {
                                var ctx = getContext("2d")
                                ctx.clearRect(0,0,32,32)
                                ctx.strokeStyle = "#22d3ee"
                                ctx.lineWidth   = 2
                                ctx.lineCap     = "round"
                                var arm = 6
                                ctx.beginPath(); ctx.moveTo(4,4+arm); ctx.lineTo(4,4); ctx.lineTo(4+arm,4); ctx.stroke()
                                ctx.beginPath(); ctx.moveTo(28-arm,4); ctx.lineTo(28,4); ctx.lineTo(28,4+arm); ctx.stroke()
                                ctx.beginPath(); ctx.moveTo(4,28-arm); ctx.lineTo(4,28); ctx.lineTo(4+arm,28); ctx.stroke()
                                ctx.beginPath(); ctx.moveTo(28-arm,28); ctx.lineTo(28,28); ctx.lineTo(28,28-arm); ctx.stroke()
                                ctx.beginPath(); ctx.ellipse(10,9,12,14); ctx.stroke()
                                ctx.fillStyle = "#22d3ee"
                                ctx.beginPath(); ctx.arc(13,15,1.2,0,Math.PI*2); ctx.fill()
                                ctx.beginPath(); ctx.arc(19,15,1.2,0,Math.PI*2); ctx.fill()
                                ctx.beginPath(); ctx.arc(16,18,3,0,Math.PI,false); ctx.stroke()
                            }
                        }
                        Text {
                            text: "Face ID"
                            color: "white"; font.pixelSize: 14; font.weight: Font.DemiBold
                            anchors.horizontalCenter: parent.horizontalCenter
                        }
                        Text {
                            text: "Enrôlement / Utilisateurs"
                            color: "#64748b"; font.pixelSize: 10
                            anchors.horizontalCenter: parent.horizontalCenter
                        }
                    }
                }
            }

            Item { width: 1; height: 12 }

            // Close button
            AppButton {
                width: parent.width
                height: 40
                variant: "secondary"
                text: "Fermer"
                fontSize: 14; bold: false
                onClicked: root.close()
            }

            Item { width: 1; height: 4 }
        }
    }
}
