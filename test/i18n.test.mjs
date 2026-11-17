import { readFileSync } from "node:fs"
import { test } from "node:test"
import assert from "node:assert/strict"
import { dirname, join } from "node:path"
import { fileURLToPath } from "node:url"

// The panel reads its labels through `strings.t(...)`, so a key missing from a
// locale file surfaces as a broken label at runtime. These checks are static on
// purpose: they need neither the shell nor a running Hyprland.
const root = dirname(dirname(fileURLToPath(import.meta.url)))
const locales = ["en.json", "pt.json"]
const sources = ["Panel.qml", "Service.qml", "BindRow.qml"]

const read = (name) => JSON.parse(readFileSync(join(root, "i18n", name), "utf8"))

test("every locale carries the same keys", () => {
  const reference = Object.keys(read("en.json")).sort()
  for (const name of locales) {
    assert.deepEqual(Object.keys(read(name)).sort(), reference, `${name} diverges from en.json`)
  }
})

test("every key the QML asks for exists in every locale", () => {
  const used = new Set()
  for (const file of sources) {
    const text = readFileSync(join(root, file), "utf8")
    for (const match of text.matchAll(/strings\.t\("([^"]+)"\)/g)) used.add(match[1])
  }
  assert.ok(used.size > 0, "no strings.t(...) call found")

  for (const name of locales) {
    const table = read(name)
    for (const key of used) assert.ok(key in table, `${name} is missing ${key}`)
  }
})

test("no locale leaves a value empty", () => {
  for (const name of locales) {
    for (const [key, value] of Object.entries(read(name))) {
      assert.equal(typeof value, "string", `${name}: ${key} must be a string`)
      assert.ok(value.trim() !== "", `${name}: ${key} is empty`)
    }
  }
})
