import { readFileSync } from "node:fs"
import { test } from "node:test"
import assert from "node:assert/strict"

// Binds.js is a QML library file, so it carries a pragma QML understands and
// node does not. Evaluating the body here tests the exact code the panel runs.
const source = readFileSync(new URL("../Binds.js", import.meta.url), "utf8")
  .replace(/^\.pragma library\s*$/m, "")
const Binds = new Function(source +
  "\nreturn { parse, group, groupTmux, parseTmux, parseNvim, groupNvim, nvimKeys, count, filter, rank, favouriteId, favouriteSet, favouriteItems, toggleFavourite, pruneFavourites, isFavourite, readState, writeState, highlight, conflicts, combo, queryTerms, moveCursor, pageStep, normalizeMods, splitCombo }")()

const SAMPLE = [
  "SUPER + K                           → Keybindings",
  "SUPER + W / SUPER + Q               → Close window",
  "SUPER SHIFT + Q / XF86Calculator    → Calculator",
  "XF86AudioRaiseVolume                → Volume up",
  "SUPER ALT + mouse_down              → Next window in group",
  "not a binding line",
  "SUPER + F                           → ",
  ""
].join("\n")

test("normalizeMods puts modifiers in a stable order", () => {
  assert.equal(Binds.normalizeMods("SHIFT SUPER"), "SUPER SHIFT")
  assert.equal(Binds.normalizeMods("SUPER SHIFT CTRL"), "SUPER CTRL SHIFT")
  assert.equal(Binds.normalizeMods("  "), "")
})

test("splitCombo separates modifiers from the key", () => {
  assert.deepEqual(Binds.splitCombo("SUPER SHIFT + F"), { mods: "SUPER SHIFT", key: "F" })
  assert.deepEqual(Binds.splitCombo("XF86Calculator"), { mods: "", key: "XF86Calculator" })
  // The key itself may contain a plus.
  assert.deepEqual(Binds.splitCombo("CTRL + PLUS"), { mods: "CTRL", key: "PLUS" })
})

test("parse reads every combo of a line and skips noise", () => {
  const entries = Binds.parse(SAMPLE)
  assert.equal(entries.length, 7)
  assert.deepEqual(entries[0], { mods: "SUPER", key: "K", description: "Keybindings" })
  assert.deepEqual(entries[1], { mods: "SUPER", key: "W", description: "Close window" })
  assert.deepEqual(entries[2], { mods: "SUPER", key: "Q", description: "Close window" })
  assert.deepEqual(entries[3], { mods: "SUPER SHIFT", key: "Q", description: "Calculator" })
  assert.deepEqual(entries[4], { mods: "", key: "XF86Calculator", description: "Calculator" })
  assert.deepEqual(entries[5], { mods: "", key: "XF86AudioRaiseVolume", description: "Volume up" })
  assert.deepEqual(entries[6], { mods: "SUPER ALT", key: "mouse_down", description: "Next window in group" })
})

test("parse ignores empty descriptions and arrow-less lines", () => {
  const entries = Binds.parse(SAMPLE)
  assert.ok(!entries.some((entry) => entry.description === ""))
  assert.ok(!entries.some((entry) => entry.key === "not a binding line"))
})

test("group puts SUPER first, unmodified keys last", () => {
  const sections = Binds.group(Binds.parse(SAMPLE))
  assert.deepEqual(sections.map((section) => section.mods), ["SUPER", "SUPER SHIFT", "SUPER ALT", ""])
  assert.equal(Binds.count(sections), 7)
})

test("group sorts keys inside a section", () => {
  const sections = Binds.group([
    { mods: "SUPER", key: "Z", description: "z" },
    { mods: "SUPER", key: "A", description: "a" },
    { mods: "SUPER", key: "M", description: "m" }
  ])
  assert.deepEqual(sections[0].items.map((item) => item.key), ["A", "M", "Z"])
})

