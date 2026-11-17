import { readFileSync } from "node:fs"
import { test } from "node:test"
import assert from "node:assert/strict"

// Binds.js is a QML library file, so it carries a pragma QML understands and
// node does not. Evaluating the body here tests the exact code the panel runs.
const source = readFileSync(new URL("../Binds.js", import.meta.url), "utf8")
  .replace(/^\.pragma library\s*$/m, "")
const Binds = new Function(source +
  "\nreturn { parse, group, groupTmux, parseTmux, count, filter, rank, highlight, conflicts, combo, queryTerms, moveCursor, pageStep, normalizeMods, splitCombo }")()

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
