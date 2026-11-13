import { readFileSync } from "node:fs"
import { test } from "node:test"
import assert from "node:assert/strict"

// Screens.js is a QML library file, so it carries a pragma node does not know.
const source = readFileSync(new URL("../Screens.js", import.meta.url), "utf8")
  .replace(/^\.pragma library\s*$/m, "")
const Screens = new Function(source + "\nreturn { layout }")()

const screen = (name, x, y, width, height) => ({ name, x, y, width, height })

test("a single screen opens on the right", () => {
  const layout = Screens.layout([screen("DP-1", 0, 0, 2560, 1440)])
  assert.deepEqual(layout["DP-1"], { side: "right", hover: true })
})

test("side by side screens open outwards", () => {
  const layout = Screens.layout([
    screen("LEFT", 0, 0, 2560, 1440),
    screen("RIGHT", 2560, 0, 2560, 1440)
  ])
  assert.deepEqual(layout["LEFT"], { side: "left", hover: true })
  assert.deepEqual(layout["RIGHT"], { side: "right", hover: true })
})

test("stacked screens both open on the right", () => {
  const layout = Screens.layout([
    screen("TOP", 0, 0, 2560, 1440),
    screen("BOTTOM", 0, 1440, 2560, 1440)
  ])
  assert.deepEqual(layout["TOP"], { side: "right", hover: true })
  assert.deepEqual(layout["BOTTOM"], { side: "right", hover: true })
})

test("only the ends of a three screen desktop open on hover", () => {
  const layout = Screens.layout([
    screen("A", 0, 0, 2560, 1440),
    screen("B", 2560, 0, 2560, 1440),
    screen("C", 5120, 0, 2560, 1440)
  ])
  assert.deepEqual(layout["A"], { side: "left", hover: true })
  assert.deepEqual(layout["B"], { side: "right", hover: false })
  assert.deepEqual(layout["C"], { side: "right", hover: true })
})

test("a 2x2 grid opens outwards on both columns", () => {
  const layout = Screens.layout([
    screen("TOP-LEFT", 0, 0, 2560, 1440),
    screen("TOP-RIGHT", 2560, 0, 2560, 1440),
    screen("BOTTOM-LEFT", 0, 1440, 2560, 1440),
    screen("BOTTOM-RIGHT", 2560, 1440, 2560, 1440)
  ])
  assert.deepEqual(layout["TOP-LEFT"], { side: "left", hover: true })
  assert.deepEqual(layout["TOP-RIGHT"], { side: "right", hover: true })
  assert.deepEqual(layout["BOTTOM-LEFT"], { side: "left", hover: true })
  assert.deepEqual(layout["BOTTOM-RIGHT"], { side: "right", hover: true })
})

test("negative coordinates are handled like any other layout", () => {
  const layout = Screens.layout([
    screen("LEFT", -2560, 0, 2560, 1440),
    screen("RIGHT", 0, 0, 2560, 1440)
  ])
  assert.deepEqual(layout["LEFT"], { side: "left", hover: true })
  assert.deepEqual(layout["RIGHT"], { side: "right", hover: true })
})

test("a narrower screen stacked under a wider one stays on the right", () => {
  const layout = Screens.layout([
    screen("EXTERNAL", 0, 0, 2560, 1440),
    screen("LAPTOP", 0, 1440, 1920, 1200)
  ])
  assert.deepEqual(layout["EXTERNAL"], { side: "right", hover: true })
  assert.deepEqual(layout["LAPTOP"], { side: "right", hover: true })
})

test("a centred screen under a wider one keeps its hover strip", () => {
  const layout = Screens.layout([
    screen("EXTERNAL", 0, 0, 2560, 1440),
    screen("LAPTOP", 320, 1440, 1920, 1200)
  ])
  assert.deepEqual(layout["LAPTOP"], { side: "right", hover: true })
})

test("a screen above the middle of a row has no seams of its own", () => {
  const layout = Screens.layout([
    screen("A", 0, 0, 1920, 1080),
    screen("B", 1920, 0, 1920, 1080),
    screen("C", 3840, 0, 1920, 1080),
    screen("TOP", 1920, -1080, 1920, 1080)
  ])
  assert.deepEqual(layout["B"], { side: "right", hover: false })
  assert.deepEqual(layout["TOP"], { side: "right", hover: true })
})

test("side by side screens with different heights and offsets still pair up", () => {
  const layout = Screens.layout([
    screen("LAPTOP", 0, 240, 1920, 1200),
    screen("EXTERNAL", 1920, 0, 2560, 1440)
  ])
  assert.deepEqual(layout["LAPTOP"], { side: "left", hover: true })
  assert.deepEqual(layout["EXTERNAL"], { side: "right", hover: true })
})

test("a pixel of gap from fractional scaling still counts as touching", () => {
  const layout = Screens.layout([
    screen("LEFT", 0, 0, 2048, 1152),
    screen("RIGHT", 2049, 0, 2560, 1440)
  ])
  assert.deepEqual(layout["LEFT"], { side: "left", hover: true })
  assert.deepEqual(layout["RIGHT"], { side: "right", hover: true })
})

test("mirrored screens are not neighbours", () => {
  const layout = Screens.layout([
    screen("A", 0, 0, 1920, 1080),
    screen("B", 0, 0, 1920, 1080)
  ])
  assert.deepEqual(layout["A"], { side: "right", hover: true })
  assert.deepEqual(layout["B"], { side: "right", hover: true })
})

test("no screens means no layout", () => {
  assert.deepEqual(Screens.layout([]), {})
  assert.deepEqual(Screens.layout(null), {})
})
