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
  for (var m = 0; m < mods.length; m++)
    sections.push({ mods: mods[m], items: sortByKey(byMods[mods[m]]) })
  return sections
}

// Function keys and numbered rows read best in numeric order: F2 belongs
// before F10, and a plain string compare would put it after. Runs of digits are
// compared as numbers, every other run as text.
function naturalCompare(a, b) {
  var left = String(a || "").match(/(\d+|\D+)/g) || []
  var right = String(b || "").match(/(\d+|\D+)/g) || []

  for (var i = 0; i < Math.min(left.length, right.length); i++) {
    var leftIsNumber = /^\d+$/.test(left[i])
    var rightIsNumber = /^\d+$/.test(right[i])
    var result
    if (leftIsNumber && rightIsNumber) {
      result = Number(left[i]) - Number(right[i])
    } else {
      var lowerLeft = left[i].toLowerCase()
      var lowerRight = right[i].toLowerCase()
      result = lowerLeft < lowerRight ? -1 : lowerLeft > lowerRight ? 1 : 0
    }
    if (result !== 0) return result
  }

  return left.length - right.length
}

function sortByKey(items) {
  var out = items.slice()
  out.sort(function(a, b) { return naturalCompare(a.key, b.key) })
  return out
}

// `omarchy-menu-tmux-keybindings --print` uses the same shape as the Hyprland
// listing, with PREFIX and COPY MODE standing in for the modifier:
//
//   PREFIX                            → CTRL + SPACE / CTRL + B
//   PREFIX + %                        → Split window horizontally
//   PREFIX + CTRL + SPACE             → Send prefix
//   ALT + LEFT                        → Previous window
//
// The lone PREFIX line names the keys that open the prefix table, so it becomes
// a row of its own instead of a group with no modifier.
function parseTmux(raw) {
  var lines = String(raw || "").split("\n")
  var out = []
  for (var i = 0; i < lines.length; i++) {
    var line = lines[i]
    var arrow = line.indexOf("\u2192")
    if (arrow === -1) continue
    var description = line.slice(arrow + 1).trim()
    if (description === "") continue

    var left = line.slice(0, arrow).trim()
    if (left === "") continue
    var cut = left.lastIndexOf(" + ")
    if (cut === -1) {
      if (left === "PREFIX") out.push({ mods: "PREFIX", key: "prefix", description: description })
      else out.push({ mods: "", key: left, description: description })
      continue
    }
    out.push({
      mods: left.slice(0, cut).trim(),
      key: left.slice(cut + 3).trim(),
      description: description
    })
  }
  return out
}

// The prefix table first, then its own modifier combos, then the root-table
// binds, and the copy-mode ones last.
function tmuxRank(mods) {
  if (mods === "PREFIX") return 0
  if (mods.indexOf("PREFIX") === 0) return 1
  if (mods.indexOf("COPY MODE") === 0) return 3
  return 2
}

function groupTmux(entries) {
  var byMods = {}
  for (var i = 0; i < entries.length; i++) {
    var entry = entries[i]
    if (!byMods[entry.mods]) byMods[entry.mods] = []
    byMods[entry.mods].push(entry)
  }

  var mods = Object.keys(byMods)
  mods.sort(function(a, b) {
    var ra = tmuxRank(a)
    var rb = tmuxRank(b)
    if (ra !== rb) return ra - rb
    if (a < b) return -1
    if (a > b) return 1
    return 0
  })

  var sections = []
  for (var m = 0; m < mods.length; m++)
    sections.push({ mods: mods[m], items: sortByKey(byMods[mods[m]]) })
  return sections
}

function count(sections) {
  var total = 0
  for (var i = 0; i < sections.length; i++) total += sections[i].items.length
  return total
}

// The words a query is made of, lowercased and without repeats. Shared by the
// filter and the highlighter so a row can never highlight something it did not
// match on, or match on something it does not highlight.
function queryTerms(query) {
  var parts = String(query || "").toLowerCase().trim().split(/\s+/)
  var terms = []
  for (var i = 0; i < parts.length; i++)
    if (parts[i] !== "" && terms.indexOf(parts[i]) === -1) terms.push(parts[i])
  return terms
}

