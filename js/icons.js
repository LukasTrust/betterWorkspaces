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

// ---- web apps -------------------------------------------------------------
//
// A Chromium-family browser (Chrome, Chromium, Brave, Edge, Vivaldi, Helium,
// ...) names a `--app=<url>` window after the URL it opened:
// "<browser>-<host>__<path>-<profile>", e.g. "chrome-app.hey.com__-Default"
// or "brave-discord.com__app-Default". That is how every `omarchy webapp
// install` launcher opens, so the class alone says which site a window is -
// no title parsing, no list of known sites or browsers. The class is stamped
// by the browser itself, so it holds even when the browser was already
// running and the window's pid (and cmdline) is the main browser process.
//
// The browser prefix isn't checked; a dotted host followed by "__" is what
// tells this apart from an ordinary class. Installed PWAs
// ("chrome-<extension id>-Default"), Firefox PWAs ("FFPWA-<id>") and GNOME
// Web apps ship a desktop entry whose id *is* the class, so the plain
// desktop-id lookup already covers those.
//
// Returns { host, path } normalized for comparing with urlsInExec, or null.
function parseWebAppClass(key) {
  var match = /^[a-z][a-z0-9]*(?:-[a-z0-9]+)*?-((?:[a-z0-9-]+\.)+[a-z0-9-]+)__(.*)-[^-]+$/i.exec(String(key || "").trim())
  return match ? { host: normalizeHost(match[1]), path: normalizeAppPath(match[2]) } : null
}

function normalizeHost(host) {
  return String(host || "").toLowerCase().replace(/^www\./, "")
}

