import QtQuick
import qs.Commons
import qs.Commons as Commons
import qs.Ui
import "Binds.js" as Binds

// One key and what it does. Hovering the row wraps the description instead of
// eliding it, so a narrow panel still shows every word when asked. Search terms
// are wrapped in underline/bold by `Binds.highlight`, which also escapes the
// plain text, so the rows render as styled text.
Item {
  id: row

  property var bind: null
  property string query: ""
  // Descriptions that share this row's combo, when there is more than one. The
  // panel computes them over the whole listing, so filtering the list never
  // hides a conflict.
  property var conflictDescriptions: []
  property string conflictHint: ""
  readonly property int conflictCount: row.conflictDescriptions
    ? row.conflictDescriptions.length : 0

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
    textFormat: Text.StyledText
    text: row.bind ? Binds.highlight(row.bind.key, row.query, "<u>", "</u>") : ""
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
    anchors.right: conflictBadge.visible ? conflictBadge.left : parent.right
    anchors.rightMargin: conflictBadge.visible ? Style.spacing.sm : 0
    anchors.top: parent.top
    textFormat: Text.StyledText
    text: row.bind ? Binds.highlight(row.bind.description, row.query, "<b>", "</b>") : ""
    color: Commons.Color.foreground
    font.family: Style.fontFamily
    font.pixelSize: Style.fontPx(0.95)
    wrapMode: row.hovered ? Text.Wrap : Text.NoWrap
    elide: row.hovered ? Text.ElideNone : Text.ElideRight
  }

  // A combo bound twice runs only one of its descriptions when pressed. The
  // count sits at the right edge, out of the way, and the tooltip names the
  // other bindings without stretching the row.
  Text {
    id: conflictBadge
    visible: row.conflictCount > 1
    anchors.right: parent.right
    anchors.top: parent.top
    anchors.topMargin: 1
    textFormat: Text.PlainText
    text: row.conflictCount + "×"
    color: Commons.Color.urgent
    font.family: Style.fontFamily
    font.pixelSize: Style.fontPx(0.75)
    font.bold: true
  }

  // Only the few conflicting rows carry a tooltip; a Loader keeps the other
  // 250 rows from instantiating a popup each.
  Loader {
    active: row.conflictCount > 1

    sourceComponent: PanelToolTip {
      visible: row.hovered
      text: row.conflictHint
      fontFamily: Style.font.family
    }
  }
}
