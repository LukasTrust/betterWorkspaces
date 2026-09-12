// Pure logic pulled out of Workspaces.qml so it can run under plain Node in
// tests, with no Quickshell/Hyprland runtime available. Anything that needs
// Quickshell singletons (Quickshell.iconPath, DesktopEntries, Hyprland) stays
// in the QML file and is passed in here as plain data or a callback.

// The workspaces the bar shows, left to right.
//
// `workspaces` is what Hyprland currently knows about, as
// [{ id, occupied }]; `options` carries the settings that decide what is
// shown, plus the focused workspace id. Ids outside 1-10 are dropped: those
// are Hyprland's special workspaces (scratchpads, negative ids), which
// aren't part of the numbered strip.
function computeWorkspaceIds(workspaces, options) {
  var list = workspaces || []
  var settings = options || {}
  var hideEmpty = clampSetting("hideEmpty", settings.hideEmpty)
  var ids = []

  function add(id) {
    var number = Number(id)
    if (number > 0 && number <= 10 && ids.indexOf(number) === -1) ids.push(number)
  }

  // With empty workspaces hidden, the always-shown ones don't apply: the
  // strip is then only what is in use.
  if (!hideEmpty) {
    var minWorkspaces = clampSetting("minWorkspaces", settings.minWorkspaces)
    for (var id = 1; id <= minWorkspaces; id++) add(id)
  }

  for (var i = 0; i < list.length; i++) {
    var workspace = list[i] || {}
    if (!hideEmpty || workspace.occupied) add(workspace.id)
  }

  // The workspace you are on is always shown, so switching to an empty one
  // doesn't make it vanish from under the cursor.
  add(settings.focusedId)

  ids.sort(function(left, right) { return left - right })
  return ids
}

// Whether two id lists hold the same ids in the same order. The widget
// rebuilds every cell when its list changes, so it uses this to leave the
// list alone when a recomputation came out identical.
function sameIds(left, right) {
  if (!left || !right || left.length !== right.length) return false
  for (var i = 0; i < left.length; i++) if (left[i] !== right[i]) return false
  return true
}

// Hyprland's own "class" (from hyprctl) is preferred over the wlr-toplevel
// appId: some XWayland apps report an empty wayland appId while hyprctl
// still reports a class, and this is what icon overrides are keyed by.
function computeWindowKey(ipcClass, ipcInitialClass, waylandAppId) {
  var key = String(ipcClass || ipcInitialClass || "")
  if (key.length === 0 && waylandAppId) key = String(waylandAppId || "")
  return key
}

// Turns a raw icon value (a user override or a DesktopEntry.icon) into
// either a themed/file image source, or - if it doesn't resolve to an
// icon-theme entry - plain text. This lets a user override with either an
// icon-theme name or a literal glyph/emoji in shell.json.
//
// iconPathLookup(name) resolves a themed icon name to a source URL (or "" if
// unresolved) - in the real widget this is Quickshell.iconPath.
function classifyIconValue(value, iconPathLookup) {
  var text = String(value || "").trim()
  if (text.length === 0) return null
  if (text.indexOf("file://") === 0 || text.indexOf("image://") === 0)
    return { kind: "image", source: text }
  if (text.charAt(0) === "/")
    return { kind: "image", source: "file://" + text }
  var themed = iconPathLookup ? String(iconPathLookup(text) || "") : ""
  if (themed.length > 0) return { kind: "image", source: themed }
  return { kind: "text", value: text }
}

function lookupIconOverride(overrides, key) {
  if (!overrides) return ""
  return String(overrides[key] || overrides[key.toLowerCase()] || "")
}

// Steam sets a game window's class to "steam_app_<appid>" (Proton and native
// Linux titles alike); Steam itself installs a matching "steam_icon_<appid>"
// entry into the icon theme when the game is added to the library, so the
// appid is all that's needed to look one up - no extra process or file read.
// Returns null for anything that isn't that exact shape.
function steamAppId(key) {
  var match = /^steam_app_(\d+)$/i.exec(String(key || "").trim())
  return match ? match[1] : null
}

