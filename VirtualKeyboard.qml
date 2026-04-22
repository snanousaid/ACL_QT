import QtQuick 2.10

// Full-screen keyboard overlay.
// Usage: keyboard.open(currentValue, isPassword, callbackFn)
// callbackFn(newValue) is called on OK/Enter.
Rectangle {
    id: root
    anchors.fill: parent
    color: "transparent"
    visible: false
    z: 60

    property bool   isPassword: false
    property string kbValue:    ""
    property string layoutName: "default"
    property var    _cb:        null   // JS callback(value)

    // ── Public API ────────────────────────────────────────────────────────────
    function open(v, isPwd, callback) {
        kbValue    = v      || ""
        isPassword = isPwd  === true
        _cb        = callback || null
        layoutName = "default"
        visible    = true
    }
    function close() { visible = false }

    // ── Key definitions ───────────────────────────────────────────────────────
    // Each key: { k, l, s, w }
    //   k = key string   l = display label (empty → use k)
    //   s = style  0=normal 1=fn 2=space 3=enter
    //   w = width factor (1 = standard)

    readonly property var layout_default: [
        [{k:"a",l:"",s:0,w:1},{k:"z",l:"",s:0,w:1},{k:"e",l:"",s:0,w:1},{k:"r",l:"",s:0,w:1},{k:"t",l:"",s:0,w:1},{k:"y",l:"",s:0,w:1},{k:"u",l:"",s:0,w:1},{k:"i",l:"",s:0,w:1},{k:"o",l:"",s:0,w:1},{k:"p",l:"",s:0,w:1},{k:"{bksp}",l:"⌫",s:1,w:1.5}],
        [{k:"q",l:"",s:0,w:1},{k:"s",l:"",s:0,w:1},{k:"d",l:"",s:0,w:1},{k:"f",l:"",s:0,w:1},{k:"g",l:"",s:0,w:1},{k:"h",l:"",s:0,w:1},{k:"j",l:"",s:0,w:1},{k:"k",l:"",s:0,w:1},{k:"l",l:"",s:0,w:1},{k:"m",l:"",s:0,w:1}],
        [{k:"{shift}",l:"⇧",s:1,w:1.5},{k:"w",l:"",s:0,w:1},{k:"x",l:"",s:0,w:1},{k:"c",l:"",s:0,w:1},{k:"v",l:"",s:0,w:1},{k:"b",l:"",s:0,w:1},{k:"n",l:"",s:0,w:1},{k:",",l:"",s:0,w:1},{k:".",l:"",s:0,w:1},{k:"{shift}",l:"⇧",s:1,w:1.5}],
        [{k:"{numbers}",l:"!@#",s:1,w:1.5},{k:"{space}",l:"espace",s:2,w:4},{k:"{enter}",l:"↵ OK",s:3,w:2}]
    ]
    readonly property var layout_shift: [
        [{k:"A",l:"",s:0,w:1},{k:"Z",l:"",s:0,w:1},{k:"E",l:"",s:0,w:1},{k:"R",l:"",s:0,w:1},{k:"T",l:"",s:0,w:1},{k:"Y",l:"",s:0,w:1},{k:"U",l:"",s:0,w:1},{k:"I",l:"",s:0,w:1},{k:"O",l:"",s:0,w:1},{k:"P",l:"",s:0,w:1},{k:"{bksp}",l:"⌫",s:1,w:1.5}],
        [{k:"Q",l:"",s:0,w:1},{k:"S",l:"",s:0,w:1},{k:"D",l:"",s:0,w:1},{k:"F",l:"",s:0,w:1},{k:"G",l:"",s:0,w:1},{k:"H",l:"",s:0,w:1},{k:"J",l:"",s:0,w:1},{k:"K",l:"",s:0,w:1},{k:"L",l:"",s:0,w:1},{k:"M",l:"",s:0,w:1}],
        [{k:"{shift}",l:"⇧",s:1,w:1.5},{k:"W",l:"",s:0,w:1},{k:"X",l:"",s:0,w:1},{k:"C",l:"",s:0,w:1},{k:"V",l:"",s:0,w:1},{k:"B",l:"",s:0,w:1},{k:"N",l:"",s:0,w:1},{k:";",l:"",s:0,w:1},{k:":",l:"",s:0,w:1},{k:"{shift}",l:"⇧",s:1,w:1.5}],
        [{k:"{numbers}",l:"!@#",s:1,w:1.5},{k:"{space}",l:"espace",s:2,w:4},{k:"{enter}",l:"↵ OK",s:3,w:2}]
    ]
    readonly property var layout_numbers: [
        [{k:"1",l:"",s:0,w:1},{k:"2",l:"",s:0,w:1},{k:"3",l:"",s:0,w:1},{k:"4",l:"",s:0,w:1},{k:"5",l:"",s:0,w:1},{k:"6",l:"",s:0,w:1},{k:"7",l:"",s:0,w:1},{k:"8",l:"",s:0,w:1},{k:"9",l:"",s:0,w:1},{k:"0",l:"",s:0,w:1},{k:"{bksp}",l:"⌫",s:1,w:1.5}],
        [{k:"@",l:"",s:0,w:1},{k:"#",l:"",s:0,w:1},{k:"/",l:"",s:0,w:1},{k:"-",l:"",s:0,w:1},{k:"_",l:"",s:0,w:1},{k:"=",l:"",s:0,w:1},{k:"+",l:"",s:0,w:1},{k:"*",l:"",s:0,w:1},{k:"(",l:"",s:0,w:1},{k:")",l:"",s:0,w:1}],
        [{k:"!",l:"",s:0,w:1},{k:"?",l:"",s:0,w:1},{k:".",l:"",s:0,w:1},{k:",",l:"",s:0,w:1},{k:";",l:"",s:0,w:1},{k:":",l:"",s:0,w:1},{k:"\"",l:"",s:0,w:1},{k:"'",l:"",s:0,w:1},{k:"~",l:"",s:0,w:1},{k:"`",l:"",s:0,w:1}],
        [{k:"{abc}",l:"ABC",s:1,w:1.5},{k:"{space}",l:"espace",s:2,w:4},{k:"{enter}",l:"↵ OK",s:3,w:2}]
    ]

    property var currentRows: layoutName === "default" ? layout_default
                            : layoutName === "shift"   ? layout_shift
                            :                           layout_numbers

    function handleKey(k) {
        if      (k === "{bksp}")   { if (kbValue.length > 0) kbValue = kbValue.slice(0,-1) }
        else if (k === "{shift}")  { layoutName = (layoutName === "shift") ? "default" : "shift" }
        else if (k === "{numbers}"){ layoutName = "numbers" }
        else if (k === "{abc}")    { layoutName = "default" }
        else if (k === "{space}")  { kbValue += " "; if (layoutName === "shift") layoutName = "default" }
        else if (k === "{enter}")  { _confirm() }
        else                       { kbValue += k; if (layoutName === "shift") layoutName = "default" }
    }

    function _confirm() {
        if (_cb) _cb(kbValue)
        close()
    }

    // ── Backdrop (tap outside → confirm) ─────────────────────────────────────
    MouseArea { anchors.fill: parent; onPressed: _confirm() }

    // ── Preview bar ───────────────────────────────────────────────────────────
    Rectangle {
        id: previewBar
        anchors { left: parent.left; right: parent.right; bottom: kbBody.top }
        height: 50
        color: "#020617"
        Rectangle { anchors.top: parent.top; width: parent.width; height: 1; color: "#334155" }

        Row {
            anchors { fill: parent; leftMargin: 8; rightMargin: 8; topMargin: 9; bottomMargin: 9 }
            spacing: 8

            Rectangle {
                height: 32
                width: parent.width - 156  // 2×68 buttons + 3×8 spacing = 156
                color: "#1e293b"; radius: 6
                anchors.verticalCenter: parent.verticalCenter
                clip: true
                Text {
                    anchors { fill: parent; leftMargin: 12; rightMargin: 6 }
                    text: root.kbValue.length > 0
                          ? (root.isPassword ? "•".repeat(root.kbValue.length) : root.kbValue)
                          : "..."
                    color: root.kbValue.length > 0 ? "white" : "#475569"
                    font.pixelSize: 14; font.family: "monospace"
                    verticalAlignment: Text.AlignVCenter
                    elide: Text.ElideRight
                }
            }

            Rectangle {
                width: 68; height: 32; radius: 6; color: "#334155"
                anchors.verticalCenter: parent.verticalCenter
                Text { anchors.centerIn: parent; text: "Effacer"; color: "#94a3b8"; font.pixelSize: 12 }
                MouseArea { anchors.fill: parent; onPressed: root.kbValue = "" }
            }

            Rectangle {
                width: 68; height: 32; radius: 6; color: "#16a34a"
                anchors.verticalCenter: parent.verticalCenter
                Text { anchors.centerIn: parent; text: "OK"; color: "white"; font.pixelSize: 12; font.weight: Font.Bold }
                MouseArea { anchors.fill: parent; onPressed: root._confirm() }
            }
        }
    }

    // ── Keyboard body ─────────────────────────────────────────────────────────
    Rectangle {
        id: kbBody
        anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
        color: "#0f172a"
        height: kbCol.height + 18
        Rectangle { anchors.top: parent.top; width: parent.width; height: 1; color: "#334155" }

        Column {
            id: kbCol
            anchors {
                left: parent.left; right: parent.right
                top: parent.top; topMargin: 6
                leftMargin: 6; rightMargin: 6
            }
            spacing: 5

            // ── Row 0 ──────────────────────────────────────────────────────
            Row {
                id: kbRow0
                property var rowKeys: root.currentRows[0]
                property real totalW: { var t=0; for(var i=0;i<rowKeys.length;i++) t+=rowKeys[i].w; return t }
                property real unitW:  (kbCol.width - spacing*(rowKeys.length-1)) / totalW
                width: kbCol.width; height: 44; spacing: 5
                Repeater {
                    model: kbRow0.rowKeys
                    Rectangle {
                        property bool dn: false
                        width: kbRow0.unitW * modelData.w; height: 44; radius: 8
                        color: dn ? "#3b82f6"
                             : modelData.s===3 ? "#2563eb"
                             : modelData.s===2 ? "#1e293b"
                             : modelData.s===1 ? "#475569" : "#334155"
                        Text {
                            anchors.centerIn: parent
                            text: modelData.l.length > 0 ? modelData.l : modelData.k
                            color: modelData.s===1 ? "#cbd5e1" : modelData.s===2 ? "#94a3b8" : "#f1f5f9"
                            font.pixelSize: modelData.s===1 ? 12 : 15
                            font.weight: modelData.s>=1 ? Font.Bold : Font.Medium
                        }
                        MouseArea {
                            anchors.fill: parent
                            onPressed:  { root.handleKey(modelData.k); parent.dn = true }
                            onReleased: parent.dn = false
                        }
                    }
                }
            }

            // ── Row 1 ──────────────────────────────────────────────────────
            Row {
                id: kbRow1
                property var rowKeys: root.currentRows[1]
                property real totalW: { var t=0; for(var i=0;i<rowKeys.length;i++) t+=rowKeys[i].w; return t }
                property real unitW:  (kbCol.width - spacing*(rowKeys.length-1)) / totalW
                width: kbCol.width; height: 44; spacing: 5
                Repeater {
                    model: kbRow1.rowKeys
                    Rectangle {
                        property bool dn: false
                        width: kbRow1.unitW * modelData.w; height: 44; radius: 8
                        color: dn ? "#3b82f6"
                             : modelData.s===3 ? "#2563eb"
                             : modelData.s===2 ? "#1e293b"
                             : modelData.s===1 ? "#475569" : "#334155"
                        Text {
                            anchors.centerIn: parent
                            text: modelData.l.length > 0 ? modelData.l : modelData.k
                            color: modelData.s===1 ? "#cbd5e1" : modelData.s===2 ? "#94a3b8" : "#f1f5f9"
                            font.pixelSize: modelData.s===1 ? 12 : 15
                            font.weight: modelData.s>=1 ? Font.Bold : Font.Medium
                        }
                        MouseArea {
                            anchors.fill: parent
                            onPressed:  { root.handleKey(modelData.k); parent.dn = true }
                            onReleased: parent.dn = false
                        }
                    }
                }
            }

            // ── Row 2 ──────────────────────────────────────────────────────
            Row {
                id: kbRow2
                property var rowKeys: root.currentRows[2]
                property real totalW: { var t=0; for(var i=0;i<rowKeys.length;i++) t+=rowKeys[i].w; return t }
                property real unitW:  (kbCol.width - spacing*(rowKeys.length-1)) / totalW
                width: kbCol.width; height: 44; spacing: 5
                Repeater {
                    model: kbRow2.rowKeys
                    Rectangle {
                        property bool dn: false
                        width: kbRow2.unitW * modelData.w; height: 44; radius: 8
                        color: dn ? "#3b82f6"
                             : modelData.s===3 ? "#2563eb"
                             : modelData.s===2 ? "#1e293b"
                             : modelData.s===1 ? "#475569" : "#334155"
                        Text {
                            anchors.centerIn: parent
                            text: modelData.l.length > 0 ? modelData.l : modelData.k
                            color: modelData.s===1 ? "#cbd5e1" : modelData.s===2 ? "#94a3b8" : "#f1f5f9"
                            font.pixelSize: modelData.s===1 ? 12 : 15
                            font.weight: modelData.s>=1 ? Font.Bold : Font.Medium
                        }
                        MouseArea {
                            anchors.fill: parent
                            onPressed:  { root.handleKey(modelData.k); parent.dn = true }
                            onReleased: parent.dn = false
                        }
                    }
                }
            }

            // ── Row 3 ──────────────────────────────────────────────────────
            Row {
                id: kbRow3
                property var rowKeys: root.currentRows[3]
                property real totalW: { var t=0; for(var i=0;i<rowKeys.length;i++) t+=rowKeys[i].w; return t }
                property real unitW:  (kbCol.width - spacing*(rowKeys.length-1)) / totalW
                width: kbCol.width; height: 44; spacing: 5
                Repeater {
                    model: kbRow3.rowKeys
                    Rectangle {
                        property bool dn: false
                        width: kbRow3.unitW * modelData.w; height: 44; radius: 8
                        color: dn ? "#3b82f6"
                             : modelData.s===3 ? "#2563eb"
                             : modelData.s===2 ? "#1e293b"
                             : modelData.s===1 ? "#475569" : "#334155"
                        Text {
                            anchors.centerIn: parent
                            text: modelData.l.length > 0 ? modelData.l : modelData.k
                            color: modelData.s===1 ? "#cbd5e1" : modelData.s===2 ? "#94a3b8" : "#f1f5f9"
                            font.pixelSize: modelData.s===1 ? 12 : 13
                            font.weight: modelData.s>=1 ? Font.Bold : Font.Medium
                        }
                        MouseArea {
                            anchors.fill: parent
                            onPressed:  { root.handleKey(modelData.k); parent.dn = true }
                            onReleased: parent.dn = false
                        }
                    }
                }
            }
        }
    }
}