test("group merges modifier orders that mean the same thing", () => {
  const sections = Binds.group([
    { mods: Binds.normalizeMods("SUPER SHIFT CTRL"), key: "A", description: "a" },
    { mods: Binds.normalizeMods("CTRL SUPER SHIFT"), key: "B", description: "b" }
  ])
  assert.equal(sections.length, 1)
  assert.equal(sections[0].mods, "SUPER CTRL SHIFT")
})

test("parse survives the real output", () => {
  const raw = readFileSync(new URL("./fixtures/binds.txt", import.meta.url), "utf8")
  const sections = Binds.group(Binds.parse(raw))
  assert.ok(sections.length > 5)
  assert.equal(sections[0].mods, "SUPER")
  assert.equal(sections[sections.length - 1].mods, "")
  assert.ok(Binds.count(sections) > 200)
  for (const section of sections) {
    assert.ok(section.items.length > 0)
    for (const item of section.items) assert.ok(item.key.length > 0 && item.description.length > 0)
  }
})

test("filter keeps only matching rows and drops empty groups", () => {
  const sections = Binds.group(Binds.parse(SAMPLE))
  const close = Binds.filter(sections, "close")
  assert.deepEqual(close.map((section) => section.mods), ["SUPER"])
  assert.deepEqual(close[0].items.map((item) => item.key), ["Q", "W"])
  assert.equal(Binds.count(close), 2)
})

test("filter is case-insensitive and matches modifiers too", () => {
  const sections = Binds.group(Binds.parse(SAMPLE))
  assert.equal(Binds.count(Binds.filter(sections, "VOLUME")), 1)
  assert.equal(Binds.count(Binds.filter(sections, "super alt")), 1)
  assert.equal(Binds.count(Binds.filter(sections, "super shift")), 1)
})

test("filter returns everything for an empty query", () => {
  const sections = Binds.group(Binds.parse(SAMPLE))
  assert.equal(Binds.filter(sections, "   "), sections)
  assert.equal(Binds.count(Binds.filter(sections, "")), Binds.count(sections))
})

test("group sorts keys in numeric order, so F2 comes before F10", () => {
  const sections = Binds.group(Binds.parse([
    "SUPER + F1  → One",
    "SUPER + F10 → Ten",
    "SUPER + F2  → Two",
    "SUPER + F12 → Twelve",
    ""
  ].join("\n")))
  assert.deepEqual(sections[0].items.map((item) => item.key), ["F1", "F2", "F10", "F12"])
})

test("filter matches every word of the query, in any order", () => {
  const sections = Binds.group(Binds.parse(SAMPLE))
  assert.equal(Binds.count(Binds.filter(sections, "super close")), 2)
  assert.equal(Binds.count(Binds.filter(sections, "close super")), 2)
  assert.equal(Binds.count(Binds.filter(sections, "xf86 volume")), 1)
  assert.equal(Binds.count(Binds.filter(sections, "close zzz")), 0)
})

const RANK_SAMPLE = [
  "SUPER + W   → Close window",
  "SUPER + Q   → Quit, then wake the window",
  "SUPER + K   → Keybindings",
  "SUPER + SPACE → Launch the app menu",
  ""
].join("\n")

test("rank puts a key match before a description match", () => {
  const sections = Binds.group(Binds.parse(RANK_SAMPLE))
  const ranked = Binds.rank(sections, "w")
  // W is the key; "window" in the other rows only matches the description.
  assert.deepEqual(ranked[0].items.map((item) => item.key), ["W", "Q"])
})

test("rank scores a key prefix above a key substring above a description", () => {
  const sections = Binds.group(Binds.parse([
    "SUPER + F1      → Alpha",
    "SUPER + BACKSPACE → Bravo",
    "SUPER + Z      → Mentions BACK in text",
    ""
  ].join("\n")))
  const ranked = Binds.rank(sections, "back")
  assert.deepEqual(ranked[0].items.map((item) => item.key), ["BACKSPACE", "Z"])
})

