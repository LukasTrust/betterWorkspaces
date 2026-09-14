import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io

import "../js/icons.js" as Icons

// Turns a Hyprland window into the icon to draw for it, and remembers the
// answer per window class. Both views need this - the bar widget for its
// per-window icons, the overview for the caption under each preview - and
// they have to agree, so it lives here rather than in either of them.
//
// Icon source, in order: a user override from this widget's shell.json
// entry, then (with `gameIcons` on) the icon of the game a launcher (Steam,
// Heroic, Lutris) started in this window, then a Steam game's icon from its
// class, then the installed app whose desktop entry id is the class, then
// the web-app launcher that opens the site a browser `--app` window shows,
// then the fuzzy desktop-entry match, then a generic executable icon.
// Resolved icons are cached by window class (not per-window), so opening a
// second terminal or a second browser window never repeats the lookup; the
// launcher-game step is cached per process instead (see _gameCache).
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
  // Launcher-game icons by "<pid>:<class>". Per process rather than per
  // class: every umu/Proton game can share a class like "steam_app_default",
  // and only the environment tells them apart. null records "looked, not a
  // launcher's game", so a window's environment is read once, ever.
  property var _gameCache: ({})

  function clearCache() {
    root._cache = ({})
    root._gameCache = ({})
  }

  // One shared synchronous reader for /proc/<pid>/environ and for checking a
  // launcher's cached icon file exists - the same pattern SaveSetupView uses
  // for /proc/<pid>/cmdline. Only ever read on a cache miss.
  FileView {
    id: fileReader
    objectName: "fileReader"
    blockLoading: true
    blockAllReads: true
    printErrors: false
  }

  function readFile(path) {
    fileReader.path = path
    return String(fileReader.text() || "")
  }

  function installedApps() {
    return DesktopEntries.applications ? DesktopEntries.applications.values : []
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
    return Icons.computeWindowKey(ipc.class, ipc.initialClass, toplevel.wayland ? toplevel.wayland.appId : "")
  }

  // Turns a raw icon value (a user override or a DesktopEntry.icon) into
  // either a themed/file image source, or - if it doesn't resolve to an
  // icon-theme entry - plain text. This lets a user override with either an
  // icon-theme name or a literal glyph/emoji in shell.json.
  function classifyIconValue(value) {
    return Icons.classifyIconValue(value, function (name) {
      return Quickshell.iconPath(name, true)
    })
  }

  // Reads this widget's "icons" map from its shell.json layout entry, e.g.:
  //   { "id": "better-workspaces", "icons": { "firefox": "󰍬" } }
  function userIconOverride(key) {
    var overrides = root.settings ? root.settings.icons : null
    return Icons.lookupIconOverride(overrides, key)
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
    var appId = Icons.steamAppId(key)
    if (!appId)
      return null
    var themed = Quickshell.iconPath("steam_icon_" + appId, true)
    return themed.length > 0 ? {
      kind: "image",
      source: themed
    } : null
  }

  // The lookup `iconFor` runs, but keyed directly by a window class rather
  // than a live toplevel - what a saved setup's windows have instead, since
  // they aren't open (or even running) to read a toplevel off of.
  function iconForKey(key) {
    if (!key || key.length === 0)
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
      var entry = DesktopEntries.byId(key)
      // A browser --app window's class names the site it shows; the launcher
      // that opens that site has to be found before the fuzzy match, which
      // would otherwise settle on the browser's own entry.
      if (!entry)
        entry = Icons.findWebAppEntry(root.installedApps(), Icons.parseWebAppClass(key))
      if (!entry)
        entry = DesktopEntries.heuristicLookup(key)
      if (entry && entry.icon)
        resolved = root.classifyIconValue(entry.icon)
    }
    if (!resolved)
      resolved = root.fallbackIcon

    root._cache[cacheKey] = resolved
    return resolved
  }

  // The icon of the game a launcher started in process `pid`, read from the
  // environment the launcher gave it (see gameHintsFromEnv), or null.
  function launcherGameIcon(pid, key) {
    var numeric = Number(pid)
    if (!(numeric > 0))
      return null
    var cacheKey = numeric + ":" + String(key || "").toLowerCase()
    var cached = root._gameCache[cacheKey]
    if (cached !== undefined)
      return cached

    var env = Icons.parseProcEnviron(root.readFile("/proc/" + numeric + "/environ"))
    var hints = Icons.gameHintsFromEnv(env, Quickshell.env("HOME"), Quickshell.env("XDG_CONFIG_HOME"))
    var resolved = hints.length === 0 ? null : Icons.resolveGameHints(hints, {
      themed: function (name) {
        return Quickshell.iconPath(name, true)
      },
      entries: root.installedApps(),
      fileExists: function (path) {
        return root.readFile(path).length > 0
      }
    })

    root._gameCache[cacheKey] = resolved
    return resolved
  }

  function iconFor(toplevel) {
    var key = root.windowKey(toplevel)
    // A user override for the class still wins over everything.
    if (toplevel && root.gameIcons && root.userIconOverride(key).length === 0) {
      var ipc = toplevel.lastIpcObject || {}
      if (ipc.pid === undefined)
        root.requestIpcRefresh(toplevel)
      var game = root.launcherGameIcon(ipc.pid, key)
      if (game)
        return game
    }
    return root.iconForKey(key)
  }

  // A window opened after the shell started has an empty `lastIpcObject` -
  // so no pid - until something asks Hyprland for its clients again (see
  // Overview's refreshToplevels). Ask once per window; Qt.callLater folds a
  // burst of new windows into one refresh, and the new `lastIpcObject`
  // re-runs the icon binding that asked. Mutated in place on purpose: this
  // is bookkeeping, not something a binding should re-run over.
  property var _ipcRequested: ({})

  function requestIpcRefresh(toplevel) {
    var address = String(toplevel.address || "")
    if (address.length === 0 || root._ipcRequested[address])
      return
    root._ipcRequested[address] = true
    Qt.callLater(Hyprland.refreshToplevels)
  }
}
