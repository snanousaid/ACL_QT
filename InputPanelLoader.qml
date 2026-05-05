import QtQuick 2.10
import QtQuick.VirtualKeyboard 2.3

// Chargé dynamiquement uniquement si Qt VKB est disponible (Loader dans main.qml)
InputPanel {
    anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
    visible: Qt.inputMethod.visible
}
