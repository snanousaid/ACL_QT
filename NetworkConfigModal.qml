import QtQuick 2.10

Rectangle {
    id: root
    anchors.fill: parent
    visible: false
    color: "#b3000000"
    z: 50

    property var controller: null
    property var keyboard: null

    property string tab: "info"   // "info" | "wifi" | "ethernet"

    property var info: ({})
    property var wifiList: []
    property string errorMsg: ""
    property string statusMsg: ""
    property bool busy: false

    // Wi-Fi form
    property string wifiSelectedSsid: ""
    property string wifiSelectedSecurity: ""
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
        wifiSelectedSsid = ""; wifiSelectedSecurity = ""; wifiPassword = ""
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
            if (info.ethMode && String(info.ethMode).toLowerCase().indexOf("manual") >= 0)
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
                root.wifiSelectedSsid = ""
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

    // ── Carte ───────────────────────────────────────────────────────────────
    Rectangle {
        anchors.centerIn: parent
        width:  parent.width  - 24
        height: parent.height - 40
        radius: 20
        color: "#0f172a"
        border.color: "#334155"

        MouseArea { anchors.fill: parent; onPressed: {} }

        // ─── Header ─────────────────────────────────────────────────────────
        Rectangle {
            id: hdr
            anchors { top: parent.top; left: parent.left; right: parent.right }
            height: 58
            color: "transparent"

            Row {
                anchors { left: parent.left; leftMargin: 18; verticalCenter: parent.verticalCenter }
                spacing: 12
                Rectangle {
                    width: 36; height: 36; radius: 10
                    color: "#3b82f620"
                    Rectangle {
                        anchors.centerIn: parent
                        width: 14; height: 14; radius: 7
                        color: "#3b82f6"
                    }
                }
                Column {
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 2
                    Text { text: "Configuration Réseau"; color: "white"; font.pixelSize: 15; font.weight: Font.Bold }
                    Text { text: "Infos et configuration"; color: "#64748b"; font.pixelSize: 10 }
                }
            }
            Rectangle {
                anchors { right: parent.right; rightMargin: 14; verticalCenter: parent.verticalCenter }
                width: 34; height: 34; radius: 17
                color: "#1e293b"
                Text { anchors.centerIn: parent; text: "✕"; color: "#cbd5e1"; font.pixelSize: 14 }
                MouseArea { anchors.fill: parent; onPressed: root.close() }
            }
            Rectangle { anchors { bottom: parent.bottom; left: parent.left; right: parent.right }
                        height: 1; color: "#1e293b" }
        }

        // ─── Onglets ────────────────────────────────────────────────────────
        Row {
            id: tabs
            anchors { top: hdr.bottom; left: parent.left; leftMargin: 6; right: parent.right; rightMargin: 6 }
            height: 42
            spacing: 0

            Repeater {
                model: [
                    {id: "info",     label: "Infos"},
                    {id: "wifi",     label: "Wi-Fi"},
                    {id: "ethernet", label: "Ethernet"},
                ]
                Rectangle {
                    width: (tabs.width) / 3
                    height: tabs.height
                    color: "transparent"
                    Text {
                        anchors.centerIn: parent
                        text: modelData.label
                        color: root.tab === modelData.id ? "#60a5fa" : "#64748b"
                        font.pixelSize: 12
                        font.weight: root.tab === modelData.id ? Font.Bold : Font.Medium
                    }
                    Rectangle {
                        anchors { bottom: parent.bottom; left: parent.left; right: parent.right; leftMargin: 16; rightMargin: 16 }
                        height: 2; radius: 1
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
        Rectangle { anchors { top: tabs.bottom; left: parent.left; right: parent.right }
                    height: 1; color: "#1e293b" }

        // ─── Bannières erreur / succès ──────────────────────────────────────
        Column {
            id: banners
            anchors { top: tabs.bottom; left: parent.left; right: parent.right
                      topMargin: 8; leftMargin: 12; rightMargin: 12 }
            spacing: 6

            Rectangle {
                width: parent.width
                visible: root.errorMsg.length > 0
                height: visible ? errLbl.implicitHeight + 14 : 0
                radius: 8; color: "#7f1d1d33"; border.color: "#7f1d1d"
                Text { id: errLbl
                    anchors { fill: parent; margins: 7 }
                    text: root.errorMsg; color: "#fca5a5"; font.pixelSize: 11; wrapMode: Text.WordWrap
                }
            }
            Rectangle {
                width: parent.width
                visible: root.statusMsg.length > 0
                height: visible ? okLbl.implicitHeight + 14 : 0
                radius: 8; color: "#14532d33"; border.color: "#16a34a"
                Text { id: okLbl
                    anchors { fill: parent; margins: 7 }
                    text: root.statusMsg; color: "#86efac"; font.pixelSize: 11; wrapMode: Text.WordWrap
                }
            }
        }

        // ═══════════════════════ Onglet INFO ════════════════════════════════
        Flickable {
            id: infoView
            visible: root.tab === "info"
            anchors {
                top: banners.bottom; left: parent.left; right: parent.right; bottom: footer.top
                topMargin: 10; leftMargin: 14; rightMargin: 14; bottomMargin: 10
            }
            contentHeight: infoCol.implicitHeight
            clip: true
            boundsBehavior: Flickable.StopAtBounds

            Column {
                id: infoCol
                width: parent.width
                spacing: 10

                // Hostname
                Rectangle {
                    width: parent.width; height: 54; radius: 12
                    color: "#1e293b"; border.color: "#334155"
                    Column {
                        anchors { fill: parent; leftMargin: 14; topMargin: 9 }
                        spacing: 2
                        Text { text: "Hostname"; color: "#64748b"; font.pixelSize: 10; font.letterSpacing: 1 }
                        Text {
                            text: root.info.hostname || "—"
                            color: "white"; font.pixelSize: 14; font.weight: Font.DemiBold
                        }
                    }
                }

                // Bloc Wi-Fi
                Rectangle {
                    width: parent.width
                    height: wifiInfoCol.implicitHeight + 24
                    radius: 12; color: "#1e293b"; border.color: "#334155"
                    Column {
                        id: wifiInfoCol
                        anchors { fill: parent; margins: 14 }
                        spacing: 8

                        Row {
                            spacing: 10
                            Rectangle {
                                width: 24; height: 24; radius: 6
                                color: "#60a5fa20"
                                Rectangle { anchors.centerIn: parent; width: 8; height: 8; radius: 4; color: "#60a5fa" }
                            }
                            Text { text: "Wi-Fi"; color: "white"; font.pixelSize: 13; font.weight: Font.Bold
                                   anchors.verticalCenter: parent.verticalCenter }
                        }
                        KvRow { k: "Interface"; v: root.info.wifiIface || "—" }
                        KvRow { k: "SSID";      v: root.info.wifiSsid || "Non connecté" }
                        KvRow { k: "Adresse IP";v: root.info.wifiIp || "—" }
                        KvRow { k: "MAC";       v: root.info.wifiMac || "—"; dim: true }
                        KvRow { k: "Mode";      v: root.info.wifiMode || "—"; dim: true }
                    }
                }

                // Bloc Ethernet
                Rectangle {
                    width: parent.width
                    height: ethInfoCol.implicitHeight + 24
                    radius: 12; color: "#1e293b"; border.color: "#334155"
                    Column {
                        id: ethInfoCol
                        anchors { fill: parent; margins: 14 }
                        spacing: 8

                        Row {
                            spacing: 10
                            Rectangle {
                                width: 24; height: 24; radius: 6
                                color: "#22c55e20"
                                Rectangle { anchors.centerIn: parent; width: 10; height: 6; radius: 1; color: "#22c55e" }
                            }
                            Text { text: "Ethernet"; color: "white"; font.pixelSize: 13; font.weight: Font.Bold
                                   anchors.verticalCenter: parent.verticalCenter }
                        }
                        KvRow { k: "Interface"; v: root.info.ethIface || "—" }
                        KvRow { k: "Adresse IP";v: root.info.ethIp || "—" }
                        KvRow { k: "MAC";       v: root.info.ethMac || "—"; dim: true }
                        KvRow { k: "Mode";      v: root.info.ethMode || "—"; dim: true }
                    }
                }
            }
        }

        // ═══════════════════════ Onglet WI-FI ═══════════════════════════════
        Item {
            id: wifiView
            visible: root.tab === "wifi"
            anchors {
                top: banners.bottom; left: parent.left; right: parent.right; bottom: footer.top
                topMargin: 10; leftMargin: 14; rightMargin: 14; bottomMargin: 10
            }

            // En-tête + bouton Rescan
            Row {
                id: wifiHeaderRow
                anchors { top: parent.top; left: parent.left; right: parent.right }
                height: 30
                Text {
                    text: root.busy && root.wifiList.length === 0 ? "Scan…" : "Réseaux détectés"
                    color: "#cbd5e1"; font.pixelSize: 12; font.weight: Font.DemiBold
                    anchors.verticalCenter: parent.verticalCenter
                }
                Item { width: parent.width - parent.children[0].width - rescanBtn.width - 6; height: 1 }
                Rectangle {
                    id: rescanBtn
                    width: 76; height: 28; radius: 8
                    color: "#1e293b"; border.color: "#334155"
                    anchors.verticalCenter: parent.verticalCenter
                    Text { anchors.centerIn: parent; text: "Rescan"; color: "#cbd5e1"; font.pixelSize: 11 }
                    MouseArea {
                        anchors.fill: parent
                        enabled: !root.busy
                        onPressed: {
                            root.errorMsg = ""; root.statusMsg = ""
                            root.busy = true
                            root.controller.scanWifi()
                        }
                    }
                }
            }

            // ── Liste SSID (hauteur max 5 items ~ 260, au-delà scroll) ──────
            Rectangle {
                id: wifiListBox
                anchors { top: wifiHeaderRow.bottom; left: parent.left; right: parent.right; topMargin: 8 }
                height: Math.min(5 * 52, Math.max(1, root.wifiList.length) * 52)
                radius: 10
                color: "#0b1220"; border.color: "#1e293b"
                clip: true

                Text {
                    anchors.centerIn: parent
                    visible: root.wifiList.length === 0 && !root.busy
                    text: "Aucun réseau"
                    color: "#64748b"; font.pixelSize: 11
                }

                ListView {
                    id: wifiListView
                    anchors.fill: parent
                    anchors.margins: 4
                    model: root.wifiList
                    spacing: 4
                    clip: true
                    boundsBehavior: Flickable.StopAtBounds

                    delegate: Rectangle {
                        width: wifiListView.width
                        height: 44; radius: 8
                        color: root.wifiSelectedSsid === modelData.ssid ? "#1e3a8a" : "#1e293b"
                        border.color: root.wifiSelectedSsid === modelData.ssid ? "#3b82f6" : "transparent"

                        Row {
                            anchors { left: parent.left; leftMargin: 12; verticalCenter: parent.verticalCenter }
                            spacing: 10
                            // Barres signal
                            Row {
                                spacing: 2
                                anchors.verticalCenter: parent.verticalCenter
                                Rectangle { width: 3; height: 6;  radius: 1
                                    color: modelData.signal >= 20 ? "#60a5fa" : "#334155" }
                                Rectangle { width: 3; height: 10; radius: 1
                                    color: modelData.signal >= 40 ? "#60a5fa" : "#334155" }
                                Rectangle { width: 3; height: 14; radius: 1
                                    color: modelData.signal >= 60 ? "#60a5fa" : "#334155" }
                                Rectangle { width: 3; height: 18; radius: 1
                                    color: modelData.signal >= 80 ? "#60a5fa" : "#334155" }
                            }
                            Column {
                                anchors.verticalCenter: parent.verticalCenter
                                spacing: 1
                                Text { text: modelData.ssid; color: "white"; font.pixelSize: 12; font.weight: Font.DemiBold }
                                Text {
                                    text: (modelData.security && modelData.security.length > 0 ? modelData.security : "Ouvert")
                                        + "  •  " + modelData.signal + "%"
                                    color: "#64748b"; font.pixelSize: 10
                                }
                            }
                        }

                        // Indicateur sélection
                        Rectangle {
                            visible: root.wifiSelectedSsid === modelData.ssid
                            anchors { right: parent.right; rightMargin: 10; verticalCenter: parent.verticalCenter }
                            width: 8; height: 8; radius: 4
                            color: "#3b82f6"
                        }

                        MouseArea {
                            anchors.fill: parent
                            onPressed: {
                                root.wifiSelectedSsid = modelData.ssid
                                root.wifiSelectedSecurity = modelData.security || ""
                                root.wifiPassword = ""
                                if (typeof wifiPwInput !== "undefined") wifiPwInput.text = ""
                            }
                        }
                    }
                }
            }

            // ── Formulaire connexion (sous la liste, toujours visible) ──────
            Flickable {
                anchors { top: wifiListBox.bottom; left: parent.left; right: parent.right; bottom: connectBtn.top
                          topMargin: 12; bottomMargin: 8 }
                contentHeight: wifiForm.implicitHeight
                clip: true
                boundsBehavior: Flickable.StopAtBounds

                Column {
                    id: wifiForm
                    width: parent.width
                    spacing: 8
                    opacity: root.wifiSelectedSsid === "" ? 0.5 : 1

                    Row {
                        spacing: 8
                        Text {
                            text: root.wifiSelectedSsid === "" ? "Sélectionnez un réseau" : "Connexion à "
                            color: "#94a3b8"; font.pixelSize: 11
                            anchors.verticalCenter: parent.verticalCenter
                        }
                        Text {
                            visible: root.wifiSelectedSsid !== ""
                            text: root.wifiSelectedSsid
                            color: "white"; font.pixelSize: 12; font.weight: Font.Bold
                            anchors.verticalCenter: parent.verticalCenter
                        }
                    }

                    Text { text: "Mot de passe"; color: "#cbd5e1"; font.pixelSize: 10 }
                    KbInput {
                        id: wifiPwInput
                        width: parent.width
                        keyboard: root.keyboard
                        isPassword: true
                        placeholder: "••••••••"
                        onTextChanged: root.wifiPassword = text
                    }

                    Text { text: "Attribution IP"; color: "#cbd5e1"; font.pixelSize: 10 }
                    Row {
                        spacing: 6
                        Repeater {
                            model: [{id:"dhcp", lbl:"DHCP"}, {id:"static", lbl:"Statique"}]
                            Rectangle {
                                width: 88; height: 30; radius: 8
                                color: root.wifiMode === modelData.id ? "#2563eb" : "#1e293b"
                                border.color: root.wifiMode === modelData.id ? "#3b82f6" : "#334155"
                                Text { anchors.centerIn: parent; text: modelData.lbl
                                       color: root.wifiMode === modelData.id ? "white" : "#94a3b8"
                                       font.pixelSize: 11; font.weight: Font.DemiBold }
                                MouseArea { anchors.fill: parent; onPressed: root.wifiMode = modelData.id }
                            }
                        }
                    }

                    Column {
                        visible: root.wifiMode === "static"
                        width: parent.width
                        spacing: 6
                        Row {
                            width: parent.width; spacing: 6
                            Column {
                                width: (parent.width - 6) / 2; spacing: 3
                                Text { text: "IP"; color: "#94a3b8"; font.pixelSize: 10 }
                                KbInput { width: parent.width; keyboard: root.keyboard; placeholder: "192.168.1.50"
                                          onTextChanged: root.wifiIp = text }
                            }
                            Column {
                                width: (parent.width - 6) / 2; spacing: 3
                                Text { text: "Préfixe"; color: "#94a3b8"; font.pixelSize: 10 }
                                KbInput { width: parent.width; keyboard: root.keyboard; placeholder: "24"
                                          onTextChanged: root.wifiPrefix = text }
                            }
                        }
                        Text { text: "Gateway"; color: "#94a3b8"; font.pixelSize: 10 }
                        KbInput { width: parent.width; keyboard: root.keyboard; placeholder: "192.168.1.1"
                                  onTextChanged: root.wifiGw = text }
                        Text { text: "DNS"; color: "#94a3b8"; font.pixelSize: 10 }
                        KbInput { width: parent.width; keyboard: root.keyboard; placeholder: "8.8.8.8"
                                  onTextChanged: root.wifiDns = text }
                    }
                }
            }

            // ── Bouton Connecter (toujours en bas) ──────────────────────────
            Rectangle {
                id: connectBtn
                anchors { bottom: parent.bottom; left: parent.left; right: parent.right }
                height: 42; radius: 10
                color: (root.wifiSelectedSsid === "" || root.busy) ? "#1e293b" : "#2563eb"
                opacity: (root.wifiSelectedSsid === "" || root.busy) ? 0.5 : 1
                Text {
                    anchors.centerIn: parent
                    text: root.busy ? "Connexion…" : "Connecter"
                    color: "white"; font.pixelSize: 13; font.weight: Font.Bold
                }
                MouseArea {
                    anchors.fill: parent
                    enabled: root.wifiSelectedSsid !== "" && !root.busy
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

        // ═══════════════════════ Onglet ETHERNET ════════════════════════════
        Flickable {
            id: ethView
            visible: root.tab === "ethernet"
            anchors {
                top: banners.bottom; left: parent.left; right: parent.right; bottom: footer.top
                topMargin: 10; leftMargin: 14; rightMargin: 14; bottomMargin: 10
            }
            contentHeight: ethForm.implicitHeight
            clip: true
            boundsBehavior: Flickable.StopAtBounds

            Column {
                id: ethForm
                width: parent.width
                spacing: 10

                Text { text: "Attribution IP"; color: "#cbd5e1"; font.pixelSize: 10 }
                Row {
                    spacing: 6
                    Repeater {
                        model: [{id:"dhcp", lbl:"DHCP"}, {id:"static", lbl:"Statique"}]
                        Rectangle {
                            width: 100; height: 30; radius: 8
                            color: root.ethMode === modelData.id ? "#2563eb" : "#1e293b"
                            border.color: root.ethMode === modelData.id ? "#3b82f6" : "#334155"
                            Text { anchors.centerIn: parent; text: modelData.lbl
                                   color: root.ethMode === modelData.id ? "white" : "#94a3b8"
                                   font.pixelSize: 11; font.weight: Font.DemiBold }
                            MouseArea { anchors.fill: parent; onPressed: root.ethMode = modelData.id }
                        }
                    }
                }

                Column {
                    visible: root.ethMode === "static"
                    width: parent.width
                    spacing: 8
                    Row {
                        width: parent.width; spacing: 6
                        Column {
                            width: (parent.width - 6) / 2; spacing: 3
                            Text { text: "IP"; color: "#94a3b8"; font.pixelSize: 10 }
                            KbInput { width: parent.width; keyboard: root.keyboard; placeholder: "192.168.10.132"
                                      onTextChanged: root.ethIp = text }
                        }
                        Column {
                            width: (parent.width - 6) / 2; spacing: 3
                            Text { text: "Préfixe"; color: "#94a3b8"; font.pixelSize: 10 }
                            KbInput { width: parent.width; keyboard: root.keyboard; placeholder: "24"
                                      onTextChanged: root.ethPrefix = text }
                        }
                    }
                    Text { text: "Gateway"; color: "#94a3b8"; font.pixelSize: 10 }
                    KbInput { width: parent.width; keyboard: root.keyboard; placeholder: "192.168.10.1"
                              onTextChanged: root.ethGw = text }
                    Text { text: "DNS"; color: "#94a3b8"; font.pixelSize: 10 }
                    KbInput { width: parent.width; keyboard: root.keyboard; placeholder: "8.8.8.8"
                              onTextChanged: root.ethDns = text }
                }

                Item { width: 1; height: 6 }

                Rectangle {
                    width: parent.width; height: 42; radius: 10
                    color: root.busy ? "#1e293b" : "#2563eb"
                    opacity: root.busy ? 0.5 : 1
                    Text {
                        anchors.centerIn: parent
                        text: root.busy ? "Application…" : "Appliquer"
                        color: "white"; font.pixelSize: 13; font.weight: Font.Bold
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
        }

        // ─── Footer ─────────────────────────────────────────────────────────
        Rectangle {
            id: footer
            anchors { bottom: parent.bottom; left: parent.left; right: parent.right }
            height: 52
            color: "transparent"

            Rectangle { anchors { top: parent.top; left: parent.left; right: parent.right }
                        height: 1; color: "#1e293b" }

            Rectangle {
                anchors.centerIn: parent
                width: 140; height: 34; radius: 10
                color: "#1e293b"; border.color: "#475569"
                Text { anchors.centerIn: parent; text: "Fermer"; color: "#cbd5e1"; font.pixelSize: 12 }
                MouseArea { anchors.fill: parent; onPressed: root.close() }
            }
        }
    }

    // ─── Composant inline pour les lignes clé: valeur dans l'onglet Infos ──
    component KvRow: Row {
        property string k: ""
        property string v: ""
        property bool dim: false
        spacing: 8
        Text { text: parent.k; color: "#64748b"; font.pixelSize: 11; width: 90 }
        Text {
            text: parent.v
            color: parent.dim ? "#94a3b8" : "#cbd5e1"
            font.pixelSize: 11
            font.family: parent.dim ? "monospace" : "sans-serif"
        }
    }
}