test("rank gives the same order whatever order the words are typed in", () => {
  const sections = Binds.group(Binds.parse(RANK_SAMPLE))
  const a = Binds.rank(sections, "super w").map((s) => s.items.map((i) => i.key))
  const b = Binds.rank(sections, "w super").map((s) => s.items.map((i) => i.key))
  assert.deepEqual(a, b)
  assert.equal(a[0][0], "W")
})

test("rank keeps the listing's order for equal scores", () => {
  const sections = Binds.group(Binds.parse([
    "SUPER + A → Same words here",
    "SUPER + B → Same words here",
    "SUPER + C → Same words here",
    ""
  ].join("\n")))
  const ranked = Binds.rank(sections, "same")
  assert.deepEqual(ranked[0].items.map((item) => item.key), ["A", "B", "C"])
})

test("rank matches exactly what filter matches", () => {
  const sections = Binds.group(Binds.parse(SAMPLE))
  for (const query of ["close", "super close", "volume", "alt", "zzz", "q"]) {
    const kept = Binds.filter(sections, query).flatMap((s) => s.items.map((i) => s.mods + i.key))
    const ranked = Binds.rank(sections, query).flatMap((s) => s.items.map((i) => s.mods + i.key))
    assert.deepEqual(ranked.slice().sort(), kept.slice().sort(), query)
  }
})

test("rank leaves group order alone and returns an empty query unchanged", () => {
  const sections = Binds.group(Binds.parse(SAMPLE))
  assert.equal(Binds.rank(sections, "  "), sections)
  const mods = Binds.rank(sections, "window").map((s) => s.mods)
  const original = sections.map((s) => s.mods).filter((m) => mods.includes(m))
  assert.deepEqual(mods, original)
})

const TMUX_SAMPLE = [
  "PREFIX                           → CTRL + SPACE / CTRL + B",
  "PREFIX + %                       → Split window horizontally",
  "PREFIX + CTRL + SPACE            → Send prefix",
  "ALT + LEFT                       → Previous window",
  "COPY MODE + y                    → Copy selection",
  ""
].join("\n")

test("parseTmux turns the prefix line into its own row", () => {
  const entries = Binds.parseTmux(TMUX_SAMPLE)
  assert.equal(entries.length, 5)
  assert.deepEqual(entries[0], { mods: "PREFIX", key: "prefix", description: "CTRL + SPACE / CTRL + B" })
  assert.deepEqual(entries[1], { mods: "PREFIX", key: "%", description: "Split window horizontally" })
  assert.deepEqual(entries[2], { mods: "PREFIX + CTRL", key: "SPACE", description: "Send prefix" })
  assert.deepEqual(entries[3], { mods: "ALT", key: "LEFT", description: "Previous window" })
  assert.deepEqual(entries[4], { mods: "COPY MODE", key: "y", description: "Copy selection" })
})

test("groupTmux puts PREFIX first and copy mode last", () => {
  const sections = Binds.groupTmux(Binds.parseTmux(TMUX_SAMPLE))
  assert.deepEqual(sections.map((section) => section.mods), ["PREFIX", "PREFIX + CTRL", "ALT", "COPY MODE"])
  assert.deepEqual(sections[0].items.map((item) => item.key), ["%", "prefix"])
})

test("filter works on tmux rows too", () => {
  const sections = Binds.groupTmux(Binds.parseTmux(TMUX_SAMPLE))
  assert.equal(Binds.count(Binds.filter(sections, "split")), 1)
  // "prefix" matches the group name, so every row in both prefix groups counts.
  assert.equal(Binds.count(Binds.filter(sections, "prefix")), 3)
})

test("filter returns nothing when no row matches", () => {
  const sections = Binds.group(Binds.parse(SAMPLE))
  assert.deepEqual(Binds.filter(sections, "zzz-no-such-bind"), [])
})

