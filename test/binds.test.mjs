import { readFileSync } from "node:fs"
import { test } from "node:test"
import assert from "node:assert/strict"

// Binds.js is a QML library file, so it carries a pragma QML understands and
// node does not. Evaluating the body here tests the exact code the panel runs.
const source = readFileSync(new URL("../Binds.js", import.meta.url), "utf8")
  .replace(/^\.pragma library\s*$/m, "")
const Binds = new Function(source + "\nreturn { parse, group, count, normalizeMods, splitCombo }")()

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
