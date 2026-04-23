import QtQuick 2.10

Item {
    id: root

    property bool   granted: true
    property string personName: ""
    property string source: "badge"     // "badge" | "face" | "fingerprint"
    property real   score: 0
    property string door: ""
    property string timeStr: ""
    property string userId: ""
    property string imageBaseUrl: ""

    // Dismiss after 5 s
    signal dismissed

    Timer {
        interval: 5000
        running: root.visible
        onTriggered: root.dismissed()
    }

    // Backdrop
    Rectangle {
        anchors.fill: parent
        color: "#8c000000"

        MouseArea {
            anchors.fill: parent
            onClicked: root.dismissed()
        }
    }

    // Card
    Rectangle {
        id: card
        anchors.centerIn: parent
        width: Math.min(parent.width - 48, 420)
        height: cardContent.implicitHeight + 80
        radius: 24
        color: root.granted ? "#0a1a12" : "#1a0a0e"
        border.color: root.granted ? "#5010b981" : "#50e11d48"
        border.width: 1

        // Glow
        Rectangle {
            anchors.fill: parent
            radius: parent.radius
            color: "transparent"
            border.color: root.granted ? "#2010b981" : "#20e11d48"
            border.width: 16
        }

        Column {
            id: cardContent
            anchors {
                top: parent.top; topMargin: 40
                left: parent.left; right: parent.right
                leftMargin: 32; rightMargin: 32
            }
            spacing: 0

            // Avatar circle
            Rectangle {
                anchors.horizontalCenter: parent.horizontalCenter
                width: 96; height: 96
                radius: 48
                clip: true
                color: root.granted ? "#1010b981" : "#10e11d48"
                border.color: root.granted ? "#10b981" : "#e11d48"
                border.width: 2

                // Photo réelle depuis l'API
                Image {
                    id: userPhoto
                    anchors.fill: parent
                    source: (root.userId.length > 0 && root.imageBaseUrl.length > 0)
                            ? (root.imageBaseUrl + "/users/" + root.userId + "/image")
                            : ""
                    fillMode: Image.PreserveAspectCrop
                    visible: status === Image.Ready
                    asynchronous: true
                }

                // Initiale — fallback si pas de photo
                Text {
                    anchors.centerIn: parent
                    visible: userPhoto.status !== Image.Ready
                    text: root.personName.length > 0
                          ? root.personName.charAt(0).toUpperCase()
                          : "?"
                    color: root.granted ? "#10b981" : "#e11d48"
                    font.pixelSize: 40
                    font.weight: Font.Bold
                }
            }

            Item { width: 1; height: 24 }

            // Name
            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: root.personName || "Anonyme"
                color: "white"
                font.pixelSize: 28
                font.weight: Font.Bold
            }

            Item { width: 1; height: 16 }

            // Source badge
            Rectangle {
                anchors.horizontalCenter: parent.horizontalCenter
                width: sourceRow.implicitWidth + 24
                height: 28
                radius: 14
                color: root.granted ? "#1510b981" : "#15e11d48"
                border.color: root.granted ? "#3010b981" : "#30e11d48"

                Row {
                    id: sourceRow
                    anchors.centerIn: parent
                    spacing: 6

                    Text {
                        text: root.source === "face" ? "◉" : (root.source === "fingerprint" ? "⬡" : "▭")
                        color: root.granted ? "#6ee7b7" : "#fca5a5"
                        font.pixelSize: 12
                    }
                    Text {
                        text: {
                            if (root.source === "face")        return "Reconnaissance faciale"
                            if (root.source === "fingerprint") return "Empreinte digitale"
                            return "Badge"
                        }
                        color: root.granted ? "#6ee7b7" : "#fca5a5"
                        font.pixelSize: 11
                        font.weight: Font.DemiBold
                        font.letterSpacing: 1
                        font.capitalization: Font.AllUppercase
                    }
                    Text {
                        visible: root.source !== "badge" && root.score > 0
                        text: "· " + Math.round(root.score * 100) + "%"
                        color: root.granted ? "#6ee7b7" : "#fca5a5"
                        font.pixelSize: 11
                        font.family: "monospace"
                    }
                }
            }

            Item { width: 1; height: 24 }

            // ACCORDÉ / REFUSÉ button
            Rectangle {
                anchors.left: parent.left; anchors.right: parent.right
                height: 56
                radius: 28
                color: root.granted ? "#10b981" : "#dc2626"

                Text {
                    anchors.centerIn: parent
                    text: root.granted ? "ACCÈS ACCORDÉ" : "ACCÈS REFUSÉ"
                    color: "white"
                    font.pixelSize: 18
                    font.weight: Font.Bold
                    font.letterSpacing: 2
                }
            }

            Item { width: 1; height: 24 }

            // Door + time row
            Rectangle {
                anchors.left: parent.left; anchors.right: parent.right
                height: 48
                radius: 16
                color: root.granted ? "#0d1a14" : "#1a0d0d"
                border.color: root.granted ? "#1f3d2e" : "#3d1f1f"

                Row {
                    anchors.centerIn: parent
                    spacing: 24

                    Row {
                        spacing: 8
                        Text { text: "⛌"; color: root.granted ? "#6ee7b7" : "#fca5a5"; font.pixelSize: 16; anchors.verticalCenter: parent.verticalCenter }
                        Text {
                            text: root.door || "—"
                            color: root.granted ? "#6ee7b7" : "#fca5a5"
                            font.pixelSize: 14
                            anchors.verticalCenter: parent.verticalCenter
                        }
                    }

                    Rectangle {
                        width: 1; height: 16
                        color: root.granted ? "#2d4a38" : "#4a2d2d"
                        anchors.verticalCenter: parent.verticalCenter
                    }

                    Text {
                        text: root.timeStr
                        color: root.granted ? "#6ee7b7" : "#fca5a5"
                        font.pixelSize: 13
                        font.family: "monospace"
                        anchors.verticalCenter: parent.verticalCenter
                    }
                }
            }

            Item { width: 1; height: 8 }
        }
    }

    // Slide-in animation
    NumberAnimation on opacity {
        from: 0; to: 1; duration: 300
        running: root.visible
        easing.type: Easing.OutCubic
    }
}
