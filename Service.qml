import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import qs.Commons
import "Binds.js" as Binds
import "Screens.js" as Screens

// Feeds every screen's cheat sheet. The window itself lives in Panel.qml; this
// service only reads the bindings and owns the pin state the panels share.
//
// A service plugin is the right kind here: there is no bar icon, the window is
// a layer surface of its own, and `ShellIpc` gives it a target to talk to.
Item {
  id: root

  property var shell: null
  property var manifest: null

  // Third-party plugins get a scoped shell API without `shellConfig`, so the
  // options come straight from the file the user already edits.
  readonly property string configPath: {
    var base = Quickshell.env("XDG_CONFIG_HOME")
    if (!base) base = Quickshell.env("HOME") + "/.config"
    return base + "/omarchy/shell.json"
  }

  property var options: ({})
  // Pinning is per screen: with two monitors, pinning one must not take the
  // other one's space. Keyed by Quickshell's screen name.
  property var pinnedScreens: ({})
  property bool optionsApplied: false
  readonly property int panelWidth: root.numberOption("width", 240, 640, 360)
  readonly property real panelOpacity: root.numberOption("opacity", 0.4, 1, 0.94)

  property var sections: []
  property bool loaded: false
  property bool failed: false
  property bool pendingReload: false

  // Tmux bindings, from Omarchy's own annotated listing: same shape as the
  // Hyprland one, so the panel renders both with the same code.
  property var tmuxSections: []
  property bool tmuxLoaded: false
  property bool tmuxFailed: false
  property bool tmuxPending: false
  readonly property string tmuxConfigPath: {
    var override = Quickshell.env("TMUX_CONF")
    if (override) return override
    var base = Quickshell.env("XDG_CONFIG_HOME")
    if (!base) base = Quickshell.env("HOME") + "/.config"
    return base + "/tmux/tmux.conf"
  }

  // Window border width from Hyprland, used to line the panel card up with the
  // tiled windows. Read on start and after every config reload.
  property int borderSize: 2

  // Plain copy of the screen geometry, so the layout below re-runs whenever a
  // monitor is plugged in, unplugged or moved.
  readonly property var screenGeometries: {
    var out = []
    for (var i = 0; i < Quickshell.screens.length; i++) {
      var s = Quickshell.screens[i]
      out.push({ name: s.name, x: s.x, y: s.y, width: s.width, height: s.height })
    }
    return out
  }

  // Which edge each screen's panel belongs to, and whether its hidden edge strip
  // exists at all. Only the outside of the desktop reveals on hover, so moving
  // the pointer between two monitors no longer grazes a strip and makes the
  // panel flicker.
  readonly property var screenLayout: Screens.layout(root.screenGeometries)

  // Bumped by the `search` IPC so the panel on the focused screen reveals
  // itself and puts the cursor in the search field.
  property int searchRequest: 0
  property string searchScreen: ""

  // Bumped when another window becomes active, so a search that holds the
  // keyboard gives it back instead of trapping it.
  property int blurRequest: 0

  // The screen whose panel holds the keyboard for a search, set by the panel
  // itself. Empty when no search is open.
  property string searchingScreen: ""
  // Bumped by `leave` so that panel lets go of the keyboard.
  property int leaveRequest: 0
  property string leaveDirection: ""

  function numberOption(name, min, max, fallback) {
    var value = Number(root.options[name])
    if (!isFinite(value)) return fallback
    return Math.max(min, Math.min(max, value))
  }

  function applyOptions(raw) {
    var parsed = null
    try {
      parsed = JSON.parse(String(raw || ""))
    } catch (error) {
      parsed = null
    }
    var keycheat = parsed && parsed.keycheat && typeof parsed.keycheat === "object"
      ? parsed.keycheat : ({})
    root.options = keycheat

    // The configured pin only seeds the session; pinning from the panel or IPC
    // afterwards must not be undone by the next config save.
    if (!root.optionsApplied) {
      root.optionsApplied = true
      root.setPinnedAll(keycheat.pinned === true)
    }
  }

  function reload() {
    if (bindsProcess.running) {
      pendingReload = true
    } else {
      bindsProcess.running = true
    }
    root.reloadTmux()
  }

  // Tmux bindings change when the user edits their config, not when Hyprland
  // reloads, so this has its own trigger.
  function reloadTmux() {
    if (tmuxProcess.running) {
      tmuxPending = true
      return
    }
    tmuxProcess.running = true
  }

  // Called when a panel is revealed, so a shell that started before Hyprland
  // was ready fills in on first use rather than staying empty.
  function ensureLoaded() {
    if (!loaded && !failed) reload()
    else if (!tmuxLoaded && !tmuxFailed) root.reloadTmux()
  }

  // Pinning is per screen: pinning the panel on one monitor must not take the
  // other monitor's space. Keyed by Quickshell's screen name.
  function isPinned(screenName) {
    return root.pinnedScreens[String(screenName || "")] === true
  }

  function setPinnedFor(screenName, value) {
    var name = String(screenName || "")
    if (name === "") return
    var next = Object.assign({}, root.pinnedScreens)
    if (value === true) next[name] = true
    else delete next[name]
    root.pinnedScreens = next
  }

  function toggleFor(screenName) {
    root.setPinnedFor(screenName, !root.isPinned(screenName))
  }

  function setPinnedAll(value) {
    if (value !== true) {
      root.pinnedScreens = ({})
      return
    }
    var next = {}
    for (var i = 0; i < Quickshell.screens.length; i++) {
      var name = String(Quickshell.screens[i].name || "")
      if (name !== "") next[name] = true
    }
    root.pinnedScreens = next
  }

  // The IPC commands act on the screen the pointer/keyboard is on, which is the
  // one the user means when they run them from a terminal in that workspace.
  function focusedScreenName() {
    return Hyprland.focusedMonitor ? String(Hyprland.focusedMonitor.name || "") : ""
  }

  function requestSearch() {
    var name = root.focusedScreenName()
    if (name === "") return
    root.searchScreen = name
    root.searchRequest += 1
  }

  // A SUPER + arrow must still move focus away while the search field holds the
  // keyboard. Hyprland refuses focus changes while a layer surface has it with
  // `Exclusive`, so the panel lets go first and the move is dispatched once the
  // compositor has seen that. With no search open there is nothing to release:
  // the bind the user already has moves focus on its own.
  function leave(direction) {
    var dir = String(direction || "").toLowerCase()
    if (["left", "right", "up", "down"].indexOf(dir) === -1) return
    if (root.searchingScreen === "") return
    root.leaveDirection = dir
    root.leaveRequest += 1
    leaveTimer.restart()
  }

  // Long enough for the panel's keyboard release to reach the compositor.
  Timer {
    id: leaveTimer
    interval: 90
    onTriggered: {
      var dir = root.leaveDirection
      root.leaveDirection = ""
      if (dir === "") return
      Quickshell.execDetached(["hyprctl", "dispatch",
        'hl.dsp.focus({ direction = "' + dir + '" })'])
    }
  }

  FileView {
    id: configFile
    path: root.configPath
    watchChanges: true
    blockLoading: true
    printErrors: false
    onLoaded: root.applyOptions(text())
    onFileChanged: root.applyOptions(text())
  }

  Process {
    id: bindsProcess
    command: ["omarchy", "menu", "keybindings", "--print"]

    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var entries = Binds.parse(text)
        root.sections = Binds.group(entries)
        root.loaded = entries.length > 0
        root.failed = entries.length === 0
      }
    }

    // Deferred: the process still reports running while it signals exit.
    onExited: {
      // A command that never produced output leaves the panel saying "reading"
      // forever; say what happened instead.
      if (!root.loaded) {
        root.failed = true
      }
      if (!root.pendingReload) return
      root.pendingReload = false
      Qt.callLater(root.reload)
    }
  }

  // Tmux runs its own config parse, so watching the file is what keeps this
  // fresh; Hyprland's reloads say nothing about it.
  FileView {
    path: root.tmuxConfigPath
    watchChanges: true
    blockLoading: true
    printErrors: false
    onFileChanged: root.reloadTmux()
  }

  Process {
    id: tmuxProcess
    command: ["omarchy-menu-tmux-keybindings", "--print"]

    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var entries = Binds.parseTmux(text)
        root.tmuxSections = Binds.groupTmux(entries)
        root.tmuxLoaded = entries.length > 0
        root.tmuxFailed = entries.length === 0
      }
    }

    onExited: {
      if (!root.tmuxLoaded) root.tmuxFailed = true
      if (!root.tmuxPending) return
      root.tmuxPending = false
      Qt.callLater(root.reloadTmux)
    }
  }

  // Every binding change reloads Hyprland, so this is the one signal that
  // covers edits to bindings.lua as well as binds added by an app.
  Connections {
    target: Hyprland
    function onRawEvent(event) {
      var name = String(event ? event.name : "")
      if (name === "activewindow") {
        root.blurRequest += 1
        return
      }
      if (name !== "configreloaded") return
      root.reload()
      borderProcess.running = true
    }
  }

  Process {
    id: borderProcess
    command: ["hyprctl", "-j", "getoption", "decoration:border_size"]

    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        try {
          var value = Number(JSON.parse(text).int)
          if (isFinite(value) && value >= 0) root.borderSize = Math.round(value)
        } catch (error) {
          // hyprctl missing / Hyprland not running — keep the previous value.
        }
      }
    }
  }

  ShellIpc {
    target: "jr.keycheat"

    function toggle(): void { root.toggleFor(root.focusedScreenName()) }
    function pin(): void { root.setPinnedFor(root.focusedScreenName(), true) }
    function unpin(): void { root.setPinnedFor(root.focusedScreenName(), false) }
    function pinAll(): void { root.setPinnedAll(true) }
    function unpinAll(): void { root.setPinnedAll(false) }
    function search(): void { root.requestSearch() }
    function leave(direction: string): void { root.leave(direction) }
    function refresh(): void { root.reload() }
  }

  Variants {
    id: panels
    model: Quickshell.screens

    delegate: Component {
      Panel {
        required property var modelData

        screen: modelData
        plugin: root
      }
    }
  }

  Component.onCompleted: {
    root.applyOptions(configFile.text())
    root.reload()
    borderProcess.running = true
  }
}
