import QtQuick 2.10
import QtQuick.Controls 2.5

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

    // Backdrop : absorbe les taps → ne ferme pas le modal sur tap arrière-plan
    MouseArea { anchors.fill: parent; onClicked: {} }

    // ── Carte ───────────────────────────────────────────────────────────────
    Rectangle {
        id: card
        anchors.centerIn: parent
        width:  parent.width  - 24
        height: Qt.inputMethod.visible
                ? Math.min(parent.height - 40,
                           parent.height - Qt.inputMethod.keyboardRectangle.height - 24)
                : parent.height - 40
        Behavior on height { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }
        radius: 20
        color: "#0f172a"
        border.color: "#334155"

        MouseArea { anchors.fill: parent; onClicked: {} }

        // ─── Header ─────────────────────────────────────────────────────────
        Rectangle {
            id: hdr
            anchors { top: parent.top; left: parent.left; right: parent.right }
            height: 64
            color: "transparent"

            Row {
                anchors { left: parent.left; leftMargin: 18; verticalCenter: parent.verticalCenter }
                spacing: 12
                // Icône router (Canvas : 2 rectangles empilés stylisés)
                Rectangle {
                    width: 38; height: 38; radius: 10
                    color: "#3b82f620"
                    anchors.verticalCenter: parent.verticalCenter
                    Canvas {
                        anchors.fill: parent
                        onPaint: {
                            var ctx = getContext("2d")
                            ctx.clearRect(0, 0, width, height)
                            ctx.strokeStyle = "#60a5fa"
                            ctx.fillStyle   = "#60a5fa"
                            ctx.lineWidth   = 1.7
                            ctx.lineJoin    = "round"
                            // Rectangle haut (top router unit)
                            ctx.strokeRect(width*0.20, height*0.28, width*0.60, height*0.16)
                            // Rectangle bas
                            ctx.strokeRect(width*0.20, height*0.50, width*0.60, height*0.16)
                            // Antennes
                            ctx.beginPath()
                            ctx.moveTo(width*0.32, height*0.28); ctx.lineTo(width*0.32, height*0.18)
                            ctx.moveTo(width*0.50, height*0.28); ctx.lineTo(width*0.50, height*0.16)
                            ctx.moveTo(width*0.68, height*0.28); ctx.lineTo(width*0.68, height*0.18)
                            ctx.stroke()
                            // Voyants (LEDs)
                            ctx.beginPath(); ctx.arc(width*0.30, height*0.36, 1.5, 0, Math.PI*2); ctx.fill()
                            ctx.beginPath(); ctx.arc(width*0.30, height*0.58, 1.5, 0, Math.PI*2); ctx.fill()
                        }
                    }
                }
                Column {
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 2
                    Text { text: "Configuration Réseau"; color: "white"; font.pixelSize: 15; font.weight: Font.Bold }
                    Text { text: "Informations et configuration réseau"; color: "#64748b"; font.pixelSize: 10 }
                }
            }
            CloseIcon {
                anchors { right: parent.right; rightMargin: 14; verticalCenter: parent.verticalCenter }
                onClicked: root.close()
            }
            Rectangle { anchors { bottom: parent.bottom; left: parent.left; right: parent.right }
                        height: 1; color: "#1e293b" }
        }

        // ─── Onglets avec icônes ────────────────────────────────────────────
        Row {
            id: tabs
            anchors { top: hdr.bottom; left: parent.left; leftMargin: 6; right: parent.right; rightMargin: 6 }
            height: 44
            spacing: 0

            Repeater {
                model: [
                    {id: "info",     label: "Infos",    icon: "info"},
                    {id: "wifi",     label: "Wi-Fi",    icon: "wifi"},
                    {id: "ethernet", label: "Ethernet", icon: "ethernet"}
                ]
                AppButton {
                    id: tabBtn
                    width: tabs.width / 3
                    height: tabs.height
                    text: ""
                    property bool isActive: root.tab === modelData.id

                    background: Item {
                        // Underline en bas
                        Rectangle {
                            anchors { bottom: parent.bottom; left: parent.left; right: parent.right
                                      leftMargin: 16; rightMargin: 16 }
                            height: 2; radius: 1
                            color: tabBtn.isActive ? "#3b82f6" : "transparent"
                            Behavior on color { ColorAnimation { duration: 200 } }
                        }
                        // Léger fond pressed
                        Rectangle {
                            anchors.fill: parent
                            color: tabBtn.pressed ? "#1e293b" : "transparent"
                            opacity: 0.5
                        }
                    }

                    contentItem: Row {
                        spacing: 6

                        // Icône Canvas selon le tab
                        Canvas {
                            width: 14; height: 14
                            anchors.verticalCenter: parent.verticalCenter
                            property color col: tabBtn.isActive ? "#60a5fa" : "#64748b"
                            onColChanged: requestPaint()
                            Component.onCompleted: requestPaint()

                            onPaint: {
                                var ctx = getContext("2d")
                                ctx.clearRect(0, 0, width, height)
                                ctx.strokeStyle = col
                                ctx.fillStyle   = col
                                ctx.lineWidth   = 1.5
                                ctx.lineCap     = "round"

                                if (modelData.icon === "info") {
                                    ctx.beginPath(); ctx.arc(width/2, height/2, width*0.45, 0, Math.PI*2); ctx.stroke()
                                    ctx.beginPath(); ctx.arc(width/2, height*0.32, 1.2, 0, Math.PI*2); ctx.fill()
                                    ctx.beginPath(); ctx.moveTo(width/2, height*0.45); ctx.lineTo(width/2, height*0.75); ctx.stroke()
                                } else if (modelData.icon === "wifi") {
                                    var wcx = width/2, wcy = height*0.85
                                    ctx.beginPath(); ctx.arc(wcx, wcy, width*0.45, Math.PI*1.20, Math.PI*1.80); ctx.stroke()
                                    ctx.beginPath(); ctx.arc(wcx, wcy, width*0.28, Math.PI*1.20, Math.PI*1.80); ctx.stroke()
                                    ctx.beginPath(); ctx.arc(wcx, wcy, 1.5, 0, Math.PI*2); ctx.fill()
                                } else if (modelData.icon === "ethernet") {
                                    ctx.beginPath()
                                    ctx.moveTo(width*0.20, height*0.30)
                                    ctx.lineTo(width*0.80, height*0.30)
                                    ctx.lineTo(width*0.80, height*0.55)
                                    ctx.lineTo(width*0.68, height*0.75)
                                    ctx.lineTo(width*0.32, height*0.75)
                                    ctx.lineTo(width*0.20, height*0.55)
                                    ctx.closePath()
                                    ctx.stroke()
                                    for (var i = 0; i < 3; i++) {
                                        ctx.fillRect(width*(0.34 + i*0.12), height*0.42, 1, height*0.16)
                                    }
                                }
                            }
                        }

                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: modelData.label
                            color: tabBtn.isActive ? "#60a5fa" : "#64748b"
                            font.pixelSize: 12
                            font.weight: tabBtn.isActive ? Font.Bold : Font.Medium
                        }
                    }

                    onClicked: {
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
        Rectangle { anchors { top: tabs.bottom; left: parent.left; right: parent.right }
                    height: 1; color: "#1e293b" }

        // ─── Bannières erreur / succès (avec X pour fermer) ─────────────────
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
                    anchors { left: parent.left; right: errCloseBtn.left; verticalCenter: parent.verticalCenter
                              leftMargin: 9; rightMargin: 4 }
                    text: root.errorMsg; color: "#fca5a5"; font.pixelSize: 11; wrapMode: Text.WordWrap
                }
                Rectangle {
                    id: errCloseBtn
                    anchors { right: parent.right; verticalCenter: parent.verticalCenter; rightMargin: 6 }
                    width: 22; height: 22; radius: 11
                    color: errCloseMA.pressed ? "#7f1d1d" : "transparent"
                    Text { anchors.centerIn: parent; text: "×"; color: "#fca5a5"; font.pixelSize: 16; font.weight: Font.Bold }
                    MouseArea { id: errCloseMA; anchors.fill: parent; onClicked: root.errorMsg = "" }
                }
            }
            Rectangle {
                width: parent.width
                visible: root.statusMsg.length > 0
                height: visible ? okLbl.implicitHeight + 14 : 0
                radius: 8; color: "#14532d33"; border.color: "#16a34a"
                Text { id: okLbl
                    anchors { left: parent.left; right: okCloseBtn.left; verticalCenter: parent.verticalCenter
                              leftMargin: 9; rightMargin: 4 }
                    text: root.statusMsg; color: "#86efac"; font.pixelSize: 11; wrapMode: Text.WordWrap
                }
                Rectangle {
                    id: okCloseBtn
                    anchors { right: parent.right; verticalCenter: parent.verticalCenter; rightMargin: 6 }
                    width: 22; height: 22; radius: 11
                    color: okCloseMA.pressed ? "#14532d" : "transparent"
                    Text { anchors.centerIn: parent; text: "×"; color: "#86efac"; font.pixelSize: 16; font.weight: Font.Bold }
                    MouseArea { id: okCloseMA; anchors.fill: parent; onClicked: root.statusMsg = "" }
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
                InfoCard {
                    width: parent.width
                    iconType: "monitor"; iconColor: "#a78bfa"
                    label: "Hostname"
                    value: root.info.hostname || "—"
                    valueColor: "#c4b5fd"; valueMono: true
                }

                // Section header WI-FI
                Text {
                    text: "WI-FI"; color: "#475569"
                    font.pixelSize: 10; font.weight: Font.Bold; font.letterSpacing: 2
                    leftPadding: 4; topPadding: 8
                }

                // Wi-Fi interface (avec IP en valeur principale + badge IPv4)
                InfoCard {
                    width: parent.width
                    iconType: "wifi"; iconColor: "#60a5fa"
                    label: root.info.wifiInterface || root.info.wifiIface || "wlan"
                    value: (root.info.wifiIp && root.info.wifiIp.length > 0)
                           ? root.info.wifiIp
                           : "Non disponible"
                    valueColor: (root.info.wifiIp && root.info.wifiIp.length > 0)
                                ? "#22c55e" : "#f87171"
                    valueMono: true
                    badge: (root.info.wifiIp && root.info.wifiIp.length > 0) ? "IPv4" : ""
                }

                // SSID actuel (si connecté)
                InfoCard {
                    visible: !!root.info.wifiSsid && String(root.info.wifiSsid).length > 0
                    width: parent.width
                    iconType: "wifi"; iconColor: "#22c55e"
                    label: "SSID"
                    value: root.info.wifiSsid || "—"
                }

                // MAC Wi-Fi
                InfoCard {
                    width: parent.width
                    iconType: "mac"; iconColor: "#94a3b8"
                    label: "Adresse MAC"
                    value: root.info.wifiMac || "—"
                    valueColor: "#cbd5e1"; valueMono: true
                }

                // Section header ETHERNET
                Text {
                    text: "ETHERNET"; color: "#475569"
                    font.pixelSize: 10; font.weight: Font.Bold; font.letterSpacing: 2
                    leftPadding: 4; topPadding: 8
                }

                // Ethernet interface
                InfoCard {
                    width: parent.width
                    iconType: "ethernet"; iconColor: "#22c55e"
                    label: root.info.ethInterface || root.info.ethIface || "Interface Ethernet"
                    value: (root.info.ethIp && root.info.ethIp.length > 0)
                           ? root.info.ethIp
                           : "Non disponible"
                    valueColor: (root.info.ethIp && root.info.ethIp.length > 0)
                                ? "#22c55e" : "#f87171"
                    valueMono: true
                    badge: (root.info.ethIp && root.info.ethIp.length > 0) ? "IPv4" : ""
                }

                // MAC Ethernet (si dispo)
                InfoCard {
                    visible: !!root.info.ethMac && String(root.info.ethMac).length > 0
                    width: parent.width
                    iconType: "mac"; iconColor: "#94a3b8"
                    label: "Adresse MAC"
                    value: root.info.ethMac || "—"
                    valueColor: "#cbd5e1"; valueMono: true
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

            // ── Header HORS Flickable (sinon Flickable A133 evdev intercepte
            //    parfois les taps sur le bouton Scanner comme drag) ────────────
            Item {
                id: wifiHeaderRow
                anchors { top: parent.top; left: parent.left; right: parent.right }
                height: 30

                Text {
                    anchors { left: parent.left; verticalCenter: parent.verticalCenter }
                    text: "Réseaux disponibles"
                    color: "#cbd5e1"; font.pixelSize: 12; font.weight: Font.DemiBold
                }
                AppButton {
                    id: scanBtn
                    anchors { right: parent.right; verticalCenter: parent.verticalCenter }
                    width: 96; height: 28
                    variant: "secondary"
                    enabled: !root.busy
                    text: root.busy ? "Scan…" : "Scanner"
                    fontSize: 11; bold: false
                    onClicked: {
                        console.log("[scanBtn] clicked → scanWifi()")
                        root.errorMsg = ""; root.statusMsg = ""
                        root.busy = true
                        root.controller.scanWifi()
                    }
                    contentItem: Row {
                        anchors.centerIn: parent
                        spacing: 6
                        Spinner {
                            visible: root.busy
                            anchors.verticalCenter: parent.verticalCenter
                            size: 12
                            color: "#cbd5e1"
                        }
                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: scanBtn.text
                            color: "#cbd5e1"; font.pixelSize: 11; font.weight: Font.DemiBold
                        }
                    }
                }
            }

            // ── Flickable : liste + form (header est en dehors) ──────────────
            Flickable {
                id: wifiFlick
                anchors { top: wifiHeaderRow.bottom; left: parent.left; right: parent.right; bottom: connectBtn.top
                          topMargin: 8; bottomMargin: 8 }
                contentHeight: wifiContent.implicitHeight
                clip: true
                boundsBehavior: Flickable.StopAtBounds
                pressDelay: 0   // pas de delay → AppButton recoit le press immediatement

                // Scroll auto sur le champ qui prend le focus (clavier visible)
                function scrollTo(item) {
                    if (!item) return
                    var pos = item.mapToItem(wifiContent, 0, 0).y
                    var target = Math.max(0, pos - height / 3)
                    var maxY   = Math.max(0, contentHeight - height)
                    contentY = Math.min(maxY, target)
                }

                // (Pas de scrollbar globale ici - elle entrait en conflit visuel
                //  avec la ScrollBar.AlwaysOn de la wifiListView. Le Flickable
                //  reste scrollable au doigt si contentHeight > height.)

                Column {
                    id: wifiContent
                    width: parent.width
                    spacing: 10


                    // ── Liste WiFi : taille adaptive ─────────────────────────
                    // Tres compacte (56px = 1 item) quand SSID selectionne :
                    // affiche seulement le SSID choisi, libere place pour le form.
                    // Sinon : jusqu'a 4 items visibles.
                    Rectangle {
                        id: wifiListBox
                        width: parent.width
                        height: root.wifiSelectedSsid !== ""
                                ? 56
                                : Math.min(4 * 50 + 8, Math.max(1, root.wifiList.length) * 50 + 8)
                        Behavior on height { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }
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
                            anchors { fill: parent; margins: 4 }
                            model: root.wifiList
                            spacing: 4
                            clip: true
                            boundsBehavior: Flickable.StopAtBounds

                            // ScrollBar built-in QtQuick.Controls 2.5 - always visible
                            // Visuel fin 7px, mais zone tactile elargie a 18px via padding
                            // -> facile a cliquer/drag, esthetique discrete
                            ScrollBar.vertical: ScrollBar {
                                id: wifiVbar
                                active: true
                                policy: ScrollBar.AlwaysOn
                                width: 18
                                padding: 5.5   // 18 - 7 = 11 / 2 = 5.5 -> handle visuel 7px centre
                                contentItem: Rectangle {
                                    implicitWidth: 7
                                    radius: 3.5
                                    color: wifiVbar.pressed ? "#60a5fa"
                                                            : (wifiVbar.hovered ? "#64748b" : "#475569")
                                    Behavior on color { ColorAnimation { duration: 100 } }
                                }
                                background: Rectangle {
                                    color: "transparent"
                                }
                            }

                            // Centre auto sur le SSID sélectionné
                            currentIndex: {
                                for (var i = 0; i < root.wifiList.length; i++)
                                    if (root.wifiList[i].ssid === root.wifiSelectedSsid) return i
                                return -1
                            }
                            onCurrentIndexChanged: if (currentIndex >= 0) positionViewAtIndex(currentIndex, ListView.Center)

                            // Auto-focus password quand SSID selectionne
                            Connections {
                                target: root
                                onWifiSelectedSsidChanged: {
                                    if (root.wifiSelectedSsid !== "" && typeof wifiPwInput !== "undefined")
                                        Qt.callLater(function() { wifiPwInput.inputItem.forceActiveFocus() })
                                }
                            }

                            delegate: ItemDelegate {
                                id: wifiBtn
                                property bool isConnected: root.info.wifiSsid === modelData.ssid
                                property bool isSelected:  root.wifiSelectedSsid === modelData.ssid
                                width: wifiListView.width - wifiVbar.width
                                height: 42
                                padding: 0

                                background: Rectangle {
                                    radius: 8
                                    color: wifiBtn.pressed ? "#0f1c47"
                                                            : (wifiBtn.isSelected ? "#1e3a8a" : "#1e293b")
                                    border.color: wifiBtn.isSelected ? "#3b82f6"
                                                                     : (wifiBtn.isConnected ? "#22c55e" : "transparent")
                                    border.width: wifiBtn.isSelected ? 1.5 : (wifiBtn.isConnected ? 1 : 0)
                                    Behavior on color { ColorAnimation { duration: 120 } }
                                }

                                contentItem: Item {
                                    Canvas {
                                        anchors { left: parent.left; leftMargin: 8; verticalCenter: parent.verticalCenter }
                                        width: 20; height: 16
                                        property int sig: modelData.signal || 0
                                        onSigChanged: requestPaint()
                                        Component.onCompleted: requestPaint()
                                        onPaint: {
                                            var ctx = getContext("2d")
                                            ctx.clearRect(0, 0, width, height)
                                            ctx.lineCap = "round"; ctx.lineWidth = 2
                                            var cx = width/2, cy = height*0.92
                                            ctx.strokeStyle = sig >= 80 ? "#60a5fa" : "#475569"
                                            ctx.beginPath(); ctx.arc(cx, cy, width*0.45, Math.PI*1.20, Math.PI*1.80); ctx.stroke()
                                            ctx.strokeStyle = sig >= 50 ? "#60a5fa" : "#475569"
                                            ctx.beginPath(); ctx.arc(cx, cy, width*0.30, Math.PI*1.20, Math.PI*1.80); ctx.stroke()
                                            ctx.strokeStyle = sig >= 20 ? "#60a5fa" : "#475569"
                                            ctx.fillStyle   = sig >= 20 ? "#60a5fa" : "#475569"
                                            ctx.beginPath(); ctx.arc(cx, cy, 1.5, 0, Math.PI*2); ctx.fill()
                                        }
                                    }
                                    Text {
                                        anchors { left: parent.left; leftMargin: 38; verticalCenter: parent.verticalCenter }
                                        text: modelData.ssid
                                        color: "white"; font.pixelSize: 12; font.weight: Font.DemiBold
                                        elide: Text.ElideRight
                                        width: parent.width - 38 - rightInfo.width - 8
                                    }
                                    Row {
                                        id: rightInfo
                                        anchors { right: parent.right; rightMargin: 6; verticalCenter: parent.verticalCenter }
                                        spacing: 6
                                        Rectangle {
                                            visible: wifiBtn.isConnected
                                            anchors.verticalCenter: parent.verticalCenter
                                            width: connText.implicitWidth + 12; height: 18; radius: 9
                                            color: "#16a34a"
                                            Text {
                                                id: connText
                                                anchors.centerIn: parent
                                                text: "Connecté"
                                                color: "white"; font.pixelSize: 9; font.weight: Font.Bold
                                            }
                                        }
                                        Text {
                                            anchors.verticalCenter: parent.verticalCenter
                                            text: (modelData.signal || 0) + "%"
                                            color: "#94a3b8"; font.pixelSize: 11
                                        }
                                        Rectangle {
                                            visible: !!modelData.security && modelData.security.length > 0
                                            anchors.verticalCenter: parent.verticalCenter
                                            width: secText.implicitWidth + 10; height: 18; radius: 4
                                            color: "#0f172a"; border.color: "#334155"; border.width: 1
                                            Text {
                                                id: secText
                                                anchors.centerIn: parent
                                                text: modelData.security || ""
                                                color: "#cbd5e1"; font.pixelSize: 9; font.weight: Font.DemiBold
                                            }
                                        }
                                    }
                                }

                                onClicked: {
                                    root.wifiSelectedSsid = modelData.ssid
                                    root.wifiSelectedSecurity = modelData.security || ""
                                    root.wifiPassword = ""
                                    if (typeof wifiPwInput !== "undefined") wifiPwInput.text = ""
                                }
                            }
                        }
                    }

                    // ── Form connexion (toujours présent, opacity selon select) ──
                    Column {
                        id: wifiForm
                        width: parent.width
                        spacing: 10
                        opacity: root.wifiSelectedSsid === "" ? 0.4 : 1
                        Behavior on opacity { NumberAnimation { duration: 180 } }

                        // Card SSID sélectionné avec X pour deselect
                        Column {
                            width: parent.width
                            spacing: 4
                            Text { text: "SSID sélectionné"; color: "#94a3b8"; font.pixelSize: 10 }
                            Rectangle {
                                width: parent.width; height: 38; radius: 8
                                color: "#1e293b"; border.color: "#334155"
                                Row {
                                    anchors { left: parent.left; leftMargin: 12; verticalCenter: parent.verticalCenter }
                                    spacing: 8
                                    Canvas {
                                        width: 14; height: 12
                                        anchors.verticalCenter: parent.verticalCenter
                                        onPaint: {
                                            var ctx = getContext("2d")
                                            ctx.clearRect(0, 0, width, height)
                                            ctx.strokeStyle = "#60a5fa"; ctx.fillStyle = "#60a5fa"
                                            ctx.lineWidth = 1.5
                                            var cx = width/2, cy = height*0.9
                                            ctx.beginPath(); ctx.arc(cx, cy, width*0.45, Math.PI*1.20, Math.PI*1.80); ctx.stroke()
                                            ctx.beginPath(); ctx.arc(cx, cy, width*0.28, Math.PI*1.20, Math.PI*1.80); ctx.stroke()
                                            ctx.beginPath(); ctx.arc(cx, cy, 1.4, 0, Math.PI*2); ctx.fill()
                                        }
                                    }
                                    Text {
                                        anchors.verticalCenter: parent.verticalCenter
                                        text: root.wifiSelectedSsid !== "" ? root.wifiSelectedSsid : "—"
                                        color: "white"; font.pixelSize: 12; font.weight: Font.DemiBold
                                    }
                                }
                                AppButton {
                                    id: deselBtn
                                    visible: root.wifiSelectedSsid !== ""
                                    anchors { right: parent.right; rightMargin: 6; verticalCenter: parent.verticalCenter }
                                    width: 24; height: 24
                                    text: "×"
                                    background: Rectangle {
                                        radius: 12
                                        color: deselBtn.pressed ? "#334155" : "transparent"
                                    }
                                    contentItem: Text {
                                        text: deselBtn.text; color: "#94a3b8"
                                        font.pixelSize: 14; font.weight: Font.Bold
                                        horizontalAlignment: Text.AlignHCenter
                                        verticalAlignment: Text.AlignVCenter
                                    }
                                    onClicked: {
                                        root.wifiSelectedSsid = ""; root.wifiSelectedSecurity = ""; root.wifiPassword = ""
                                        if (typeof wifiPwInput !== "undefined") wifiPwInput.text = ""
                                    }
                                }
                            }
                        }

                        // Mot de passe
                        Column {
                            width: parent.width; spacing: 4
                            Text { text: "Mot de passe"; color: "#94a3b8"; font.pixelSize: 10 }
                            KbInput {
                                id: wifiPwInput
                                width: parent.width
                                keyboard: root.keyboard
                                isPassword: true
                                placeholder: "Mot de passe Wi-Fi"
                                onTextChanged: root.wifiPassword = text
                                onActiveFocusChanged: if (activeFocus)
                                    Qt.callLater(function() { wifiFlick.scrollTo(wifiPwInput) })
                            }
                        }

                        // 2 gros boutons DHCP / IP STATIQUE
                        Row {
                            width: parent.width; spacing: 8
                            Repeater {
                                model: [{id:"dhcp", lbl:"DHCP (AUTO)"}, {id:"static", lbl:"IP STATIQUE"}]
                                AppButton {
                                    id: modeBtn
                                    width: (parent.width - 8) / 2; height: 40
                                    text: modelData.lbl
                                    fontSize: 11
                                    background: Rectangle {
                                        radius: 8
                                        color: root.wifiMode === modelData.id ? "#2563eb"
                                                : (modeBtn.pressed ? "#0f172a" : "#1e293b")
                                        border.color: root.wifiMode === modelData.id ? "#3b82f6" : "#334155"
                                        border.width: 1
                                        Behavior on color { ColorAnimation { duration: 150 } }
                                    }
                                    contentItem: Text {
                                        text: modelData.lbl
                                        color: root.wifiMode === modelData.id ? "white" : "#94a3b8"
                                        font.pixelSize: 11; font.weight: Font.Bold
                                        horizontalAlignment: Text.AlignHCenter
                                        verticalAlignment: Text.AlignVCenter
                                    }
                                    onClicked: root.wifiMode = modelData.id
                                }
                            }
                        }

                        // Helper text Mode actuel (DHCP)
                        Row {
                            visible: root.wifiMode === "dhcp"
                            spacing: 6
                            Rectangle {
                                anchors.verticalCenter: parent.verticalCenter
                                width: 6; height: 6; radius: 3
                                color: "#22c55e"
                            }
                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                text: "Mode actuel : "
                                color: "#94a3b8"; font.pixelSize: 10
                            }
                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                text: root.info.wifiMode || "DHCP (auto)"
                                color: "white"; font.pixelSize: 10; font.weight: Font.DemiBold
                            }
                        }

                        // Champs IP statique (visibles uniquement si IP STATIQUE)
                        Column {
                            visible: root.wifiMode === "static"
                            width: parent.width
                            spacing: 6
                            Row {
                                width: parent.width; spacing: 6
                                Column {
                                    width: (parent.width - 6) / 2; spacing: 3
                                    Text { text: "IP"; color: "#94a3b8"; font.pixelSize: 10 }
                                    KbInput {
                                        id: wifiIpInput
                                        width: parent.width; keyboard: root.keyboard; placeholder: "192.168.1.50"
                                        onTextChanged: root.wifiIp = text
                                        onActiveFocusChanged: if (activeFocus)
                                            Qt.callLater(function() { wifiFlick.scrollTo(wifiIpInput) })
                                    }
                                }
                                Column {
                                    width: (parent.width - 6) / 2; spacing: 3
                                    Text { text: "Préfixe"; color: "#94a3b8"; font.pixelSize: 10 }
                                    KbInput {
                                        id: wifiPrefixInput
                                        width: parent.width; keyboard: root.keyboard; placeholder: "24"
                                        onTextChanged: root.wifiPrefix = text
                                        onActiveFocusChanged: if (activeFocus)
                                            Qt.callLater(function() { wifiFlick.scrollTo(wifiPrefixInput) })
                                    }
                                }
                            }
                            Text { text: "Gateway"; color: "#94a3b8"; font.pixelSize: 10 }
                            KbInput {
                                id: wifiGwInput
                                width: parent.width; keyboard: root.keyboard; placeholder: "192.168.1.1"
                                onTextChanged: root.wifiGw = text
                                onActiveFocusChanged: if (activeFocus)
                                    Qt.callLater(function() { wifiFlick.scrollTo(wifiGwInput) })
                            }
                            Text { text: "DNS"; color: "#94a3b8"; font.pixelSize: 10 }
                            KbInput {
                                id: wifiDnsInput
                                width: parent.width; keyboard: root.keyboard; placeholder: "8.8.8.8"
                                onTextChanged: root.wifiDns = text
                                onActiveFocusChanged: if (activeFocus)
                                    Qt.callLater(function() { wifiFlick.scrollTo(wifiDnsInput) })
                            }
                        }
                    }
                }
            }

            // Bouton Se connecter (full-width, en bas)
            AppButton {
                id: connectBtn
                anchors { bottom: parent.bottom; left: parent.left; right: parent.right }
                height: 46
                variant: "primary"
                enabled: root.wifiSelectedSsid !== "" && !root.busy
                text: root.busy ? "Connexion…" : "Se connecter"
                onClicked: {
                    root.errorMsg = ""; root.statusMsg = ""; root.busy = true
                    if (root.keyboard) root.keyboard.close()
                    root.controller.connectWifi(
                        root.wifiSelectedSsid, root.wifiPassword, root.wifiMode,
                        root.wifiIp, root.wifiPrefix, root.wifiGw, root.wifiDns)
                }
                contentItem: Row {
                    anchors.centerIn: parent
                    spacing: 8
                    Spinner {
                        visible: root.busy
                        anchors.verticalCenter: parent.verticalCenter
                        size: 18; color: "#cbd5e1"
                    }
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: connectBtn.text
                        color: "white"; font.pixelSize: 13; font.weight: Font.Bold
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

            function scrollTo(item) {
                if (!item) return
                var pos = item.mapToItem(ethForm, 0, 0).y
                var target = Math.max(0, pos - height / 3)
                var maxY   = Math.max(0, contentHeight - height)
                contentY = Math.min(maxY, target)
            }

            Column {
                id: ethForm
                width: parent.width
                spacing: 10

                // Interface (display read-only)
                Column {
                    width: parent.width; spacing: 4
                    Text { text: "Interface"; color: "#94a3b8"; font.pixelSize: 10 }
                    Rectangle {
                        width: parent.width; height: 38; radius: 8
                        color: "#1e293b"; border.color: "#334155"
                        Text {
                            anchors { left: parent.left; leftMargin: 12; verticalCenter: parent.verticalCenter }
                            text: root.info.ethInterface || root.info.ethIface || "ex: eth0, enp3s0"
                            color: (root.info.ethInterface || root.info.ethIface) ? "white" : "#475569"
                            font.pixelSize: 12
                            font.family: "monospace"
                        }
                    }
                }

                // 2 gros boutons DHCP / IP STATIQUE
                Row {
                    width: parent.width; spacing: 8
                    Repeater {
                        model: [{id:"dhcp", lbl:"DHCP (AUTO)"}, {id:"static", lbl:"IP STATIQUE"}]
                        Rectangle {
                            width: (parent.width - 8) / 2; height: 40; radius: 8
                            color: root.ethMode === modelData.id ? "#2563eb" : "#1e293b"
                            border.color: root.ethMode === modelData.id ? "#3b82f6" : "#334155"
                            Behavior on color { ColorAnimation { duration: 150 } }
                            Text {
                                anchors.centerIn: parent
                                text: modelData.lbl
                                color: root.ethMode === modelData.id ? "white" : "#94a3b8"
                                font.pixelSize: 11; font.weight: Font.Bold
                            }
                            MouseArea { anchors.fill: parent; onClicked: root.ethMode = modelData.id }
                        }
                    }
                }

                // Helper text dans box grise (DHCP)
                Rectangle {
                    visible: root.ethMode === "dhcp"
                    width: parent.width; height: 38; radius: 8
                    color: "#1e293b"; border.color: "#334155"
                    Text {
                        anchors { fill: parent; margins: 10 }
                        verticalAlignment: Text.AlignVCenter
                        text: "L'adresse IP sera attribuée automatiquement par le serveur DHCP."
                        color: "#94a3b8"; font.pixelSize: 10
                        wrapMode: Text.WordWrap
                    }
                }

                // Champs IP statique (visibles uniquement si IP STATIQUE)
                Column {
                    visible: root.ethMode === "static"
                    width: parent.width
                    spacing: 8
                    Row {
                        width: parent.width; spacing: 6
                        Column {
                            width: (parent.width - 6) / 2; spacing: 3
                            Text { text: "IP"; color: "#94a3b8"; font.pixelSize: 10 }
                            KbInput {
                                id: ethIpInput
                                width: parent.width; keyboard: root.keyboard; placeholder: "192.168.10.132"
                                onTextChanged: root.ethIp = text
                                onActiveFocusChanged: if (activeFocus)
                                    Qt.callLater(function() { ethView.scrollTo(ethIpInput) })
                            }
                        }
                        Column {
                            width: (parent.width - 6) / 2; spacing: 3
                            Text { text: "Préfixe"; color: "#94a3b8"; font.pixelSize: 10 }
                            KbInput {
                                id: ethPrefixInput
                                width: parent.width; keyboard: root.keyboard; placeholder: "24"
                                onTextChanged: root.ethPrefix = text
                                onActiveFocusChanged: if (activeFocus)
                                    Qt.callLater(function() { ethView.scrollTo(ethPrefixInput) })
                            }
                        }
                    }
                    Text { text: "Gateway"; color: "#94a3b8"; font.pixelSize: 10 }
                    KbInput {
                        id: ethGwInput
                        width: parent.width; keyboard: root.keyboard; placeholder: "192.168.10.1"
                        onTextChanged: root.ethGw = text
                        onActiveFocusChanged: if (activeFocus)
                            Qt.callLater(function() { ethView.scrollTo(ethGwInput) })
                    }
                    Text { text: "DNS"; color: "#94a3b8"; font.pixelSize: 10 }
                    KbInput {
                        id: ethDnsInput
                        width: parent.width; keyboard: root.keyboard; placeholder: "8.8.8.8"
                        onTextChanged: root.ethDns = text
                        onActiveFocusChanged: if (activeFocus)
                            Qt.callLater(function() { ethView.scrollTo(ethDnsInput) })
                    }
                }

                Item { width: 1; height: 4 }

                // Bouton Appliquer (full-width)
                AppButton {
                    id: applyBtn
                    width: parent.width; height: 46
                    variant: "primary"
                    enabled: !root.busy
                    text: root.busy ? "Application…" : "Appliquer"
                    onClicked: {
                        root.errorMsg = ""; root.statusMsg = ""; root.busy = true
                        if (root.keyboard) root.keyboard.close()
                        root.controller.setEthernet(
                            root.ethMode, root.ethIp, root.ethPrefix, root.ethGw, root.ethDns)
                    }
                    contentItem: Row {
                        anchors.centerIn: parent
                        spacing: 8
                        Spinner {
                            visible: root.busy
                            anchors.verticalCenter: parent.verticalCenter
                            size: 18; color: "#cbd5e1"
                        }
                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: applyBtn.text
                            color: "white"; font.pixelSize: 13; font.weight: Font.Bold
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

            AppButton {
                anchors { right: parent.right; rightMargin: 14; verticalCenter: parent.verticalCenter }
                width: 100; height: 34
                variant: "secondary"
                text: "Fermer"; fontSize: 12; bold: false
                onClicked: root.close()
            }
        }
    }
}
