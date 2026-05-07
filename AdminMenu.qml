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
    function close() {
        // Defer (A133 evdev : cacher MouseArea dans onPressed perd le release).
        Qt.callLater(function() { visible = false; closed() })
    }

    // Backdrop
    MouseArea { anchors.fill: parent; onPressed: root.close() }

    // ── Card ─────────────────────────────────────────────────────────────────
    Rectangle {
        anchors.centerIn: parent
        width: 420; height: card.implicitHeight + 48
        radius: 20
        color: "#0f172a"
        border.color: "#334155"

        MouseArea { anchors.fill: parent; onPressed: {} }  // absorb backdrop tap

        Column {
            id: card
            anchors {
                top: parent.top; left: parent.left; right: parent.right
                topMargin: 28; leftMargin: 24; rightMargin: 24
            }
            spacing: 0

            // Title
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

                // Réseau button
                Rectangle {
                    width: (parent.width - 12) / 2
                    height: btnNetCol.implicitHeight + 40
                    radius: 12; color: "#1e293b"; border.color: "#334155"

                    Column {
                        id: btnNetCol
                        anchors.centerIn: parent
                        spacing: 8

                        // Wi-Fi icon (Canvas arcs)
                        Canvas {
                            width: 32; height: 32
                            anchors.horizontalCenter: parent.horizontalCenter
                            onPaint: {
                                var ctx = getContext("2d")
                                ctx.clearRect(0,0,32,32)
                                ctx.strokeStyle = "#60a5fa"
                                ctx.lineWidth   = 2.5
                                ctx.lineCap     = "round"
                                // dot
                                ctx.fillStyle = "#60a5fa"
                                ctx.beginPath(); ctx.arc(16,26,2.5,0,Math.PI*2); ctx.fill()
                                // arc 1
                                ctx.beginPath(); ctx.arc(16,26,6,Math.PI*1.2,Math.PI*1.8,false); ctx.stroke()
                                // arc 2
                                ctx.beginPath(); ctx.arc(16,26,12,Math.PI*1.2,Math.PI*1.8,false); ctx.stroke()
                                // arc 3
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

                    MouseArea {
                        anchors.fill: parent
                        onPressed: Qt.callLater(function() {
                            root.visible = false; root.openNetwork()
                        })
                    }
                }

                // Face ID button
                Rectangle {
                    width: (parent.width - 12) / 2
                    height: btnFaceCol.implicitHeight + 40
                    radius: 12; color: "#1e293b"; border.color: "#334155"

                    Column {
                        id: btnFaceCol
                        anchors.centerIn: parent
                        spacing: 8

                        // Face-scan icon (Canvas)
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
                                // corner brackets
                                ctx.beginPath(); ctx.moveTo(4,4+arm); ctx.lineTo(4,4); ctx.lineTo(4+arm,4); ctx.stroke()
                                ctx.beginPath(); ctx.moveTo(28-arm,4); ctx.lineTo(28,4); ctx.lineTo(28,4+arm); ctx.stroke()
                                ctx.beginPath(); ctx.moveTo(4,28-arm); ctx.lineTo(4,28); ctx.lineTo(4+arm,28); ctx.stroke()
                                ctx.beginPath(); ctx.moveTo(28-arm,28); ctx.lineTo(28,28); ctx.lineTo(28,28-arm); ctx.stroke()
                                // face oval
                                ctx.beginPath(); ctx.ellipse(10,9,12,14); ctx.stroke()
                                // eyes
                                ctx.fillStyle = "#22d3ee"
                                ctx.beginPath(); ctx.arc(13,15,1.2,0,Math.PI*2); ctx.fill()
                                ctx.beginPath(); ctx.arc(19,15,1.2,0,Math.PI*2); ctx.fill()
                                // mouth arc
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

                    MouseArea {
                        anchors.fill: parent
                        onPressed: Qt.callLater(function() {
                            root.visible = false; root.openFace()
                        })
                    }
                }
            }

            Item { width: 1; height: 12 }

            // Close button
            Rectangle {
                width: parent.width; height: 40
                radius: 10; color: "#1e293b"
                Text { anchors.centerIn: parent; text: "Fermer"; color: "#cbd5e1"; font.pixelSize: 14; font.weight: Font.Medium }
                MouseArea { anchors.fill: parent; onPressed: root.close() }
            }

            Item { width: 1; height: 4 }
        }
    }
}
