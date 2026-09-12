// Pure logic pulled out of Workspaces.qml so it can run under plain Node in
// tests, with no Quickshell/Hyprland runtime available. Anything that needs
// Quickshell singletons (Quickshell.iconPath, DesktopEntries, Hyprland) stays
// in the QML file and is passed in here as plain data or a callback.

function computeWorkspaceIds(existingIds) {
  var ids = [1, 2, 3, 4, 5]

  for (var i = 0; i < existingIds.length; i++) {
    var id = existingIds[i]
    if (id > 0 && id <= 10 && ids.indexOf(id) === -1) ids.push(id)
  }

  ids.sort(function(left, right) { return left - right })
  return ids
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

// Bounds for the widget's numeric settings, kept in one place: the widget
// clamps with them, and test/manifest.test.js checks that the schema the
// Setup menu renders (manifest.json) offers exactly these ranges.
var SETTING_BOUNDS = {
  maxIcons: { min: 1, max: 10, fallback: 5 },
  iconSize: { min: 8, max: 32, fallback: 14 }
}

// A setting straight out of shell.json is whatever the user typed, so an
// out-of-range number, a string or a boolean all have to end up as a usable
// value rather than a broken widget.
function clampSetting(name, value) {
  var bounds = SETTING_BOUNDS[name]
  if (!bounds) return value

  var raw = typeof value === "string" ? value.trim() : value
  var usable = typeof raw === "number" || (typeof raw === "string" && raw.length > 0)
  var number = usable ? Number(raw) : NaN
  if (!isFinite(number)) return bounds.fallback

  return Math.min(bounds.max, Math.max(bounds.min, Math.round(number)))
}

// The fields the edit view offers, in order. Labels live here rather than in
// manifest.json: settings are edited in this plugin's own overlay, not in the
// Setup menu's generated form.
var SETTING_FIELDS = [
  {
    key: "maxIcons",
    label: "Icons per workspace",
    description: "How many window icons to show before the rest are counted as +N."
  },
  {
    key: "iconSize",
    label: "Icon size",
    description: "Size of each window icon, in pixels."
  }
]

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
    clampSetting: clampSetting,
    SETTING_BOUNDS: SETTING_BOUNDS,
    SETTING_FIELDS: SETTING_FIELDS,
    applySetting: applySetting,
    settingValue: settingValue,
    widgetSettingsFrom: widgetSettingsFrom,
    parseOverlayPayload: parseOverlayPayload
  }
}
