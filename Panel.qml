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

  // Declared before anything that reads a label, so every binding below sees it.
  Commons.Translations {
    id: strings
    directory: Qt.resolvedUrl("i18n")
  }

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
    left: window.side === "left"
    right: window.side !== "left"
  }

  implicitWidth: window.plugin ? window.plugin.panelWidth : 360
  implicitHeight: 0

  readonly property int edgeDepth: window.plugin
    ? window.plugin.panelEdgeWidth
    : Style.space(8)
  // Hyprland leaves `gaps_out + border_size` between a tiled window and the
  // screen edge. The card keeps the same inset on its outer side and on the top
  // and bottom, so its outline lines up with the windows. On the inner side it
  // is flush with the space the exclusive zone reserved, which leaves the usual
  // gap between the card and the neighbouring window.
  readonly property int frameInset: Style.gapsOut * 2
    + (window.plugin ? window.plugin.borderSize : 2)
  // The pin belongs to the screen this surface is on; `screen` is set by the
  // delegate in Service.qml and can be null for a moment while it is created.
  readonly property string screenName: window.screen ? String(window.screen.name || "") : ""
  // Which side of its screen this panel sits on. Two side-by-side monitors open
  // outwards, one on each side, and a screen with neighbours on both sides has
  // no hover strip at all — the desktop edges are the only ones that reveal, so
  // crossing between monitors does not make the panel flicker.
  readonly property var screenLayout: window.plugin && window.plugin.screenLayout
    ? window.plugin.screenLayout[window.screenName] : null
  readonly property string side: window.screenLayout ? window.screenLayout.side : "right"
  readonly property bool hoverEdge: window.screenLayout ? window.screenLayout.hover : true
  readonly property bool pinned: window.plugin ? window.plugin.isPinned(window.screenName) : false
  readonly property bool loaded: window.plugin ? window.plugin.loaded : false

  property bool hoverRevealed: false
  readonly property bool revealed: window.hoverRevealed || window.pinned

  // Search state. The query lives here so the list can filter without touching
  // the shared bindings the service parsed.
  property string query: ""
  // Flat index into the filtered rows, shared by all sections. It clamps at the
  // ends instead of wrapping, and is only -1 when there is nothing to select.
  property int cursor: 0
  // Flat index of the row that was just copied, or -1. Cleared by `copyTimer`.
  property int copiedAt: -1
  property bool searchFocused: false
  // Which listing the panel shows: the compositor's bindings or tmux's. Both
  // come from Omarchy's own annotated listings and render the same way. Kept in
  // one place so the pills and the keyboard shortcut cannot drift apart.
  property string tab: "omarchy"
  // Tmux only earns a pill when its listing exists: a tab that can only report
  // that the command is missing is noise. It stays while the first read is in
  // flight, so the pills do not flicker on startup.
  readonly property bool tmuxAvailable: window.plugin ? !window.plugin.tmuxFailed : true
  readonly property var tabs: {
    var list = [{ id: "omarchy", label: strings.t("tab.omarchy") }]
    if (window.tmuxAvailable) list.push({ id: "tmux", label: strings.t("tab.tmux") })
    return list
  }
  // Number of times the focus nudge below has fired, so a panel that cannot
  // get the keyboard gives up instead of retrying forever.
  property int focusAttempts: 0
  readonly property var activeSections: {
    if (!window.plugin) return []
    return window.tab === "tmux" ? window.plugin.tmuxSections : window.plugin.sections
  }
  readonly property bool activeLoaded: window.plugin
    ? (window.tab === "tmux" ? window.plugin.tmuxLoaded : window.plugin.loaded)
    : false
  readonly property var visibleSections: Binds.filter(window.activeSections, window.query)
  readonly property int matchCount: Binds.count(window.visibleSections)
  readonly property int totalCount: Binds.count(window.activeSections)
  // Where each section's rows start in the flat cursor index, so a row delegate
  // knows whether it is the selected one.
  readonly property var rowStart: {
    var starts = []
    var total = 0
    for (var s = 0; s < window.visibleSections.length; s++) {
      starts.push(total)
      total += window.visibleSections[s].items.length
    }
    return starts
  }
  // Combos bound to more than one description. Computed over the whole tab, not
  // the filtered view, so a badge does not disappear while a query is typed.
  readonly property var conflicts: Binds.conflicts(window.activeSections)
  // One row plus the gap between rows, so an arrow key moves exactly one line.
  readonly property int rowStep: Math.round(Style.fontPx(0.95) * 1.5) + Style.spacing.sm

  onTabChanged: window.resetCursor()
  // A listing that disappears while the panel is open must not leave it on a tab
  // that no longer exists.
  onTabsChanged: {
    var ids = window.tabs.map(function(tab) { return tab.id })
    if (ids.indexOf(window.tab) === -1) window.tab = "omarchy"
  }

  // Tell the service which panel holds the keyboard, so a SUPER + arrow only
  // takes the detour below when there is a search to let go of.
  onSearchFocusedChanged: {
    if (!window.plugin) return
    if (window.searchFocused) window.plugin.searchingScreen = window.screenName
    else if (window.plugin.searchingScreen === window.screenName)
      window.plugin.searchingScreen = ""
  }

  // A monitor unplugged mid-search takes its panel with it without the change
  // above firing, which would leave `leave` dispatching a second focus move on
  // every SUPER + arrow. `screen` may already be gone here, so this checks the
  // panel's own state rather than its name.
  Component.onDestruction: {
    if (window.plugin && window.searchFocused) window.plugin.searchingScreen = ""
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

  // Flat index -> row item. The rows live in per-section Repeaters, so the one
  // that owns the index is found by walking the section lengths; there is no
  // second model of the geometry to keep in sync.
  function rowAt(index) {
    if (index < 0) return null
    var remaining = index
    for (var s = 0; s < sectionRepeater.count; s++) {
      var section = sectionRepeater.itemAt(s)
      if (!section || !section.rowItems) continue
      var count = section.modelData.items.length
      if (remaining < count) return section.rowItems.itemAt(remaining)
      remaining -= count
    }
    return null
  }

  // Keep the selected row inside the viewport. Only scrolls when it is out of
  // view, so moving one row does not recentre the list under the pointer.
  function scrollCursorIntoView() {
    var row = window.rowAt(window.cursor)
    if (!row) return
    var y = row.mapToItem(bindColumn, 0, 0).y
    var maxY = Math.max(0, list.contentHeight - list.height)
    if (y < list.contentY) list.contentY = Math.max(0, y)
    else if (y + row.height > list.contentY + list.height)
      list.contentY = Math.min(maxY, y + row.height - list.height)
  }

  // Move the cursor by `delta` rows. `Binds.moveCursor` clamps, so the ends of
  // the list do not wrap.
  function moveCursor(delta) {
    if (window.matchCount === 0) return
    window.cursor = Binds.moveCursor(window.cursor, delta, window.matchCount)
    window.scrollCursorIntoView()
  }

  // Put the selected binding on the clipboard. The combo alone is what gets
  // pasted back into a config or a terminal, so the description stays behind.
  function copyCursor() {
    if (!window.plugin || window.matchCount === 0) return
    var row = window.rowAt(window.cursor)
    if (!row || !row.bind) return
    window.plugin.copy(Binds.combo(row.bind))
    window.copiedAt = window.cursor
    copyTimer.restart()
  }

  // A new query or tab starts the cursor at the top again, and forgets any
  // "Copied" label left over from the previous listing.
  function resetCursor() {
    list.contentY = 0
    window.cursor = 0
    window.copiedAt = -1
  }

  // Tab and Shift + Tab cycle the two listings without leaving the field, so
  // typing a query and switching source never needs the pointer.
  function switchTab(step) {
    var ids = window.tabs.map(function(tab) { return tab.id })
    var index = ids.indexOf(window.tab)
    if (index === -1) index = 0
    window.tab = ids[(index + step + ids.length) % ids.length]
  }

  // Every description that shares a row's combo. Empty for a conflict-free row.
  function conflictDescriptions(bind) {
    if (!bind) return []
    return window.conflicts[Binds.combo(bind)] || []
  }

  // The tooltip: the count, then every description that shares the combo. Kept
  // in one string so each row needs no translations object of its own.
  function conflictHint(bind) {
    var descriptions = window.conflictDescriptions(bind)
    if (descriptions.length < 2) return ""
    return strings.t("row.conflict").arg(descriptions.length) + "\n"
      + descriptions.join(" · ")
  }

  onQueryChanged: window.resetCursor()
  onMatchCountChanged: {
    // A shorter listing (a narrower query, a reload) must not leave the cursor
    // past the last row.
    var last = Math.max(0, window.matchCount - 1)
    if (window.cursor > last) window.cursor = last
    if (window.copiedAt >= window.matchCount) window.copiedAt = -1
  }
  onRevealedChanged: if (!window.revealed) window.releaseSearchFocus()

  // A keybind asks the panel on the focused screen to open with the field
  // ready, so the whole sheet is reachable without the pointer.
  Connections {
    target: window.plugin

    function onSearchRequestChanged() {
      if (!window.plugin || window.plugin.searchScreen !== window.screenName) return
      // The same keybind closes the search: an unpinned panel slides away, a
      // pinned one only gives the keyboard back and stays where it was pinned.
      // Unpinning is the pin keybind's job, or the Hide button's.
      if (window.searchFocused) {
        window.hoverRevealed = false
        window.releaseSearchFocus()
        return
      }
      window.hoverRevealed = true
      window.startSearch()
    }

    // Another window took the focus: stop holding the keyboard, and let an
    // unpinned panel slide away if the pointer is not keeping it open. A pinned
    // one stays, which is what pinning is for.
    function onBlurRequestChanged() {
      if (!window.searchFocused) return
      window.releaseSearchFocus()
      hideTimer.restart()
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

  mask: Region {
    item: window.revealed ? body : null
    Region { item: window.hoverEdge ? edgeTrigger : null }
  }

  // The strip that brings the panel back. It is the whole input region while
  // the panel is hidden, so everything else falls through to the windows below.
  // Only the outside edges of the desktop get one: a screen sandwiched between
  // two others must not grab the pointer as it crosses.
  Item {
    id: edgeTrigger
    visible: window.hoverEdge
    x: window.side === "left" ? 0 : window.width - width
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
    anchors.left: window.side === "left" ? parent.left : undefined
    anchors.right: window.side === "left" ? undefined : parent.right
    anchors.verticalCenter: parent.verticalCenter
    visible: window.hoverEdge
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
    x: window.revealed ? 0 : (window.side === "left" ? -window.width : window.width)

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
      anchors.leftMargin: window.side === "left" ? window.frameInset : 0
      anchors.topMargin: window.frameInset
      anchors.rightMargin: window.side === "left" ? 0 : window.frameInset
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
            Accessible.role: Accessible.Button
            Accessible.name: pinLabel.text
            Accessible.onPressAction: if (window.plugin) window.plugin.toggleFor(window.screenName)

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
            Accessible.role: Accessible.Button
            Accessible.name: closeLabel.text
            Accessible.onPressAction: {
              window.hoverRevealed = false
              if (window.plugin) window.plugin.setPinnedFor(window.screenName, false)
            }

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
          Accessible.role: Accessible.EditableText
          Accessible.name: strings.t("panel.search")
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
          // Handle navigation before the field's own key handling: a single-line
          // TextInput would otherwise swallow Home/End and Tab.
          Keys.priority: Keys.BeforeItem
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
          Keys.onPressed: function(event) {
            switch (event.key) {
            case Qt.Key_Down:
              window.moveCursor(1)
              event.accepted = true
              break
            case Qt.Key_Up:
              window.moveCursor(-1)
              event.accepted = true
              break
            case Qt.Key_PageDown:
              window.moveCursor(Binds.pageStep(window.rowStep, list.height))
              event.accepted = true
              break
            case Qt.Key_PageUp:
              window.moveCursor(-Binds.pageStep(window.rowStep, list.height))
              event.accepted = true
              break
            case Qt.Key_Home:
              window.cursor = 0
              window.scrollCursorIntoView()
              event.accepted = true
              break
            case Qt.Key_End:
              window.cursor = Math.max(0, window.matchCount - 1)
              window.scrollCursorIntoView()
              event.accepted = true
              break
            case Qt.Key_Return:
            case Qt.Key_Enter:
              window.copyCursor()
              event.accepted = true
              break
            case Qt.Key_Tab:
              window.switchTab(1)
              event.accepted = true
              break
            case Qt.Key_Backtab:
              window.switchTab(-1)
              event.accepted = true
              break
            }
          }
        }

        // Above the input, so a click anywhere in the box (the text line
        // included) asks for the keyboard first. The press is then passed on, so
        // the input still places the cursor and selects with the mouse. Below
        // the clear button, which keeps its own click.
        MouseArea {
          anchors.fill: parent
          cursorShape: Qt.IBeamCursor
          onPressed: function(mouse) {
            window.startSearch()
            mouse.accepted = false
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

      // Which listing the panel shows. Both come from Omarchy's own annotated
      // listings, so the two tabs render exactly the same way.
      Row {
        id: tabs
        anchors.top: searchBox.bottom
        anchors.topMargin: Style.spacing.md
        anchors.left: parent.left
        anchors.leftMargin: Style.spacing.xxl
        spacing: Style.spacing.xs

        Repeater {
          model: window.tabs

          delegate: Rectangle {
            id: tabPill
            required property var modelData
            readonly property bool active: window.tab === modelData.id

            width: tabLabel.implicitWidth + Style.spacing.md * 2
            height: Math.round(Style.spacing.controlHeight * 0.82)
            radius: Style.cornerRadius
            color: tabPill.active ? Style.hoverFill : "transparent"
            border.width: Style.normalBorderWidth
            border.color: tabPill.active ? Commons.Color.accent : "transparent"
            Accessible.role: Accessible.PageTab
            Accessible.name: tabPill.modelData.label
            Accessible.selected: tabPill.active
            Accessible.onPressAction: window.tab = tabPill.modelData.id

            Text {
              id: tabLabel
              anchors.centerIn: parent
              textFormat: Text.PlainText
              text: tabPill.modelData.label
              color: tabPill.active ? Commons.Color.accent : Commons.Color.muted
              font.family: Style.fontFamily
              font.pixelSize: Style.fontPx(0.92)
              font.bold: tabPill.active
            }

            MouseArea {
              anchors.fill: parent
              cursorShape: Qt.PointingHandCursor
              onClicked: {
                // Clicking a pill must not steal the keyboard from the search
                // field; only give it back if it already had it.
                var wasSearching = window.searchFocused
                window.tab = tabPill.modelData.id
                if (wasSearching) window.startSearch()
              }
            }
          }
        }
      }

      // How much of the listing the search is showing, so a filtered list never
      // looks like a short one.
      Text {
        id: resultCount
        anchors.right: parent.right
        anchors.rightMargin: Style.spacing.xxl
        anchors.verticalCenter: tabs.verticalCenter
        visible: window.activeLoaded && window.totalCount > 0
        textFormat: Text.PlainText
        text: strings.t("panel.results").arg(window.matchCount).arg(window.totalCount)
        color: Commons.Color.muted
        font.family: Style.fontFamily
        font.pixelSize: Style.fontPx(0.85)
      }

      Rectangle {
        id: rule
        anchors.top: tabs.bottom
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
            id: sectionRepeater
            model: window.visibleSections

            delegate: Column {
              id: section
              required property var modelData
              required property int index

              // The rows are Repeater-owned; exposing the Repeater lets the
              // panel find the row at a flat cursor index without mirroring
              // section heights and gaps here.
              readonly property var rowItems: rowRepeater

              width: bindColumn.width
              spacing: Style.spacing.xs
              topPadding: index === 0 ? 0 : Style.spacing.md

              Text {
                textFormat: Text.StyledText
                // The filter also matches a section's modifier, so the header
                // has to show the highlight for that match to make sense.
                text: Binds.highlight(
                  section.modelData.mods === "" ? strings.t("group.none") : section.modelData.mods,
                  window.query, "<u>", "</u>")
                color: Commons.Color.foreground
                font.family: Style.fontFamily
                font.pixelSize: Style.fontPx(0.85)
                font.bold: true
                font.letterSpacing: 0.8
                font.capitalization: Font.AllUppercase
              }

              Repeater {
                id: rowRepeater
                model: section.modelData.items

                delegate: BindRow {
                  readonly property int flatIndex: window.rowStart[section.index] + index

                  width: section.width
                  bind: modelData
                  query: window.query
                  selected: window.cursor === flatIndex
                  copied: window.copiedAt === flatIndex
                  copiedLabel: strings.t("row.copied")
                  conflictDescriptions: window.conflictDescriptions(modelData)
                  conflictHint: window.conflictHint(modelData)
                }
              }
            }
          }
        }
      }

      // Thin position indicator. The wheel and the arrow keys both move the
      // list, and without this a long listing gives no sense of place.
      Rectangle {
        id: scrollThumb
        readonly property real maxY: Math.max(0, list.contentHeight - list.height)
        visible: maxY > 0
        x: list.x + list.width - width
        y: list.y + (maxY > 0 ? (list.contentY / maxY) * (list.height - height) : 0)
        width: Style.space(2)
        height: Math.max(Style.space(16),
          list.height * list.height / Math.max(list.height, list.contentHeight))
        radius: width / 2
        color: Commons.Color.muted
        opacity: 0.45
      }

      Text {
        anchors.centerIn: parent
        width: parent.width - Style.spacing.xxl * 2
        visible: !window.activeLoaded || (window.query !== "" && window.matchCount === 0)
        textFormat: Text.PlainText
        horizontalAlignment: Text.AlignHCenter
        wrapMode: Text.Wrap
        text: window.activeLoaded
          ? strings.t("panel.noResults")
          : window.tab === "tmux"
            ? (window.plugin && window.plugin.tmuxFailed
                ? strings.t("panel.tmuxMissing")
                : strings.t("panel.loading"))
            : (window.plugin && window.plugin.failed
                ? strings.t("panel.empty")
                : strings.t("panel.loading"))
        color: Commons.Color.muted
        font.family: Style.fontFamily
        font.pixelSize: Style.fontPx(0.95)
      }
    }
  }

  // Long enough to read, short enough not to linger on a row that is no longer
  // the one being looked at.
  Timer {
    id: copyTimer
    interval: 1400
    onTriggered: window.copiedAt = -1
  }

  Timer {
    id: hideTimer
    // Long enough to cross the gap between the edge strip and the card by
    // default; `hideDelay` replaces that guess, and 0 hides as soon as the
    // pointer leaves.
    interval: window.plugin ? window.plugin.panelHideDelay : 220
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
