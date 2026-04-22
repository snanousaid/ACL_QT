import QtQuick 2.10
import QtQuick.Window 2.10
import ACL 1.0

Window {
    id: root
    visible: true
    // eglfs fills the physical screen automatically (landscape 1024×600 on A133).
    // Content is portrait 600×1024 — rotated 90° inside this window.
    width:  1024
    height: 600
    color: "#0d1117"
    title: "ACL Terminal"

    // ── Backend (non-visual — lives outside the rotation container) ──────────
    AppControllerType {
        id: controller
        onAccessEvent: {
            accessCard.granted    = granted
            accessCard.personName = name
            accessCard.source     = source
            accessCard.score      = score
            accessCard.door       = door
            accessCard.timeStr    = time
            accessCard.visible    = true
        }
    }

    property bool adminVisible: false

    // Compteur de double-tap (le MouseArea est dans rotatedContent — voir ci-dessous)
    property int _tapCount: 0
    Timer {
        id: doubleTapTimer
        interval: 5000
        onTriggered: root._tapCount = 0
    }

    // ── Rotation container ───────────────────────────────────────────────────
    // Portrait content (600×1024) rotated -90° (CCW) to fill landscape screen.
    // anchors.centerIn places the geometry center at the window center;
    // after -90° rotation the visual bounding box becomes 1024×600, filling the window.
    Item {
        id: rotatedContent
        anchors.centerIn: parent
        width:  600
        height: 1024
        rotation: 90

        // Détecteur de double-tap — DANS rotatedContent pour partager le même
        // système de coordonnées que les boutons. z:-1 → derrière toute l'UI,
        // ne capte un tap que si aucun bouton ne l'a accepté.
        MouseArea {
            anchors.fill: parent
            z: -1
            onPressed: {
                root._tapCount++
                if (root._tapCount >= 2) {
                    root._tapCount = 0
                    doubleTapTimer.stop()
                    settingsBtn.visible = true
                    settingsHideTimer.restart()
                } else {
                    doubleTapTimer.restart()
                }
            }
        }

        // ── Header ───────────────────────────────────────────────────────────
        Rectangle {
            id: header
            anchors { top: parent.top; left: parent.left; right: parent.right }
            height: 60
            color: "#0d1421"
            z: 10

            Rectangle {
                anchors.bottom: parent.bottom
                width: parent.width; height: 1
                color: "#1e293b"
            }

            Row {
                anchors { left: parent.left; leftMargin: 24; verticalCenter: parent.verticalCenter }
                spacing: 10

                Rectangle {
                    width: 12; height: 12; radius: 6
                    color: "#3b82f6"
                    anchors.verticalCenter: parent.verticalCenter

                    SequentialAnimation on opacity {
                        loops: Animation.Infinite
                        NumberAnimation { from: 1; to: 0.3; duration: 900 }
                        NumberAnimation { from: 0.3; to: 1; duration: 900 }
                    }
                }

                Text {
                    text: "<b><font color='#3b82f6'>ACL</font></b><font color='white' style='font-weight:300'> Terminal</font>"
                    font.pixelSize: 20
                    font.letterSpacing: 2
                    textFormat: Text.RichText
                    anchors.verticalCenter: parent.verticalCenter
                }
            }

            Text {
                anchors { right: parent.right; rightMargin: 24; verticalCenter: parent.verticalCenter }
                text: "Borne d'accès — Entrée Principale"
                color: "#64748b"
                font.pixelSize: 11
                font.letterSpacing: 2
                font.capitalization: Font.AllUppercase
            }
        }

        // ── Main area ─────────────────────────────────────────────────────────
        IdleScreen {
            anchors {
                top: header.bottom
                left: parent.left; right: parent.right
                bottom: statusBar.top
            }
            mjpegUrl:     controller.mjpegUrl
            streamPaused: root.adminVisible
        }

        // ── Access card overlay ───────────────────────────────────────────────
        AccessCard {
            id: accessCard
            anchors {
                top: header.bottom
                left: parent.left; right: parent.right
                bottom: statusBar.top
            }
            visible: false
            z: 20
            onDismissed: visible = false
        }

        Timer {
            id: settingsHideTimer
            interval: 6000
            onTriggered: settingsBtn.visible = false
        }

        Rectangle {
            id: settingsBtn
            visible: false
            z: 30
            width: 44; height: 44; radius: 22
            color: "#cc1e293b"
            border.color: "#4d64748b"
            anchors { verticalCenter: parent.verticalCenter; right: parent.right; rightMargin: 16 }

            Text {
                anchors.centerIn: parent
                text: "⚙"
                color: "#94a3b8"
                font.pixelSize: 22
            }

            MouseArea {
                anchors.fill: parent
                onPressed: {
                    settingsBtn.visible = false
                    passwordModal.visible = true
                    root.adminVisible = true
                    controller.pauseRecognition()
                }
            }
        }

        // ── Password modal ────────────────────────────────────────────────────
        Rectangle {
            id: passwordModal
            visible: false
            anchors.fill: parent
            color: "#b3000000"
            z: 40

            Rectangle {
                anchors.centerIn: parent
                width: 320; height: pwCol.implicitHeight + 48
                radius: 20
                color: "#0f172a"
                border.color: "#334155"

                Column {
                    id: pwCol
                    anchors { top: parent.top; left: parent.left; right: parent.right
                              topMargin: 28; leftMargin: 24; rightMargin: 24 }
                    spacing: 0

                    Row {
                        spacing: 12
                        Rectangle {
                            width: 36; height: 36; radius: 8
                            color: "#331f2937"
                            Text { anchors.centerIn: parent; text: "🔒"; font.pixelSize: 18 }
                        }
                        Column {
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: 2
                            Text { text: "Accès administrateur"; color: "white"; font.pixelSize: 14; font.weight: Font.Bold }
                            Text { text: "Entrez le mot de passe admin"; color: "#64748b"; font.pixelSize: 11 }
                        }
                    }

                    Item { width: 1; height: 20 }

                    KbInput {
                        id: pwInput
                        width: parent.width
                        keyboard:   keyboard
                        isPassword: true
                        placeholder: "••••••••••"
                    }

                    Item { width: 1; height: 8 }

                    Text {
                        id: pwError
                        visible: false
                        text: "Mot de passe incorrect."
                        color: "#f87171"
                        font.pixelSize: 12
                    }

                    Item { width: 1; height: 16 }

                    Row {
                        width: parent.width
                        spacing: 8

                        Rectangle {
                            width: (parent.width - 8) / 2; height: 40
                            radius: 10; color: "#1e293b"
                            Text { anchors.centerIn: parent; text: "Annuler"; color: "#94a3b8"; font.pixelSize: 13 }
                            MouseArea {
                                anchors.fill: parent
                                onPressed: {
                                    passwordModal.visible = false
                                    pwInput.text = ""; keyboard.close()
                                    pwError.visible = false
                                    root.adminVisible = false
                                    controller.resumeRecognition()
                                }
                            }
                        }

                        Rectangle {
                            width: (parent.width - 8) / 2; height: 40
                            radius: 10; color: "#2563eb"
                            Text { anchors.centerIn: parent; text: "Valider"; color: "white"; font.pixelSize: 13; font.weight: Font.Bold }
                            MouseArea {
                                anchors.fill: parent
                                onPressed: passwordModal.checkPassword()
                            }
                        }
                    }

                    Item { width: 1; height: 4 }
                }
            }

            function checkPassword() {
                if (pwInput.text === "2899100*-+") {
                    keyboard.close()
                    passwordModal.visible = false
                    pwInput.text = ""
                    pwError.visible = false
                    adminMenu.open()   // → admin menu, recognition reste pausée
                } else {
                    pwError.visible = true
                }
            }

            MouseArea {
                anchors.fill: parent
                z: -1
                onPressed: {
                    passwordModal.visible = false
                    pwInput.text = ""; keyboard.close()
                    pwError.visible = false
                    root.adminVisible = false
                    controller.resumeRecognition()
                }
            }
        }

        // ── Status bar ────────────────────────────────────────────────────────
        StatusBar {
            id: statusBar
            anchors { bottom: parent.bottom; left: parent.left; right: parent.right }
            badgeConnected: controller.badgeConnected
            faceConnected:  controller.faceConnected
        }

        // ── Admin menu ────────────────────────────────────────────────────────
        AdminMenu {
            id: adminMenu
            onClosed:      { root.adminVisible = false; controller.resumeRecognition() }
            onOpenNetwork: { networkSettings.open() }
            onOpenFace:    { faceSettings.open() }
        }

        // ── Network config modal ──────────────────────────────────────────────
        NetworkConfigModal {
            id: networkSettings
            controller: controller
            keyboard: keyboard
            onClosed: adminMenu.open()
        }

        // ── Face settings modal ───────────────────────────────────────────────
        FaceSettingsModal {
            id: faceSettings
            controller: controller
            // Re-ouvre l'admin menu en sortant (admin reste pausée)
            onClosed: adminMenu.open()
            onOpenEnroll: { faceSettings.visible = false; enrollment.open() }
        }

        // ── Enrolment modal (sous-modal de FaceSettings) ─────────────────────
        EnrollmentModal {
            id: enrollment
            controller: controller
            keyboard: keyboard
            onClosed: { faceSettings.open() }   // retour à la liste
        }

        // ── Virtual keyboard (shared, z:60) ───────────────────────────────────
        VirtualKeyboard { id: keyboard }
    }
}