const NVIM_SAMPLE = [
  "n\t<Leader>ff\tFind files",
  "n\t<Leader>sg\tLive grep",
  "v\t<C-S-P>\tPaste without yanking",
  "i\t<M-k>\tMove Up",
  "t\t<C-\\><C-n>\tGo to normal mode",
  "c\t<C-b>\tScroll backward",
  "o\t<Leader>z\tOperator only",
  ""
].join("\n")

test("parseNvim reads the mode, the keys and the description", () => {
  const entries = Binds.parseNvim(NVIM_SAMPLE)
  assert.equal(entries.length, 7)
  assert.deepEqual(entries[0], {
    mods: "NORMAL",
    key: "LEADER FF",
    description: "Find files",
    copy: "<Leader>ff"
  })
  assert.deepEqual(entries[2].mods, "VISUAL")
  assert.deepEqual(entries[2].key, "CTRL+SHIFT+P")
  assert.deepEqual(entries[3].key, "ALT+K")
  assert.deepEqual(entries[4].key, "CTRL+\\ CTRL+N")
})

test("nvimKeys keeps presses apart from chords", () => {
  assert.equal(Binds.nvimKeys("<C-w>v"), "CTRL+W V")
  assert.equal(Binds.nvimKeys("<Leader><Tab>["), "LEADER TAB [")
  assert.equal(Binds.nvimKeys("gcc"), "GCC")
  assert.equal(Binds.nvimKeys("<Space>w"), "SPACE W")
  assert.equal(Binds.nvimKeys("<Esc>"), "ESC")
})

test("parseNvim skips lines without a description or a known mode", () => {
  const raw = [
    "n\t<Leader>x\t",
    "z\t<Leader>y\tUnknown mode",
    "n\t<Leader>z\tKept"
  ].join("\n")
  assert.deepEqual(Binds.parseNvim(raw).map((item) => item.key), ["LEADER Z"])
})

test("groupNvim puts normal first, operator last and sorts the keys", () => {
  const sections = Binds.groupNvim(Binds.parseNvim(NVIM_SAMPLE))
  assert.deepEqual(sections.map((section) => section.mods),
    ["NORMAL", "VISUAL", "INSERT", "TERMINAL", "COMMAND", "OPERATOR"])
  assert.deepEqual(sections[0].items.map((item) => item.key), ["LEADER FF", "LEADER SG"])
})

test("the same Neovim keys in two modes are not a conflict", () => {
  const sections = Binds.groupNvim(Binds.parseNvim([
    "n\t<C-s>\tSave",
    "v\t<C-s>\tSave selection"
  ].join("\n")))
  assert.deepEqual(Binds.conflicts(sections), {})
})

const CONFLICT_SAMPLE = [
  "ALT + TAB                      → Focus on next window",
  "ALT + TAB                      → Reveal active window on top",
  "SHIFT ALT + TAB                → Focus on previous window",
  "ALT SHIFT + TAB                → Reveal active window on top",
  "ALT + Alt_R                    → Start dictation (push-to-talk)",
  "ALT + Alt_R                    → Stop dictation (push-to-talk)",
  "SUPER + W                      → Close window",
  "SUPER + W                      → Close window",
  ""
].join("\n")

test("queryTerms splits on whitespace and drops repeats", () => {
  assert.deepEqual(Binds.queryTerms("  SUPER   close super "), ["super", "close"])
  assert.deepEqual(Binds.queryTerms("   "), [])
  assert.deepEqual(Binds.queryTerms(""), [])
})

test("highlight wraps every term and leaves the rest alone", () => {
  assert.equal(Binds.highlight("SUPER + W", "super", "<u>", "</u>"), "<u>SUPER</u> + W")
  assert.equal(Binds.highlight("w close w", "w"), "<b>w</b> close <b>w</b>")
  assert.equal(Binds.highlight("SUPER + W", ""), "SUPER + W")
})

