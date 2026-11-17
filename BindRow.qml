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
  // The keyboard cursor is on this row. `copied` is the short confirmation
  // after Enter put the binding on the clipboard.
  property bool selected: false
  property bool copied: false
  property string copiedLabel: ""
  // A favourite shows its star all the time; any other row shows an empty one
  // while hovered or selected. Clicking it only asks: the service owns the list.
  property bool favourite: false
  property string favouriteLabel: ""
  signal favouriteToggled()
  readonly property bool starVisible: row.favourite || row.hovered || row.selected
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

  Accessible.role: Accessible.ListItem
  Accessible.name: row.bind
    ? String(row.bind.key) + " — " + String(row.bind.description) : ""
  Accessible.selected: row.selected
  Accessible.description: row.conflictHint

  HoverHandler {
    onHoveredChanged: row.hovered = hovered
  }

  // Behind the text, so the selected row reads as one block rather than two
  // highlighted columns.
  Rectangle {
    anchors.fill: parent
    radius: Style.cornerRadius
    color: Style.selectedFill
    visible: row.selected
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
    anchors.right: row.copied
      ? copiedLabel.left
      : (conflictBadge.visible ? conflictBadge.left : star.visible ? star.left : parent.right)
    anchors.rightMargin: (row.copied || conflictBadge.visible || star.visible) ? Style.spacing.sm : 0
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
    visible: row.conflictCount > 1 && !row.copied
    anchors.right: star.visible ? star.left : parent.right
    anchors.rightMargin: star.visible ? Style.spacing.sm : 0
    anchors.top: parent.top
    anchors.topMargin: 1
    textFormat: Text.PlainText
    text: row.conflictCount + "×"
    color: Commons.Color.urgent
    font.family: Style.fontFamily
    font.pixelSize: Style.fontPx(0.75)
    font.bold: true
  }

  Text {
    id: copiedLabel
    visible: row.copied
    anchors.right: star.visible ? star.left : parent.right
    anchors.rightMargin: star.visible ? Style.spacing.sm : 0
    anchors.top: parent.top
    anchors.topMargin: 1
    textFormat: Text.PlainText
    text: row.copiedLabel
    color: Commons.Color.accent
    font.family: Style.fontFamily
    font.pixelSize: Style.fontPx(0.75)
    font.bold: true
  }

  // The mark. Filled for a favourite, an outline otherwise.
  Text {
    id: star
    visible: row.starVisible
    anchors.right: parent.right
    anchors.top: parent.top
    textFormat: Text.PlainText
    text: row.favourite ? "\u2605" : "\u2606"
    color: row.favourite ? Commons.Color.accent : Commons.Color.muted
    font.family: Style.fontFamily
    font.pixelSize: Style.fontPx(0.95)

    Accessible.role: Accessible.Button
    Accessible.name: row.favouriteLabel

    MouseArea {
      anchors.fill: parent
      anchors.margins: -Style.spacing.xs
      cursorShape: Qt.PointingHandCursor
      onClicked: row.favouriteToggled()
    }
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
