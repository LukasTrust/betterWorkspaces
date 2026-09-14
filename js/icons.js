// Working out what a window is and which icon stands for it, plus the
// overview's search over the same two facts. The lookups themselves need
// Quickshell (iconPath, DesktopEntries) and stay in IconResolver.qml; what
// is here is the deciding.
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

function own(object, key) {
  return Object.prototype.hasOwnProperty.call(object, key)
}

// A window class is whatever the app running in it says it is, so it can
// collide with a name every object inherits - a window classing itself
// "constructor" or "__proto__" would otherwise read Object.prototype's
// member and render it as this app's icon. Only the map's own keys count.
function lookupIconOverride(overrides, key) {
  if (!overrides) return ""
  var name = String(key || "")
  if (own(overrides, name)) return String(overrides[name] || "")
  var lower = name.toLowerCase()
  return own(overrides, lower) ? String(overrides[lower] || "") : ""
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

// Whether a window matches an overview search query - case-insensitively,
// against either its title or its window class. An empty/blank query
// matches everything, so the overview's default (no query yet) never hides
// anything.
function matchesSearchQuery(title, windowClass, query) {
  var q = String(query || "").trim().toLowerCase()
  if (q.length === 0) return true
  if (String(title || "").toLowerCase().indexOf(q) !== -1) return true
  return String(windowClass || "").toLowerCase().indexOf(q) !== -1
}

// Node, for the unit tests. In QML this branch is never taken - the file is
// imported as a plain JavaScript resource, and `module` doesn't exist there.
if (typeof module !== "undefined") {
  module.exports = {
    computeWindowKey: computeWindowKey,
    classifyIconValue: classifyIconValue,
    lookupIconOverride: lookupIconOverride,
    steamAppId: steamAppId,
    groupToplevels: groupToplevels,
    matchesSearchQuery: matchesSearchQuery
  }
}
