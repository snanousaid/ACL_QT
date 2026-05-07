import QtQuick 2.10

Rectangle {
    id: root
    anchors.fill: parent
    visible: false
    color: "#b3000000"
    z: 50

    property var controller: null
    property var users: []
    property string errorMsg: ""
    property string busyName: ""   // nom en cours d'opération (toggle/delete) → spinner / disable

    signal closed()
    signal openEnroll()

    function open() {
        visible = true
        errorMsg = ""
        if (controller) controller.listFaceUsers()
    }
    function close() {
        visible = false
        confirmDelete.visible = false
        closed()
    }

    Connections {
        target: root.controller
        ignoreUnknownSignals: true
        onFaceUsersLoaded: {
            root.users = users
            root.busyName = ""
        }
        onFaceApiError: {
            root.errorMsg = op + ": " + msg
            root.busyName = ""
        }
        onFaceUserMutated: {
            // recharge la liste après toggle/delete
            if (root.controller) root.controller.listFaceUsers()
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
                    Text { text: "Face ID — Utilisateurs"; color: "white"; font.pixelSize: 16; font.weight: Font.Bold }
                    Text {
                        text: root.users.length + " enregistré" + (root.users.length > 1 ? "s" : "")
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
        Text {
            anchors.centerIn: parent
            visible: root.users.length === 0 && root.errorMsg.length === 0
            text: "Aucun utilisateur enrôlé."
            color: "#64748b"; font.pixelSize: 13
        }

        // Users list
        ListView {
            id: usersList
            clip: true
            anchors {
                top: errBanner.visible ? errBanner.bottom : cardHeader.bottom
                left: parent.left; right: parent.right
                bottom: refreshBar.top
                topMargin: 8; leftMargin: 12; rightMargin: 12; bottomMargin: 8
            }
            model: root.users
            spacing: 8
            visible: root.users.length > 0

            delegate: Rectangle {
                width: usersList.width
                height: 64
                radius: 10
                color: modelData.active ? "#1e293b" : "#0b1220"
                border.color: "#334155"
                opacity: root.busyName === modelData.name ? 0.5 : 1

                Row {
                    anchors { left: parent.left; leftMargin: 14; verticalCenter: parent.verticalCenter }
                    spacing: 12

                    Rectangle {
                        width: 8; height: 40; radius: 4
                        color: modelData.active ? "#22c55e" : "#475569"
                        anchors.verticalCenter: parent.verticalCenter
                    }

                    Column {
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 3
                        Text { text: modelData.name; color: "white"; font.pixelSize: 14; font.weight: Font.DemiBold }
                        Text {
                            text: modelData.role + (modelData.created_at ? " — " + modelData.created_at : "")
                            color: "#64748b"; font.pixelSize: 10
                        }
                    }
                }

                Row {
                    anchors { right: parent.right; rightMargin: 12; verticalCenter: parent.verticalCenter }
                    spacing: 8

                    AppButton {
                        width: 64; height: 32
                        enabled: root.busyName === ""
                        text: modelData.active ? "Actif" : "Off"
                        fontSize: 10
                        background: Rectangle {
                            radius: 8
                            color: modelData.active ? "#0f3a26" : "#1e293b"
                            border.color: modelData.active ? "#22c55e" : "#475569"
                            border.width: 1
                            opacity: parent.enabled ? 1 : 0.5
                        }
                        contentItem: Text {
                            text: parent.text
                            color: modelData.active ? "#86efac" : "#94a3b8"
                            font.pixelSize: 10; font.weight: Font.DemiBold
                            horizontalAlignment: Text.AlignHCenter
                            verticalAlignment: Text.AlignVCenter
                        }
                        onClicked: {
                            root.busyName = modelData.name
                            root.controller.toggleFaceUser(modelData.name)
                        }
                    }

                    AppButton {
                        width: 36; height: 32
                        enabled: root.busyName === ""
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
                            confirmDelete.targetName = modelData.name
                            confirmDelete.visible = true
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
                    onClicked: { root.errorMsg = ""; root.controller.listFaceUsers() }
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

                Text { text: "Supprimer ?"; color: "white"; font.pixelSize: 15; font.weight: Font.Bold }
                Text {
                    text: "L'utilisateur « " + confirmDelete.targetName + " » sera supprimé définitivement."
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
                            root.busyName = confirmDelete.targetName
                            root.controller.deleteFaceUser(confirmDelete.targetName)
                        }
                    }
                }
            }
        }
    }
}
