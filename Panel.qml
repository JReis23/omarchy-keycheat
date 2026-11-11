import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.Commons
import qs.Commons as Commons

// One screen's cheat sheet: a layer surface pinned to the right edge that stays
// mapped and only slides its card off-screen, so revealing it never waits on a
// new surface. While it is hidden the input region is just the edge strip, so
// clicks and scrolls reach the windows underneath.
PanelWindow {
  id: window

  required property var modelData
  property var plugin: null

  screen: modelData
  color: "transparent"
  WlrLayershell.namespace: "jr-keycheat"
  WlrLayershell.layer: WlrLayer.Top
  // Never take keyboard focus: the cheat sheet is for reading while another
  // window keeps typing.
  WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
  // Placed clear of the bar's reserved edge without reserving one of its own.
  exclusionMode: ExclusionMode.Normal
  exclusiveZone: 0

  anchors {
    top: true
    bottom: true
    right: true
  }

  implicitWidth: window.plugin ? window.plugin.panelWidth : 360
  implicitHeight: 0

  readonly property int gap: Style.space(6)
  readonly property int edgeDepth: Style.space(8)
  readonly property bool pinned: window.plugin ? window.plugin.pinned : false
  readonly property bool loaded: window.plugin ? window.plugin.loaded : false

  property bool hoverRevealed: false
  readonly property bool revealed: window.hoverRevealed || window.pinned

  Commons.Translations {
    id: strings
    directory: Qt.resolvedUrl("i18n")
  }

  mask: Region {
    item: window.revealed ? body : null
    Region { item: edgeTrigger }
  }

  // The strip that brings the panel back. It is the whole input region while
  // the panel is hidden, so everything else falls through to the windows below.
  Item {
    id: edgeTrigger
    x: window.width - width
    y: 0
    width: window.edgeDepth
    height: window.height

    HoverHandler {
      id: edgeHover
      onHoveredChanged: {
        if (hovered) {
          window.hoverRevealed = true
          if (window.plugin) window.plugin.ensureLoaded()
        } else {
          hideTimer.restart()
        }
      }
    }
  }

  // A sliver of accent at the edge, so the panel is discoverable while hidden.
  Rectangle {
    id: edgeTab
    anchors.right: parent.right
    anchors.verticalCenter: parent.verticalCenter
    width: Style.space(3)
    height: Math.round(window.height * 0.22)
    radius: width / 2
    color: Commons.Color.accent
    opacity: window.revealed ? 0 : 0.5

    Behavior on opacity {
      NumberAnimation { duration: Style.duration(120); easing.type: Easing.OutCubic }
    }
  }

  Item {
    id: body
    width: window.width
    height: window.height
    x: window.revealed ? 0 : window.width

    Behavior on x {
      NumberAnimation {
        duration: window.revealed ? Style.duration(180) : Style.duration(120)
        easing.type: Easing.OutCubic
      }
    }

    HoverHandler {
      id: bodyHover
      onHoveredChanged: if (!hovered) hideTimer.restart()
    }

    Rectangle {
      id: card
      anchors.fill: parent
      anchors.margins: window.gap
      radius: Style.cornerRadius
      color: Util.alpha(Commons.Color.background, window.plugin ? window.plugin.panelOpacity : 0.94)
      border.width: Style.normalBorderWidth
      border.color: Commons.Color.popups.border
      clip: true

      Item {
        id: header
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.margins: Style.spacing.xxl
        anchors.bottomMargin: 0
        height: Style.spacing.controlHeight

        Text {
          id: title
          anchors.left: parent.left
          anchors.verticalCenter: parent.verticalCenter
          textFormat: Text.PlainText
          text: strings.t("panel.title")
          color: Commons.Color.foreground
          font.family: Style.fontFamily
          font.pixelSize: Style.fontPx(1.0)
          font.bold: true
        }

        Row {
          anchors.right: parent.right
          anchors.verticalCenter: parent.verticalCenter
          spacing: Style.spacing.sm

          Rectangle {
            id: pinButton
            width: pinLabel.implicitWidth + Style.spacing.lg * 2
            height: Style.spacing.controlHeight
            radius: Style.cornerRadius
            color: pinArea.containsMouse || window.pinned ? Style.hoverFill : Style.normalFill
            border.width: Style.normalBorderWidth
            border.color: Style.normalBorderColor

            Text {
              id: pinLabel
              anchors.centerIn: parent
              textFormat: Text.PlainText
              text: window.pinned ? strings.t("panel.unpin") : strings.t("panel.pin")
              color: Commons.Color.foreground
              font.family: Style.fontFamily
              font.pixelSize: Style.fontPx(0.92)
            }

            MouseArea {
              id: pinArea
              anchors.fill: parent
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              onClicked: if (window.plugin) window.plugin.setPinned(!window.pinned)
            }
          }

          Rectangle {
            id: closeButton
            visible: window.pinned
            width: closeLabel.implicitWidth + Style.spacing.lg * 2
            height: Style.spacing.controlHeight
            radius: Style.cornerRadius
            color: closeArea.containsMouse ? Style.hoverFill : Style.normalFill
            border.width: Style.normalBorderWidth
            border.color: Style.normalBorderColor

            Text {
              id: closeLabel
              anchors.centerIn: parent
              textFormat: Text.PlainText
              text: strings.t("panel.close")
              color: Commons.Color.foreground
              font.family: Style.fontFamily
              font.pixelSize: Style.fontPx(0.92)
            }

            MouseArea {
              id: closeArea
              anchors.fill: parent
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              onClicked: {
                window.hoverRevealed = false
                if (window.plugin) window.plugin.setPinned(false)
              }
            }
          }
        }
      }

      Rectangle {
        id: rule
        anchors.top: header.bottom
        anchors.topMargin: Style.spacing.md
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.leftMargin: Style.spacing.xxl
        anchors.rightMargin: Style.spacing.xxl
        height: Style.spacing.hairline
        color: Commons.Color.popups.border
      }

      Flickable {
        id: list
        anchors.top: rule.bottom
        anchors.topMargin: Style.spacing.md
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.leftMargin: Style.spacing.xxl
        anchors.rightMargin: Style.spacing.sm
        anchors.bottomMargin: Style.spacing.md
        contentWidth: width
        contentHeight: bindColumn.height
        clip: true
        boundsBehavior: Flickable.StopAtBounds

        Column {
          id: bindColumn
          width: list.width
          spacing: Style.spacing.sm

          Repeater {
            model: window.plugin ? window.plugin.sections : []

            delegate: Column {
              id: section
              required property var modelData
              required property int index

              width: bindColumn.width
              spacing: Style.spacing.xs
              topPadding: index === 0 ? 0 : Style.spacing.md

              Text {
                textFormat: Text.PlainText
                text: section.modelData.mods === "" ? strings.t("group.none") : section.modelData.mods
                color: Commons.Color.muted
                font.family: Style.fontFamily
                font.pixelSize: Style.fontPx(0.78)
                font.letterSpacing: 0.8
                font.capitalization: Font.AllUppercase
              }

              Repeater {
                model: section.modelData.items

                delegate: BindRow {
                  width: section.width
                  bind: modelData
                }
              }
            }
          }
        }
      }

      Text {
        anchors.centerIn: parent
        width: parent.width - Style.spacing.xxl * 2
        visible: !window.loaded
        textFormat: Text.PlainText
        horizontalAlignment: Text.AlignHCenter
        wrapMode: Text.Wrap
        text: window.plugin && window.plugin.failed
          ? strings.t("panel.empty")
          : strings.t("panel.loading")
        color: Commons.Color.muted
        font.family: Style.fontFamily
        font.pixelSize: Style.fontPx(0.95)
      }
    }
  }

  Timer {
    id: hideTimer
    // Long enough to cross the gap between the edge strip and the card.
    interval: 220
    onTriggered: {
      if (bodyHover.hovered || edgeHover.hovered || window.pinned) return
      window.hoverRevealed = false
    }
  }
}
