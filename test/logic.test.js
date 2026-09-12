const test = require("node:test")
const assert = require("node:assert/strict")

const {
  computeWorkspaceIds,
  sameIds,
  computeWindowKey,
  classifyIconValue,
  lookupIconOverride,
  steamAppId,
  groupToplevels,
  spreadLayout,
  cardWindowRect,
  nextWorkspaceId,
  windowSelector,
  navigateGrid,
  planReorder,
  clampSetting,
  SETTING_FIELDS,
  SETTING_DEFAULTS,
  settingField,
  applySetting,
  settingValue,
  widgetSettingsFrom,
  parseOverlayPayload,
  overlayState,
  overlayEscape
} = require("../logic.js")

// The shape Workspaces.qml hands computeWorkspaceIds: what Hyprland knows
// about right now. Ids listed without a "+" are empty workspaces.
function workspaces(spec) {
  return spec.map(entry => ({
    id: parseInt(entry, 10),
    occupied: String(entry).endsWith("+")
  }))
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

test("computeWindowKey prefers class, then initialClass, then the wayland appId", () => {
  assert.equal(computeWindowKey("firefox", "Firefox", "firefox-appid"), "firefox")
  assert.equal(computeWindowKey("", "Firefox", "firefox-appid"), "Firefox")
  assert.equal(computeWindowKey("", "", "org.wezfurlong.wezterm"), "org.wezfurlong.wezterm")
  assert.equal(computeWindowKey("", "", ""), "")
})

test("classifyIconValue resolves images, else falls back to literal text", () => {
  const unresolvable = () => ""

  assert.equal(classifyIconValue("   ", unresolvable), null)
  assert.deepEqual(classifyIconValue("file:///tmp/icon.png", unresolvable), {
    kind: "image",
    source: "file:///tmp/icon.png"
  })
  assert.deepEqual(classifyIconValue("/usr/share/icons/foo.png", unresolvable), {
    kind: "image",
    source: "file:///usr/share/icons/foo.png"
  })
  assert.deepEqual(classifyIconValue("firefox", name => `themed:${name}`), {
    kind: "image",
    source: "themed:firefox"
  })
  assert.deepEqual(classifyIconValue("🦊", unresolvable), { kind: "text", value: "🦊" })
})

test("lookupIconOverride matches a key exactly, then case-insensitively", () => {
  assert.equal(lookupIconOverride({ firefox: "🦊" }, "firefox"), "🦊")
  assert.equal(lookupIconOverride({ firefox: "🦊" }, "Firefox"), "🦊")
  assert.equal(lookupIconOverride({ firefox: "🦊" }, "steam"), "")
  assert.equal(lookupIconOverride(null, "firefox"), "")
})

test("steamAppId pulls the appid out of a Steam window class, else null", () => {
  assert.equal(steamAppId("steam_app_570"), "570")
  assert.equal(steamAppId("STEAM_APP_570"), "570")
  assert.equal(steamAppId("  steam_app_570  "), "570")
  assert.equal(steamAppId("steam_app_0"), "0")
  assert.equal(steamAppId("steam_app_"), null)
  assert.equal(steamAppId("steam_app_570x"), null)
  assert.equal(steamAppId("not_steam_app_570"), null)
  assert.equal(steamAppId("steamapp570"), null)
  assert.equal(steamAppId(""), null)
  assert.equal(steamAppId(null), null)
  assert.equal(steamAppId(undefined), null)
})

test("groupToplevels groups by key, in first-seen order, keeping every window", () => {
  const code1 = { id: "code1" }
  const firefox1 = { id: "firefox1" }
  const code2 = { id: "code2" }
  const keyOf = toplevel => ({ code1: "code", code2: "code", firefox1: "firefox" })[toplevel.id]

  const groups = groupToplevels([code1, firefox1, code2], keyOf)

  assert.deepEqual(groups.map(group => group.key), ["code", "firefox"])
  assert.deepEqual(groups.map(group => group.toplevels), [[code1, code2], [firefox1]])
})

test("groupToplevels groups a window class case-insensitively", () => {
  const lower = { id: "lower" }
  const upper = { id: "upper" }
  const keyOf = toplevel => (toplevel.id === "lower" ? "firefox" : "Firefox")

  const groups = groupToplevels([lower, upper], keyOf)

  assert.equal(groups.length, 1)
  assert.equal(groups[0].key, "firefox")
  assert.deepEqual(groups[0].toplevels, [lower, upper])
})

test("groupToplevels counts a group's windows", () => {
  const windows = [{ id: 1 }, { id: 2 }, { id: 3 }]
  const groups = groupToplevels(windows, () => "code")
  assert.equal(groups.length, 1)
  assert.equal(groups[0].toplevels.length, 3)
})

test("groupToplevels copes with nothing to group and an unusable key", () => {
  assert.deepEqual(groupToplevels([], () => "code"), [])
  assert.deepEqual(groupToplevels([{ id: 1 }], null), [{ key: "", toplevels: [{ id: 1 }] }])
  assert.deepEqual(groupToplevels([{ id: 1 }], () => ""), [{ key: "", toplevels: [{ id: 1 }] }])
})

test("the +N overflow counts groups, not the windows inside them", () => {
  const windows = [{ id: 1 }, { id: 2 }, { id: 3 }, { id: 4 }, { id: 5 }]
  const keyOf = toplevel => (toplevel.id <= 3 ? "code" : "firefox")
  const maxIcons = 1

  const groups = groupToplevels(windows, keyOf)

  assert.equal(groups.length, 2)
  assert.equal(Math.max(0, groups.length - maxIcons), 1)
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
    assert.ok(["integer", "boolean"].includes(field.type), `${field.key}: unknown type ${field.type}`)
    if (field.type === "integer") {
      assert.ok(field.min < field.max, `${field.key}: empty range`)
      assert.ok(field.fallback >= field.min && field.fallback <= field.max, `${field.key}: default out of range`)
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

test("parseOverlayPayload picks the view, defaulting to the overview", () => {
  assert.deepEqual(parseOverlayPayload('{"view":"settings"}'), { view: "settings" })
  assert.deepEqual(parseOverlayPayload("{}"), { view: "overview" })
  assert.deepEqual(parseOverlayPayload(""), { view: "overview" })
  assert.deepEqual(parseOverlayPayload("not json"), { view: "overview" })
  assert.deepEqual(parseOverlayPayload('{"view":42}'), { view: "overview" })
})

test("overlayState opens the overview, or the settings on their own", () => {
  assert.deepEqual(overlayState("{}"), { base: "overview", settingsOpen: false })
  assert.deepEqual(overlayState('{"view":"settings"}'), { base: "settings", settingsOpen: true })
  assert.deepEqual(overlayState("not json"), { base: "overview", settingsOpen: false })
})

test("overlayEscape steps back to the overview, or closes", () => {
  // Reached through the overview's gear: the first Escape goes back.
  assert.equal(overlayEscape("overview", true), "back")
  // Summoned straight to the settings: there is nothing behind them.
  assert.equal(overlayEscape("settings", true), "close")
  // Plain overview, and the settings once they are already closed.
  assert.equal(overlayEscape("overview", false), "close")
})

// ---- overview layout -------------------------------------------------------

const AREA = { width: 1600, height: 900 }

function sized(count, width, height) {
  return Array.from({ length: count }, () => ({ width, height }))
}

// Every window drawn inside the area it was given, none overlapping any
// other - the one property the overview's middle section has to hold no
// matter how many windows are open or what shape they are.
function assertLaidOut(result, area, count) {
  assert.equal(result.items.length, count)
  for (const item of result.items) {
    assert.ok(item.width > 0 && item.height > 0, "a window was laid out with no size")
    assert.ok(item.x >= -0.001 && item.y >= -0.001, "a window was laid out off the top or left")
    assert.ok(item.x + item.width <= area.width + 0.001, "a window was laid out past the right edge")
    assert.ok(item.y + item.height <= area.height + 0.001, "a window was laid out past the bottom edge")
  }
  for (let i = 0; i < result.items.length; i++) {
    for (let j = i + 1; j < result.items.length; j++) {
      const a = result.items[i]
      const b = result.items[j]
      const apart = a.x + a.width <= b.x + 0.001 || b.x + b.width <= a.x + 0.001
        || a.y + a.height <= b.y + 0.001 || b.y + b.height <= a.y + 0.001
      assert.ok(apart, `windows ${i} and ${j} overlap`)
    }
  }
}

test("spreadLayout fits any number of windows into the area without overlap", () => {
  for (const count of [1, 2, 5, 12]) {
    const landscape = spreadLayout(sized(count, 1920, 1080), AREA, { spacing: 16, captionHeight: 40 })
    assertLaidOut(landscape, AREA, count)
    const portrait = spreadLayout(sized(count, 1080, 1920), AREA, { spacing: 16, captionHeight: 40 })
    assertLaidOut(portrait, AREA, count)
  }
})

test("spreadLayout keeps every window at its real aspect ratio", () => {
  const result = spreadLayout([
    { width: 1920, height: 1080 },
    { width: 600, height: 1200 },
    { width: 800, height: 800 }
  ], AREA, { spacing: 16, captionHeight: 40 })

  assertLaidOut(result, AREA, 3)
  assert.ok(Math.abs(result.items[0].width / result.items[0].height - 16 / 9) < 0.001)
  assert.ok(Math.abs(result.items[1].width / result.items[1].height - 0.5) < 0.001)
  assert.ok(Math.abs(result.items[2].width / result.items[2].height - 1) < 0.001)
})

test("spreadLayout scales every window by the same factor", () => {
  const result = spreadLayout([{ width: 1920, height: 1080 }, { width: 960, height: 540 }], AREA, {})
  assert.ok(Math.abs(result.items[0].width / 2 - result.items[1].width) < 0.001)
})

test("spreadLayout picks the grid shape that renders the windows largest", () => {
  const spaced = { spacing: 16, captionHeight: 40 }
  // The same two landscape windows: side by side in a wide area, stacked in
  // a tall one.
  assert.equal(spreadLayout(sized(2, 1920, 1080), { width: 1600, height: 900 }, spaced).columns, 2)
  assert.equal(spreadLayout(sized(2, 1920, 1080), { width: 600, height: 1400 }, spaced).columns, 1)
  // Three squares across a wide area, stacked in a narrow one.
  assert.equal(spreadLayout(sized(3, 1000, 1000), AREA, spaced).columns, 3)
  assert.equal(spreadLayout(sized(3, 1000, 1000), { width: 400, height: 1200 }, spaced).columns, 1)

  const twelve = spreadLayout(sized(12, 1920, 1080), AREA, spaced)
  assert.ok(twelve.columns * twelve.rows >= 12, "12 windows need at least 12 slots")
  assert.ok(twelve.columns > 1 && twelve.rows > 1, "12 windows should not end up in a single row or column")
})

test("spreadLayout centres the block, and a short last row under it", () => {
  // 5 landscape windows in a square area come out 2 wide and 3 deep, so the
  // last row holds one window on its own.
  const result = spreadLayout(sized(5, 1600, 900), { width: 1000, height: 1000 }, { spacing: 10 })
  assert.equal(result.columns, 2)
  assert.equal(result.rows, 3)

  const lonely = result.items[4]
  const middleOfRowAbove = (result.items[2].cellX + result.items[3].cellX + result.items[3].cellWidth) / 2
  assert.ok(Math.abs(middleOfRowAbove - (lonely.cellX + lonely.cellWidth / 2)) < 0.001,
    "the last row is not centred under the one above it")

  // And the block as a whole sits centred in the area, top and bottom alike.
  const top = result.items[0].cellY
  const bottom = 1000 - (lonely.cellY + lonely.cellHeight)
  assert.ok(Math.abs(top - bottom) < 0.001, "the block is not vertically centred")
})

test("spreadLayout reserves the caption room under each window, inside its cell", () => {
  const result = spreadLayout(sized(2, 1000, 1000), AREA, { captionHeight: 40 })
  for (const item of result.items) {
    assert.equal(item.cellHeight - item.height, 40)
    assert.ok(item.y + item.height + 40 <= item.cellY + item.cellHeight + 0.001)
  }
})

test("spreadLayout honours an area origin and a scale cap", () => {
  const offset = spreadLayout(sized(1, 1000, 1000), { x: 100, y: 50, width: 400, height: 400 }, {})
  assert.equal(offset.items[0].x, 100)
  assert.equal(offset.items[0].y, 50)

  const capped = spreadLayout(sized(1, 100, 100), AREA, { maxScale: 1 })
  assert.equal(capped.scale, 1)
  assert.equal(capped.items[0].width, 100)
})

test("spreadLayout treats a window with no usable size as a full-area one", () => {
  const result = spreadLayout([{ width: 0, height: 0 }], { width: 800, height: 400 }, {})
  assert.ok(Math.abs(result.items[0].width / result.items[0].height - 2) < 0.001)
})

test("spreadLayout returns nothing to draw rather than breaking", () => {
  const nothing = { columns: 0, rows: 0, scale: 0, items: [] }
  assert.deepEqual(spreadLayout([], AREA, {}), nothing)
  assert.deepEqual(spreadLayout(null, AREA, null), nothing)
  assert.deepEqual(spreadLayout(sized(1, 100, 100), { width: 0, height: 0 }, {}), nothing)
  // An area with no room left once the caption is reserved.
  assert.deepEqual(spreadLayout(sized(1, 100, 100), { width: 100, height: 40 }, { captionHeight: 40 }), nothing)
})

// ---- windows on a workspace card -------------------------------------------

const MONITOR = { x: 0, y: 0, width: 1920, height: 1080 }
const CARD = { width: 192, height: 108 }

test("cardWindowRect shrinks a window's real rectangle onto the card", () => {
  assert.deepEqual(cardWindowRect({ x: 0, y: 0, width: 1920, height: 1080 }, MONITOR, CARD),
    { x: 0, y: 0, width: 192, height: 108 })
  assert.deepEqual(cardWindowRect({ x: 960, y: 540, width: 960, height: 540 }, MONITOR, CARD),
    { x: 96, y: 54, width: 96, height: 54 })
})

test("cardWindowRect places a window relative to its own monitor", () => {
  const second = { x: 1920, y: 0, width: 1920, height: 1080 }
  assert.deepEqual(cardWindowRect({ x: 2880, y: 0, width: 960, height: 1080 }, second, CARD),
    { x: 96, y: 0, width: 96, height: 108 })
})

test("cardWindowRect clips a window that hangs off the monitor", () => {
  assert.deepEqual(cardWindowRect({ x: -100, y: -50, width: 2120, height: 1180 }, MONITOR, CARD),
    { x: 0, y: 0, width: 192, height: 108 })
  assert.deepEqual(cardWindowRect({ x: 1820, y: 0, width: 1920, height: 1080 }, MONITOR, CARD),
    { x: 182, y: 0, width: 10, height: 108 })
})

test("cardWindowRect keeps a tiny window visible", () => {
  const sliver = cardWindowRect({ x: 0, y: 0, width: 4, height: 4 }, MONITOR, CARD)
  assert.ok(sliver.width >= 1 && sliver.height >= 1)
})

test("cardWindowRect reports nothing to draw rather than an unusable rectangle", () => {
  assert.equal(cardWindowRect({ x: 0, y: 0, width: 100, height: 100 }, MONITOR, { width: 0, height: 0 }), null)
  assert.equal(cardWindowRect({ x: 0, y: 0, width: 100, height: 100 }, { width: 0, height: 0 }, CARD), null)
  // Entirely off the monitor - another screen's window on this card.
  assert.equal(cardWindowRect({ x: 4000, y: 0, width: 800, height: 600 }, MONITOR, CARD), null)
  assert.equal(cardWindowRect({ x: 0, y: 0, width: 0, height: 0 }, MONITOR, CARD), null)
  assert.equal(cardWindowRect(null, null, null), null)
})

// ---- the "+" card ----------------------------------------------------------

test("nextWorkspaceId offers the one after the highest shown", () => {
  assert.equal(nextWorkspaceId([1, 2, 3, 4, 5]), 6)
  assert.equal(nextWorkspaceId([1, 2, 8]), 9)
  assert.equal(nextWorkspaceId([7]), 8)
})

// Not "the first gap": emptying workspace 3 shouldn't make "+" reopen the
// one you just cleared instead of carrying on past the end.
test("nextWorkspaceId skips past gaps rather than filling them", () => {
  assert.equal(nextWorkspaceId([1, 5]), 6)
  assert.equal(nextWorkspaceId([2, 3]), 4)
})

test("nextWorkspaceId reports nothing left once 10 is taken", () => {
  assert.equal(nextWorkspaceId([10]), 0)
  assert.equal(nextWorkspaceId([1, 2, 3, 4, 5, 6, 7, 8, 9, 10]), 0)
})

test("nextWorkspaceId starts at 1 when nothing is shown", () => {
  assert.equal(nextWorkspaceId([]), 1)
  assert.equal(nextWorkspaceId(null), 1)
})

// ---- naming one window to Hyprland -----------------------------------------

// Quickshell reports an address without the "0x" Hyprland's selector wants.
// A selector missing it matches no window at all - and Hyprland still answers
// "ok", so the move, or the focus, silently does nothing.
test("windowSelector puts back the 0x Quickshell leaves off", () => {
  assert.equal(windowSelector("558b2094a300"), "address:0x558b2094a300")
  assert.equal(windowSelector(" 558b2094a300 "), "address:0x558b2094a300")
})

test("windowSelector leaves an address that already has it alone", () => {
  assert.equal(windowSelector("0x558b2094a300"), "address:0x558b2094a300")
  assert.equal(windowSelector("0X558b2094a300"), "address:0X558b2094a300")
})

test("windowSelector names nothing rather than a broken selector", () => {
  assert.equal(windowSelector(""), "")
  assert.equal(windowSelector(null), "")
  assert.equal(windowSelector(undefined), "")
})

// ---- keyboard selection ----------------------------------------------------

test("navigateGrid walks the grid and stops at its edges", () => {
  // 0 1 2
  // 3 4 5
  assert.equal(navigateGrid(0, 6, 3, "right"), 1)
  assert.equal(navigateGrid(2, 6, 3, "right"), 2)
  assert.equal(navigateGrid(1, 6, 3, "left"), 0)
  assert.equal(navigateGrid(0, 6, 3, "left"), 0)
  assert.equal(navigateGrid(1, 6, 3, "down"), 4)
  assert.equal(navigateGrid(4, 6, 3, "down"), 4)
  assert.equal(navigateGrid(4, 6, 3, "up"), 1)
  assert.equal(navigateGrid(1, 6, 3, "up"), 1)
})

test("navigateGrid lands on the last item when the row below is short", () => {
  // 0 1 2
  // 3 4
  assert.equal(navigateGrid(2, 5, 3, "down"), 4)
  assert.equal(navigateGrid(1, 5, 3, "down"), 4)
  assert.equal(navigateGrid(4, 5, 3, "right"), 4)
})

test("navigateGrid copes with an empty grid and a selection off the end", () => {
  assert.equal(navigateGrid(0, 0, 3, "down"), -1)
  assert.equal(navigateGrid(9, 5, 3, "down"), 0)
  assert.equal(navigateGrid(-1, 5, 3, "up"), 0)
  assert.equal(navigateGrid(1, 5, 0, "right"), 1)
  assert.equal(navigateGrid(1, 5, 3, "sideways"), 1)
})

// ---- reordering workspaces -------------------------------------------------

// The strip as the overview shows it: an id per card, with the addresses of
// the windows currently on it.
function strip(spec) {
  return Object.entries(spec).map(([id, addresses]) => ({ id: Number(id), addresses }))
}

test("planReorder swaps two neighbouring workspaces' windows", () => {
  const cards = strip({ 1: ["a"], 2: ["b", "c"], 3: [] })
  assert.deepEqual(planReorder(cards, 0, 1), [
    { address: "b", workspace: 1 },
    { address: "c", workspace: 1 },
    { address: "a", workspace: 2 }
  ])
})

test("planReorder rotates everything in between when a card moves further", () => {
  const cards = strip({ 1: ["a"], 2: ["b"], 3: ["c"], 4: ["d"], 5: ["e"] })
  // Dropping 5 onto 2: 5's windows land on 2, and 2, 3 and 4 each shift one
  // number up, exactly as swapping 5 leftwards one place at a time would.
  assert.deepEqual(planReorder(cards, 4, 1), [
    { address: "e", workspace: 2 },
    { address: "b", workspace: 3 },
    { address: "c", workspace: 4 },
    { address: "d", workspace: 5 }
  ])
  // The same drag the other way round.
  assert.deepEqual(planReorder(cards, 1, 4), [
    { address: "c", workspace: 2 },
    { address: "d", workspace: 3 },
    { address: "e", workspace: 4 },
    { address: "b", workspace: 5 }
  ])
})

test("planReorder moves nothing for an empty workspace, but still shifts the rest", () => {
  const cards = strip({ 1: ["a"], 2: [], 3: ["c"] })
  assert.deepEqual(planReorder(cards, 2, 0), [
    { address: "c", workspace: 1 },
    { address: "a", workspace: 2 }
  ])
  assert.deepEqual(planReorder(strip({ 1: [], 2: [] }), 0, 1), [])
})

test("planReorder works on the ids actually shown, not on 1..n", () => {
  const cards = strip({ 2: ["a"], 5: ["b"], 9: ["c"] })
  assert.deepEqual(planReorder(cards, 2, 0), [
    { address: "c", workspace: 2 },
    { address: "a", workspace: 5 },
    { address: "b", workspace: 9 }
  ])
})

test("planReorder plans nothing for a drag that changes no order", () => {
  const cards = strip({ 1: ["a"], 2: ["b"] })
  assert.deepEqual(planReorder(cards, 1, 1), [])
  assert.deepEqual(planReorder(cards, -1, 0), [])
  assert.deepEqual(planReorder(cards, 0, 7), [])
  assert.deepEqual(planReorder(null, 0, 1), [])
  assert.deepEqual(planReorder([{ id: 1, addresses: ["a", ""] }, { id: 2 }], 1, 0), [
    { address: "a", workspace: 2 }
  ])
})
