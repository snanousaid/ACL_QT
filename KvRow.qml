import QtQuick 2.10

Row {
    id: kvRow
    property string k: ""
    property string v: ""
    property bool dim: false
    spacing: 8
    Text { text: kvRow.k; color: "#64748b"; font.pixelSize: 11; width: 90 }
    Text {
        text: kvRow.v
        color: kvRow.dim ? "#94a3b8" : "#cbd5e1"
        font.pixelSize: 11
        font.family: kvRow.dim ? "monospace" : "sans-serif"
    }
}
