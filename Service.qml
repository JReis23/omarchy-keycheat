import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import qs.Commons
import "Binds.js" as Binds

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
      return
    }
    bindsProcess.running = true
  }

  // Called when a panel is revealed, so a shell that started before Hyprland
  // was ready fills in on first use rather than staying empty.
  function ensureLoaded() {
    if (!loaded && !failed) reload()
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

  // Every binding change reloads Hyprland, so this is the one signal that
  // covers edits to bindings.lua as well as binds added by an app.
  Connections {
    target: Hyprland
    function onRawEvent(event) {
      if (String(event ? event.name : "") === "configreloaded") root.reload()
    }
  }

  ShellIpc {
    target: "jr.keycheat"

    function toggle(): void { root.toggleFor(root.focusedScreenName()) }
    function pin(): void { root.setPinnedFor(root.focusedScreenName(), true) }
    function unpin(): void { root.setPinnedFor(root.focusedScreenName(), false) }
    function pinAll(): void { root.setPinnedAll(true) }
    function unpinAll(): void { root.setPinnedAll(false) }
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
  }
}
