import QtQuick 2.10
import ACL 1.0

Rectangle {
    id: root
    anchors.fill: parent
    visible: false
    color: "#cc000000"
    z: 70

    property var controller: null
    property var keyboard: null

    // États : "form" (saisie nom/role) → "live" (capture poses) → "done"
    property string state: "form"
    property string errorMsg: ""

    // Saisie
    property string userName: ""
    property string userRole: "user"

    // Statut backend (rempli par poll)
    property var status: ({})

    // URL de base pour les thumbnails de poses
    property string _baseUrl: controller ? controller.mjpegUrl.replace("/video_feed", "") : ""

    signal closed()

    function open() {
        visible = true
        state = "form"
        errorMsg = ""
        userName = ""
        userRole = "user"
        status = {}
        if (typeof nameInput !== "undefined") nameInput.text = ""
    }
    function close() {
        if (state === "live") controller.cancelEnroll()
        pollTimer.stop()
        visible = false
        if (keyboard) keyboard.close()
        closed()
    }

    Connections {
        target: root.controller
        ignoreUnknownSignals: true
        onEnrollResult: {
            if (op === "start") {
                if (ok) {
                    root.state = "live"
                    pollTimer.start()
                    controller.pollEnrollStatus()
                } else {
                    root.errorMsg = "Démarrage : " + msg
                }
            } else if (op === "finalize") {
                pollTimer.stop()
                if (ok) {
                    root.state = "done"
                    doneText.text = msg.length > 0 ? msg : "Utilisateur enrôlé."
                } else {
                    root.errorMsg = "Finalisation : " + msg
                }
            } else if (op === "cancel") {
                pollTimer.stop()
            }
        }
        onEnrollStatus: {
            root.status = status
            // auto-finalize uniquement si l'utilisateur clique "Valider" — pas ici
        }
    }

    Timer {
        id: pollTimer
        interval: 600
        repeat: true
        onTriggered: if (root.controller) root.controller.pollEnrollStatus()
    }

    MouseArea { anchors.fill: parent; onPressed: {} }   // bloque les clics derrière

    // ── Carte ───────────────────────────────────────────────────────────────
    Rectangle {
        anchors.centerIn: parent
        width:  parent.width  - 30
        height: parent.height - 60
        radius: 20
        color: "#0f172a"
        border.color: "#334155"

        // ---- Header ----
        Rectangle {
            id: hdr
            anchors { top: parent.top; left: parent.left; right: parent.right }
            height: 60
            color: "transparent"

            Text {
                anchors { left: parent.left; leftMargin: 20; verticalCenter: parent.verticalCenter }
                text: root.state === "form" ? "Nouvel utilisateur"
                    : root.state === "live" ? "Enrôlement — " + root.userName
                    : "Terminé"
                color: "white"; font.pixelSize: 16; font.weight: Font.Bold
            }
            Rectangle {
                anchors { right: parent.right; rightMargin: 14; verticalCenter: parent.verticalCenter }
                width: 36; height: 36; radius: 18
                color: "#1e293b"
                Text { anchors.centerIn: parent; text: "✕"; color: "#cbd5e1"; font.pixelSize: 14 }
                MouseArea { anchors.fill: parent; onPressed: root.close() }
            }
            Rectangle {
                anchors { bottom: parent.bottom; left: parent.left; right: parent.right }
                height: 1; color: "#1e293b"
            }
        }

        // ---- Erreur ----
        Rectangle {
            id: err
            anchors { top: hdr.bottom; left: parent.left; right: parent.right; margins: 12 }
            visible: root.errorMsg.length > 0
            height: visible ? errLbl.implicitHeight + 16 : 0
            radius: 8; color: "#7f1d1d33"; border.color: "#7f1d1d"
            Text {
                id: errLbl
                anchors { fill: parent; margins: 8 }
                text: root.errorMsg; color: "#fca5a5"; font.pixelSize: 11
                wrapMode: Text.WordWrap
            }
        }

        // ─────────── État FORM ──────────────────────────────────────────────
        Item {
            visible: root.state === "form"
            anchors {
                top: err.visible ? err.bottom : hdr.bottom
                left: parent.left; right: parent.right; bottom: parent.bottom
                margins: 16
            }

            Column {
                anchors.fill: parent
                spacing: 14

                Text { text: "Nom"; color: "#cbd5e1"; font.pixelSize: 12 }
                KbInput {
                    id: nameInput
                    width: parent.width
                    keyboard: root.keyboard
                    placeholder: "ex: Jean Dupont"
                    onTextChanged: root.userName = text
                }

                Text { text: "Rôle"; color: "#cbd5e1"; font.pixelSize: 12 }
                Row {
                    spacing: 8
                    Repeater {
                        model: ["user", "admin"]
                        Rectangle {
                            width: 100; height: 36; radius: 8
                            color: root.userRole === modelData ? "#2563eb" : "#1e293b"
                            border.color: root.userRole === modelData ? "#3b82f6" : "#334155"
                            Text {
                                anchors.centerIn: parent; text: modelData
                                color: root.userRole === modelData ? "white" : "#94a3b8"
                                font.pixelSize: 12; font.weight: Font.DemiBold
                            }
                            MouseArea { anchors.fill: parent; onPressed: root.userRole = modelData }
                        }
                    }
                }

                Item { width: 1; height: 8 }

                Text {
                    width: parent.width
                    text: "L'enrôlement capture 5 poses (centre / gauche / droite / haut / bas), 5 échantillons par pose."
                    color: "#64748b"; font.pixelSize: 11; wrapMode: Text.WordWrap
                }
            }

            // Bouton démarrer (en bas)
            Rectangle {
                anchors { bottom: parent.bottom; left: parent.left; right: parent.right }
                height: 44; radius: 10
                color: root.userName.length > 0 ? "#2563eb" : "#1e293b"
                opacity: root.userName.length > 0 ? 1 : 0.5
                Text {
                    anchors.centerIn: parent
                    text: "Démarrer l'enrôlement"
                    color: "white"; font.pixelSize: 13; font.weight: Font.Bold
                }
                MouseArea {
                    anchors.fill: parent
                    enabled: root.userName.length > 0
                    onPressed: {
                        root.errorMsg = ""
                        if (root.keyboard) root.keyboard.close()
                        root.controller.startEnroll(root.userName, root.userRole, 5)
                    }
                }
            }
        }

        // ─────────── État LIVE ──────────────────────────────────────────────
        Item {
            visible: root.state === "live"
            anchors {
                top: err.visible ? err.bottom : hdr.bottom
                left: parent.left; right: parent.right; bottom: parent.bottom
                margins: 12
            }

            // MJPEG preview (carré centré)
            Rectangle {
                id: previewBox
                anchors { top: parent.top; left: parent.left; right: parent.right }
                height: 200
                color: "#000"; radius: 12
                clip: true

                MjpegItem {
                    anchors.fill: parent
                    source: root.controller ? root.controller.mjpegUrl : ""
                    active: root.visible && root.state === "live"
                }

                Rectangle {
                    anchors.fill: parent
                    color: "transparent"
                    border.color: "#22d3ee"; border.width: 2
                    radius: 12
                }
            }

            // Message status
            Text {
                id: msgTxt
                anchors { top: previewBox.bottom; left: parent.left; right: parent.right; topMargin: 10 }
                horizontalAlignment: Text.AlignHCenter
                text: root.status.enroll_msg || "Positionnez votre visage…"
                color: "#cbd5e1"; font.pixelSize: 12
                wrapMode: Text.WordWrap
            }

            // Grille thumbnails 5 poses
            Row {
                id: poseGrid
                anchors { top: msgTxt.bottom; left: parent.left; right: parent.right; topMargin: 12 }
                spacing: 4

                Repeater {
                    model: root.status.enroll_poses || []

                    Rectangle {
                        property bool isCurrent: modelData.id === root.status.enroll_current_pose
                        property int  cellW: (poseGrid.width - 4 * poseGrid.spacing) / 5

                        width:  cellW; height: 94; radius: 8
                        clip:   true
                        color:  modelData.done ? "#0f3a26" : (isCurrent ? "#0c2a3a" : "#1e293b")
                        border.width: 1.5
                        border.color: modelData.done ? "#22c55e" : (isCurrent ? "#22d3ee" : "#334155")

                        // Thumbnail (si des échantillons existent)
                        Image {
                            id: thumb
                            anchors { top: parent.top; left: parent.left; right: parent.right }
                            height: 72
                            source: modelData.count > 0
                                    ? (root._baseUrl + "/pose_thumb/" + modelData.id + ".jpg?c=" + modelData.count)
                                    : ""
                            fillMode: Image.PreserveAspectCrop
                            visible: modelData.count > 0 && status === Image.Ready
                            asynchronous: true
                        }

                        // Placeholder quand pas encore de sample
                        Text {
                            anchors { top: parent.top; horizontalCenter: parent.horizontalCenter; topMargin: 18 }
                            visible: modelData.count === 0
                            text:    isCurrent ? "◎" : "◉"
                            color:   isCurrent ? "#22d3ee" : "#475569"
                            font.pixelSize: 22
                        }

                        // Badge compteur (si en cours)
                        Rectangle {
                            anchors { top: parent.top; right: parent.right; margins: 3 }
                            visible: modelData.count > 0 && !modelData.done
                            width:  cntLbl.implicitWidth + 6; height: 14; radius: 4
                            color:  "#cc0f172a"
                            Text {
                                id: cntLbl
                                anchors.centerIn: parent
                                text:  modelData.count + "/" + modelData.target
                                color: "#94a3b8"; font.pixelSize: 8
                            }
                        }

                        // Coche verte (done)
                        Rectangle {
                            anchors { top: parent.top; right: parent.right; margins: 3 }
                            visible: modelData.done
                            width: 16; height: 16; radius: 8
                            color: "#22c55e"
                            Text { anchors.centerIn: parent; text: "✓"; color: "white"; font.pixelSize: 9; font.weight: Font.Bold }
                        }

                        // Label pose
                        Text {
                            anchors { bottom: parent.bottom; bottomMargin: 4; horizontalCenter: parent.horizontalCenter }
                            text:  modelData.label
                            color: modelData.done ? "#22c55e" : (isCurrent ? "#22d3ee" : "#64748b")
                            font.pixelSize: 9; font.weight: Font.DemiBold
                            font.capitalization: Font.AllUppercase
                        }
                    }
                }
            }

            // Boutons bas
            Row {
                anchors { bottom: parent.bottom; left: parent.left; right: parent.right }
                spacing: 8

                Rectangle {
                    width: (parent.width - 8) / 2; height: 44; radius: 10
                    color: "#1e293b"; border.color: "#7f1d1d"
                    Text { anchors.centerIn: parent; text: "Annuler"; color: "#fca5a5"; font.pixelSize: 13 }
                    MouseArea {
                        anchors.fill: parent
                        onPressed: root.close()   // close() s'occupe du cancelEnroll si state==="live"
                    }
                }
                Rectangle {
                    width: (parent.width - 8) / 2; height: 44; radius: 10
                    color: root.status.enroll_complete ? "#16a34a" : "#1e293b"
                    opacity: root.status.enroll_complete ? 1 : 0.5
                    Text {
                        anchors.centerIn: parent
                        text: "Valider"; color: "white"; font.pixelSize: 13; font.weight: Font.Bold
                    }
                    MouseArea {
                        anchors.fill: parent
                        enabled: root.status.enroll_complete === true
                        onPressed: root.controller.finalizeEnroll()
                    }
                }
            }
        }

        // ─────────── État DONE ──────────────────────────────────────────────
        Item {
            visible: root.state === "done"
            anchors { fill: parent; topMargin: 60 }

            Column {
                anchors.centerIn: parent
                spacing: 16
                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: "✓"; color: "#22c55e"; font.pixelSize: 64
                }
                Text {
                    id: doneText
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: "Utilisateur enrôlé."
                    color: "white"; font.pixelSize: 14; font.weight: Font.DemiBold
                }
                Rectangle {
                    width: 160; height: 40; radius: 10
                    color: "#2563eb"
                    anchors.horizontalCenter: parent.horizontalCenter
                    Text { anchors.centerIn: parent; text: "Fermer"; color: "white"; font.pixelSize: 12; font.weight: Font.Bold }
                    MouseArea { anchors.fill: parent; onPressed: root.close() }
                }
            }
        }
    }
}
