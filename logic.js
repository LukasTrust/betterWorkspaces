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

// Node's CommonJS module loader defines `module`; QML's JS engine never
// does, so this is a no-op when the file is imported as a QML library.
if (typeof module !== "undefined" && module.exports) {
  module.exports = {
    computeWorkspaceIds: computeWorkspaceIds,
    computeWindowKey: computeWindowKey,
    classifyIconValue: classifyIconValue,
    lookupIconOverride: lookupIconOverride
  }
}