// Groups windows by their window key (case-insensitively, same as icon
// overrides), in first-seen order. With `groupApps` off, the caller wraps
// each window as its own single-window group instead of calling this, so
// the rest of the widget can treat both modes the same way - maxIcons and
// the +N overflow count groups either way, not raw windows.
//
// `keyOf(toplevel)` returns the string a window is grouped and iconified
// by; in the real widget this is windowKey (Hyprland's "class", falling
// back to the wlr appId).
function groupToplevels(toplevels, keyOf) {
  var list = toplevels || []
  var groups = []
  var indexByKey = {}

  for (var i = 0; i < list.length; i++) {
    var toplevel = list[i]
    var rawKey = String((keyOf ? keyOf(toplevel) : "") || "")
    var lookupKey = rawKey.toLowerCase()
    var index = indexByKey[lookupKey]
    if (index === undefined) {
      index = groups.length
      indexByKey[lookupKey] = index
      groups.push({ key: rawKey, toplevels: [] })
    }
    groups[index].toplevels.push(toplevel)
  }

  return groups
}

// ---- overview ------------------------------------------------------------

// Lays a set of rectangles out side by side, the way the overview arranges
// its workspace cards: no overlap, every one at its real aspect ratio, the
// whole block centred in the area it was given.
//
// `items` are the rectangles to fit as [{ width, height }] - for the cards,
// the monitor each workspace is on, so a card comes out the shape of the
// screen it stands for. `area` is the space to fill,
// { width, height } plus an optional { x, y } origin. `options`:
//   spacing        gap between neighbouring cells, both axes
//   captionHeight  room reserved under each window for its icon and title
//   maxScale       largest factor a window may be blown up by; Infinity by
//                  default, so a near-empty workspace still fills the area
//
// The grid shape is picked by trying every column count and keeping the one
// that renders them largest, because what "largest" means depends on both
// the area and the rectangles: two landscape cards want two columns in a
// wide area and two rows in a tall one, and nothing short of measuring gets
// that right for every mix of portrait and landscape.
//
// Returns { columns, rows, scale, items: [...] }, one entry per input in the
// same order: `x`/`y`/`width`/`height` is where the card itself is drawn,
// `cellX`/`cellY`/`cellWidth`/`cellHeight` the slot around it that the
// caption below shares.
function spreadLayout(items, area, options) {
  var list = items || []
  var bounds = area || {}
  var settings = options || {}
  var count = list.length
  var areaWidth = Number(bounds.width) || 0
  var areaHeight = Number(bounds.height) || 0
  var originX = Number(bounds.x) || 0
  var originY = Number(bounds.y) || 0
  var spacing = Math.max(0, Number(settings.spacing) || 0)
  var captionHeight = Math.max(0, Number(settings.captionHeight) || 0)
  var maxScale = Number(settings.maxScale)
  if (!(maxScale > 0)) maxScale = Infinity

  var empty = { columns: 0, rows: 0, scale: 0, items: [] }
  if (count === 0 || areaWidth <= 0 || areaHeight <= 0) return empty

  // A window Hyprland reports no usable size for is treated as filling the
  // area: better one wrongly-shaped preview than a zero-sized one that also
  // drags the whole grid's scale off, since the scale is the tightest fit
  // across every window.
  var sizes = []
  for (var i = 0; i < count; i++) {
    var item = list[i] || {}
    var width = Number(item.width)
    var height = Number(item.height)
    sizes.push({
      width: width > 0 ? width : areaWidth,
      height: height > 0 ? height : areaHeight
    })
  }

  var best = null
  for (var columns = 1; columns <= count; columns++) {
    var rows = Math.ceil(count / columns)
    var cellWidth = (areaWidth - spacing * (columns - 1)) / columns
    var cellHeight = (areaHeight - spacing * (rows - 1)) / rows
    var windowHeight = cellHeight - captionHeight
    if (cellWidth <= 0 || windowHeight <= 0) continue

    var scale = maxScale
    for (var s = 0; s < count; s++)
      scale = Math.min(scale, cellWidth / sizes[s].width, windowHeight / sizes[s].height)
    if (!(scale > 0)) continue

    // Ties happen once `maxScale` caps every candidate. Then the grid that
    // leaves no empty slot wins, and failing that the squarer one.
    var emptySlots = rows * columns - count
    if (best === null
        || scale > best.scale
        || (scale === best.scale && emptySlots < best.emptySlots)
        || (scale === best.scale && emptySlots === best.emptySlots && Math.abs(columns - rows) < Math.abs(best.columns - best.rows))) {
      best = { columns: columns, rows: rows, scale: scale, emptySlots: emptySlots }
    }
  }

  if (best === null) return empty

  // Cells are only as big as the largest window they have to hold, so the
  // block stays tight and centred instead of stretched across slack the
  // scale couldn't use.
  var slotWidth = 0
  var slotHeight = 0
  for (var m = 0; m < count; m++) {
    slotWidth = Math.max(slotWidth, sizes[m].width * best.scale)
    slotHeight = Math.max(slotHeight, sizes[m].height * best.scale)
  }
  var cellW = slotWidth
  var cellH = slotHeight + captionHeight

  var gridWidth = best.columns * cellW + spacing * (best.columns - 1)
  var gridHeight = best.rows * cellH + spacing * (best.rows - 1)
  var left = originX + (areaWidth - gridWidth) / 2
  var top = originY + (areaHeight - gridHeight) / 2

  var placed = []
  for (var index = 0; index < count; index++) {
    var row = Math.floor(index / best.columns)
    var column = index % best.columns
    // A short last row is centred under the rows above it rather than left
    // aligned, so the block reads as one shape.
    var inRow = Math.min(best.columns, count - row * best.columns)
    var rowInset = (best.columns - inRow) * (cellW + spacing) / 2

    var cellX = left + rowInset + column * (cellW + spacing)
    var cellY = top + row * (cellH + spacing)
    var width = sizes[index].width * best.scale
    var height = sizes[index].height * best.scale

    placed.push({
      x: cellX + (cellW - width) / 2,
      y: cellY + (slotHeight - height) / 2,
      width: width,
      height: height,
      cellX: cellX,
      cellY: cellY,
      cellWidth: cellW,
      cellHeight: cellH
    })
  }

  return {
    columns: best.columns,
    rows: best.rows,
    scale: best.scale,
    items: placed
  }
}

