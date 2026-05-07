import QtQuick 2.10
import QtQuick.Window 2.10
import QtQuick.Controls 2.5

// ─────────────────────────────────────────────────────────────────────────────
// VALIDATION : choisir entre Plan A (Button) et Plan B (MouseArea + onClicked)
//
// Pour chaque test :
//   - Tap plusieurs fois (5+ taps)
//   - Pour les tests "+ HIDE" : attendre 1.5s que le bouton revienne, retap
//   - Vérifier dans logs : aucun "TouchPointPressed without previous release"
//
// Decision :
//   * Tous les 4 tests OK     → Plan A ou Plan B au choix
//   * Plan A KO, Plan B OK    → Plan B (MouseArea.onClicked)
//   * Inverse                 → Plan A (Button)
//   * Les 2 KO sur HIDE       → garder code actuel (Qt.callLater)
// ─────────────────────────────────────────────────────────────────────────────

Window {
    id: root
    visible: true
    width: 1024
    height: 600
    color: "#0d1117"
    title: "Touch Test — Plan A vs Plan B"

    Column {
        anchors.centerIn: parent
        spacing: 16

        Text {
            text: "Validation : Plan A (Button) vs Plan B (MouseArea + onClicked)"
            color: "#cbd5e1"; font.pixelSize: 16; font.weight: Font.Bold
            anchors.horizontalCenter: parent.horizontalCenter
        }

        Text {
            text: "Tap chaque bouton 5+ fois — observe les logs pour les warnings TouchPointPressed"
            color: "#94a3b8"; font.pixelSize: 11
            anchors.horizontalCenter: parent.horizontalCenter
        }

        Item { width: 1; height: 12 }

        // ═════════════════════ PLAN A — Button + onClicked ═════════════════
        Text {
            text: "── PLAN A : QtQuick.Controls Button ──"
            color: "#60a5fa"; font.pixelSize: 13; font.weight: Font.Bold
            anchors.horizontalCenter: parent.horizontalCenter
        }

        // Test A1 : Button compteur (sans hide)
        Button {
            id: btnA1
            text: "A1 — Button onClicked compteur : " + n
            width: 700; height: 60
            property int n: 0
            onClicked: {
                n++
                console.log("[A1] Button clicked", n)
            }
        }

        // Test A2 : Button + HIDE (mimique close modal)
        Item {
            width: 700; height: 60
            Button {
                id: btnA2
                anchors.fill: parent
                text: "A2 — Button onClicked + HIDE (revient en 1.5s)"
                onClicked: {
                    console.log("[A2] Button clicked, hiding")
                    btnA2.visible = false
                }
            }
            Timer {
                interval: 1500
                running: !btnA2.visible
                onTriggered: btnA2.visible = true
            }
        }

        Item { width: 1; height: 12 }

        // ═════════════════════ PLAN B — MouseArea + onClicked ══════════════
        Text {
            text: "── PLAN B : Rectangle + MouseArea + onClicked ──"
            color: "#22c55e"; font.pixelSize: 13; font.weight: Font.Bold
            anchors.horizontalCenter: parent.horizontalCenter
        }

        // Test B1 : MouseArea compteur (sans hide)
        Rectangle {
            width: 700; height: 60; radius: 10
            color: maB1.pressed ? "#0e7490" : "#0891b2"
            property int n: 0
            Text {
                anchors.centerIn: parent
                text: "B1 — MouseArea.onClicked compteur : " + parent.n
                color: "white"; font.pixelSize: 14; font.weight: Font.Bold
            }
            MouseArea {
                id: maB1
                anchors.fill: parent
                onClicked: {
                    parent.n++
                    console.log("[B1] MouseArea clicked", parent.n)
                }
            }
        }

        // Test B2 : MouseArea + HIDE (mimique close modal)
        Item {
            width: 700; height: 60
            Rectangle {
                id: btnB2
                anchors.fill: parent; radius: 10
                color: maB2.pressed ? "#7c2d12" : "#ea580c"
                Text {
                    anchors.centerIn: parent
                    text: "B2 — MouseArea.onClicked + HIDE (revient en 1.5s)"
                    color: "white"; font.pixelSize: 14; font.weight: Font.Bold
                }
                MouseArea {
                    id: maB2
                    anchors.fill: parent
                    onClicked: {
                        console.log("[B2] MouseArea clicked, hiding")
                        btnB2.visible = false
                    }
                }
            }
            Timer {
                interval: 1500
                running: !btnB2.visible
                onTriggered: btnB2.visible = true
            }
        }
    }
}
