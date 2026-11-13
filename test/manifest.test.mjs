import { readFileSync, existsSync, lstatSync, readdirSync } from "node:fs"
import { test } from "node:test"
import assert from "node:assert/strict"
import { dirname, isAbsolute, join, normalize } from "node:path"
import { fileURLToPath } from "node:url"

// Mirrors the checks `omarchy plugin validate` makes, so CI catches a broken
// manifest on a stock runner where the Omarchy CLI does not exist.
const root = dirname(dirname(fileURLToPath(import.meta.url)))
const manifest = JSON.parse(readFileSync(join(root, "manifest.json"), "utf8"))

test("manifest declares every field the shell and marketplace require", () => {
  assert.equal(manifest.schemaVersion, 1)
  for (const field of ["id", "name", "version", "author", "description"]) {
    assert.equal(typeof manifest[field], "string", `${field} must be a string`)
    assert.ok(manifest[field].trim() !== "", `${field} must not be empty`)
  }
})

test("manifest id is valid and outside the reserved namespace", () => {
  assert.match(manifest.id, /^[A-Za-z0-9][A-Za-z0-9._-]*$/)
  assert.ok(!manifest.id.includes(".."))
  assert.ok(!manifest.id.startsWith("omarchy."))
})

test("manifest kinds is a non-empty array", () => {
  assert.ok(Array.isArray(manifest.kinds))
  assert.ok(manifest.kinds.length > 0)
  for (const kind of manifest.kinds) assert.equal(typeof kind, "string")
})

test("every entry point is a relative path inside the repository", () => {
  assert.equal(typeof manifest.entryPoints, "object")
  assert.ok(!Array.isArray(manifest.entryPoints))
  for (const [name, entry] of Object.entries(manifest.entryPoints)) {
    assert.equal(typeof entry, "string", `${name} must be a string`)
    assert.ok(entry !== "", `${name} must not be empty`)
    assert.ok(!isAbsolute(entry), `${name} must be relative`)
    assert.ok(!normalize(entry).startsWith(".."), `${name} must stay inside the plugin`)
    assert.ok(existsSync(join(root, entry)), `${name} points at a missing file: ${entry}`)
    assert.ok(lstatSync(join(root, entry)).isFile(), `${name} must point at a file: ${entry}`)
  }
})

test("each kind has the entry point the shell loads for it", () => {
  const required = {
    bar: "bar",
    "bar-widget": "barWidget",
    menu: "menu",
    overlay: "overlay",
    panel: "panel",
    service: "service",
  }
  for (const kind of manifest.kinds) {
    if (!required[kind]) continue
    assert.ok(
      Object.hasOwn(manifest.entryPoints, required[kind]),
      `kind "${kind}" needs entryPoints.${required[kind]}`,
    )
  }
})

test("the plugin folder contains no symlinks", () => {
  const links = []
  const walk = (dir) => {
    for (const entry of readdirSync(dir, { withFileTypes: true })) {
      if (entry.name === ".git") continue
      const path = join(dir, entry.name)
      if (entry.isSymbolicLink()) links.push(path)
      else if (entry.isDirectory()) walk(path)
    }
  }
  walk(root)
  assert.deepEqual(links, [])
})