// A window's place on a workspace card: its real rectangle on the monitor,
// shrunk to the card. `window` and `monitor` are in Hyprland's global
// coordinates (what `lastIpcObject.at`/`size` and a monitor's x/y/width/
// height report), `card` is just { width, height }.
//
// The result is clipped to the card, so a window hanging off the edge of the
// monitor - or one on another monitor entirely - can't draw outside it, and
// never collapses to nothing: a card is small enough that an honest 0.4px
// tall window would simply disappear.
function cardWindowRect(window, monitor, card) {
  var rect = window || {}
  var screen = monitor || {}
  var size = card || {}
  var cardWidth = Number(size.width) || 0
  var cardHeight = Number(size.height) || 0
  var screenWidth = Number(screen.width) || 0
  var screenHeight = Number(screen.height) || 0
  if (cardWidth <= 0 || cardHeight <= 0 || screenWidth <= 0 || screenHeight <= 0) return null

  var scaleX = cardWidth / screenWidth
  var scaleY = cardHeight / screenHeight
  var left = ((Number(rect.x) || 0) - (Number(screen.x) || 0)) * scaleX
  var top = ((Number(rect.y) || 0) - (Number(screen.y) || 0)) * scaleY
  var right = left + Math.max(0, Number(rect.width) || 0) * scaleX
  var bottom = top + Math.max(0, Number(rect.height) || 0) * scaleY

  left = Math.min(Math.max(0, left), cardWidth)
  top = Math.min(Math.max(0, top), cardHeight)
  right = Math.min(Math.max(0, right), cardWidth)
  bottom = Math.min(Math.max(0, bottom), cardHeight)
  if (right <= left || bottom <= top) return null

  return {
    x: left,
    y: top,
    width: Math.max(1, right - left),
    height: Math.max(1, bottom - top)
  }
}

