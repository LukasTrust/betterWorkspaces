// The settings contract: ranges, fallbacks, and what a value read out of a
// hand-edited shell.json is pulled to - plus the workspace strip those
// settings decide.

const test = require("node:test")
const assert = require("node:assert/strict")

const {
  SETTING_FIELDS,
  settingField,
  SETTING_DEFAULTS,
  clampSetting,
  applySetting,
  settingValue,
  widgetSettingsFrom,
  computeWorkspaceIds,
  sameIds
} = require("../js/settings.js")

// The shape Workspaces.qml hands computeWorkspaceIds: what Hyprland knows
// about right now. Ids listed without a "+" are empty workspaces.
function workspaces(spec) {
  return spec.map(entry => ({
    id: parseInt(entry, 10),
    occupied: String(entry).endsWith("+")
  }))
}

// The strip as the overview shows it: an id per card, with the addresses of
// the windows currently on it.
function strip(spec) {
  return Object.entries(spec).map(([id, addresses]) => ({ id: Number(id), addresses }))
}

test("computeWorkspaceIds shows the first minWorkspaces, plus the ones in use", () => {
  assert.deepEqual(computeWorkspaceIds([], {}), [1, 2, 3, 4, 5])
  assert.deepEqual(computeWorkspaceIds(workspaces(["9+", "7+", "3+"]), {}), [1, 2, 3, 4, 5, 7, 9])
  assert.deepEqual(computeWorkspaceIds(workspaces(["4"]), {}), [1, 2, 3, 4, 5])
})

test("computeWorkspaceIds follows minWorkspaces", () => {
  const inUse = workspaces(["7+"])
  assert.deepEqual(computeWorkspaceIds(inUse, { minWorkspaces: 0 }), [7])
  assert.deepEqual(computeWorkspaceIds(inUse, { minWorkspaces: 1 }), [1, 7])
  assert.deepEqual(computeWorkspaceIds(inUse, { minWorkspaces: 5 }), [1, 2, 3, 4, 5, 7])
  assert.deepEqual(computeWorkspaceIds(inUse, { minWorkspaces: 10 }), [1, 2, 3, 4, 5, 6, 7, 8, 9, 10])
})

test("computeWorkspaceIds clamps an unusable minWorkspaces like the widget does", () => {
  assert.deepEqual(computeWorkspaceIds([], { minWorkspaces: -3 }), [])
  assert.deepEqual(computeWorkspaceIds([], { minWorkspaces: 99 }), [1, 2, 3, 4, 5, 6, 7, 8, 9, 10])
  assert.deepEqual(computeWorkspaceIds([], { minWorkspaces: "abc" }), [1, 2, 3, 4, 5])
})

test("computeWorkspaceIds ignores workspaces outside the numbered strip", () => {
  const odd = workspaces(["0+", "-1+", "10+", "11+"])
  assert.deepEqual(computeWorkspaceIds(odd, {}), [1, 2, 3, 4, 5, 10])
  assert.deepEqual(computeWorkspaceIds(odd, { hideEmpty: true }), [10])
})

test("computeWorkspaceIds lists a workspace once, in order", () => {
  const duplicated = workspaces(["3+", "3+", "8+", "6+"])
  assert.deepEqual(computeWorkspaceIds(duplicated, { minWorkspaces: 3, focusedId: 8 }), [1, 2, 3, 6, 8])
})

test("hideEmpty shows only the workspaces in use, plus the focused one", () => {
  const mixed = workspaces(["1+", "2", "4+"])
  assert.deepEqual(computeWorkspaceIds(mixed, { hideEmpty: true }), [1, 4])
  assert.deepEqual(computeWorkspaceIds(mixed, { hideEmpty: true, focusedId: 2 }), [1, 2, 4])
  assert.deepEqual(computeWorkspaceIds(mixed, { hideEmpty: true, focusedId: 4 }), [1, 4])
})

