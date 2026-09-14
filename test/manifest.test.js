// The manifest has to line up with what the plugin actually does: the entry
// points it declares must exist, and a fresh shell.json entry must start on
// the same defaults the widget clamps to.
//
// There is deliberately no `schema` here: settings are edited in this
// plugin's own overlay, not in the Setup menu's generated form.
const test = require("node:test")
const assert = require("node:assert/strict")
const fs = require("node:fs")
const path = require("node:path")

const { SETTING_DEFAULTS } = require("../logic.js")

const root = path.join(__dirname, "..")
const manifest = JSON.parse(fs.readFileSync(path.join(root, "manifest.json"), "utf8"))
const barWidget = manifest.barWidget ?? {}

test("declares a bar widget, the overlay that edits its settings, and the boot service", () => {
  assert.deepEqual(manifest.kinds, ["bar-widget", "overlay", "service"])
  assert.equal(manifest.entryPoints.barWidget, "Workspaces.qml")
  assert.equal(manifest.entryPoints.overlay, "Overlay.qml")
  assert.equal(manifest.entryPoints.service, "Service.qml")
})

test("every declared entry point exists", () => {
  for (const [kind, file] of Object.entries(manifest.entryPoints)) {
    assert.ok(fs.existsSync(path.join(root, file)), `${kind} entry point ${file} is missing`)
  }
})

test("settings are edited in the plugin's own view, not the Setup menu", () => {
  assert.ok(!("schema" in barWidget), "a schema would put a second settings form in Setup > Plugins")
})

test("a fresh entry starts on the defaults the widget clamps to", () => {
  assert.deepEqual(barWidget.defaults, SETTING_DEFAULTS)
})
