import QtQuick 2.10
import QtQuick.Window 2.10
import QtQuick.VirtualKeyboard 2.3
import ACL 1.0
// controller est injecté comme context property depuis main.cpp

Window {
    id: root
    visible: true
    // eglfs fills the physical screen automatically (landscape 1024×600 on A133).
    // Content is portrait 600×1024 — rotated 90° inside this window.
    width:  1024
    height: 600
    color: "#0d1117"
    title: "ACL Terminal"

    // ── Connexion accessEvent (controller injecté depuis main.cpp) ───────────
    Connections {
        target: controller
        onAccessEvent: {
            accessCard.granted      = granted
            accessCard.personName   = name
            accessCard.source       = source
            accessCard.score        = score
            accessCard.door         = door
            accessCard.timeStr      = time
            accessCard.userId       = userId
            accessCard.visible      = true
        }
    }

    // Alias de la context property "controller" pour éviter les boucles de binding
    // dans les modals qui ont aussi une propriété nommée "controller".
    property var _ctrl: controller

    property bool adminVisible: false

    // ── Pause du flux vidéo UI (CameraWorker) ────────────────────────────────
    // Quand un modal admin est ouvert MAIS pas l'enrôlement : le stream est
    // inutile (UI cachée) → on coupe cvtColor + emit côté C++ pour économiser
    // ~30 % CPU. L'enrôlement DOIT garder la caméra active (pose detection).
    property bool streamShouldPause: (passwordModal.visible || root.adminVisible)
                                  && !enrollment.visible
    onStreamShouldPauseChanged: controller.setStreamPaused(streamShouldPause)

    // Compteur de double-tap
    property int  _tapCount:  0
    property real _lastTapMs: 0   // déduplication touch natif + synthèse mouse

    function _handleTap() {
        // Ignorer les taps quand un modal admin est ouvert (sinon le double-tap
        // detector continue de compter sur des taps qui sont en réalité des
        // interactions modal → bouton settings réapparaît / autre comportement
        // imprévu).
        if (root.adminVisible) return
        if (passwordModal.visible) return

        var now = Date.now()
        if (now - root._lastTapMs < 150) return   // même tap reçu deux fois (MPTA + synthèse)
        root._lastTapMs = now
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

        // ── Détecteur de double-tap ──────────────────────────────────────────
        // Solution C++ : event filter app-level (TapDetector) émet
        // controller.screenTapped() à chaque MouseButtonPress / TouchBegin
        // SANS consommer l'événement (propagation normale aux boutons QML).
        // Évite le bug A133 evdev (MPTA bloque les releases → flood warnings).
        Connections {
            target: controller
            onScreenTapped: root._handleTap()
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
            faceInFrame:  controller.faceInFrame
            faceInRoi:    controller.faceInRoi
            faceAccess:   controller.faceAccess
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
            imageBaseUrl: controller.controllerUrl
            onDismissed: visible = false
        }

        Timer {
            id: settingsHideTimer
            interval: 6000
            onTriggered: settingsBtn.visible = false
        }

        // ── Bouton Settings flottant (apparaît temporairement après tap-tap) ──
        Rectangle {
            id: settingsBtn
            visible: false
            z: 30
            width: 56; height: 56; radius: 28
            anchors { verticalCenter: parent.verticalCenter; right: parent.right; rightMargin: 18 }
            color: settingsMA.pressed ? "#1d4ed8" : "#2563eb"
            border.color: "#60a5fa"; border.width: 2

            // Pulse halo derrière le bouton (purement visuel, pas d'interaction)
            Rectangle {
                z: -1
                anchors.centerIn: parent
                width:  parent.width  + 16
                height: parent.height + 16
                radius: width / 2
                color: "transparent"
                border.color: "#3b82f6"; border.width: 1
                opacity: 0.5
                SequentialAnimation on opacity {
                    loops: Animation.Infinite; running: settingsBtn.visible
                    NumberAnimation { from: 0.5; to: 0.0; duration: 1200; easing.type: Easing.OutQuad }
                    PauseAnimation  { duration: 100 }
                }
            }

            // Engrenage en Canvas
            Canvas {
                anchors.centerIn: parent
                width: 26; height: 26
                onPaint: {
                    var ctx = getContext("2d")
                    ctx.clearRect(0, 0, width, height)
                    ctx.strokeStyle = "white"
                    ctx.fillStyle   = "white"
                    ctx.lineWidth   = 1.6
                    ctx.lineJoin    = "round"
                    var cx = 13, cy = 13, r = 9, rIn = 4.5, n = 8
                    ctx.beginPath()
                    for (var i = 0; i < n * 2; i++) {
                        var a   = (Math.PI * 2 * i) / (n * 2) - Math.PI / 2
                        var rad = (i % 2 === 0) ? r : r - 2.2
                        var x   = cx + rad * Math.cos(a)
                        var y   = cy + rad * Math.sin(a)
                        if (i === 0) ctx.moveTo(x, y); else ctx.lineTo(x, y)
                    }
                    ctx.closePath()
                    ctx.stroke()
                    ctx.beginPath(); ctx.arc(cx, cy, rIn, 0, Math.PI * 2); ctx.stroke()
                    ctx.beginPath(); ctx.arc(cx, cy, 2, 0, Math.PI * 2); ctx.fill()
                }
            }

            MouseArea {
                id: settingsMA
                anchors.fill: parent
                onClicked: {
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

            // Backdrop : absorbe les clics → ne ferme pas le modal sur tap arrière-plan
            MouseArea { anchors.fill: parent; onClicked: {} }

            Rectangle {
                anchors.centerIn: parent
                width: 320; height: pwCol.implicitHeight + 48
                radius: 20
                color: "#0f172a"
                border.color: "#334155"

                // Carte : absorbe explicitement les clics non gérés
                MouseArea { anchors.fill: parent; onClicked: {}; z: -1 }

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
                        keyboard:    keyboard
                        isPassword:  true
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

                        AppButton {
                            width: (parent.width - 8) / 2; height: 40
                            variant: "secondary"
                            text: "Annuler"
                            onClicked: {
                                passwordModal.visible = false
                                pwInput.text = ""; keyboard.close()
                                pwError.visible = false
                                root.adminVisible = false
                                controller.resumeRecognition()
                            }
                        }

                        AppButton {
                            width: (parent.width - 8) / 2; height: 40
                            variant: "primary"
                            text: "Valider"
                            onClicked: passwordModal.checkPassword()
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
                    adminMenu.open()
                } else {
                    pwError.visible = true
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
            controller: root._ctrl
            keyboard: keyboard
            onClosed: adminMenu.open()
        }

        // ── Face settings modal ───────────────────────────────────────────────
        FaceSettingsModal {
            id: faceSettings
            controller: root._ctrl
            onClosed: adminMenu.open()
            onOpenEnroll: { faceSettings.visible = false; enrollment.open() }
        }

        // ── Enrolment modal (sous-modal de FaceSettings) ─────────────────────
        EnrollmentModal {
            id: enrollment
            controller: root._ctrl
            keyboard: keyboard
            onClosed: { faceSettings.open() }
        }

        // ── Qt Virtual Keyboard ───────────────────────────────────────────────
        // Wrapper Item pour maintenir l'API keyboard.close() utilisée partout.
        // Le clavier auto-sélectionne sa disposition (Symbols/Numbers/QWERTY)
        // en fonction de inputMethodHints du champ qui a le focus :
        //   • Qt.ImhDigitsOnly       → pavé numérique 0-9
        //   • Qt.ImhFormattedNumbers → numérique avec séparateurs
        //   • aucun hint             → QWERTY normal
        Item {
            id: keyboard
            anchors.fill: parent
            z: 999
            visible: Qt.inputMethod.visible

            function close() { Qt.inputMethod.hide() }

            // Clavier à taille native (compatible écran 7"), avec zoom 1.3×
            // uniquement quand le champ focus a Qt.ImhDigitsOnly (champs nombres).
            InputPanel {
                id: inputPanel
                anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
                visible: Qt.inputMethod.visible

                // Détection du mode numérique depuis le hint du champ focus
                property bool numericMode: {
                    var item = Qt.inputMethod.inputItem
                    if (!item) return false
                    return (item.inputMethodHints & Qt.ImhDigitsOnly) !== 0
                }

                scale: numericMode ? 1.3 : 1.0
                transformOrigin: Item.Bottom
            }
        }
    }
}
