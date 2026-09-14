// The manifest has to line up with what the plugin actually does: the entry
// points it declares must exist, and a fresh shell.json entry must start on
// the same defaults the widget clamps to.
//
// The `schema` puts these settings in Setup > Plugins, alongside every other
// widget's - the plugin's own overlay stays the richer view (it applies live
// and carries the per-setup boot assignments, which aren't plugin-wide
// settings a schema could describe), but it is reachable only from the
// overview's gear or a key you bound yourself, so without a schema the
// settings are invisible where a user would first look for them. Both write
// the same shell.json keys, so neither can disagree with the other.
//
// The schema is a second copy of what SETTING_FIELDS already says, in the
// shape Omarchy's generated form wants. The tests below are what keep the
// copy honest: every range, label and default is compared back to the field
// list rather than trusted.
const test = require("node:test")
const assert = require("node:assert/strict")
const fs = require("node:fs")
const path = require("node:path")

const { SETTING_DEFAULTS, SETTING_FIELDS } = require("../js/logic.js")

const root = path.join(__dirname, "..")
const manifest = JSON.parse(fs.readFileSync(path.join(root, "manifest.json"), "utf8"))
const barWidget = manifest.barWidget ?? {}

test("declares a bar widget, the overlay that edits its settings, and the boot service", () => {
  assert.deepEqual(manifest.kinds, ["bar-widget", "overlay", "service"])
  assert.equal(manifest.entryPoints.barWidget, "qml/Workspaces.qml")
  assert.equal(manifest.entryPoints.overlay, "qml/Overlay.qml")
  assert.equal(manifest.entryPoints.service, "qml/Service.qml")
})

test("every declared entry point exists", () => {
  for (const [kind, file] of Object.entries(manifest.entryPoints)) {
    assert.ok(fs.existsSync(path.join(root, file)), `${kind} entry point ${file} is missing`)
  }
})

test("a fresh entry starts on the defaults the widget clamps to", () => {
  assert.deepEqual(barWidget.defaults, SETTING_DEFAULTS)
})

// Every setting the plugin has, in the same order, so the generated form
// reads like the plugin's own view rather than a subset in another order.
test("the Setup menu form offers exactly the settings the plugin has", () => {
  assert.deepEqual(
    (barWidget.schema ?? []).map(field => field.key),
    SETTING_FIELDS.map(field => field.key)
  )
})

// The schema is what Setup > Plugins clamps and labels by, so a range that
// drifts from SETTING_FIELDS would let that form write a value the widget
// then silently pulls back - the setting would look like it didn't take.
test("every schema field carries the same type, range, label and default as the widget's own", () => {
  for (const field of SETTING_FIELDS) {
    const entry = (barWidget.schema ?? []).find(candidate => candidate.key === field.key)
    assert.ok(entry, `${field.key} is missing from the schema`)
    assert.equal(entry.type, field.type, `${field.key} type`)
    assert.equal(entry.label, field.label, `${field.key} label`)
    assert.equal(entry.description, field.description, `${field.key} description`)
    assert.equal(entry.defaultValue, field.fallback, `${field.key} default`)

    if (field.type === "integer") {
      assert.equal(entry.min, field.min, `${field.key} min`)
      assert.equal(entry.max, field.max, `${field.key} max`)
      assert.equal(entry.step, 1, `${field.key} step`)
    }

    // Omarchy's form wants {value, label} pairs where SETTING_FIELDS keeps
    // bare values, so only the values have to survive the translation.
    if (field.type === "enum") {
      assert.deepEqual(entry.options.map(option => option.value), field.options, `${field.key} options`)
      for (const option of entry.options) {
        assert.ok(option.label && option.label.length > 0, `${field.key} option ${option.value} needs a label`)
      }
    }
  }
})

// A default that the widget would immediately clamp away would make the
// form's own starting value a lie.
test("every schema default is a value the widget accepts unchanged", () => {
  const { clampSetting } = require("../js/logic.js")
  for (const entry of barWidget.schema ?? []) {
    assert.equal(clampSetting(entry.key, entry.defaultValue), entry.defaultValue, `${entry.key} default`)
  }
})