// The class spells the URL path with "_" for "/"; spell both sides that way,
// minus leading/trailing separators, so "discord.com/app/" and "__app" agree.
function normalizeAppPath(path) {
  return String(path || "").replace(/\//g, "_").replace(/^_+|_+$/g, "")
}

// Every http(s) URL in a desktop entry's Exec line, as { host, path } in the
// same normalized form parseWebAppClass returns.
function urlsInExec(execString) {
  var found = String(execString || "").match(/https?:\/\/[^\s"'<>]+/gi) || []
  var urls = []
  for (var i = 0; i < found.length; i++) {
    var parts = /^https?:\/\/([^\/?#:]+)(?::\d+)?([^?#]*)/i.exec(found[i])
    if (parts) urls.push({ host: normalizeHost(parts[1]), path: normalizeAppPath(parts[2]) })
  }
  return urls
}

// The installed launcher (with an icon) that opens the site a web-app window
// shows: same host and path beats same host alone, and the first entry wins
// a tie. `entries` are DesktopEntry-shaped ({ execString, icon }).
function findWebAppEntry(entries, app) {
  if (!app) return null
  var list = entries || []
  var best = null
  var bestScore = 0
  for (var i = 0; i < list.length; i++) {
    var entry = list[i]
    if (!entry || !entry.icon) continue
    var urls = urlsInExec(entry.execString)
    for (var j = 0; j < urls.length; j++) {
      if (urls[j].host !== app.host) continue
      var score = urls[j].path === app.path ? 2 : 1
      if (score > bestScore) {
        best = entry
        bestScore = score
      }
    }
  }
  return best
}

// ---- games started by a launcher --------------------------------------------
//
// A game started from Heroic, Lutris or Steam usually runs under Wine/Proton
// with a class that says nothing about which game it is ("steam_app_default",
// "game.exe"). What does say it is the environment the launcher starts the
// game with, which every process of the game inherits:
//   Steam / Proton / umu   SteamAppId, SteamGameId, STEAM_COMPAT_APP_ID
//   Heroic                 HEROIC_APP_NAME
//   Lutris                 GAME_NAME
// These are the launchers' own conventions, not a list of games - any game
// they start is covered.

// /proc/<pid>/environ: NUL-separated NAME=value pairs. Names are kept on an
// object with no prototype, so a variable called "constructor" is just data.
function parseProcEnviron(raw) {
  var env = Object.create(null)
  var parts = String(raw || "").split(String.fromCharCode(0))
  for (var i = 0; i < parts.length; i++) {
    var split = parts[i].indexOf("=")
    if (split <= 0) continue
    var name = parts[i].slice(0, split)
    if (!own(env, name)) env[name] = parts[i].slice(split + 1)
  }
  return env
}

// Lutris names a game's icon "lutris_<slug>", with the slug made the way
// Django's slugify does it.
function lutrisSlug(name) {
  return String(name || "")
    .normalize("NFKD")
    .replace(/[^\x00-\x7f]/g, "")
    .replace(/[^\w\s-]/g, "")
    .trim()
    .toLowerCase()
    .replace(/[-\s]+/g, "-")
}

// Something a launcher's id can safely become a single file name from.
function isPlainFileName(name) {
  return name.length > 0 && name.indexOf("/") === -1 && name.charAt(0) !== "."
}

var HEROIC_ICON_EXTENSIONS = ["png", "jpg", "jpeg", "webp", "svg", "ico"]

// Heroic caches each game's icon as <config>/heroic/icons/<appName>.<ext>,
// the extension being whatever the store served; the Flatpak keeps its config
// under ~/.var instead.
function heroicIconPaths(appName, home, configHome) {
  var name = String(appName || "")
  var homeDir = String(home || "")
  if (!isPlainFileName(name) || homeDir.length === 0) return []
  var dirs = [
    (String(configHome || "") || homeDir + "/.config") + "/heroic/icons",
    homeDir + "/.var/app/com.heroicgameslauncher.hgl/config/heroic/icons"
  ]
  var paths = []
  for (var i = 0; i < dirs.length; i++)
    for (var j = 0; j < HEROIC_ICON_EXTENSIONS.length; j++)
      paths.push(dirs[i] + "/" + name + "." + HEROIC_ICON_EXTENSIONS[j])
  return paths
}

// What a game's launcher environment offers towards an icon, most specific
// first. Each hint is one of
//   { kind: "themed", name }   an icon-theme name
//   { kind: "exec", token }    a desktop entry whose Exec names this id
//   { kind: "name", name }     a desktop entry with this exact Name
//   { kind: "file", paths }    the first of these files that exists
// An empty list means nothing marks the window as a launcher's game.
function gameHintsFromEnv(env, home, configHome) {
  var vars = env || {}
  var hints = []

  var steamVars = ["SteamAppId", "SteamGameId", "STEAM_COMPAT_APP_ID"]
  for (var i = 0; i < steamVars.length; i++) {
    var appId = own(vars, steamVars[i]) ? String(vars[steamVars[i]]).trim() : ""
    if (/^[1-9]\d*$/.test(appId)) {
      hints.push({ kind: "themed", name: "steam_icon_" + appId })
      break
    }
  }

  var heroicApp = own(vars, "HEROIC_APP_NAME") ? String(vars.HEROIC_APP_NAME).trim() : ""
  if (heroicApp.length > 0) {
    // A "Add to applications menu" shortcut runs heroic://launch/.../<appName>.
    hints.push({ kind: "exec", token: heroicApp })
    var paths = heroicIconPaths(heroicApp, home, configHome)
    if (paths.length > 0) hints.push({ kind: "file", paths: paths })
  }

  var lutrisGame = own(vars, "GAME_NAME") ? String(vars.GAME_NAME).trim() : ""
  if (lutrisGame.length > 0) {
    hints.push({ kind: "name", name: lutrisGame })
    var slug = lutrisSlug(lutrisGame)
    if (slug.length > 0) hints.push({ kind: "themed", name: "lutris_" + slug })
  }

  return hints
}

// Whether `token` appears in an Exec line as a whole id - "CrabEA" in
// "heroic://launch/legendary/CrabEA", not inside "CrabEAX".
function execReferences(execString, token) {
  var exec = String(execString || "")
  var wanted = String(token || "")
  if (wanted.length === 0) return false
  var isIdChar = function (c) {
    return /[A-Za-z0-9_]/.test(c)
  }
  for (var at = exec.indexOf(wanted); at !== -1; at = exec.indexOf(wanted, at + 1)) {
    var before = at > 0 ? exec.charAt(at - 1) : ""
    var after = exec.charAt(at + wanted.length)
    if (!isIdChar(before) && !isIdChar(after)) return true
  }
  return false
}

// Turns gameHintsFromEnv's hints into an icon, trying them in order. The
// lookups needing Quickshell come in as `lookup`:
//   themed(name)     -> source URL, or "" (Quickshell.iconPath)
//   entries          -> installed DesktopEntry-shaped objects
//   fileExists(path) -> bool
// Returns an image icon, or null when no hint resolves - a game icon is never
// a text fallback.
function resolveGameHints(hints, lookup) {
  var list = hints || []
  var entries = lookup.entries || []
  for (var i = 0; i < list.length; i++) {
    var hint = list[i]
    var icon = null
    if (hint.kind === "themed") {
      var themed = String(lookup.themed(hint.name) || "")
      if (themed.length > 0) icon = { kind: "image", source: themed }
    } else if (hint.kind === "file") {
      for (var p = 0; p < hint.paths.length && !icon; p++)
        if (lookup.fileExists(hint.paths[p])) icon = { kind: "image", source: "file://" + hint.paths[p] }
    } else {
      for (var e = 0; e < entries.length && !icon; e++) {
        var entry = entries[e]
        if (!entry || !entry.icon) continue
        var matches = hint.kind === "exec"
          ? execReferences(entry.execString, hint.token)
          : String(entry.name || "").toLowerCase() === hint.name.toLowerCase()
        if (!matches) continue
        var classified = classifyIconValue(entry.icon, lookup.themed)
        if (classified && classified.kind === "image") icon = classified
      }
    }
    if (icon) return icon
  }
  return null
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
    parseWebAppClass: parseWebAppClass,
    urlsInExec: urlsInExec,
    findWebAppEntry: findWebAppEntry,
    parseProcEnviron: parseProcEnviron,
    lutrisSlug: lutrisSlug,
    heroicIconPaths: heroicIconPaths,
    gameHintsFromEnv: gameHintsFromEnv,
    execReferences: execReferences,
    resolveGameHints: resolveGameHints,
    groupToplevels: groupToplevels,
    matchesSearchQuery: matchesSearchQuery
  }
}
