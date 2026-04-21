import QtQuick 2.10
import QtQuick.Window 2.10
import ACL 1.0

Window {
    visible: true
    width:   640
    height:  480
    color:   "#0f172a"
    title:   "ACL — Video Stream"

    VideoItem {
        id:      videoItem
        anchors.fill: parent
    }

    // Overlay : FPS et statut en bas à gauche
    Text {
        anchors {
            left:   parent.left
            bottom: parent.bottom
            margins: 8
        }
        text:  "ACL Face Detection"
        color: "#64748b"
        font { pixelSize: 11; family: "monospace" }
    }
}
