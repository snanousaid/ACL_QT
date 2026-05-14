import QtQuick 2.10

Rectangle {
    id: root
    anchors.fill: parent
    visible: false
    color: "#b3000000"
    z: 50

    property var controller: null
    // Liste des profils faces : [{ id, userId, user: {first_name, last_name, cin, isActif}, createdAt }]
    property var profiles: []
    property string errorMsg: ""
    property string busyUserId: ""   // userId en cours de suppression (spinner / disable)

    signal closed()
    signal openEnroll()

    function open() {
        visible = true
        errorMsg = ""
        if (controller) controller.listFaceProfiles()
    }
    function close() {
        visible = false
        confirmDelete.visible = false
        closed()
    }

    Connections {
        target: root.controller
        ignoreUnknownSignals: true
        onFaceProfilesLoaded: {
            root.profiles = profiles
            root.busyUserId = ""
        }
        onFaceApiError: {
            root.errorMsg = op + ": " + msg
            root.busyUserId = ""
        }
        onFaceProfileMutated: {
            // recharge la liste après enroll / delete
            if (root.controller) root.controller.listFaceProfiles()
        }
    }

    // Backdrop tap → close
    MouseArea { anchors.fill: parent; onClicked: root.close() }

    // ── Card ─────────────────────────────────────────────────────────────────
    Rectangle {
        anchors.centerIn: parent
        width:  parent.width  - 40
        height: parent.height - 80
        radius: 20
        color: "#0f172a"
        border.color: "#334155"

        MouseArea { anchors.fill: parent; onClicked: {} }  // absorb backdrop

        // Header
        Rectangle {
            id: cardHeader
            anchors { top: parent.top; left: parent.left; right: parent.right }
            height: 64
            color: "transparent"

            Row {
                anchors { left: parent.left; leftMargin: 20; verticalCenter: parent.verticalCenter }
                spacing: 12
                Rectangle {
                    width: 36; height: 36; radius: 8
                    color: "#22d3ee33"
                    Text { anchors.centerIn: parent; text: "👤"; font.pixelSize: 18 }
                }
                Column {
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 2
                    Text { text: "Face ID — Profils"; color: "white"; font.pixelSize: 16; font.weight: Font.Bold }
                    Text {
                        text: root.profiles.length + " profil" + (root.profiles.length > 1 ? "s" : "")
                              + " enregistré" + (root.profiles.length > 1 ? "s" : "")
                        color: "#64748b"; font.pixelSize: 11
                    }
                }
            }

            CloseIcon {
                anchors { right: parent.right; rightMargin: 14; verticalCenter: parent.verticalCenter }
                onClicked: root.close()
            }

            Rectangle {
                anchors { bottom: parent.bottom; left: parent.left; right: parent.right }
                height: 1; color: "#1e293b"
            }
        }

        // Error banner
        Rectangle {
            id: errBanner
            anchors { top: cardHeader.bottom; left: parent.left; right: parent.right; margins: 12 }
            visible: root.errorMsg.length > 0
            height: visible ? errText.implicitHeight + 16 : 0
            radius: 8
            color: "#7f1d1d33"; border.color: "#7f1d1d"
            Text {
                id: errText
                anchors { fill: parent; margins: 8 }
                text: root.errorMsg; color: "#fca5a5"; font.pixelSize: 11
                wrapMode: Text.WordWrap
            }
        }

        // Empty state
        Column {
            anchors.centerIn: parent
            spacing: 8
            visible: root.profiles.length === 0 && root.errorMsg.length === 0
            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: "Aucun profil face enregistré."
                color: "#64748b"; font.pixelSize: 13
            }
            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: "Cliquez sur + Nouveau pour enrôler un utilisateur."
                color: "#475569"; font.pixelSize: 11
            }
        }

        // Profiles list
        ListView {
            id: profilesList
            clip: true
            anchors {
                top: errBanner.visible ? errBanner.bottom : cardHeader.bottom
                left: parent.left; right: parent.right
                bottom: refreshBar.top
                topMargin: 8; leftMargin: 12; rightMargin: 12; bottomMargin: 8
            }
            model: root.profiles
            spacing: 8
            visible: root.profiles.length > 0

            delegate: Rectangle {
                readonly property var p: modelData
                readonly property var u: modelData.user || ({})
                readonly property bool userActive: u.isActif !== false
                readonly property string fullName:
                    ((u.first_name || "") + " " + (u.last_name || "")).trim() || "(sans nom)"
                readonly property string userId: p.userId || ""

                width: profilesList.width
                height: 64
                radius: 10
                color: userActive ? "#1e293b" : "#0b1220"
                border.color: "#334155"
                opacity: root.busyUserId === userId ? 0.5 : 1

                Row {
                    anchors { left: parent.left; leftMargin: 14; verticalCenter: parent.verticalCenter }
                    spacing: 12

                    // Indicateur état User.isActif (vert / gris)
                    Rectangle {
                        width: 8; height: 40; radius: 4
                        color: userActive ? "#22c55e" : "#475569"
                        anchors.verticalCenter: parent.verticalCenter
                    }

                    Column {
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 3
                        Text {
                            text: fullName
                            color: "white"; font.pixelSize: 14; font.weight: Font.DemiBold
                        }
                        Text {
                            text: "CIN: " + (u.cin || "—")
                                  + (p.createdAt ? "  •  " + String(p.createdAt).substr(0, 10) : "")
                            color: "#64748b"; font.pixelSize: 10
                        }
                    }
                }

                Row {
                    anchors { right: parent.right; rightMargin: 12; verticalCenter: parent.verticalCenter }
                    spacing: 8

                    // Statut User.isActif (lecture seule - geré dans dashboard web)
                    Rectangle {
                        width: 64; height: 24; radius: 8
                        color: userActive ? "#0f3a26" : "#1e293b"
                        border.color: userActive ? "#22c55e" : "#475569"
                        border.width: 1
                        Text {
                            anchors.centerIn: parent
                            text: userActive ? "Actif" : "Inactif"
                            color: userActive ? "#86efac" : "#94a3b8"
                            font.pixelSize: 10; font.weight: Font.DemiBold
                        }
                    }

                    // Bouton supprimer (DELETE /face/profile/:userId)
                    AppButton {
                        width: 36; height: 32
                        enabled: root.busyUserId === ""
                        text: "🗑"
                        background: Rectangle {
                            radius: 8
                            color: "#7f1d1d33"; border.color: "#7f1d1d"; border.width: 1
                            opacity: parent.enabled ? 1 : 0.5
                        }
                        contentItem: Text {
                            text: parent.text
                            font.pixelSize: 13
                            horizontalAlignment: Text.AlignHCenter
                            verticalAlignment: Text.AlignVCenter
                        }
                        onClicked: {
                            confirmDelete.targetUserId  = userId
                            confirmDelete.targetName    = fullName
                            confirmDelete.visible       = true
                        }
                    }
                }
            }
        }

        // Bottom bar
        Rectangle {
            id: refreshBar
            anchors { bottom: parent.bottom; left: parent.left; right: parent.right }
            height: 56
            color: "transparent"

            Rectangle {
                anchors { top: parent.top; left: parent.left; right: parent.right }
                height: 1; color: "#1e293b"
            }

            Row {
                anchors.centerIn: parent
                spacing: 8

                AppButton {
                    width: 110; height: 36
                    variant: "success"
                    text: "+ Nouveau"
                    fontSize: 12
                    onClicked: root.openEnroll()
                }

                AppButton {
                    width: 100; height: 36
                    variant: "secondary"
                    text: "Rafraîchir"
                    fontSize: 12; bold: false
                    onClicked: { root.errorMsg = ""; root.controller.listFaceProfiles() }
                }

                AppButton {
                    width: 90; height: 36
                    variant: "secondary"
                    text: "Fermer"
                    fontSize: 12; bold: false
                    onClicked: root.close()
                }
            }
        }
    }

    // ── Confirm-delete sub-modal ─────────────────────────────────────────────
    Rectangle {
        id: confirmDelete
        anchors.fill: parent
        visible: false
        color: "#cc000000"
        z: 60
        property string targetUserId: ""
        property string targetName: ""

        MouseArea { anchors.fill: parent; onClicked: confirmDelete.visible = false }

        Rectangle {
            anchors.centerIn: parent
            width: 300; height: confirmCol.implicitHeight + 40
            radius: 14; color: "#0f172a"; border.color: "#7f1d1d"

            MouseArea { anchors.fill: parent; onClicked: {} }

            Column {
                id: confirmCol
                anchors { top: parent.top; left: parent.left; right: parent.right
                          topMargin: 20; leftMargin: 20; rightMargin: 20 }
                spacing: 12

                Text { text: "Supprimer le profil face ?"; color: "white"; font.pixelSize: 15; font.weight: Font.Bold }
                Text {
                    text: "Le profil face de « " + confirmDelete.targetName
                          + " » sera supprimé. L'utilisateur reste actif "
                          + "(seul son accès Face ID est retiré)."
                    color: "#cbd5e1"; font.pixelSize: 11; wrapMode: Text.WordWrap; width: parent.width
                }

                Row {
                    width: parent.width; spacing: 8
                    AppButton {
                        width: (parent.width - 8) / 2; height: 36
                        variant: "secondary"
                        text: "Annuler"; fontSize: 12; bold: false
                        onClicked: confirmDelete.visible = false
                    }
                    AppButton {
                        width: (parent.width - 8) / 2; height: 36
                        variant: "danger"
                        text: "Supprimer"; fontSize: 12
                        onClicked: {
                            confirmDelete.visible = false
                            root.busyUserId = confirmDelete.targetUserId
                            root.controller.deleteFaceProfile(confirmDelete.targetUserId)
                        }
                    }
                }
            }
        }
    }
}
