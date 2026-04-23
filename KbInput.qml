import QtQuick 2.10

// Touch-friendly input field that opens VirtualKeyboard on tap.
// Usage:
//   KbInput {
//       keyboard:    keyboard          // VirtualKeyboard id from parent
//       text:        myVar
//       onTextChanged: myVar = text
//       isPassword:  false
//       placeholder: "Entrez une valeur"
//       label:       "Nom"
//   }
Item {
    id: root
    height: col.implicitHeight
    width: 200  // override in usage

    property var    keyboard:    null
    property string text:        ""
    property bool   isPassword:  false
    property string placeholder: ""
    property string label:       ""

    Column {
        id: col
        width: parent.width
        spacing: 4

        Text {
            visible: root.label.length > 0
            text: root.label
            color: "#64748b"
            font.pixelSize: 12
        }

        Rectangle {
            width:  parent.width
            height: 38
            radius: 8
            color: "#1e293b"
            border.color: inputArea.containsMouse ? "#3b82f6" : "#475569"
            border.width: 1

            Row {
                anchors { fill: parent; leftMargin: 12; rightMargin: 8 }
                spacing: 6

                Text {
                    width: parent.width - (cursor.visible ? cursor.width + 6 : 0)
                    anchors.verticalCenter: parent.verticalCenter
                    text: {
                        if (root.text.length === 0) return ""
                        return root.isPassword ? "•".repeat(root.text.length) : root.text
                    }
                    color: "white"
                    font.pixelSize: 14
                    font.family: "monospace"
                    elide: Text.ElideRight
                    verticalAlignment: Text.AlignVCenter
                    // placeholder
                    Text {
                        anchors.fill: parent
                        visible: root.text.length === 0
                        text: root.placeholder
                        color: "#475569"
                        font.pixelSize: 14
                        verticalAlignment: Text.AlignVCenter
                    }
                }

                Rectangle {
                    id: cursor
                    width: 2; height: 18
                    color: "#3b82f6"
                    anchors.verticalCenter: parent.verticalCenter
                    visible: root.keyboard !== null && root.keyboard.visible

                    SequentialAnimation on opacity {
                        running: cursor.visible; loops: Animation.Infinite
                        NumberAnimation { from: 1; to: 0; duration: 500 }
                        NumberAnimation { from: 0; to: 1; duration: 500 }
                    }
                }
            }

            MouseArea {
                id: inputArea
                anchors.fill: parent
                hoverEnabled: true
                onPressed: {
                    if (root.keyboard !== null)
                        root.keyboard.open(root.text, root.isPassword, function(v) { root.text = v })
                }
            }
        }
    }
}