// How a Hyprland dispatch names one particular window.
//
// Hyprland's selector wants `address:0x55f...`, and Quickshell hands the
// address over *without* the `0x` - so pasting it straight in produces a
// selector that matches nothing. Hyprland still answers "ok", it just
// silently does nothing, which is a far worse failure than an error: every
// drag and every focus-by-address looks like it worked and doesn't.
function windowSelector(address) {
  var text = String(address || "").trim()
  if (text.length === 0) return ""
  return "address:" + (text.indexOf("0x") === 0 || text.indexOf("0X") === 0 ? text : "0x" + text)
}

// The workspace the "+" card opens: the one after the highest the overview
// shows. A strip of 1-5 grows to 6, and one that already reaches 8 grows to
// 9 - "the next one along", not "the first gap", which would reopen a
// workspace you had just emptied. 0 once 10 is taken, because Hyprland's
// numbered strip stops there.
function nextWorkspaceId(ids) {
  var list = ids || []
  var highest = 0
  for (var i = 0; i < list.length; i++) {
    var id = Number(list[i])
    if (id > highest) highest = id
  }
  var next = highest + 1
  return next <= 10 ? next : 0
}

// Where the keyboard selection lands when an arrow (or its hjkl twin) is
// pressed in a `columns`-wide grid of `count` items. Movement stops at the
// edges rather than wrapping, and a step off the end of a short last row
// lands on its last item instead of nowhere.
function navigateGrid(index, count, columns, direction) {
  var total = Math.max(0, Number(count) || 0)
  if (total === 0) return -1
  var width = Math.max(1, Number(columns) || 1)
  var current = Number(index)
  if (!(current >= 0 && current < total)) return 0

  var row = Math.floor(current / width)
  var column = current % width

  if (direction === "left") return column === 0 ? current : current - 1
  if (direction === "right") return current + 1 < total && column + 1 < width ? current + 1 : current
  if (direction === "up") return row === 0 ? current : current - width
  if (direction === "down") {
    if (current + width < total) return current + width
    // Nothing directly below: from the row above a short last row, step to
    // that row's last item rather than refusing to move.
    return row === Math.floor((total - 1) / width) ? current : total - 1
  }
  return current
}

// The window moves that drag a workspace from one place in the strip to
// another. Hyprland can't renumber a workspace, so the numbers stay put and
// the windows move between them: dropping 5 onto 2 leaves 5's windows on 2,
// 2's on 3, 3's on 4 and 4's on 5 - the same end state as swapping 5 with
// its neighbour over and over, done in one pass.
//
// `cards` is the strip as shown, [{ id, addresses }] in display order, with
// every window's Hyprland address. Because every window is addressed
// individually and the whole plan is worked out before anything moves, no
// scratch workspace is needed and it doesn't matter that two workspaces'
// windows share a number in between.
//
// Returns [{ address, workspace }], or nothing at all when the drag changes
// no window's workspace.
function planReorder(cards, fromIndex, toIndex) {
  var list = cards || []
  var from = Number(fromIndex)
  var to = Number(toIndex)
  if (!(from >= 0 && from < list.length)) return []
  if (!(to >= 0 && to < list.length)) return []
  if (from === to) return []

  var reordered = list.slice()
  reordered.splice(to, 0, reordered.splice(from, 1)[0])

  var moves = []
  for (var slot = 0; slot < list.length; slot++) {
    var target = list[slot] || {}
    var card = reordered[slot] || {}
    if (card.id === target.id) continue
    var addresses = card.addresses || []
    for (var i = 0; i < addresses.length; i++) {
      var address = String(addresses[i] || "")
      if (address.length > 0) moves.push({ address: address, workspace: target.id })
    }
  }
  return moves
}