test("hideEmpty ignores minWorkspaces", () => {
  assert.deepEqual(computeWorkspaceIds(workspaces(["7+"]), { hideEmpty: true, minWorkspaces: 10 }), [7])
  assert.deepEqual(computeWorkspaceIds([], { hideEmpty: true, minWorkspaces: 5 }), [])
})

test("the focused workspace is shown even when it is empty", () => {
  assert.deepEqual(computeWorkspaceIds(workspaces(["9"]), { focusedId: 9 }), [1, 2, 3, 4, 5, 9])
  assert.deepEqual(computeWorkspaceIds([], { minWorkspaces: 0, focusedId: 3 }), [3])
})

test("computeWorkspaceIds copes with nothing usable passed in", () => {
  assert.deepEqual(computeWorkspaceIds(null, null), [1, 2, 3, 4, 5])
  assert.deepEqual(computeWorkspaceIds([null, undefined], {}), [1, 2, 3, 4, 5])
})

test("sameIds spots a list the widget doesn't need to re-render", () => {
  assert.equal(sameIds([1, 2, 3], [1, 2, 3]), true)
  assert.equal(sameIds([], []), true)
  assert.equal(sameIds([1, 2], [2, 1]), false)
  assert.equal(sameIds([1, 2], [1, 2, 3]), false)
  assert.equal(sameIds(undefined, []), false)
  assert.equal(sameIds([], null), false)
})

test("clampSetting keeps a usable number in range", () => {
  assert.equal(clampSetting("maxIcons", 3), 3)
  assert.equal(clampSetting("maxIcons", "3"), 3)
  assert.equal(clampSetting("maxIcons", 2.6), 3)
  assert.equal(clampSetting("iconSize", " 20 "), 20)
})

test("clampSetting pulls out-of-range values to the nearest bound", () => {
  assert.equal(clampSetting("maxIcons", 0), 1)
  assert.equal(clampSetting("maxIcons", -5), 1)
  assert.equal(clampSetting("maxIcons", 99), 10)
  assert.equal(clampSetting("iconSize", 2), 8)
  assert.equal(clampSetting("iconSize", 999), 32)
})

test("clampSetting falls back to the default for anything unusable", () => {
  for (const value of [undefined, null, "", "   ", "abc", true, false, NaN, Infinity, {}, []]) {
    assert.equal(clampSetting("maxIcons", value), SETTING_DEFAULTS.maxIcons)
  }
})

test("clampSetting reads a boolean setting out of what shell.json may hold", () => {
  assert.equal(clampSetting("hideEmpty", true), true)
  assert.equal(clampSetting("hideEmpty", false), false)
  assert.equal(clampSetting("hideEmpty", "true"), true)
  assert.equal(clampSetting("hideEmpty", " TRUE "), true)
  assert.equal(clampSetting("hideEmpty", "false"), false)
  assert.equal(clampSetting("hideEmpty", 1), true)
  assert.equal(clampSetting("hideEmpty", "1"), true)
  assert.equal(clampSetting("hideEmpty", 0), false)
  assert.equal(clampSetting("hideEmpty", "0"), false)
})

test("clampSetting falls back for a boolean it can't read", () => {
  for (const value of [undefined, null, "", "yes", "abc", 2, NaN, {}, []]) {
    assert.equal(clampSetting("hideEmpty", value), SETTING_DEFAULTS.hideEmpty)
  }
})

test("clampSetting leaves settings it has no field for alone", () => {
  assert.equal(clampSetting("icons", "anything"), "anything")
})

test("clampSetting keeps a usable enum value", () => {
  assert.equal(clampSetting("setupTargetMode", "replace"), "replace")
  assert.equal(clampSetting("setupTargetMode", "add"), "add")
  assert.equal(clampSetting("setupTargetMode", "  replace  "), "replace")
})

