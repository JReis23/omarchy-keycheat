.pragma library

// Turns the plain-text output of `omarchy menu keybindings --print` into the
// groups the panel renders. Kept free of QML so test/binds.test.mjs can run the
// same code under node.
//
// One line of that output looks like:
//
//   SUPER SHIFT + F                     → File manager
//   SUPER + W / SUPER + Q               → Close window
//   XF86AudioRaiseVolume                → Volume up
//
// The left side is modifiers joined by spaces, then " + ", then the key. A line
// can carry several combos for one description, separated by " / ".

var MODIFIER_ORDER = ["SUPER", "CTRL", "ALT", "SHIFT"]

// Groups read best with the most used modifiers first and the unmodified media
// and function keys last.
var GROUP_ORDER = [
  "SUPER",
  "SUPER SHIFT",
  "SUPER CTRL",
  "SUPER ALT",
  "SUPER CTRL SHIFT",
  "SUPER CTRL ALT",
  "SUPER ALT SHIFT",
  "SUPER CTRL ALT SHIFT",
  "CTRL",
  "CTRL ALT",
  "CTRL ALT SHIFT",
  "ALT",
  "ALT SHIFT",
  "SHIFT",
  ""
]

function modifierRank(name) {
  var index = MODIFIER_ORDER.indexOf(name)
  return index === -1 ? MODIFIER_ORDER.length : index
}

// Hyprland writes the same modifier set in different orders ("SUPER SHIFT CTRL"
// and "SUPER CTRL SHIFT"). Normalising them keeps one group per real combo.
function normalizeMods(mods) {
  var parts = String(mods || "").split(/\s+/)
  var kept = []
  for (var i = 0; i < parts.length; i++)
    if (parts[i] !== "") kept.push(parts[i])
  kept.sort(function(a, b) { return modifierRank(a) - modifierRank(b) })
  return kept.join(" ")
}

function splitCombo(combo) {
  var left = String(combo || "").trim()
  var cut = left.lastIndexOf(" + ")
  if (cut === -1) return { mods: "", key: left }
  return {
    mods: normalizeMods(left.slice(0, cut)),
    key: left.slice(cut + 3).trim()
  }
}

function parse(raw) {
  var lines = String(raw || "").split("\n")
  var out = []
  for (var i = 0; i < lines.length; i++) {
    var line = lines[i]
    var arrow = line.indexOf("\u2192")
    if (arrow === -1) continue
    var description = line.slice(arrow + 1).trim()
    if (description === "") continue

    var combos = line.slice(0, arrow).trim().split(" / ")
    for (var c = 0; c < combos.length; c++) {
      var combo = splitCombo(combos[c])
      if (combo.key === "") continue
      out.push({ mods: combo.mods, key: combo.key, description: description })
    }
  }
  return out
}

function groupRank(mods) {
  var index = GROUP_ORDER.indexOf(mods)
  // An unknown combo still gets a group; it just sorts before the unmodified
  // one instead of vanishing.
  return index === -1 ? GROUP_ORDER.length - 1 : index
}

function group(entries) {
  var byMods = {}
  for (var i = 0; i < entries.length; i++) {
    var entry = entries[i]
    if (!byMods[entry.mods]) byMods[entry.mods] = []
    byMods[entry.mods].push(entry)
  }

  var mods = Object.keys(byMods)
  mods.sort(function(a, b) { return groupRank(a) - groupRank(b) })

  var sections = []
  for (var m = 0; m < mods.length; m++) {
    var items = byMods[mods[m]].slice()
    items.sort(function(a, b) {
      var ka = String(a.key).toLowerCase()
      var kb = String(b.key).toLowerCase()
      if (ka < kb) return -1
      if (ka > kb) return 1
      return 0
    })
    sections.push({ mods: mods[m], items: items })
  }
  return sections
}

function count(sections) {
  var total = 0
  for (var i = 0; i < sections.length; i++) total += sections[i].items.length
  return total
}