// Every setting the widget understands, in the order the edit view shows
// them. This is the one place their bounds, fallbacks and wording live: the
// widget clamps with them, the edit view renders its form from them, and
// test/manifest.test.js checks that a fresh shell.json entry starts on the
// same defaults.
//
// `type` decides both the control the form shows and how a stored value is
// read back: "integer" (with `min`/`max`) or "boolean".
//
// Labels live here rather than in manifest.json: settings are edited in this
// plugin's own overlay, not in the Setup menu's generated form.
var SETTING_FIELDS = [
  {
    key: "maxIcons",
    type: "integer",
    min: 1,
    max: 10,
    fallback: 5,
    label: "Icons per workspace",
    description: "How many window icons to show before the rest are counted as +N."
  },
  {
    key: "iconSize",
    type: "integer",
    min: 8,
    max: 32,
    fallback: 14,
    label: "Icon size",
    description: "Size of each window icon, in pixels."
  },
  {
    key: "minWorkspaces",
    type: "integer",
    min: 0,
    max: 10,
    fallback: 5,
    label: "Workspaces always shown",
    description: "Workspaces shown even while they are empty, counted from 1. Ignored while empty workspaces are hidden."
  },
  {
    key: "hideEmpty",
    type: "boolean",
    fallback: false,
    label: "Hide empty workspaces",
    description: "Show only workspaces that have windows in them, plus the one you are on."
  },
  {
    key: "groupApps",
    type: "boolean",
    fallback: false,
    label: "Group windows by app",
    description: "Show one icon per app, with a count badge once it has 2 or more windows, instead of one icon per window."
  },
  {
    key: "gameIcons",
    type: "boolean",
    fallback: true,
    label: "Game icons",
    description: "Show a game's own icon for Proton-run games that are in your Steam library, including ones launched from Heroic or similar. Native Linux game binaries aren't covered. Resolved once per window class and cached, same as every other icon; turn off to skip that extra lookup entirely."
  },
  {
    key: "overviewEnabled",
    type: "boolean",
    fallback: true,
    label: "Workspace overview",
    description: "Clicking the workspace you are already on, or the key you bound, opens an overview of every workspace, window and saved setup. Off, a click only ever switches workspace."
  }
]

function settingField(name) {
  for (var i = 0; i < SETTING_FIELDS.length; i++)
    if (SETTING_FIELDS[i].key === name) return SETTING_FIELDS[i]
  return null
}

// What a fresh shell.json entry starts on - manifest.json's `defaults`.
var SETTING_DEFAULTS = {}
for (var field = 0; field < SETTING_FIELDS.length; field++)
  SETTING_DEFAULTS[SETTING_FIELDS[field].key] = SETTING_FIELDS[field].fallback

// shell.json is hand-edited, so a boolean can arrive as a real boolean, as
// the string "true"/"false", or as 1/0. Anything else is a typo rather than
// an intent, and falls back.
function coerceBoolean(value, fallback) {
  if (typeof value === "boolean") return value
  if (typeof value === "string") {
    var text = value.trim().toLowerCase()
    if (text === "true" || text === "1") return true
    if (text === "false" || text === "0") return false
    return fallback
  }
  if (value === 1) return true
  if (value === 0) return false
  return fallback
}

// A setting straight out of shell.json is whatever the user typed, so an
// out-of-range number, a string or a boolean all have to end up as a usable
// value rather than a broken widget.
function clampSetting(name, value) {
  var field = settingField(name)
  if (!field) return value
  if (field.type === "boolean") return coerceBoolean(value, field.fallback)

  var raw = typeof value === "string" ? value.trim() : value
  var usable = typeof raw === "number" || (typeof raw === "string" && raw.length > 0)
  var number = usable ? Number(raw) : NaN
  if (!isFinite(number)) return field.fallback

  return Math.min(field.max, Math.max(field.min, Math.round(number)))
}