test("highlight escapes the text before it adds markup", () => {
  assert.equal(Binds.highlight("A & B < C", ""), "A &amp; B &lt; C")
  assert.equal(Binds.highlight("A & B < C", "b"), "A &amp; <b>B</b> &lt; C")
})

test("highlight treats regex characters as literal terms", () => {
  assert.equal(Binds.highlight("CTRL + [", "[", "<b>", "</b>"), "CTRL + <b>[</b>")
})

test("highlight matches the longest term first", () => {
  assert.equal(Binds.highlight("super", "su super", "<b>", "</b>"), "<b>super</b>")
})

test("conflicts flags combos bound to different descriptions", () => {
  const map = Binds.conflicts(Binds.group(Binds.parse(CONFLICT_SAMPLE)))
  assert.deepEqual(Object.keys(map).sort(), ["ALT + Alt_R", "ALT + TAB", "ALT SHIFT + TAB"])
  assert.deepEqual(map["ALT + TAB"], ["Focus on next window", "Reveal active window on top"])
})

test("a combo listed twice with the same description is not a conflict", () => {
  const map = Binds.conflicts(Binds.group(Binds.parse(CONFLICT_SAMPLE)))
  assert.equal(map["SUPER + W"], undefined)
  assert.deepEqual(Binds.conflicts([]), {})
})

test("combo rebuilds the key as it is pressed", () => {
  assert.equal(Binds.combo({ mods: "SUPER", key: "W" }), "SUPER + W")
  assert.equal(Binds.combo({ mods: "", key: "XF86AudioMute" }), "XF86AudioMute")
  assert.equal(Binds.combo(null), "")
})

test("moveCursor clamps at both ends instead of wrapping", () => {
  assert.equal(Binds.moveCursor(0, 1, 5), 1)
  assert.equal(Binds.moveCursor(4, 1, 5), 4)
  assert.equal(Binds.moveCursor(0, -1, 5), 0)
  assert.equal(Binds.moveCursor(2, 10, 5), 4)
  assert.equal(Binds.moveCursor(2, -10, 5), 0)
})

test("moveCursor handles an empty list and bad input", () => {
  assert.equal(Binds.moveCursor(0, 1, 0), -1)
  assert.equal(Binds.moveCursor(-1, 0, 3), 0)
  assert.equal(Binds.moveCursor("2", "1", 5), 3)
  assert.equal(Binds.moveCursor(0, NaN, 5), 0)
})

test("pageStep turns a viewport into whole rows, at least one", () => {
  assert.equal(Binds.pageStep(30, 300), 10)
  assert.equal(Binds.pageStep(30, 329), 10)
  assert.equal(Binds.pageStep(30, 10), 1)
  assert.equal(Binds.pageStep(0, 300), 1)
  assert.equal(Binds.pageStep(30, 0), 1)
})

const FAV_SAMPLE = [
  "SUPER + W   → Close window",
  "SUPER + K   → Keybindings",
  "SUPER + T   → Terminal",
  "ALT + TAB   → Cycle windows",
  "ALT + TAB   → Cycle workspaces",
  ""
].join("\n")

const favSections = () => Binds.group(Binds.parse(FAV_SAMPLE))
const keysOf = (items) => items.map((item) => item.key)

test("favouriteId carries the combo and the description", () => {
  const item = favSections()[0].items[0]
  assert.match(Binds.favouriteId(item), /^SUPER \+ \w\|.+/)
  assert.equal(Binds.favouriteId(null), "")
})

test("favourites come out in the listing's order, not the order they were marked", () => {
  const sections = favSections()
  const ids = ["SUPER + T|Terminal", "SUPER + W|Close window"]
  assert.deepEqual(keysOf(Binds.favouriteItems(sections, ids, "")), ["T", "W"])
})

