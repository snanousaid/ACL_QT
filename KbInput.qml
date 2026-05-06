import QtQuick 2.10

Item {
    id: root
    height: col.implicitHeight
    width: 200

    property alias text:        inputField.text
    property alias inputItem:   inputField
    property bool   isPassword:   false
    property bool   showPassword: false   // toggle : true = texte en clair
    property string placeholder: ""
    property string label:       ""
    property var    keyboard:    null

    // Workaround Qt 5.12 : changer echoMode ne re-masque pas le texte déjà affiché.
    // On vide puis restaure le texte pour forcer le refresh visuel.
    onShowPasswordChanged: {
        if (root.isPassword && !root.showPassword) {
            var saved = inputField.text
            inputField.text = ""
            inputField.text = saved
        }
    }

    Column {
        id: col
        width: parent.width
        spacing: 4

        Text {
            visible: root.label.length > 0
            text:    root.label
            color:   "#64748b"
            font.pixelSize: 12
        }

        Rectangle {
            width:  parent.width
            height: 38
            radius: 8
            color:  "#1e293b"
            border.color: inputField.activeFocus ? "#3b82f6" : "#475569"
            border.width: 1

            TextInput {
                id: inputField
                anchors { fill: parent; leftMargin: 12; rightMargin: 8 }
                verticalAlignment: TextInput.AlignVCenter
                color:       "white"
                font.pixelSize: 14
                font.family: "monospace"
                echoMode: (root.isPassword && !root.showPassword)
                          ? TextInput.Password : TextInput.Normal
                inputMethodHints: (root.isPassword && !root.showPassword)
                                  ? Qt.ImhHiddenText | Qt.ImhNoPredictiveText
                                  : Qt.ImhNone
                activeFocusOnPress: true

                Text {
                    anchors { fill: parent; leftMargin: 0 }
                    visible: inputField.text.length === 0
                    text:    root.placeholder
                    color:   "#475569"
                    font.pixelSize: 14
                    font.family:    "monospace"
                    verticalAlignment: Text.AlignVCenter
                }
            }
        }
    }
}