// The shell replaces a widget's shell.json entry wholesale, so a changed
// setting has to be merged into everything the entry already holds - the icon
// overrides above all.
function applySetting(settings, key, value) {
  var current = settings && typeof settings === "object" ? settings : {}
  var next = {}
  for (var existing in current) if (existing !== "id") next[existing] = current[existing]
  next[key] = clampSetting(key, value)
  return next
}

function settingValue(settings, key) {
  var current = settings && typeof settings === "object" ? settings : {}
  var raw = current[key]
  return clampSetting(key, raw === undefined ? null : raw)
}

// This widget's own entry out of the bar layout the shell hands plugins, so
// the edit view starts from what is actually configured.
function widgetSettingsFrom(barConfig, pluginId) {
  var settings = {}
  var layout = barConfig && barConfig.layout ? barConfig.layout : null
  if (!layout) return settings

  var sections = ["left", "center", "right"]
  for (var s = 0; s < sections.length; s++) {
    var entries = layout[sections[s]]
    if (!entries || typeof entries.length !== "number") continue
    for (var i = 0; i < entries.length; i++) {
      var entry = entries[i]
      if (!entry || String(entry.id || "") !== String(pluginId)) continue
      for (var key in entry) if (key !== "id") settings[key] = entry[key]
      return settings
    }
  }
  return settings
}

// What the overlay shows, from the payload it was summoned with. `base` is
// the view that owns the surface; `settingsOpen` says whether the settings
// card is on top of it. Asking for the settings directly opens them on their
// own, with no overview behind - that is the difference Escape turns on.
function overlayState(payloadJson) {
  var view = parseOverlayPayload(payloadJson).view
  return {
    base: view === "settings" ? "settings" : "overview",
    settingsOpen: view === "settings"
  }
}

// What Escape (or a click on the backdrop) does next. Reaching the settings
// through the overview's gear is a step in, so the first Escape is a step
// back out to the overview rather than closing everything - the settings
// change what the overview shows, and going back is how you see it.
function overlayEscape(base, settingsOpen) {
  return settingsOpen && base === "overview" ? "back" : "close"
}

// One overlay serves every summonable view of this plugin, so the payload
// picks which one. A bare `{}` - what the documented toggle command and the
// bar click both send - means the overview; the settings form has to be
// asked for by name. Anything unreadable falls back to the overview too.
function parseOverlayPayload(payloadJson) {
  var view = "overview"
  try {
    var payload = JSON.parse(String(payloadJson || "{}"))
    if (payload && typeof payload.view === "string" && payload.view.length > 0)
      view = payload.view
  } catch (error) {}
  return { view: view }
}

// Node's CommonJS module loader defines `module`; QML's JS engine never
// does, so this is a no-op when the file is imported as a QML library.
if (typeof module !== "undefined" && module.exports) {
  module.exports = {
    computeWorkspaceIds: computeWorkspaceIds,
    computeWindowKey: computeWindowKey,
    classifyIconValue: classifyIconValue,
    lookupIconOverride: lookupIconOverride,
    steamAppId: steamAppId,
    groupToplevels: groupToplevels,
    spreadLayout: spreadLayout,
    cardWindowRect: cardWindowRect,
    nextWorkspaceId: nextWorkspaceId,
    windowSelector: windowSelector,
    navigateGrid: navigateGrid,
    planReorder: planReorder,
    sameIds: sameIds,
    clampSetting: clampSetting,
    SETTING_FIELDS: SETTING_FIELDS,
    SETTING_DEFAULTS: SETTING_DEFAULTS,
    settingField: settingField,
    applySetting: applySetting,
    settingValue: settingValue,
    widgetSettingsFrom: widgetSettingsFrom,
    parseOverlayPayload: parseOverlayPayload,
    overlayState: overlayState,
    overlayEscape: overlayEscape
  }
}
