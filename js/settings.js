// The settings a shell.json entry carries: what they are called, what they
// range over, and how a value read back out of the file is pulled into
// something the widget can use. shell.json is hand-editable, so nothing here
// trusts what it is given.
//
// `computeWorkspaceIds` and `sameIds` live here rather than with the rest of
// the overview because which workspaces are shown is a pure function of
// these settings - it clamps them itself, and a file in js/ cannot call into
// another one (see below).
//
// Pure logic, so it runs under plain Node in the tests with no
// Quickshell/Hyprland runtime. Anything needing a Quickshell singleton
// (Quickshell.iconPath, DesktopEntries, Hyprland) stays in QML and is passed
// in here as plain data or a callback.
//
// A QML JavaScript resource cannot import another one without `.import`,
// which plain Node cannot parse - so every file in js/ stands alone, and a
// QML file imports each of the ones it needs. That is also why the two
// three-line helpers `own` and `isPlainObject` appear in more than one file
// rather than being shared.

// Every setting the widget understands, in the order the edit view shows
// them. This is the one place their bounds, fallbacks and wording live: the
// widget clamps with them, the edit view renders its form from them, and
// test/manifest.test.js checks that a fresh shell.json entry starts on the
// same defaults.
//
// `type` decides both the control the form shows and how a stored value is
// read back: "integer" (with `min`/`max`), "boolean", "enum" (with
// `options`) or "string" (with `maxLength`).
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
    key: "workspaceLabels",
    type: "string",
    maxLength: 500,
    fallback: "",
    label: "Workspace labels",
    description: "A comma-separated list shown instead of the numbers, in order from workspace 1 - for example \"a, b, c\" or \"一, 二, 三\". Workspaces past the end of the list, or left blank in it, keep their number."
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
    description: "Show a game's own icon for games started from Steam, Heroic or Lutris, native or Proton alike, read from the environment the launcher gives the game. Resolved once per game window and cached; turn off to skip that extra lookup entirely."
  },
  {
    key: "overviewEnabled",
    type: "boolean",
    fallback: true,
    label: "Workspace overview",
    description: "Clicking the workspace you are already on, or the key you bound, opens an overview of every workspace, window and saved setup. Off, a click only ever switches workspace."
  },
  {
    key: "setupTargetMode",
    type: "enum",
    options: ["add", "replace"],
    fallback: "add",
    label: "Opening a setup on an occupied workspace",
    description: "\"Add\" opens the setup's windows alongside what's already there. \"Replace\" closes the existing windows first - a normal close request, never a kill, so an app that wants to ask \"save changes?\" still gets to."
  },
  {
    key: "focusAfterSetupDrop",
    type: "boolean",
    fallback: true,
    label: "Focus after dropping a setup",
    description: "Switch to the workspace a setup was dropped on and close the overview. Off, the focus stays where it was and the overview stays open."
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
  if (field.type === "enum") {
    var text = typeof value === "string" ? value.trim() : value
    return field.options.indexOf(text) !== -1 ? text : field.fallback
  }
  // Someone editing shell.json by hand may well write the list as a JSON
  // array rather than one string, so that is taken as the same list.
  if (field.type === "string") {
    var list = value
    if (Array.isArray(list)) list = list.map(function(item) { return item === null || item === undefined ? "" : String(item) }).join(",")
    if (typeof list !== "string") return field.fallback
    return list.slice(0, field.maxLength)
  }

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

// What a workspace is called in the bar and on its overview card. `labels`
// is the `workspaceLabels` setting: any comma-separated list, where the Nth
// entry names workspace N. An entry left blank, or a workspace past the end
// of the list, keeps its number - with 10 shown as "0", matching the key
// that switches to it.
function workspaceLabel(id, labels) {
  var number = Number(id)
  var entries = clampSetting("workspaceLabels", labels).split(",")
  var entry = number >= 1 && number <= entries.length ? entries[number - 1].trim() : ""
  if (entry.length > 0) return entry
  return number === 10 ? "0" : String(id)
}

// Whether two id lists hold the same ids in the same order. The widget
// rebuilds every cell when its list changes, so it uses this to leave the
// list alone when a recomputation came out identical.
function sameIds(left, right) {
  if (!left || !right || left.length !== right.length) return false
  for (var i = 0; i < left.length; i++) if (left[i] !== right[i]) return false
  return true
}

// Node, for the unit tests. In QML this branch is never taken - the file is
// imported as a plain JavaScript resource, and `module` doesn't exist there.
if (typeof module !== "undefined") {
  module.exports = {
    SETTING_FIELDS: SETTING_FIELDS,
    settingField: settingField,
    SETTING_DEFAULTS: SETTING_DEFAULTS,
    clampSetting: clampSetting,
    applySetting: applySetting,
    settingValue: settingValue,
    widgetSettingsFrom: widgetSettingsFrom,
    computeWorkspaceIds: computeWorkspaceIds,
    workspaceLabel: workspaceLabel,
    sameIds: sameIds
  }
}