// How much a single query word says about a row. The bands are ordered on
// purpose: a key that starts with the word is the best answer, then a key that
// contains it, then the modifier group, then the description. A word that
// matches two fields only earns the best of them, so the score never depends on
// the order the words were typed in.
var SCORE_KEY_PREFIX = 100
var SCORE_KEY = 80
var SCORE_MODS = 60
var SCORE_DESCRIPTION_PREFIX = 40
var SCORE_DESCRIPTION = 20

function scoreTerm(section, item, term) {
  var key = String(item.key || "").toLowerCase()
  if (key.indexOf(term) === 0) return SCORE_KEY_PREFIX
  if (key.indexOf(term) !== -1) return SCORE_KEY

  if (String(section.mods || "").toLowerCase().indexOf(term) !== -1) return SCORE_MODS

  var description = String(item.description || "").toLowerCase()
  if (description.indexOf(term) === 0) return SCORE_DESCRIPTION_PREFIX
  if (description.indexOf(term) !== -1) return SCORE_DESCRIPTION

  return 0
}

// A row scores the sum of its words, and only when every word matched. Summing
// makes "super w" and "w super" produce the same number; a word that matches
// nothing rules the row out, exactly as `filter` did before ranking existed.
function score(section, item, terms) {
  var total = 0
  for (var t = 0; t < terms.length; t++) {
    var value = scoreTerm(section, item, terms[t])
    if (value === 0) return 0
    total += value
  }
  return total
}

// Case-insensitive search over the modifier, the key and the description.
// Groups left without a match disappear, so the list only shows what matched.
// Every word of the query must appear somewhere, so "super close" finds
// SUPER + W even though the two words are not adjacent, and the order they are
// typed in does not matter. Rows keep the listing's order; `rank` is the one
// that sorts them by how well they match.
function filter(sections, query) {
  var terms = queryTerms(query)
  if (terms.length === 0) return sections

  var out = []
  for (var s = 0; s < sections.length; s++) {
    var section = sections[s]
    var items = []
    for (var i = 0; i < section.items.length; i++) {
      if (score(section, section.items[i], terms) > 0) items.push(section.items[i])
    }
    if (items.length > 0) out.push({ mods: section.mods, items: items })
  }
  return out
}

// The same match as `filter`, with the closest rows first inside each group.
// Ties keep the listing's natural order (modifier group, then numeric key
// order), so a query that matches everything equally changes nothing. Groups
// keep their order too: the list still reads SUPER, then CTRL, then ALT.
function rank(sections, query) {
  var terms = queryTerms(query)
  if (terms.length === 0) return sections

  var out = []
  for (var s = 0; s < sections.length; s++) {
    var section = sections[s]
    var scored = []
    for (var i = 0; i < section.items.length; i++) {
      var value = score(section, section.items[i], terms)
      if (value > 0) scored.push({ item: section.items[i], score: value, order: i })
    }
    if (scored.length === 0) continue

    scored.sort(function(a, b) {
      if (b.score !== a.score) return b.score - a.score
      return a.order - b.order
    })

    var items = []
    for (var k = 0; k < scored.length; k++) items.push(scored[k].item)
    out.push({ mods: section.mods, items: items })
  }
  return out
}

// Match positions are indices into the plain string, but the row renders HTML,
// so every run has to be escaped before it gets there. `&` first, or the
// entities of the later replacements would be escaped again.
function escapeHtml(text) {
  return String(text || "")
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
}

function escapePattern(text) {
  return String(text).replace(/[.*+?^${}()|[\]\\]/g, "\\$&")
}

