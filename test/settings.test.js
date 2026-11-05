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
  workspaceLabel,
  sameIds,
  WORKSPACE_BLOCK_SIZE,
  blockOf,
  slotOf,
  workspaceIdFor,
  parseMonitorBlocks,
  parseMonitorIdentities,
  perMonitorActive,
  monitorBlock,
  focusWorkspaceRequest
} = require("../js/settings.js")

// The shape Workspaces.qml hands computeWorkspaceIds: what Hyprland knows
// about right now. Ids listed without a "+" are empty workspaces.
// `monitor` is the connector name each sits on, when a test cares.
function workspaces(spec, monitor) {
  return spec.map(entry => ({
    id: parseInt(entry, 10),
    occupied: String(entry).endsWith("+"),
    monitor: monitor || ""
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

test("computeWorkspaceIds shows only the monitor's own block, always its first minWorkspaces", () => {
  assert.deepEqual(computeWorkspaceIds([], { block: 1 }), [11, 12, 13, 14, 15])
  assert.deepEqual(computeWorkspaceIds([], { block: 2, minWorkspaces: 2 }), [21, 22])
  assert.deepEqual(computeWorkspaceIds(workspaces(["3+", "12+", "18", "25+"]), { block: 1 }), [11, 12, 13, 14, 15, 18])
  assert.deepEqual(computeWorkspaceIds(workspaces(["12+", "20"]), { block: 1, minWorkspaces: 0 }), [12, 20])
})

test("computeWorkspaceIds treats a missing or unusable block as block 0", () => {
  assert.deepEqual(computeWorkspaceIds([], { block: undefined }), [1, 2, 3, 4, 5])
  assert.deepEqual(computeWorkspaceIds([], { block: -2 }), [1, 2, 3, 4, 5])
  assert.deepEqual(computeWorkspaceIds([], { block: "abc" }), [1, 2, 3, 4, 5])
  assert.deepEqual(computeWorkspaceIds([], { block: "1" }), [11, 12, 13, 14, 15])
})

test("computeWorkspaceIds puts a monitor's guests after its own, each in order", () => {
  // 3 and 21 are on this monitor but belong to other blocks: an unplugged
  // monitor's workspaces end up on one that is left.
  const list = workspaces(["21+", "3+"], "DP-5").concat(workspaces(["13+", "2+"], "HDMI-A-1"))
  assert.deepEqual(computeWorkspaceIds(list, { block: 1, monitorName: "DP-5", minWorkspaces: 1 }), [11, 13, 3, 21])
})

test("computeWorkspaceIds shows no guests without a monitor name to match", () => {
  const list = workspaces(["3+", "21+"], "DP-5")
  assert.deepEqual(computeWorkspaceIds(list, { block: 1, minWorkspaces: 1 }), [11])
  assert.deepEqual(computeWorkspaceIds(list, { block: 1, monitorName: "DP-6", minWorkspaces: 1 }), [11])
  assert.deepEqual(computeWorkspaceIds(list, { block: 1, monitorName: "", minWorkspaces: 1 }), [11])
})

test("computeWorkspaceIds lists a guest once, and drops special workspaces", () => {
  const list = workspaces(["3+", "3+", "0+", "-98+"], "DP-5")
  assert.deepEqual(computeWorkspaceIds(list, { block: 1, monitorName: "DP-5", minWorkspaces: 0 }), [3])
})

test("hideEmpty applies to guests too, but the monitor's shown workspace always stays", () => {
  const list = workspaces(["3", "21+"], "DP-5")
  assert.deepEqual(computeWorkspaceIds(list, { block: 1, monitorName: "DP-5", hideEmpty: true }), [21])
  // The workspace the monitor is on, from its own block or another, is shown even empty.
  assert.deepEqual(computeWorkspaceIds(list, { block: 1, monitorName: "DP-5", hideEmpty: true, focusedId: 14 }), [14, 21])
  assert.deepEqual(computeWorkspaceIds(list, { block: 1, monitorName: "DP-5", hideEmpty: true, focusedId: 3 }), [3, 21])
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
    assert.ok(["integer", "boolean", "enum", "string"].includes(field.type), `${field.key}: unknown type ${field.type}`)
    if (field.type === "string") {
      assert.equal(typeof field.fallback, "string", `${field.key}: default is not a string`)
      assert.ok(field.maxLength > 0, `${field.key}: needs a maxLength`)
    } else if (field.type === "integer") {
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

test("workspaceLabel keeps the numbers, with 10 as 0, while no labels are set", () => {
  assert.equal(workspaceLabel(1, ""), "1")
  assert.equal(workspaceLabel(9, undefined), "9")
  assert.equal(workspaceLabel(10, null), "0")
})

test("workspaceLabel takes any comma-separated list, in order from workspace 1", () => {
  assert.equal(workspaceLabel(1, "a, b,c"), "a")
  assert.equal(workspaceLabel(2, "a, b,c"), "b")
  assert.equal(workspaceLabel(3, "a, b,c"), "c")
  assert.equal(workspaceLabel(2, "a, 1, $"), "1")
  assert.equal(workspaceLabel(3, "a, 1, $"), "$")
  assert.equal(workspaceLabel(3, "一,二,三"), "三")
  assert.equal(workspaceLabel(10, "1,2,3,4,5,6,7,8,9,十"), "十")
})

test("workspaceLabel falls back to the number past the list's end or on a blank entry", () => {
  assert.equal(workspaceLabel(4, "a, b, c"), "4")
  assert.equal(workspaceLabel(10, "a, b, c"), "0")
  assert.equal(workspaceLabel(2, "a, , c"), "2")
  assert.equal(workspaceLabel(2, "a,   ,c"), "2")
  assert.equal(workspaceLabel(1, ",b"), "1")
})

test("workspaceLabel names a workspace by its slot in the monitor's block", () => {
  assert.equal(workspaceLabel(11, ""), "1")
  assert.equal(workspaceLabel(15, ""), "5")
  assert.equal(workspaceLabel(20, ""), "0")
  assert.equal(workspaceLabel(21, "a, b, c"), "a")
  assert.equal(workspaceLabel(23, "a, b, c"), "c")
  assert.equal(workspaceLabel(24, "a, b, c"), "4")
  assert.equal(workspaceLabel(30, "1,2,3,4,5,6,7,8,9,十"), "十")
})

test("workspaceLabel leaves a special or unusable workspace id as it is", () => {
  assert.equal(workspaceLabel(0, "a, b"), "0")
  assert.equal(workspaceLabel(-98, "a, b"), "-98")
  assert.equal(workspaceLabel("x", "a, b"), "x")
})

test("blockOf and slotOf split a Hyprland id into monitor block and 1-10 slot", () => {
  assert.equal(WORKSPACE_BLOCK_SIZE, 10)
  assert.deepEqual([1, 5, 10, 11, 20, 21, 35].map(blockOf), [0, 0, 0, 1, 1, 2, 3])
  assert.deepEqual([1, 5, 10, 11, 20, 21, 35].map(slotOf), [1, 5, 10, 1, 10, 1, 5])
  assert.equal(blockOf("12"), 1)
  assert.equal(slotOf("12"), 2)
})

test("workspaceIdFor is the inverse of blockOf and slotOf", () => {
  assert.equal(workspaceIdFor(0, 3), 3)
  assert.equal(workspaceIdFor(1, 1), 11)
  assert.equal(workspaceIdFor(2, 10), 30)
  for (const id of [1, 9, 10, 11, 19, 20, 21, 40])
    assert.equal(workspaceIdFor(blockOf(id), slotOf(id)), id)
})

test("parseMonitorBlocks reads Hyprland's tab-separated state file", () => {
  const text = "0\tDP-4\tLG Electronics LG HDR 4K 0x00\n1\tDP-5\tDell Inc. DELL S2722QC 7NWWLD3\n"
  assert.deepEqual(parseMonitorBlocks(text), { "DP-4": 0, "DP-5": 1 })
  assert.deepEqual(parseMonitorBlocks("12\teDP-1\tAU Optronics 0x1\textra\tfields"), { "eDP-1": 12 })
})

test("parseMonitorBlocks skips a line that is half written or makes no sense", () => {
  assert.deepEqual(parseMonitorBlocks("1\tDP-5"), {})
  assert.deepEqual(parseMonitorBlocks("1\t\tidentity"), {})
  assert.deepEqual(parseMonitorBlocks("x\tDP-5\tidentity"), {})
  assert.deepEqual(parseMonitorBlocks("-1\tDP-5\tidentity"), {})
  assert.deepEqual(parseMonitorBlocks("garbage\n\n0\tDP-4\tid\n"), { "DP-4": 0 })
})

test("parseMonitorBlocks copes with a missing file", () => {
  assert.deepEqual(parseMonitorBlocks(""), {})
  assert.deepEqual(parseMonitorBlocks(null), {})
  assert.deepEqual(parseMonitorBlocks(undefined), {})
})

test("monitorBlock takes the state file's block for a monitor it lists", () => {
  assert.equal(monitorBlock({ "DP-4": 0, "DP-5": 3 }, "DP-5", 2), 3)
  assert.equal(monitorBlock({ "DP-4": 0 }, "DP-4", 15), 0)
})

test("monitorBlock falls back to the block of the monitor's active workspace, then to 0", () => {
  assert.equal(monitorBlock({}, "DP-5", 14), 1)
  assert.equal(monitorBlock({ "DP-4": 0 }, "DP-5", 25), 2)
  assert.equal(monitorBlock(null, "DP-5", 7), 0)
  assert.equal(monitorBlock({}, "DP-5", 0), 0)
  assert.equal(monitorBlock({}, "DP-5", -98), 0)
  assert.equal(monitorBlock({}, "", undefined), 0)
})

test("monitorBlock does not mistake an object property for a monitor", () => {
  assert.equal(monitorBlock({}, "constructor", 12), 1)
})

test("focusWorkspaceRequest focuses a monitor's own workspace by slot and monitor name", () => {
  assert.equal(focusWorkspaceRequest(3, 0, "DP-4", true), 'o.workspaces.focus(3, "DP-4")')
  assert.equal(focusWorkspaceRequest(10, 0, "DP-4", true), 'o.workspaces.focus(10, "DP-4")')
  assert.equal(focusWorkspaceRequest(12, 1, "DP-5", true), 'o.workspaces.focus(2, "DP-5")')
})

test("focusWorkspaceRequest focuses a visiting workspace by its Hyprland id", () => {
  assert.equal(focusWorkspaceRequest(3, 1, "DP-5", true), 'hl.dsp.focus({ workspace = "3" })')
  assert.equal(focusWorkspaceRequest(21, 0, "DP-4", true), 'hl.dsp.focus({ workspace = "21" })')
})

test("focusWorkspaceRequest copes with no monitor name yet", () => {
  assert.equal(focusWorkspaceRequest(2, 0, "", true), 'o.workspaces.focus(2, "")')
  assert.equal(focusWorkspaceRequest(2, 0, undefined, true), 'o.workspaces.focus(2, "")')
})

test("focusWorkspaceRequest keeps the old hl.dsp.focus request when no state file was loaded", () => {
  // Omarchy before 4.5 has no o.workspaces, so nothing may call it.
  assert.equal(focusWorkspaceRequest(3, 0, "DP-4", false), 'hl.dsp.focus({ workspace = "3" })')
  assert.equal(focusWorkspaceRequest(12, 1, "DP-5", false), 'hl.dsp.focus({ workspace = "12" })')
  assert.equal(focusWorkspaceRequest(3, 0, "DP-4"), 'hl.dsp.focus({ workspace = "3" })')
  assert.equal(focusWorkspaceRequest(3, 0, "DP-4", undefined), 'hl.dsp.focus({ workspace = "3" })')
  assert.equal(focusWorkspaceRequest(3, 0, "DP-4", "yes"), 'hl.dsp.focus({ workspace = "3" })')
})

test("parseMonitorIdentities keeps the identity column by connector", () => {
  const text = "0\tDP-4\tLG Electronics LG HDR 4K 0x00\n1\tDP-5\tDell Inc. DELL S2722QC 7NWWLD3\r\n"
  assert.deepEqual(parseMonitorIdentities(text), { "DP-4": "LG Electronics LG HDR 4K 0x00", "DP-5": "Dell Inc. DELL S2722QC 7NWWLD3" })
  assert.deepEqual(parseMonitorIdentities("12\teDP-1\tAU Optronics 0x1\textra\tfields"), { "eDP-1": "AU Optronics 0x1" })
})

test("parseMonitorIdentities skips what parseMonitorBlocks skips, and an empty identity", () => {
  assert.deepEqual(parseMonitorIdentities("1\tDP-5"), {})
  assert.deepEqual(parseMonitorIdentities("x\tDP-5\tid"), {})
  assert.deepEqual(parseMonitorIdentities("0\tDP-4\t\n1\tDP-5\tid"), { "DP-5": "id" })
  assert.deepEqual(parseMonitorIdentities(null), {})
})

test("perMonitorActive is true only once the state file has put a monitor in blocks", () => {
  assert.equal(perMonitorActive({ "DP-4": 0 }), true)
  assert.equal(perMonitorActive(parseMonitorBlocks("0\tDP-4\tid")), true)
  assert.equal(perMonitorActive({}), false)
  assert.equal(perMonitorActive(parseMonitorBlocks("")), false)
  assert.equal(perMonitorActive(parseMonitorBlocks("1\tDP-5")), false)
  assert.equal(perMonitorActive(null), false)
  assert.equal(perMonitorActive(undefined), false)
})

test("workspaceLabels accepts a JSON array and rejects anything else", () => {
  assert.equal(clampSetting("workspaceLabels", ["a", "b"]), "a,b")
  assert.equal(workspaceLabel(2, ["a", "b"]), "b")
  assert.equal(workspaceLabel(1, [null, "b"]), "1")
  assert.equal(workspaceLabel(2, [1, 2]), "2")
  assert.equal(clampSetting("workspaceLabels", 42), "")
  assert.equal(clampSetting("workspaceLabels", { a: 1 }), "")
  assert.equal(workspaceLabel(3, true), "3")
})

test("workspaceLabels is capped rather than growing without bound", () => {
  const max = settingField("workspaceLabels").maxLength
  assert.equal(clampSetting("workspaceLabels", "x".repeat(max + 50)).length, max)
})