test("a removed bind is dropped quietly and a bare combo still marks its row", () => {
  const sections = favSections()
  assert.deepEqual(keysOf(Binds.favouriteItems(sections, ["SUPER + Z|Gone"], "")), [])
  assert.deepEqual(keysOf(Binds.favouriteItems(sections, ["SUPER + K"], "")), ["K"])
})

test("an id falls back to its combo when the description was edited", () => {
  const sections = favSections()
  const items = Binds.favouriteItems(sections, ["SUPER + K|Old description"], "")
  assert.deepEqual(keysOf(items), ["K"])
})

test("a combo bound twice keeps its two favourites apart", () => {
  const sections = favSections()
  const alt = sections.find((section) => section.mods === "ALT")
  const marked = Binds.favouriteSet(sections, ["ALT + TAB|Cycle workspaces"])
  assert.equal(Binds.isFavourite(alt.items[0], marked), false)
  assert.equal(Binds.isFavourite(alt.items[1], marked), true)
})

test("the query filters favourites without reordering them", () => {
  const sections = favSections()
  const ids = ["SUPER + W|Close window", "SUPER + T|Terminal"]
  assert.deepEqual(keysOf(Binds.favouriteItems(sections, ids, "term")), ["T"])
})

test("toggleFavourite marks, unmarks and leaves other ids in place", () => {
  const sections = favSections()
  const super_ = sections.find((section) => section.mods === "SUPER").items
  const w = super_.find((item) => item.key === "W")
  const t = super_.find((item) => item.key === "T")

  let ids = Binds.toggleFavourite([], sections, w)
  ids = Binds.toggleFavourite(ids, sections, t)
  assert.deepEqual(ids, ["SUPER + W|Close window", "SUPER + T|Terminal"])

  ids = Binds.toggleFavourite(ids, sections, w)
  assert.deepEqual(ids, ["SUPER + T|Terminal"])
})

test("unmarking removes a bare combo that was marking the row", () => {
  const sections = favSections()
  const k = sections.find((section) => section.mods === "SUPER").items.find((item) => item.key === "K")
  assert.deepEqual(Binds.toggleFavourite(["SUPER + K", "SUPER + T|Terminal"], sections, k),
    ["SUPER + T|Terminal"])
})

test("pruneFavourites drops ids whose bind is gone", () => {
  const sections = favSections()
  assert.deepEqual(
    Binds.pruneFavourites(["SUPER + W|Close window", "SUPER + Z|Gone", "SUPER + K|Edited"], sections),
    ["SUPER + W|Close window", "SUPER + K|Edited"])
})

test("the state file round-trips favourites and pins", () => {
  const text = Binds.writeState(["DP-3", "DP-1"], { omarchy: ["SUPER + W|Close window"], tmux: [] })
  const state = Binds.readState(text)
  assert.equal(JSON.parse(text).version, 1)
  assert.deepEqual(state.screens, ["DP-1", "DP-3"])
  assert.deepEqual(state.favourites, { omarchy: ["SUPER + W|Close window"], tmux: [] })
})

test("a state file from before favourites loads its pins and no favourites", () => {
  const state = Binds.readState('{ "screens": ["DP-3"] }')
  assert.deepEqual(state.screens, ["DP-3"])
  assert.deepEqual(state.favourites, { omarchy: [], tmux: [] })
})

test("a missing or broken state file reads as empty, without pins to restore", () => {
  for (const raw of ["", "{", "null", "[]", undefined]) {
    const state = Binds.readState(raw)
    assert.equal(state.screens, null)
    assert.deepEqual(state.favourites, { omarchy: [], tmux: [] })
  }
})

test("readState ignores junk inside the favourites lists", () => {
  const state = Binds.readState(JSON.stringify({
    version: 1,
    favourites: { omarchy: ["A|b", "", "A|b", 3], tmux: "nope" }
  }))
  assert.deepEqual(state.favourites, { omarchy: ["A|b", "3"], tmux: [] })
})