// Returns `text` ready for `Text.StyledText`, with every query term wrapped in
// `open`/`close` and everything else escaped. The terms are the same ones
// `filter` used, so the highlight explains why the row is in the list.
function highlight(text, query, open, close) {
  var source = String(text || "")
  var terms = queryTerms(query)
  if (terms.length === 0) return escapeHtml(source)

  // Longest first, so a query of "su super" wraps the whole word instead of
  // leaving "per" outside the match.
  terms = terms.slice().sort(function(a, b) { return b.length - a.length })
  var pattern = new RegExp("(" + terms.map(escapePattern).join("|") + ")", "gi")
  var opening = open === undefined ? "<b>" : String(open)
  var closing = close === undefined ? "</b>" : String(close)

  var out = ""
  var last = 0
  var match
  while ((match = pattern.exec(source)) !== null) {
    out += escapeHtml(source.slice(last, match.index))
    out += opening + escapeHtml(match[0]) + closing
    last = match.index + match[0].length
    // A zero-length match would loop forever. No term can be empty, but this
    // keeps a future change from hanging the shell.
    if (match[0] === "") pattern.lastIndex += 1
  }
  return out + escapeHtml(source.slice(last))
}

// A combo as it is pressed, rebuilt from the parts the listing gives. The
// modifiers are already normalised by `parse`/`parseTmux`.
function combo(item) {
  if (!item) return ""
  var mods = String(item.mods || "")
  var key = String(item.key || "")
  return mods === "" ? key : mods + " + " + key
}

// How a favourite is stored in the state file. The combo alone is stable when a
// description is edited, but ambiguous when the same combo is bound twice, so
// the description rides along: "SUPER + W|Close window".
function favouriteId(item) {
  if (!item) return ""
  var key = combo(item)
  if (key === "") return ""
  var description = String(item.description || "").trim()
  return description === "" ? key : key + "|" + description
}

// The combo part of a stored id. The first "|" splits it: a combo never holds
// one, a description may.
function idCombo(id) {
  var text = String(id || "")
  var cut = text.indexOf("|")
  return cut === -1 ? text : text.slice(0, cut)
}

// What a listing can answer about a list of stored ids: which row ids exist and
// which combos exist. One pass, shared by every function below.
function favouriteIndex(sections) {
  var index = { exact: {}, combos: {} }
  for (var s = 0; s < (sections || []).length; s++) {
    var items = sections[s].items
    for (var i = 0; i < items.length; i++) {
      index.exact[favouriteId(items[i])] = true
      index.combos[combo(items[i])] = true
    }
  }
  return index
}

// The rows a list of stored ids marks, keyed by `favouriteId`. An id marks the
// row it names exactly; when no row has that description any more it falls back
// to every row on the same combo, so editing a description does not lose the
// favourite. An id that matches nothing marks nothing: a bind removed from the
// config is dropped quietly rather than shown as a ghost.
function favouriteSet(sections, ids) {
  var index = favouriteIndex(sections)
  var byCombo = {}
  for (var s = 0; s < (sections || []).length; s++) {
    var items = sections[s].items
    for (var i = 0; i < items.length; i++) {
      var key = combo(items[i])
      ;(byCombo[key] || (byCombo[key] = [])).push(favouriteId(items[i]))
    }
  }

  var marked = {}
  for (var n = 0; n < (ids || []).length; n++) {
    var id = String(ids[n])
    if (index.exact[id]) {
      marked[id] = true
      continue
    }
    var rows = byCombo[idCombo(id)] || []
    for (var r = 0; r < rows.length; r++) marked[rows[r]] = true
  }
  return marked
}

function isFavourite(item, marked) {
  return !!item && !!marked && marked[favouriteId(item)] === true
}

// The favourite rows of a listing, in the listing's own order. Favourites are a
// shortcut to rows that already exist, never a second list with its own order:
// marking one must not renumber the rest. `query` filters them like any other
// row, and ranking never reorders them.
function favouriteItems(sections, ids, query) {
  var marked = favouriteSet(sections, ids)
  var terms = queryTerms(query)
  var out = []
  for (var s = 0; s < (sections || []).length; s++) {
    var section = sections[s]
    for (var i = 0; i < section.items.length; i++) {
      var item = section.items[i]
      if (!isFavourite(item, marked)) continue
      if (terms.length > 0 && score(section, item, terms) === 0) continue
      out.push(item)
    }
  }
  return out
}

