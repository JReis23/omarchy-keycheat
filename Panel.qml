import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.Commons
import qs.Commons as Commons
import "Binds.js" as Binds

// One screen's cheat sheet: a layer surface pinned to the right edge that stays
// mapped and only slides its card off-screen, so revealing it never waits on a
// new surface. While it is hidden the input region is just the edge strip, so
// clicks and scrolls reach the windows underneath.
PanelWindow {
  id: window

  property var plugin: null

  color: "transparent"
  WlrLayershell.namespace: "jr-keycheat"
  WlrLayershell.layer: WlrLayer.Top
  // Keyboard focus is only asked for around the search field, so the panel can
  // sit open without swallowing what you type elsewhere. Hovering the field
  // arms it before the click, which is when the compositor grants focus.
  WlrLayershell.keyboardFocus: (window.searchFocused || window.searchArmed)
    ? WlrKeyboardFocus.OnDemand
    : WlrKeyboardFocus.None
  // While hidden the surface reserves nothing and the card is off-screen, so
  // tiled windows keep their full width. While pinned it reserves its own width
  // on this screen only, so the tiling layout makes room instead of being
  // covered.
  exclusionMode: ExclusionMode.Normal
  exclusiveZone: window.pinned ? window.width : 0

  anchors {
    top: true
    bottom: true
    right: true
  }

  implicitWidth: window.plugin ? window.plugin.panelWidth : 360
  implicitHeight: 0

  readonly property int gap: Style.space(6)
  readonly property int edgeDepth: Style.space(8)
  // The pin belongs to the screen this surface is on; `screen` is set by the
  // delegate in Service.qml and can be null for a moment while it is created.
  readonly property string screenName: window.screen ? String(window.screen.name || "") : ""
  readonly property bool pinned: window.plugin ? window.plugin.isPinned(window.screenName) : false
  readonly property bool loaded: window.plugin ? window.plugin.loaded : false

  property bool hoverRevealed: false
  readonly property bool revealed: window.hoverRevealed || window.pinned

  // Search state. The query lives here so the list can filter without touching
  // the shared bindings the service parsed.
  property string query: ""
  property bool searchFocused: false
  // Set while the pointer is over the field, so the surface is already
  // keyboard-interactive by the time the click lands.
  property bool searchArmed: false
  readonly property var visibleSections: window.plugin
    ? Binds.filter(window.plugin.sections, window.query)
    : []
  readonly property int matchCount: Binds.count(window.visibleSections)

  // Clicking anywhere in the field starts a search; the surface only becomes
  // keyboard-interactive from this point on.
  function startSearch() {
    window.searchFocused = true
    searchInput.forceActiveFocus()
  }

  // Give the keyboard back without forgetting what was typed: the panel can
  // hide and be re-revealed with the same filter still applied.
  function releaseSearchFocus() {
    searchInput.focus = false
    window.searchFocused = false
    window.searchArmed = false
  }

  onQueryChanged: list.contentY = 0
  onRevealedChanged: if (!window.revealed) window.releaseSearchFocus()

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
              onClicked: if (window.plugin) window.plugin.toggleFor(window.screenName)
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
                if (window.plugin) window.plugin.setPinnedFor(window.screenName, false)
              }
            }
          }
        }
      }

      Rectangle {
        id: searchBox
        anchors.top: header.bottom
        anchors.topMargin: Style.spacing.md
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.leftMargin: Style.spacing.xxl
        anchors.rightMargin: Style.spacing.xxl
        height: Style.spacing.controlHeight
        radius: Style.cornerRadius
        color: Style.normalFill
        border.width: Style.normalBorderWidth
        border.color: searchInput.activeFocus ? Commons.Color.accent : Style.normalBorderColor

        // Behind the input, so a click on the padding focuses it too.
        MouseArea {
          anchors.fill: parent
          onClicked: window.startSearch()
        }

        HoverHandler {
          onHoveredChanged: window.searchArmed = hovered
        }

        Text {
          anchors.left: parent.left
          anchors.leftMargin: Style.spacing.lg
          anchors.verticalCenter: parent.verticalCenter
          visible: searchInput.text === ""
          textFormat: Text.PlainText
          text: strings.t("panel.search")
          color: Commons.Color.muted
          font.family: Style.fontFamily
          font.pixelSize: Style.fontPx(0.95)
        }

        TextInput {
          id: searchInput
          anchors.left: parent.left
          anchors.leftMargin: Style.spacing.lg
          anchors.right: clearLabel.left
          anchors.rightMargin: Style.spacing.sm
          anchors.verticalCenter: parent.verticalCenter
          color: Commons.Color.foreground
          selectionColor: Commons.Color.accent
          selectedTextColor: Commons.Color.background
          font.family: Style.fontFamily
          font.pixelSize: Style.fontPx(0.95)
          clip: true
          selectByMouse: true
          onTextChanged: window.query = text
          onActiveFocusChanged: {
            if (activeFocus) return
            window.searchFocused = false
            // A click elsewhere dropped the keyboard: let the panel go away if
            // the pointer is no longer on it.
            if (!bodyHover.hovered && !edgeHover.hovered && !window.pinned)
              window.hoverRevealed = false
          }
          Keys.onEscapePressed: {
            if (searchInput.text !== "") searchInput.text = ""
            else if (!window.pinned) window.hoverRevealed = false
            else window.releaseSearchFocus()
          }
        }

        Text {
          id: clearLabel
          anchors.right: parent.right
          anchors.rightMargin: Style.spacing.lg
          anchors.verticalCenter: parent.verticalCenter
          visible: searchInput.text !== ""
          textFormat: Text.PlainText
          text: "\u00d7"
          color: Commons.Color.foreground
          font.family: Style.fontFamily
          font.pixelSize: Style.fontPx(1.1)

          MouseArea {
            anchors.fill: parent
            anchors.margins: -Style.spacing.sm
            cursorShape: Qt.PointingHandCursor
            onClicked: {
              searchInput.text = ""
              window.startSearch()
            }
          }
        }
      }

      Rectangle {
        id: rule
        anchors.top: searchBox.bottom
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
            model: window.visibleSections

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
                color: Commons.Color.foreground
                font.family: Style.fontFamily
                font.pixelSize: Style.fontPx(0.85)
                font.bold: true
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
        visible: !window.loaded || (window.query !== "" && window.matchCount === 0)
        textFormat: Text.PlainText
        horizontalAlignment: Text.AlignHCenter
        wrapMode: Text.Wrap
        text: !window.loaded
          ? (window.plugin && window.plugin.failed
              ? strings.t("panel.empty")
              : strings.t("panel.loading"))
          : strings.t("panel.noResults")
        color: Commons.Color.muted
        font.family: Style.fontFamily
        font.pixelSize: Style.fontPx(0.95)
      }
    }
  }

  Timer {
    id: hideTimer
    // Long enough to cross the gap between the edge strip and the card, and
    // longer while a search is focused so drifting off the panel does not close
    // it mid-word.
    interval: window.searchFocused ? 1200 : 220
    onTriggered: {
      if (bodyHover.hovered || edgeHover.hovered || window.pinned) return
      window.hoverRevealed = false
    }
  }
}
