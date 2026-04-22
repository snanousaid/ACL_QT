import QtQuick 2.10

Rectangle {
    id: root
    anchors.fill: parent
    visible: false
    color: "#b3000000"
    z: 50

    property var controller: null
    property var keyboard: null

    // Tabs : "info" | "wifi" | "ethernet"
    property string tab: "info"

    // Data
    property var info: ({})
    property var wifiList: []
    property string errorMsg: ""
    property string statusMsg: ""
    property bool busy: false

    // Wifi form
    property string wifiSelectedSsid: ""
    property string wifiPassword: ""
    property string wifiMode: "dhcp"
    property string wifiIp: ""
    property string wifiPrefix: "24"
    property string wifiGw: ""
    property string wifiDns: ""

    // Ethernet form
    property string ethMode: "dhcp"
    property string ethIp: ""
    property string ethPrefix: "24"
    property string ethGw: ""
    property string ethDns: ""

    signal closed()

    function open() {
        visible = true
        tab = "info"
        errorMsg = ""; statusMsg = ""; busy = false
        wifiSelectedSsid = ""; wifiPassword = ""
        if (controller) controller.getNetworkInfo()
    }
    function close() {
        visible = false
        if (keyboard) keyboard.close()
        closed()
    }

    Connections {
        target: root.controller
        ignoreUnknownSignals: true
        onNetworkInfoLoaded: {
            root.info = info
            // pré-remplit le formulaire Ethernet à partir du mode détecté
            if (info.ethMode && info.ethMode.toLowerCase().indexOf("manual") >= 0)
                root.ethMode = "static"
        }
        onWifiNetworksLoaded: {
            root.wifiList = networks
            root.busy = false
        }
        onWifiConnectResult: {
            root.busy = false
            if (ok) {
                root.statusMsg = "Wi-Fi connecté."
                if (root.controller) root.controller.getNetworkInfo()
            } else {
                root.errorMsg = "Connexion Wi-Fi : " + msg
            }
        }
        onEthernetResult: {
            root.busy = false
            if (ok) {
                root.statusMsg = "Ethernet configuré."
                if (root.controller) root.controller.getNetworkInfo()
            } else {
                root.errorMsg = "Ethernet : " + msg
            }
        }
        onNetworkApiError: {
            root.busy = false
            root.errorMsg = op + ": " + msg
        }
    }

    MouseArea { anchors.fill: parent; onPressed: root.close() }

    // ── Card ────────────────────────────────────────────────────────────────
    Rectangle {
        anchors.centerIn: parent
        width:  parent.width  - 30
        height: parent.height - 60
        radius: 20
        color: "#0f172a"
        border.color: "#334155"

        MouseArea { anchors.fill: parent; onPressed: {} }

        // Header
        Rectangle {
            id: hdr
            anchors { top: parent.top; left: parent.left; right: parent.right }
            height: 60
            color: "transparent"

            Row {
                anchors { left: parent.left; leftMargin: 18; verticalCenter: parent.verticalCenter }
                spacing: 12
                Rectangle {
                    width: 36; height: 36; radius: 8
                    color: "#60a5fa33"
                    Text { anchors.centerIn: parent; text: "📡"; font.pixelSize: 16 }
                }
                Column {
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 2
                    Text { text: "Configuration Réseau"; color: "white"; font.pixelSize: 15; font.weight: Font.Bold }
                    Text { text: "Wi-Fi / Ethernet"; color: "#64748b"; font.pixelSize: 10 }
                }
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

        // Tabs
        Row {
            id: tabs
            anchors { top: hdr.bottom; left: parent.left; leftMargin: 8; right: parent.right }
            height: 40
            spacing: 0

            Repeater {
                model: [
                    {id: "info",     label: "Infos"},
                    {id: "wifi",     label: "Wi-Fi"},
                    {id: "ethernet", label: "Ethernet"},
                ]
                Rectangle {
                    width: (tabs.width - 16) / 3
                    height: tabs.height
                    color: "transparent"
                    Text {
                        anchors.centerIn: parent
                        text: modelData.label
                        color: root.tab === modelData.id ? "#60a5fa" : "#64748b"
                        font.pixelSize: 12; font.weight: Font.DemiBold
                    }
                    Rectangle {
                        anchors { bottom: parent.bottom; left: parent.left; right: parent.right }
                        height: 2
                        color: root.tab === modelData.id ? "#3b82f6" : "transparent"
                    }
                    MouseArea {
                        anchors.fill: parent
                        onPressed: {
                            root.tab = modelData.id
                            root.errorMsg = ""; root.statusMsg = ""
                            if (modelData.id === "wifi" && root.wifiList.length === 0) {
                                root.busy = true
                                root.controller.scanWifi()
                            }
                        }
                    }
                }
            }
        }

        Rectangle {
            anchors { top: tabs.bottom; left: parent.left; right: parent.right }
            height: 1; color: "#1e293b"
        }

        // Banners
        Column {
            id: banners
            anchors { top: tabs.bottom; left: parent.left; right: parent.right; topMargin: 10; leftMargin: 12; rightMargin: 12 }
            spacing: 6
            Rectangle {
                width: parent.width
                visible: root.errorMsg.length > 0
                height: visible ? errLbl.implicitHeight + 14 : 0
                radius: 8; color: "#7f1d1d33"; border.color: "#7f1d1d"
                Text {
                    id: errLbl
                    anchors { fill: parent; margins: 7 }
                    text: root.errorMsg; color: "#fca5a5"; font.pixelSize: 11
                    wrapMode: Text.WordWrap
                }
            }
            Rectangle {
                width: parent.width
                visible: root.statusMsg.length > 0
                height: visible ? okLbl.implicitHeight + 14 : 0
                radius: 8; color: "#14532d33"; border.color: "#16a34a"
                Text {
                    id: okLbl
                    anchors { fill: parent; margins: 7 }
                    text: root.statusMsg; color: "#86efac"; font.pixelSize: 11
                    wrapMode: Text.WordWrap
                }
            }
        }

        // ─────────── Onglet INFO ────────────────────────────────────────────
        Flickable {
            visible: root.tab === "info"
            anchors {
                top: banners.bottom; left: parent.left; right: parent.right; bottom: footer.top
                topMargin: 10; leftMargin: 14; rightMargin: 14; bottomMargin: 8
            }
            contentHeight: infoCol.implicitHeight
            clip: true

            Column {
                id: infoCol
                width: parent.width
                spacing: 10

                // Hostname
                Rectangle {
                    width: parent.width; height: 50; radius: 10
                    color: "#1e293b"; border.color: "#334155"
                    Column {
                        anchors { fill: parent; leftMargin: 14; topMargin: 8 }
                        Text { text: "Hostname"; color: "#64748b"; font.pixelSize: 10 }
                        Text { text: root.info.hostname || "—"; color: "white"; font.pixelSize: 13; font.weight: Font.DemiBold }
                    }
                }

                // Wi-Fi
                Rectangle {
                    width: parent.width
                    height: wifiInfoCol.implicitHeight + 20
                    radius: 10; color: "#1e293b"; border.color: "#334155"
                    Column {
                        id: wifiInfoCol
                        anchors { fill: parent; margins: 14 }
                        spacing: 6
                        Row {
                            spacing: 8
                            Text { text: "📶"; font.pixelSize: 14 }
                            Text { text: "Wi-Fi"; color: "white"; font.pixelSize: 13; font.weight: Font.Bold }
                        }
                        Text { text: "Interface : " + (root.info.wifiIface || "—"); color: "#cbd5e1"; font.pixelSize: 11 }
                        Text { text: "SSID : " + (root.info.wifiSsid || "Non connecté"); color: "#cbd5e1"; font.pixelSize: 11 }
                        Text { text: "IP : " + (root.info.wifiIp || "—"); color: "#cbd5e1"; font.pixelSize: 11 }
                        Text { text: "MAC : " + (root.info.wifiMac || "—"); color: "#64748b"; font.pixelSize: 10 }
                        Text { text: "Mode : " + (root.info.wifiMode || "—"); color: "#64748b"; font.pixelSize: 10 }
                    }
                }

                // Ethernet
                Rectangle {
                    width: parent.width
                    height: ethInfoCol.implicitHeight + 20
                    radius: 10; color: "#1e293b"; border.color: "#334155"
                    Column {
                        id: ethInfoCol
                        anchors { fill: parent; margins: 14 }
                        spacing: 6
                        Row {
                            spacing: 8
                            Text { text: "🔌"; font.pixelSize: 14 }
                            Text { text: "Ethernet"; color: "white"; font.pixelSize: 13; font.weight: Font.Bold }
                        }
                        Text { text: "Interface : " + (root.info.ethIface || "—"); color: "#cbd5e1"; font.pixelSize: 11 }
                        Text { text: "IP : " + (root.info.ethIp || "—"); color: "#cbd5e1"; font.pixelSize: 11 }
                        Text { text: "MAC : " + (root.info.ethMac || "—"); color: "#64748b"; font.pixelSize: 10 }
                        Text { text: "Mode : " + (root.info.ethMode || "—"); color: "#64748b"; font.pixelSize: 10 }
                    }
                }
            }
        }

        // ─────────── Onglet WI-FI ───────────────────────────────────────────
        Item {
            visible: root.tab === "wifi"
            anchors {
                top: banners.bottom; left: parent.left; right: parent.right; bottom: footer.top
                topMargin: 10; leftMargin: 14; rightMargin: 14; bottomMargin: 8
            }

            // Liste des SSID (si aucun selectionné)
            Column {
                visible: root.wifiSelectedSsid === ""
                anchors.fill: parent
                spacing: 8

                Row {
                    width: parent.width
                    Text {
                        text: root.busy ? "Scan en cours…" : "Réseaux détectés"
                        color: "#cbd5e1"; font.pixelSize: 12
                        anchors.verticalCenter: parent.verticalCenter
                    }
                    Item { width: parent.width - parent.children[0].width - scanBtn.width - 8; height: 1 }
                    Rectangle {
                        id: scanBtn
                        width: 80; height: 28; radius: 6
                        color: "#1e293b"; border.color: "#334155"
                        Text { anchors.centerIn: parent; text: "Rescan"; color: "#cbd5e1"; font.pixelSize: 11 }
                        MouseArea {
                            anchors.fill: parent
                            onPressed: {
                                root.errorMsg = ""; root.statusMsg = ""
                                root.busy = true
                                root.controller.scanWifi()
                            }
                        }
                    }
                }

                ListView {
                    clip: true
                    width: parent.width
                    height: parent.height - y
                    model: root.wifiList
                    spacing: 6
                    delegate: Rectangle {
                        width: ListView.view.width; height: 48; radius: 8
                        color: "#1e293b"; border.color: "#334155"
                        Row {
                            anchors { left: parent.left; leftMargin: 12; verticalCenter: parent.verticalCenter }
                            spacing: 10
                            Text {
                                text: modelData.signal >= 70 ? "▮▮▮▮"
                                    : modelData.signal >= 50 ? "▮▮▮▯"
                                    : modelData.signal >= 30 ? "▮▮▯▯"
                                    :                          "▮▯▯▯"
                                color: "#60a5fa"; font.pixelSize: 11
                                anchors.verticalCenter: parent.verticalCenter
                            }
                            Column {
                                anchors.verticalCenter: parent.verticalCenter
                                spacing: 2
                                Text { text: modelData.ssid; color: "white"; font.pixelSize: 12; font.weight: Font.DemiBold }
                                Text {
                                    text: (modelData.security || "Ouvert") + " — " + modelData.signal + "%"
                                    color: "#64748b"; font.pixelSize: 10
                                }
                            }
                        }
                        MouseArea {
                            anchors.fill: parent
                            onPressed: {
                                root.wifiSelectedSsid = modelData.ssid
                                root.wifiPassword = ""
                                root.wifiMode = "dhcp"
                            }
                        }
                    }
                }
            }

            // Formulaire de connexion (après sélection SSID)
            Column {
                visible: root.wifiSelectedSsid !== ""
                anchors.fill: parent
                spacing: 10

                Row {
                    spacing: 8
                    Rectangle {
                        width: 28; height: 28; radius: 6
                        color: "#1e293b"
                        Text { anchors.centerIn: parent; text: "←"; color: "#cbd5e1"; font.pixelSize: 14 }
                        MouseArea { anchors.fill: parent; onPressed: root.wifiSelectedSsid = "" }
                    }
                    Text {
                        text: root.wifiSelectedSsid; color: "white"; font.pixelSize: 14; font.weight: Font.Bold
                        anchors.verticalCenter: parent.verticalCenter
                    }
                }

                Text { text: "Mot de passe"; color: "#cbd5e1"; font.pixelSize: 11 }
                KbInput {
                    id: wifiPwInput
                    width: parent.width
                    keyboard: root.keyboard
                    isPassword: true
                    placeholder: "••••••••"
                    onTextChanged: root.wifiPassword = text
                }

                Text { text: "Mode"; color: "#cbd5e1"; font.pixelSize: 11 }
                Row {
                    spacing: 8
                    Repeater {
                        model: [{id:"dhcp", lbl:"DHCP"}, {id:"static", lbl:"Statique"}]
                        Rectangle {
                            width: 100; height: 32; radius: 8
                            color: root.wifiMode === modelData.id ? "#2563eb" : "#1e293b"
                            border.color: root.wifiMode === modelData.id ? "#3b82f6" : "#334155"
                            Text {
                                anchors.centerIn: parent; text: modelData.lbl
                                color: root.wifiMode === modelData.id ? "white" : "#94a3b8"
                                font.pixelSize: 11; font.weight: Font.DemiBold
                            }
                            MouseArea { anchors.fill: parent; onPressed: root.wifiMode = modelData.id }
                        }
                    }
                }

                // Champs statiques
                Column {
                    visible: root.wifiMode === "static"
                    width: parent.width
                    spacing: 6
                    Text { text: "IP"; color: "#cbd5e1"; font.pixelSize: 10 }
                    KbInput { width: parent.width; keyboard: root.keyboard; placeholder: "192.168.1.50"
                              onTextChanged: root.wifiIp = text }
                    Text { text: "Préfixe"; color: "#cbd5e1"; font.pixelSize: 10 }
                    KbInput { width: parent.width; keyboard: root.keyboard; placeholder: "24"
                              onTextChanged: root.wifiPrefix = text }
                    Text { text: "Gateway"; color: "#cbd5e1"; font.pixelSize: 10 }
                    KbInput { width: parent.width; keyboard: root.keyboard; placeholder: "192.168.1.1"
                              onTextChanged: root.wifiGw = text }
                    Text { text: "DNS"; color: "#cbd5e1"; font.pixelSize: 10 }
                    KbInput { width: parent.width; keyboard: root.keyboard; placeholder: "8.8.8.8"
                              onTextChanged: root.wifiDns = text }
                }

                Rectangle {
                    width: parent.width; height: 40; radius: 10
                    color: root.busy ? "#1e293b" : "#2563eb"
                    opacity: root.busy ? 0.5 : 1
                    Text {
                        anchors.centerIn: parent
                        text: root.busy ? "Connexion…" : "Connecter"
                        color: "white"; font.pixelSize: 12; font.weight: Font.Bold
                    }
                    MouseArea {
                        anchors.fill: parent
                        enabled: !root.busy
                        onPressed: {
                            root.errorMsg = ""; root.statusMsg = ""; root.busy = true
                            if (root.keyboard) root.keyboard.close()
                            root.controller.connectWifi(
                                root.wifiSelectedSsid, root.wifiPassword, root.wifiMode,
                                root.wifiIp, root.wifiPrefix, root.wifiGw, root.wifiDns)
                        }
                    }
                }
            }
        }

        // ─────────── Onglet ETHERNET ────────────────────────────────────────
        Column {
            visible: root.tab === "ethernet"
            anchors {
                top: banners.bottom; left: parent.left; right: parent.right; bottom: footer.top
                topMargin: 10; leftMargin: 14; rightMargin: 14; bottomMargin: 8
            }
            spacing: 10

            Text { text: "Mode"; color: "#cbd5e1"; font.pixelSize: 11 }
            Row {
                spacing: 8
                Repeater {
                    model: [{id:"dhcp", lbl:"DHCP"}, {id:"static", lbl:"Statique"}]
                    Rectangle {
                        width: 100; height: 32; radius: 8
                        color: root.ethMode === modelData.id ? "#2563eb" : "#1e293b"
                        border.color: root.ethMode === modelData.id ? "#3b82f6" : "#334155"
                        Text {
                            anchors.centerIn: parent; text: modelData.lbl
                            color: root.ethMode === modelData.id ? "white" : "#94a3b8"
                            font.pixelSize: 11; font.weight: Font.DemiBold
                        }
                        MouseArea { anchors.fill: parent; onPressed: root.ethMode = modelData.id }
                    }
                }
            }

            Column {
                visible: root.ethMode === "static"
                width: parent.width
                spacing: 6
                Text { text: "IP"; color: "#cbd5e1"; font.pixelSize: 10 }
                KbInput { width: parent.width; keyboard: root.keyboard; placeholder: "192.168.10.132"
                          onTextChanged: root.ethIp = text }
                Text { text: "Préfixe"; color: "#cbd5e1"; font.pixelSize: 10 }
                KbInput { width: parent.width; keyboard: root.keyboard; placeholder: "24"
                          onTextChanged: root.ethPrefix = text }
                Text { text: "Gateway"; color: "#cbd5e1"; font.pixelSize: 10 }
                KbInput { width: parent.width; keyboard: root.keyboard; placeholder: "192.168.10.1"
                          onTextChanged: root.ethGw = text }
                Text { text: "DNS"; color: "#cbd5e1"; font.pixelSize: 10 }
                KbInput { width: parent.width; keyboard: root.keyboard; placeholder: "8.8.8.8"
                          onTextChanged: root.ethDns = text }
            }

            Item { width: 1; height: 6 }

            Rectangle {
                width: parent.width; height: 40; radius: 10
                color: root.busy ? "#1e293b" : "#2563eb"
                opacity: root.busy ? 0.5 : 1
                Text {
                    anchors.centerIn: parent
                    text: root.busy ? "Application…" : "Appliquer"
                    color: "white"; font.pixelSize: 12; font.weight: Font.Bold
                }
                MouseArea {
                    anchors.fill: parent
                    enabled: !root.busy
                    onPressed: {
                        root.errorMsg = ""; root.statusMsg = ""; root.busy = true
                        if (root.keyboard) root.keyboard.close()
                        root.controller.setEthernet(
                            root.ethMode, root.ethIp, root.ethPrefix, root.ethGw, root.ethDns)
                    }
                }
            }
        }

        // Footer
        Rectangle {
            id: footer
            anchors { bottom: parent.bottom; left: parent.left; right: parent.right }
            height: 52
            color: "transparent"

            Rectangle {
                anchors { top: parent.top; left: parent.left; right: parent.right }
                height: 1; color: "#1e293b"
            }

            Rectangle {
                anchors.centerIn: parent
                width: 120; height: 36; radius: 10
                color: "#1e293b"; border.color: "#475569"
                Text { anchors.centerIn: parent; text: "Fermer"; color: "#94a3b8"; font.pixelSize: 12 }
                MouseArea { anchors.fill: parent; onPressed: root.close() }
            }
        }
    }
}
