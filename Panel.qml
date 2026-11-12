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
  // The keyboard is only taken while a search is being typed in, and handed
  // back as soon as the field loses it. `Exclusive` is the only mode that makes
  // the compositor give a mapped surface the keyboard on request, so it is what
  // makes the field typable. Hyprland then refuses to move focus to another
  // window, so a SUPER + arrow asks the panel to let go first (see `leave`).
  WlrLayershell.keyboardFocus: window.searchFocused
    ? WlrKeyboardFocus.Exclusive
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

  readonly property int edgeDepth: Style.space(8)
  // Hyprland leaves `gaps_out + border_size` between a tiled window and the
  // screen edge. The card keeps the same inset on the top, right and bottom so
  // its outline lines up with the windows. On the left it is flush with the
  // space the exclusive zone reserved, which leaves the usual gap between the
  // card and the neighbouring window.
  readonly property int frameInset: Style.gapsOut * 2
    + (window.plugin ? window.plugin.borderSize : 2)
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
  // Number of times the focus nudge below has fired, so a panel that cannot
  // get the keyboard gives up instead of retrying forever.
  property int focusAttempts: 0
  readonly property var visibleSections: window.plugin
    ? Binds.filter(window.plugin.sections, window.query)
    : []
  readonly property int matchCount: Binds.count(window.visibleSections)

  // Tell the service which panel holds the keyboard, so a SUPER + arrow only
  // takes the detour below when there is a search to let go of.
  onSearchFocusedChanged: {
    if (!window.plugin) return
    if (window.searchFocused) window.plugin.searchingScreen = window.screenName
    else if (window.plugin.searchingScreen === window.screenName)
      window.plugin.searchingScreen = ""
  }

  // Clicking anywhere in the field starts a search; the surface only becomes
  // keyboard-interactive from this point on.
  function startSearch() {
    window.focusAttempts = 0
    window.searchFocused = true
    searchInput.forceActiveFocus()
  }

  // Give the keyboard back without forgetting what was typed: the panel can
  // hide and be re-revealed with the same filter still applied.
  function releaseSearchFocus() {
    searchInput.focus = false
    window.searchFocused = false
  }

  onQueryChanged: list.contentY = 0
  onRevealedChanged: if (!window.revealed) window.releaseSearchFocus()

  // A keybind asks the panel on the focused screen to open with the field
  // ready, so the whole sheet is reachable without the pointer.
  Connections {
    target: window.plugin

    function onSearchRequestChanged() {
      if (!window.plugin || window.plugin.searchScreen !== window.screenName) return
      // The same keybind closes it: a pinned screen behaves like the Hide
      // button (unpin + slide away), an unpinned one just slides away.
      if (window.searchFocused) {
        window.hoverRevealed = false
        if (window.pinned) window.plugin.setPinnedFor(window.screenName, false)
        window.releaseSearchFocus()
        return
      }
      window.hoverRevealed = true
      window.startSearch()
    }

    // Another window took the focus: stop holding the keyboard.
    function onBlurRequestChanged() {
      if (window.searchFocused) window.releaseSearchFocus()
    }

    // A SUPER + arrow bind asks the searching panel to let the compositor move
    // focus. `Exclusive` is what blocks the move, so the keyboard goes back
    // first; the service dispatches the focus change right after.
    function onLeaveRequestChanged() {
      if (!window.searchFocused) return
      window.releaseSearchFocus()
      if (!window.pinned) window.hoverRevealed = false
    }
  }

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
      anchors.leftMargin: 0
      anchors.topMargin: window.frameInset
      anchors.rightMargin: window.frameInset
      anchors.bottomMargin: window.frameInset
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
    // Long enough to cross the gap between the edge strip and the card.
    interval: 220
    onTriggered: {
      // Never close under someone who is typing into the search field, even
      // when the pointer is elsewhere (the keybind opens it that way).
      if (bodyHover.hovered || edgeHover.hovered || window.pinned || window.searchFocused) return
      window.hoverRevealed = false
    }
  }

  // The compositor hands the keyboard over a moment after the surface asks for
  // it, so nudge Qt until the field really has focus. `activeFocus` stops the
  // timer, and the attempt count stops it if the keyboard never arrives.
  Timer {
    interval: 40
    repeat: true
    running: window.searchFocused && !searchInput.activeFocus && window.focusAttempts < 30
    onTriggered: {
      window.focusAttempts += 1
      searchInput.forceActiveFocus()
    }
  }
}
