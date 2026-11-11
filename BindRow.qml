import QtQuick
import qs.Commons
import qs.Commons as Commons

// One key and what it does. Hovering the row wraps the description instead of
// eliding it, so a narrow panel still shows every word when asked.
Item {
  id: row

  property var bind: null
  readonly property real keyWidth: Math.round(width * 0.38)
  property bool hovered: false

  readonly property int lineHeight: Math.round(Style.fontPx(0.95) * 1.5)
  height: Math.max(lineHeight, keyText.implicitHeight, description.implicitHeight)

  HoverHandler {
    onHoveredChanged: row.hovered = hovered
  }

  Text {
    id: keyText
    width: row.keyWidth
    anchors.left: parent.left
    anchors.top: parent.top
    textFormat: Text.PlainText
    text: row.bind ? String(row.bind.key) : ""
    color: Commons.Color.accent
    font.family: Style.fontFamily
    font.pixelSize: Style.fontPx(0.95)
    font.bold: true
    wrapMode: row.hovered ? Text.Wrap : Text.NoWrap
    elide: row.hovered ? Text.ElideNone : Text.ElideRight
  }

  Text {
    id: description
    anchors.left: keyText.right
    anchors.leftMargin: Style.spacing.md
    anchors.right: parent.right
    anchors.top: parent.top
    textFormat: Text.PlainText
    text: row.bind ? String(row.bind.description) : ""
    color: Commons.Color.foreground
    font.family: Style.fontFamily
    font.pixelSize: Style.fontPx(0.95)
    wrapMode: row.hovered ? Text.Wrap : Text.NoWrap
    elide: row.hovered ? Text.ElideNone : Text.ElideRight
  }
}
