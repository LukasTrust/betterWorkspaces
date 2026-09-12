import QtQuick
import Quickshell

import "logic.js" as Logic

// Turns a Hyprland window into the icon to draw for it, and remembers the
// answer per window class. Both views need this - the bar widget for its
// per-window icons, the overview for the caption under each preview - and
// they have to agree, so it lives here rather than in either of them.
//
// Icon source, in order: a user override from this widget's shell.json
// entry, then (with `gameIcons` on) a Steam game's own icon, then the icon
// of the installed app whose desktop entry best matches the window's class,
// then a generic executable icon. Resolved icons are cached by window class
// (not per-window), so opening a second terminal or a second browser window
// never repeats the lookup.
//
// An Item rather than a QtObject only because it has to hold a Connections
// child; it draws nothing.
Item {
  id: root

  visible: false

  // This widget's shell.json entry - read for its "icons" overrides.
  property var settings: ({})
  property bool gameIcons: true

  property var _cache: ({})

  function clearCache() {
    root._cache = ({})
  }

  // The user's app list can change (installs/uninstalls); drop the cache so
  // affected windows re-resolve instead of keeping a stale fallback icon.
  Connections {
    target: DesktopEntries
    function onApplicationsChanged() {
      root.clearCache()
    }
  }

  // shell.json edits (e.g. to the "icons" overrides) hot-reload into
  // `settings` - drop the cache so they take effect immediately.
  onSettingsChanged: root.clearCache()
  onGameIconsChanged: root.clearCache()

  // Hyprland's own "class" (from hyprctl) is preferred over the wlr-toplevel
  // appId: some XWayland apps report an empty wayland appId while hyprctl
  // still reports a class, and this is what icon overrides are keyed by.
  function windowKey(toplevel) {
    if (!toplevel)
      return ""
    var ipc = toplevel.lastIpcObject || {}
    return Logic.computeWindowKey(ipc.class, ipc.initialClass, toplevel.wayland ? toplevel.wayland.appId : "")
  }

  // Turns a raw icon value (a user override or a DesktopEntry.icon) into
  // either a themed/file image source, or - if it doesn't resolve to an
  // icon-theme entry - plain text. This lets a user override with either an
  // icon-theme name or a literal glyph/emoji in shell.json.
  function classifyIconValue(value) {
    return Logic.classifyIconValue(value, function (name) {
      return Quickshell.iconPath(name, true)
    })
  }

  // Reads this widget's "icons" map from its shell.json layout entry, e.g.:
  //   { "id": "better-workspaces", "icons": { "firefox": "󰍬" } }
  function userIconOverride(key) {
    var overrides = root.settings ? root.settings.icons : null
    return Logic.lookupIconOverride(overrides, key)
  }

  readonly property var fallbackIcon: ({
      kind: "image",
      source: Quickshell.iconPath("application-x-executable", true)
    })

  // Steam installs a "steam_icon_<appid>" icon-theme entry for every game in
  // the library, so a Steam window's own icon is one theme lookup away once
  // its appid is pulled out of the class - no desktop-entry match needed and
  // nothing to guess. Returns null (rather than a text fallback) when the
  // class isn't a Steam window or the icon isn't installed, so the caller
  // falls through to the desktop-entry lookup instead of showing a raw name.
  function steamIcon(key) {
    var appId = Logic.steamAppId(key)
    if (!appId)
      return null
    var themed = Quickshell.iconPath("steam_icon_" + appId, true)
    return themed.length > 0 ? { kind: "image", source: themed } : null
  }

  function iconFor(toplevel) {
    var key = root.windowKey(toplevel)
    if (key.length === 0)
      return root.fallbackIcon

    var cacheKey = key.toLowerCase()
    var cached = root._cache[cacheKey]
    if (cached !== undefined)
      return cached

    var resolved = root.classifyIconValue(root.userIconOverride(key))
    if (!resolved && root.gameIcons)
      resolved = root.steamIcon(key)
    if (!resolved) {
      // An exact desktop-id match (e.g. window class "zen" -> zen.desktop)
      // beats the fuzzy heuristic: heuristicLookup scores by name/exec
      // similarity and can under-match a short, generic-looking class like
      // "zen" even though the id match is exact and free.
      var entry = DesktopEntries.byId(key) || DesktopEntries.heuristicLookup(key)
      if (entry && entry.icon)
        resolved = root.classifyIconValue(entry.icon)
    }
    if (!resolved)
      resolved = root.fallbackIcon

    root._cache[cacheKey] = resolved
    return resolved
  }
}
