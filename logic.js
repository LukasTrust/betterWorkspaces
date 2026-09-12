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

// One overlay serves every summonable view of this plugin, so the payload
// picks which one. Anything unreadable falls back to the settings view.
function parseOverlayPayload(payloadJson) {
  var view = "settings"
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
    groupToplevels: groupToplevels,
    sameIds: sameIds,
    clampSetting: clampSetting,
    SETTING_FIELDS: SETTING_FIELDS,
    SETTING_DEFAULTS: SETTING_DEFAULTS,
    settingField: settingField,
    applySetting: applySetting,
    settingValue: settingValue,
    widgetSettingsFrom: widgetSettingsFrom,
    parseOverlayPayload: parseOverlayPayload
  }
}
