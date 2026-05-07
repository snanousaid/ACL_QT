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
    property int    samplesPerPose: 10

    // Debounce global pour les boutons tactiles (driver A133 : presses
    // dupliqués sans release entre les deux).
    property real _lastFireMs: 0
    function _debounce() {
        var now = Date.now()
        if (now - _lastFireMs < 250) return false
        _lastFireMs = now
        return true
    }

    // Statut backend (rempli par poll)
    property var status: ({})

    // Compteurs dérivés du backend pour la progress bar globale
    readonly property int totalCount: {
        var p = root.status.enroll_poses
        if (!p || p.length === 0) return 0
        var n = 0
        for (var i = 0; i < p.length; i++) n += p[i].count
        return n
    }
    readonly property int totalTarget: root.samplesPerPose * 5

    // Index numérique de l'étape pour le stepper (0=form, 1=live, 2=done)
    readonly property int stepIndex: state === "form" ? 0 : (state === "live" ? 1 : 2)

    signal closed()

    function open() {
        visible = true
        state = "form"
        errorMsg = ""
        userName = ""
        userRole = "user"
        samplesPerPose = 10
        status = {}
        if (typeof nameInput !== "undefined") nameInput.text = ""
    }
    function close() {
        // Defer la fermeture (cf. NetworkConfigModal.close) — A133 evdev.
        Qt.callLater(function() {
            if (state === "live") controller.cancelEnroll()
            pollTimer.stop()
            visible = false
            if (keyboard) keyboard.close()
            closed()
        })
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

        // ---- Header avec stepper visuel ----
        Rectangle {
            id: hdr
            anchors { top: parent.top; left: parent.left; right: parent.right }
            height: 88
            color: "transparent"

            Text {
                anchors { left: parent.left; leftMargin: 20; top: parent.top; topMargin: 12 }
                text: root.state === "form" ? "Nouvel utilisateur"
                    : root.state === "live" ? "Enrôlement — " + root.userName
                    : "Terminé"
                color: "white"; font.pixelSize: 15; font.weight: Font.Bold
            }
            CloseIcon {
                anchors { right: parent.right; rightMargin: 14; top: parent.top; topMargin: 8 }
                onClicked: root.close()
            }

            // Stepper : 3 ronds reliés par des lignes
            Row {
                id: stepperRow
                anchors { left: parent.left; right: parent.right; bottom: parent.bottom; bottomMargin: 14
                          leftMargin: 28; rightMargin: 28 }
                spacing: 0

                Repeater {
                    model: [
                        { idx: 0, label: "Infos" },
                        { idx: 1, label: "Capture" },
                        { idx: 2, label: "Terminé" }
                    ]
                    Item {
                        property bool isLast:    modelData.idx === 2
                        property bool isActive:  root.stepIndex === modelData.idx
                        property bool isDone:    root.stepIndex >  modelData.idx
                        width:  isLast ? 32 : (stepperRow.width - 32 * 3) / 2 + 32
                        height: 32

                        // Ligne reliant ce step au suivant (sauf dernier)
                        Rectangle {
                            visible: !parent.isLast
                            anchors { left: parent.left; leftMargin: 32; right: parent.right
                                      verticalCenter: parent.verticalCenter }
                            height: 2
                            color: parent.isDone ? "#22c55e" : "#334155"
                            Behavior on color { ColorAnimation { duration: 300 } }
                        }

                        // Cercle du step
                        Rectangle {
                            anchors { left: parent.left; verticalCenter: parent.verticalCenter }
                            width: 32; height: 32; radius: 16
                            color: parent.isActive ? "#2563eb" : (parent.isDone ? "#22c55e" : "#1e293b")
                            border.color: parent.isActive ? "#3b82f6" : (parent.isDone ? "#22c55e" : "#334155")
                            border.width: 2
                            Behavior on color { ColorAnimation { duration: 200 } }

                            Text {
                                anchors.centerIn: parent
                                text: parent.parent.isDone ? "✓" : (modelData.idx + 1)
                                color: "white"
                                font.pixelSize: parent.parent.isDone ? 16 : 13
                                font.weight: Font.Bold
                            }
                        }

                        // Label sous le cercle
                        Text {
                            anchors { left: parent.left; top: parent.bottom; topMargin: 2 }
                            width: 60
                            horizontalAlignment: Text.AlignHCenter
                            x: 32 / 2 - width / 2
                            text: modelData.label
                            color: parent.isActive ? "#cbd5e1" : "#64748b"
                            font.pixelSize: 9; font.weight: Font.DemiBold
                        }
                    }
                }
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
                            id: roleBtn
                            property bool selected: root.userRole === modelData
                            width: 100; height: 36; radius: 8
                            color: selected ? "#2563eb" : (roleMA.pressed ? "#0f172a" : "#1e293b")
                            border.color: selected ? "#3b82f6" : "#334155"
                            Text {
                                anchors.centerIn: parent; text: modelData
                                color: roleBtn.selected ? "white" : "#94a3b8"
                                font.pixelSize: 12; font.weight: Font.DemiBold
                            }
                            MouseArea {
                                id: roleMA
                                anchors.fill: parent
                                onPressed: {
                                    if (!root._debounce()) return
                                    root.userRole = modelData
                                }
                            }
                        }
                    }
                }

                Item { width: 1; height: 8 }

                Text { text: "Échantillons par pose (3-30)"; color: "#cbd5e1"; font.pixelSize: 12 }
                Row {
                    id: samplesRow
                    spacing: 10

                    Rectangle {
                        id: minusBtn
                        width: 48; height: 48; radius: 10
                        color: minusMA.pressed ? "#1d4ed8" : "#1e293b"
                        border.color: "#475569"; border.width: 1
                        Text { anchors.centerIn: parent; text: "−"; color: "white"; font.pixelSize: 24; font.weight: Font.Bold }
                        MouseArea {
                            id: minusMA
                            anchors.fill: parent
                            onPressed: {
                                if (!root._debounce()) return
                                root.samplesPerPose = Math.max(3, root.samplesPerPose - 1)
                            }
                        }
                    }

                    // Champ éditable : permet de taper directement la valeur (clavier Qt VKB en mode numérique)
                    Rectangle {
                        width: 90; height: 48; radius: 10
                        color: "#0f172a"; border.color: samplesField.activeFocus ? "#3b82f6" : "#475569"; border.width: 1
                        TextInput {
                            id: samplesField
                            anchors.fill: parent
                            horizontalAlignment: TextInput.AlignHCenter
                            verticalAlignment:   TextInput.AlignVCenter
                            color: "white"; font.pixelSize: 18; font.weight: Font.Bold
                            // Binding unidirectionnel : root.samplesPerPose → text (pas de surcharge manuelle)
                            text: String(root.samplesPerPose)
                            inputMethodHints: Qt.ImhDigitsOnly
                            validator: IntValidator { bottom: 3; top: 30 }
                            // Mise à jour de root.samplesPerPose UNIQUEMENT à la fin de l'édition
                            // (évite le binding loop avec le setter)
                            onEditingFinished: {
                                var v = parseInt(text)
                                if (isNaN(v) || v < 3) v = 3
                                if (v > 30) v = 30
                                if (root.samplesPerPose !== v) root.samplesPerPose = v
                            }
                        }
                    }

                    Rectangle {
                        id: plusBtn
                        width: 48; height: 48; radius: 10
                        color: plusMA.pressed ? "#1d4ed8" : "#1e293b"
                        border.color: "#475569"; border.width: 1
                        Text { anchors.centerIn: parent; text: "+"; color: "white"; font.pixelSize: 24; font.weight: Font.Bold }
                        MouseArea {
                            id: plusMA
                            anchors.fill: parent
                            onPressed: {
                                if (!root._debounce()) return
                                root.samplesPerPose = Math.min(30, root.samplesPerPose + 1)
                            }
                        }
                    }
                }

                Text {
                    width: parent.width
                    text: "5 poses : centre / gauche / droite (obligatoires) + haut / bas (bonus). Total : "
                          + (root.samplesPerPose * 5) + " échantillons (3 obligatoires × " + root.samplesPerPose + ")."
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
                        root.controller.startEnroll(root.userName, root.userRole, root.samplesPerPose)
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

            // MJPEG preview agrandi
            Rectangle {
                id: previewBox
                anchors { top: parent.top; left: parent.left; right: parent.right }
                height: 280
                color: "#000"; radius: 12
                clip: true

                Image {
                    id: enrollCam
                    anchors.fill: parent
                    source: "image://camera/frame"
                    cache: false
                    fillMode: Image.PreserveAspectCrop
                    asynchronous: false
                }
                Timer {
                    interval: 33
                    running: root.visible && root.state === "live"
                    repeat: true
                    onTriggered: enrollCam.source = "image://camera/frame?" + Date.now()
                }

                // Ellipse guide positionnement visage
                Canvas {
                    id: faceGuide
                    anchors.fill: parent

                    property bool inRoi: root.status.in_roi === true

                    Component.onCompleted: requestPaint()
                    onInRoiChanged:        requestPaint()

                    onPaint: {
                        var ctx = getContext("2d")
                        ctx.clearRect(0, 0, width, height)

                        var cx = width  / 2
                        var cy = height / 2
                        var rx = width  * 0.28
                        var ry = height * 0.42
                        var k  = 0.5523

                        ctx.setLineDash(inRoi ? [] : [8, 5])
                        ctx.lineWidth   = inRoi ? 3 : 2
                        ctx.strokeStyle = inRoi ? "#22c55e" : "#22d3ee"

                        ctx.beginPath()
                        ctx.moveTo(cx - rx, cy)
                        ctx.bezierCurveTo(cx - rx, cy - k*ry, cx - k*rx, cy - ry, cx,      cy - ry)
                        ctx.bezierCurveTo(cx + k*rx, cy - ry, cx + rx, cy - k*ry, cx + rx, cy)
                        ctx.bezierCurveTo(cx + rx, cy + k*ry, cx + k*rx, cy + ry, cx,      cy + ry)
                        ctx.bezierCurveTo(cx - k*rx, cy + ry, cx - rx, cy + k*ry, cx - rx, cy)
                        ctx.closePath()
                        ctx.stroke()
                    }
                }

                Rectangle {
                    anchors.fill: parent
                    color: "transparent"
                    border.color: "#22d3ee"; border.width: 2
                    radius: 12
                }

                // Flash vert d'animation lors d'une capture (declenche par totalCount change)
                Rectangle {
                    id: flashOverlay
                    anchors.fill: parent
                    radius: 12
                    color: "#22c55e"
                    opacity: 0
                    NumberAnimation {
                        id: flashAnim
                        target: flashOverlay
                        property: "opacity"
                        from: 0.35; to: 0
                        duration: 350
                        easing.type: Easing.OutQuad
                    }
                }
            }

            // Trigger pulse à chaque incrément de totalCount
            Connections {
                target: root
                onTotalCountChanged: if (root.totalCount > 0) flashAnim.restart()
            }

            // Progress bar globale + compteur
            Rectangle {
                id: progressBar
                anchors { top: previewBox.bottom; left: parent.left; right: parent.right; topMargin: 10 }
                height: 6; radius: 3
                color: "#1e293b"
                Rectangle {
                    height: parent.height; radius: parent.radius
                    width: parent.width * (root.totalTarget > 0
                                           ? Math.min(1, root.totalCount / root.totalTarget) : 0)
                    color: "#22d3ee"
                    Behavior on width { NumberAnimation { duration: 250; easing.type: Easing.OutCubic } }
                }
            }
            Text {
                id: progressLabel
                anchors { top: progressBar.bottom; right: parent.right; topMargin: 4 }
                text: root.totalCount + " / " + root.totalTarget + " échantillons"
                color: "#64748b"; font.pixelSize: 10
            }

            // Message status
            Text {
                id: msgTxt
                anchors { top: progressLabel.bottom; left: parent.left; right: parent.right; topMargin: 6 }
                horizontalAlignment: Text.AlignHCenter
                text: root.status.enroll_msg || "Positionnez votre visage…"
                color: "#cbd5e1"; font.pixelSize: 12
                wrapMode: Text.WordWrap
            }

            // Grille thumbnails 5 poses
            Row {
                id: poseGrid
                anchors { top: msgTxt.bottom; left: parent.left; right: parent.right; topMargin: 10 }
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
                        Behavior on color       { ColorAnimation { duration: 250 } }
                        Behavior on border.color { ColorAnimation { duration: 250 } }

                        // Picto directionnel Canvas (cible / flèches)
                        Canvas {
                            anchors { top: parent.top; horizontalCenter: parent.horizontalCenter; topMargin: 12 }
                            width: 28; height: 28
                            property string poseId: modelData.id
                            property bool   done:   modelData.done
                            property bool   curr:   modelData.id === root.status.enroll_current_pose
                            onDoneChanged: requestPaint()
                            onCurrChanged: requestPaint()
                            Component.onCompleted: requestPaint()

                            onPaint: {
                                var ctx = getContext("2d")
                                ctx.clearRect(0, 0, width, height)
                                var col = done ? "#22c55e" : (curr ? "#22d3ee" : "#475569")
                                ctx.strokeStyle = col
                                ctx.fillStyle   = col
                                ctx.lineWidth   = 2.2
                                ctx.lineCap     = "round"
                                ctx.lineJoin    = "round"

                                if (done) {
                                    // Checkmark
                                    ctx.beginPath()
                                    ctx.moveTo(width*0.20, height*0.55)
                                    ctx.lineTo(width*0.42, height*0.78)
                                    ctx.lineTo(width*0.82, height*0.28)
                                    ctx.stroke()
                                } else if (poseId === "center") {
                                    // Cible : 2 cercles concentriques + point
                                    ctx.beginPath(); ctx.arc(width/2, height/2, width*0.40, 0, Math.PI*2); ctx.stroke()
                                    ctx.beginPath(); ctx.arc(width/2, height/2, width*0.20, 0, Math.PI*2); ctx.stroke()
                                    ctx.beginPath(); ctx.arc(width/2, height/2, 2.5, 0, Math.PI*2); ctx.fill()
                                } else if (poseId === "left" || poseId === "right") {
                                    // Flèche horizontale
                                    var dir = (poseId === "left") ? -1 : 1
                                    var cy  = height/2, cx = width/2
                                    ctx.beginPath()
                                    ctx.moveTo(cx - dir*width*0.35, cy)
                                    ctx.lineTo(cx + dir*width*0.35, cy)
                                    ctx.stroke()
                                    ctx.beginPath()
                                    ctx.moveTo(cx + dir*width*0.15, cy - height*0.20)
                                    ctx.lineTo(cx + dir*width*0.35, cy)
                                    ctx.lineTo(cx + dir*width*0.15, cy + height*0.20)
                                    ctx.stroke()
                                } else if (poseId === "up" || poseId === "down") {
                                    // Flèche verticale
                                    var dirV = (poseId === "up") ? -1 : 1
                                    var cxV  = width/2, cyV = height/2
                                    ctx.beginPath()
                                    ctx.moveTo(cxV, cyV - dirV*height*0.35)
                                    ctx.lineTo(cxV, cyV + dirV*height*0.35)
                                    ctx.stroke()
                                    ctx.beginPath()
                                    ctx.moveTo(cxV - width*0.20, cyV - dirV*height*0.15)
                                    ctx.lineTo(cxV, cyV - dirV*height*0.35)
                                    ctx.lineTo(cxV + width*0.20, cyV - dirV*height*0.15)
                                    ctx.stroke()
                                }
                            }
                        }

                        // Compteur
                        Text {
                            anchors { top: parent.top; horizontalCenter: parent.horizontalCenter; topMargin: 50 }
                            visible: !modelData.done
                            text: modelData.count + "/" + modelData.target
                            color: isCurrent ? "#22d3ee" : "#64748b"
                            font.pixelSize: 11; font.weight: Font.DemiBold
                        }

                        // Badge "REQ"
                        Rectangle {
                            anchors { top: parent.top; right: parent.right; margins: 3 }
                            visible: modelData.required && !modelData.done
                            width: 26; height: 12; radius: 3
                            color: "#7f1d1d33"; border.color: "#7f1d1d"; border.width: 1
                            Text {
                                anchors.centerIn: parent
                                text: "REQ"; color: "#fca5a5"
                                font.pixelSize: 7; font.weight: Font.Bold
                            }
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
            id: doneItem
            visible: root.state === "done"
            anchors { fill: parent; topMargin: 88 }

            // Trigger animations à chaque entrée dans le state
            onVisibleChanged: {
                if (visible) {
                    successHalo.scale     = 0
                    successCircle.scale   = 0
                    successCircle.opacity = 0
                    doneTitle.opacity     = 0
                    doneSubtitle.opacity  = 0
                    closeBtn.opacity      = 0
                    successAnim.start()
                }
            }

            // Halo concentrique animé (effet de pulsation)
            Rectangle {
                id: successHalo
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.top: parent.top
                anchors.topMargin: 20
                width: 160; height: 160; radius: 80
                color: "#22c55e15"
                border.color: "#22c55e55"; border.width: 2
                scale: 0
                transformOrigin: Item.Center
                SequentialAnimation on opacity {
                    loops: Animation.Infinite
                    running: doneItem.visible
                    NumberAnimation { from: 0.7; to: 0.2; duration: 1400; easing.type: Easing.InOutQuad }
                    NumberAnimation { from: 0.2; to: 0.7; duration: 1400; easing.type: Easing.InOutQuad }
                }
            }

            // Cercle plein vert avec checkmark dessiné en Canvas
            Rectangle {
                id: successCircle
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.top: parent.top
                anchors.topMargin: 50
                width: 100; height: 100; radius: 50
                color: "#22c55e"
                opacity: 0
                scale: 0
                transformOrigin: Item.Center

                Canvas {
                    id: checkCanvas
                    anchors.fill: parent
                    property real progress: 0
                    onProgressChanged: requestPaint()
                    onPaint: {
                        var ctx = getContext("2d")
                        ctx.clearRect(0, 0, width, height)
                        ctx.strokeStyle = "white"
                        ctx.lineWidth   = 7
                        ctx.lineCap     = "round"
                        ctx.lineJoin    = "round"

                        // Checkmark : 2 segments. progress 0..1 dessine progressivement.
                        var p1x = width*0.28, p1y = height*0.52
                        var p2x = width*0.45, p2y = height*0.68
                        var p3x = width*0.74, p3y = height*0.36
                        var seg1Len = 1.0   // poids relatif segment 1
                        var seg2Len = 1.5   // poids relatif segment 2
                        var total   = seg1Len + seg2Len
                        var p       = progress

                        ctx.beginPath()
                        ctx.moveTo(p1x, p1y)
                        if (p * total <= seg1Len) {
                            var t1 = (p * total) / seg1Len
                            ctx.lineTo(p1x + (p2x - p1x) * t1, p1y + (p2y - p1y) * t1)
                        } else {
                            ctx.lineTo(p2x, p2y)
                            var t2 = (p * total - seg1Len) / seg2Len
                            ctx.lineTo(p2x + (p3x - p2x) * t2, p2y + (p3y - p2y) * t2)
                        }
                        ctx.stroke()
                    }
                }
            }

            Text {
                id: doneTitle
                anchors { top: successCircle.bottom; horizontalCenter: parent.horizontalCenter; topMargin: 24 }
                text: "Utilisateur enrôlé !"
                color: "white"; font.pixelSize: 18; font.weight: Font.Bold
                opacity: 0
            }

            Text {
                id: doneSubtitle
                objectName: "doneText"
                anchors { top: doneTitle.bottom; topMargin: 8
                          left: parent.left; right: parent.right; leftMargin: 24; rightMargin: 24 }
                horizontalAlignment: Text.AlignHCenter
                text: ""
                color: "#94a3b8"; font.pixelSize: 12
                wrapMode: Text.WordWrap
                opacity: 0
            }

            // Compatibilité ascendante : alias `doneText` utilisé par onEnrollResult
            // pour pousser le message backend.
            Item {
                id: doneText
                property string text: ""
                onTextChanged: doneSubtitle.text = text
            }

            Rectangle {
                id: closeBtn
                anchors { bottom: parent.bottom; horizontalCenter: parent.horizontalCenter; bottomMargin: 24 }
                width: 180; height: 44; radius: 10
                color: closeMA.pressed ? "#1d4ed8" : "#2563eb"
                opacity: 0
                Text { anchors.centerIn: parent; text: "Fermer"; color: "white"; font.pixelSize: 13; font.weight: Font.Bold }
                MouseArea { id: closeMA; anchors.fill: parent; onPressed: root.close() }
            }

            // Séquence d'animation : halo+cercle scale → checkmark draw → texte fade
            SequentialAnimation {
                id: successAnim
                ParallelAnimation {
                    NumberAnimation { target: successHalo;   property: "scale";   from: 0; to: 1; duration: 400; easing.type: Easing.OutBack }
                    NumberAnimation { target: successCircle; property: "scale";   from: 0; to: 1; duration: 400; easing.type: Easing.OutBack }
                    NumberAnimation { target: successCircle; property: "opacity"; from: 0; to: 1; duration: 250 }
                }
                NumberAnimation { target: checkCanvas; property: "progress"; from: 0; to: 1; duration: 400; easing.type: Easing.OutQuad }
                ParallelAnimation {
                    NumberAnimation { target: doneTitle;    property: "opacity"; from: 0; to: 1; duration: 300 }
                    NumberAnimation { target: doneSubtitle; property: "opacity"; from: 0; to: 1; duration: 300 }
                }
                NumberAnimation { target: closeBtn; property: "opacity"; from: 0; to: 1; duration: 250 }
            }
        }
    }
}
