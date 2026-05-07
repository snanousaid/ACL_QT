import QtQuick 2.10
import QtQuick.Window 2.10
import QtQuick.Controls 2.5

// ─────────────────────────────────────────────────────────────────────────────
// Test isolé : 4 scénarios de boutons pour identifier la cause des warnings
// "TouchPointPressed without previous release event" sur A133.
//
// Pour le lancer temporairement sur la board :
//   qmlscene /opt/ACL_qt/qml-test/TouchTest.qml
// (ou modifier engine.load(QUrl("qrc:/TouchTest.qml")) dans main.cpp)
//
// Observer dans les logs :
//   - Test 1 (no hide)         : pas de warning attendu
//   - Test 2 (hide in onPressed): warning attendu sur le 2e tap
//   - Test 3 (Qt.callLater)    : pas de warning attendu (fix proposé)
//   - Test 4 (compteurs P/R)   : si pressed != released, releases sont perdus
// ─────────────────────────────────────────────────────────────────────────────

Window {
    id: root
    visible: true
    width: 1024
    height: 600
    color: "#0d1117"
    title: "Touch Test A133"

    // PAS DE ROTATION pour isoler la cause

    Column {
        anchors.centerIn: parent
        spacing: 16

        Text {
            text: "Touch Test — vérifier logs Qt"
            color: "#cbd5e1"; font.pixelSize: 16
            anchors.horizontalCenter: parent.horizontalCenter
        }

        // ── Test 1 : simple compteur (pas de modif visibilité) ──────────────
        Rectangle {
            width: 700; height: 60; radius: 10
            color: ma1.pressed ? "#1e3a8a" : "#2563eb"
            property int n: 0
            Text {
                anchors.centerIn: parent
                text: "Test 1 — taps : " + parent.n + "  (pas de modif visibilité)"
                color: "white"; font.pixelSize: 14; font.weight: Font.Bold
            }
            MouseArea {
                id: ma1
                anchors.fill: parent
                onPressed: parent.n++
            }
        }

        // ── Test 2 : hide IMMÉDIAT dans onPressed (suspect du bug) ──────────
        Item {
            width: 700; height: 60
            Rectangle {
                id: btn2
                anchors.fill: parent; radius: 10
                color: ma2.pressed ? "#7f1d1d" : "#dc2626"
                Text {
                    anchors.centerIn: parent
                    text: "Test 2 — HIDE IN onPressed (suspect du warning)"
                    color: "white"; font.pixelSize: 14; font.weight: Font.Bold
                }
                MouseArea {
                    id: ma2
                    anchors.fill: parent
                    onPressed: btn2.visible = false   // ← hide IMMÉDIAT
                }
            }
            Timer {
                interval: 1500
                running: !btn2.visible
                onTriggered: btn2.visible = true
            }
        }

        // ── Test 3 : hide via Qt.callLater (fix proposé) ────────────────────
        Item {
            width: 700; height: 60
            Rectangle {
                id: btn3
                anchors.fill: parent; radius: 10
                color: ma3.pressed ? "#14532d" : "#16a34a"
                Text {
                    anchors.centerIn: parent
                    text: "Test 3 — HIDE via Qt.callLater (fix)"
                    color: "white"; font.pixelSize: 14; font.weight: Font.Bold
                }
                MouseArea {
                    id: ma3
                    anchors.fill: parent
                    onPressed: Qt.callLater(function() { btn3.visible = false })
                }
            }
            Timer {
                interval: 1500
                running: !btn3.visible
                onTriggered: btn3.visible = true
            }
        }

        // ── Test 4 : compteurs Press / Release pour détecter événements perdus
        Rectangle {
            width: 700; height: 80; radius: 10
            color: "#1e293b"; border.color: "#475569"
            property int p: 0
            property int r: 0
            Column {
                anchors.centerIn: parent
                spacing: 4
                Text {
                    text: "Test 4 — Press: " + parent.parent.p + "   Release: " + parent.parent.r
                    color: "#cbd5e1"; font.pixelSize: 14; font.weight: Font.Bold
                }
                Text {
                    text: "Si Press > Release : le driver A133 perd des releases."
                    color: "#94a3b8"; font.pixelSize: 11
                }
            }
            MouseArea {
                anchors.fill: parent
                onPressed:  parent.p++
                onReleased: parent.r++
            }
        }

        // ── Test 5 : le même Test 1 mais avec rotation 90° (isole la rotation)
        Item {
            width: 700; height: 80
            Rectangle {
                id: rotItem
                anchors.centerIn: parent
                width: 700; height: 60
                rotation: 90  // rotation 90° → bbox 60×700
                radius: 10
                color: ma5.pressed ? "#581c87" : "#9333ea"
                property int n: 0
                Text {
                    anchors.centerIn: parent
                    text: "Test 5 — rotation 90° taps: " + parent.n
                    color: "white"; font.pixelSize: 14; font.weight: Font.Bold
                }
                MouseArea {
                    id: ma5
                    anchors.fill: parent
                    onPressed: parent.n++
                }
            }
        }

        // ── Test 6 : onClicked simple (sans hide, compteur) ────────────────
        // Doit fire UNE fois par tap (Press + Release dans la zone).
        Rectangle {
            width: 700; height: 60; radius: 10
            color: ma6.pressed ? "#0e7490" : "#0891b2"
            property int n: 0
            Text {
                anchors.centerIn: parent
                text: "Test 6 — onClicked compteur : " + parent.n
                color: "white"; font.pixelSize: 14; font.weight: Font.Bold
            }
            MouseArea {
                id: ma6
                anchors.fill: parent
                onClicked: parent.n++
            }
        }

        // ── Test 7 : onClicked + HIDE (mimique fermeture modal) ────────────
        // Le release est livre AVANT que onClicked fire → le hide est sain.
        // Si pas de warning ici → on peut migrer toute l'app vers onClicked.
        Item {
            width: 700; height: 60
            Rectangle {
                id: btn7
                anchors.fill: parent; radius: 10
                color: ma7.pressed ? "#7c2d12" : "#ea580c"
                Text {
                    anchors.centerIn: parent
                    text: "Test 7 — onClicked + HIDE (cible migration)"
                    color: "white"; font.pixelSize: 14; font.weight: Font.Bold
                }
                MouseArea {
                    id: ma7
                    anchors.fill: parent
                    onClicked: btn7.visible = false   // hide DANS onClicked
                }
            }
            Timer {
                interval: 1500
                running: !btn7.visible
                onTriggered: btn7.visible = true
            }
        }

        // ── Test 8 : QtQuick.Controls Button + onClicked (exemple user) ────
        // Composant Button standard Qt (avec gestion auto press/release/click).
        // C'est le pattern propose pour la migration.
        Button {
            id: testButton
            text: "Test 8 — Button onClicked : " + n
            width: 700; height: 60
            property int n: 0
            onClicked: {
                n++
                console.log("[Test 8] Button clicked!", n)
            }
        }

        // ── Test 9 : Button + HIDE dans onClicked ──────────────────────────
        Item {
            width: 700; height: 60
            Button {
                id: btn9
                anchors.fill: parent
                text: "Test 9 — Button onClicked + HIDE"
                onClicked: btn9.visible = false
            }
            Timer {
                interval: 1500
                running: !btn9.visible
                onTriggered: btn9.visible = true
            }
        }
    }
}