// The ids after marking or unmarking `item`. Unmarking removes whatever marked
// it, which may be a bare combo or an id whose description was edited, and
// leaves every other id where it was.
function toggleFavourite(ids, sections, item) {
  var list = (ids || []).map(String)
  var id = favouriteId(item)
  if (id === "") return list

  if (!isFavourite(item, favouriteSet(sections, list))) return list.concat([id])

  var index = favouriteIndex(sections)
  var key = combo(item)
  return list.filter(function(stored) {
    if (stored === id) return false
    return !(idCombo(stored) === key && !index.exact[stored])
  })
}

// Ids that no longer name anything in a loaded listing. Only called once that
// listing has rows: an empty or failed read must not wipe the favourites.
function pruneFavourites(ids, sections) {
  var index = favouriteIndex(sections)
  return (ids || []).map(String).filter(function(id) {
    return index.exact[id] === true || index.combos[idCombo(id)] === true
  })
}

// The state file. Version 1 adds the favourites; a file without a version holds
// only pins and loads as the same pins with no favourites.
var STATE_VERSION = 1

function readState(raw) {
  var parsed = null
  try {
    parsed = JSON.parse(String(raw || ""))
  } catch (error) {
    parsed = null
  }
  var state = { screens: null, favourites: { omarchy: [], tmux: [] } }
  if (!parsed || typeof parsed !== "object") return state

  if (Array.isArray(parsed.screens)) {
    state.screens = parsed.screens.map(String).filter(function(name) { return name !== "" })
  }
  var saved = parsed.favourites
  if (saved && typeof saved === "object") {
    var tabs = ["omarchy", "tmux"]
    for (var t = 0; t < tabs.length; t++) {
      var list = saved[tabs[t]]
      if (!Array.isArray(list)) continue
      state.favourites[tabs[t]] = list.map(String).filter(function(id, at, all) {
        return id !== "" && all.indexOf(id) === at
      })
    }
  }
  return state
}

function writeState(screens, favourites) {
  return JSON.stringify({
    version: STATE_VERSION,
    screens: (screens || []).slice().sort(),
    favourites: {
      omarchy: ((favourites || {}).omarchy || []).slice(),
      tmux: ((favourites || {}).tmux || []).slice()
    }
  }, null, 2) + "\n"
}

// Cursor arithmetic over the flat list of visible rows. It clamps at the ends
// instead of wrapping: pressing Down on the last row keeps the last row
// selected, so the keyboard never jumps back to the top by accident.
function moveCursor(index, delta, total) {
  if (!(total > 0)) return -1
  var next = Number(index) + Number(delta)
  if (!isFinite(next)) next = 0
  return Math.max(0, Math.min(total - 1, Math.round(next)))
}

// How many rows a PageUp/PageDown should move. A viewport shorter than one row
// still moves one.
function pageStep(rowHeight, viewportHeight) {
  var row = Number(rowHeight)
  var view = Number(viewportHeight)
  if (!(row > 0) || !(view > 0)) return 1
  return Math.max(1, Math.floor(view / row))
}

// Combos bound to more than one description, keyed by combo. A combo listed
// twice with the same description is one binding shown twice, not a conflict.
// Each listing has its own keyspace, so never pass Hyprland and tmux bindings
// to the same call.
function conflicts(sections) {
  var byCombo = {}
  for (var s = 0; s < (sections || []).length; s++) {
    var items = sections[s].items
    for (var i = 0; i < items.length; i++) {
      var key = combo(items[i])
      var descriptions = byCombo[key] || (byCombo[key] = [])
      if (descriptions.indexOf(items[i].description) === -1)
        descriptions.push(items[i].description)
    }
  }

  var out = {}
  var keys = Object.keys(byCombo).sort()
  for (var k = 0; k < keys.length; k++)
    if (byCombo[keys[k]].length > 1) out[keys[k]] = byCombo[keys[k]]
  return out
}