test("clampSetting falls back to the default for an enum value that isn't one of its options", () => {
  for (const value of [undefined, null, "", "REPLACE", "overwrite", 1, {}, []]) {
    assert.equal(clampSetting("setupTargetMode", value), SETTING_DEFAULTS.setupTargetMode)
  }
})

test("settingField finds a setting by key, and nothing for an unknown one", () => {
  assert.equal(settingField("iconSize").max, 32)
  assert.equal(settingField("icons"), null)
})

test("applySetting keeps every other setting, id aside", () => {
  const current = { id: "better-workspaces", maxIcons: 3, icons: { firefox: "🦊" } }
  assert.deepEqual(applySetting(current, "iconSize", 20), {
    maxIcons: 3,
    icons: { firefox: "🦊" },
    iconSize: 20
  })
})

test("applySetting clamps what it stores", () => {
  assert.deepEqual(applySetting({}, "maxIcons", 99), { maxIcons: 10 })
  assert.deepEqual(applySetting({}, "iconSize", "abc"), { iconSize: 14 })
  assert.deepEqual(applySetting(null, "maxIcons", 4), { maxIcons: 4 })
  assert.deepEqual(applySetting({}, "hideEmpty", true), { hideEmpty: true })
})

test("settingValue reads a stored value, or the default when there is none", () => {
  assert.equal(settingValue({ maxIcons: 3 }, "maxIcons"), 3)
  assert.equal(settingValue({}, "maxIcons"), SETTING_DEFAULTS.maxIcons)
  assert.equal(settingValue(null, "iconSize"), SETTING_DEFAULTS.iconSize)
  assert.equal(settingValue({ iconSize: 999 }, "iconSize"), settingField("iconSize").max)
  assert.equal(settingValue({ hideEmpty: true }, "hideEmpty"), true)
  assert.equal(settingValue({}, "hideEmpty"), SETTING_DEFAULTS.hideEmpty)
})

test("every setting carries the bounds and wording the form needs", () => {
  for (const field of SETTING_FIELDS) {
    assert.ok(field.label, `${field.key}: no label`)
    assert.ok(field.description, `${field.key}: no description`)
    assert.ok(["integer", "boolean", "enum"].includes(field.type), `${field.key}: unknown type ${field.type}`)
    if (field.type === "integer") {
      assert.ok(field.min < field.max, `${field.key}: empty range`)
      assert.ok(field.fallback >= field.min && field.fallback <= field.max, `${field.key}: default out of range`)
    } else if (field.type === "enum") {
      assert.ok(field.options && field.options.length >= 2, `${field.key}: needs at least two options`)
      assert.ok(field.options.includes(field.fallback), `${field.key}: default is not one of its own options`)
    } else {
      assert.equal(typeof field.fallback, "boolean", `${field.key}: default is not a boolean`)
    }
  }
})

test("SETTING_DEFAULTS is one default per setting", () => {
  assert.deepEqual(Object.keys(SETTING_DEFAULTS), SETTING_FIELDS.map(field => field.key))
  for (const field of SETTING_FIELDS) assert.equal(SETTING_DEFAULTS[field.key], field.fallback)
})

test("widgetSettingsFrom picks this widget's entry out of any bar section", () => {
  const barConfig = {
    layout: {
      left: [{ id: "omarchy.menu" }],
      center: [],
      right: [{ id: "better-workspaces", maxIcons: 3, icons: { firefox: "🦊" } }]
    }
  }
  assert.deepEqual(widgetSettingsFrom(barConfig, "better-workspaces"), {
    maxIcons: 3,
    icons: { firefox: "🦊" }
  })
})

test("widgetSettingsFrom returns nothing usable rather than throwing", () => {
  assert.deepEqual(widgetSettingsFrom(null, "better-workspaces"), {})
  assert.deepEqual(widgetSettingsFrom({}, "better-workspaces"), {})
  assert.deepEqual(widgetSettingsFrom({ layout: { left: [{ id: "other" }] } }, "better-workspaces"), {})
})
