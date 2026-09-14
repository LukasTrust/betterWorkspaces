// Saved setups: a named snapshot of a workspace - how to start each window
// again (its recipe), what it looked like, and where it sat, relative to the
// workspace (0..1) so it survives a different monitor resolution.
//
// This file is the setups.json contract: what a valid file holds, what a
// name may be, and what boot does with them. setups.json is hand-editable,
// so a load never throws - anything malformed is dropped, not fatal.
// Rebuilding a setup's window layout is `splits.js`.
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

var SETUP_SCHEMA_VERSION = 1

function isPlainObject(value) {
  return !!value && typeof value === "object" && !Array.isArray(value)
}

function own(object, key) {
  return Object.prototype.hasOwnProperty.call(object, key)
}

// A name is free text - it's a JSON key and a label, never a filename, since
// every setup lives in the one file - so anything is allowed except blank.
// An existing name isn't rejected, only flagged: overwriting it is a
// deliberate choice the caller confirms, not an error the form blocks.
function setupNameStatus(name, existingNames) {
  var trimmed = String(name || "").trim()
  if (trimmed.length === 0) return "empty"
  var list = existingNames || []
  for (var i = 0; i < list.length; i++)
    if (String(list[i]) === trimmed) return "duplicate"
  return "ok"
}

// One window inside a setup: how to start it again (a desktop entry id, or
// the argv a plain process was launched with), what it looked like
// (`class`, floating, fullscreen), and its rectangle relative to the
// workspace it was saved from.
function validateSetupWindow(window) {
  if (!isPlainObject(window)) return false
  var recipe = window.recipe
  if (!isPlainObject(recipe)) return false
  if (recipe.type === "desktop-entry") {
    if (typeof recipe.id !== "string" || recipe.id.length === 0) return false
  } else if (recipe.type === "argv") {
    if (!Array.isArray(recipe.argv) || recipe.argv.length === 0) return false
    for (var i = 0; i < recipe.argv.length; i++)
      if (typeof recipe.argv[i] !== "string" || recipe.argv[i].length === 0) return false
  } else {
    return false
  }
  if (typeof window.class !== "string") return false
  if (typeof window.floating !== "boolean") return false
  if (typeof window.fullscreen !== "boolean") return false
  var rect = window.rect
  if (!isPlainObject(rect)) return false
  var fields = ["x", "y", "width", "height"]
  for (var f = 0; f < fields.length; f++)
    if (typeof rect[fields[f]] !== "number" || !isFinite(rect[fields[f]])) return false
  return true
}

// One saved setup: an ordered, non-empty list of windows, plus which
// workspace it should open on at boot (`null`/absent for "never"). Anything
// that fails this is dropped rather than crashing the whole load - one
// broken entry shouldn't cost every other saved setup.
function validateSetupEntry(setup) {
  if (!isPlainObject(setup)) return false
  if (!Array.isArray(setup.windows) || setup.windows.length === 0) return false
  for (var i = 0; i < setup.windows.length; i++)
    if (!validateSetupWindow(setup.windows[i])) return false
  if (setup.bootWorkspace !== null && setup.bootWorkspace !== undefined) {
    if (typeof setup.bootWorkspace !== "number" || setup.bootWorkspace < 1 || setup.bootWorkspace > 10)
      return false
  }
  return true
}

// The whole setups.json file, as read off disk. A missing or corrupt file,
// an unreadable schemaVersion, or a top-level shape that isn't
// `{ schemaVersion, setups: {} }` comes back as no setups at all rather than
// throwing - the file is hand-editable and nothing here should be able to
// crash the plugin over it. A malformed entry inside an otherwise-valid file
// is dropped on its own, so the rest of the file still loads.
function validateSetupFile(raw) {
  var parsed
  try {
    parsed = typeof raw === "string" ? JSON.parse(raw) : raw
  } catch (error) {
    return {}
  }
  if (!isPlainObject(parsed)) return {}
  if (parsed.schemaVersion !== SETUP_SCHEMA_VERSION) return {}
  if (!isPlainObject(parsed.setups)) return {}

  var setups = {}
  for (var name in parsed.setups)
    if (validateSetupEntry(parsed.setups[name])) setups[name] = parsed.setups[name]
  return setups
}

// Renames a setup, keeping everything it holds - its windows and whichever
// boot workspace it was assigned. Every setup lives in one document keyed by
// name, so a rename is a key change and the whole map is rewritten.
//
// Returns null rather than a changed map for anything that isn't a rename
// that can go ahead: an unknown setup, a blank name, the name it already has,
// or one another setup is using. The caller shows why using
// `setupNameStatus`; refusing here is what keeps a rename from quietly
// swallowing the setup it collided with.
function renameSetup(setups, from, to) {
  var current = setups || {}
  var oldName = String(from || "")
  var newName = String(to || "").trim()

  if (!own(current, oldName)) return null
  if (newName.length === 0) return null
  if (newName === oldName) return null
  if (own(current, newName)) return null

  var next = {}
  for (var key in current) {
    if (key === oldName) next[newName] = current[key]
    else next[key] = current[key]
  }
  return next
}

// Which windows a drop onto an already-occupied workspace has to close
// before the setup opens. `add` never closes anything; `replace` closes
// every window already there - a plain `close()` request each, never a
// kill, so an app that wants to ask "save changes?" still gets to. An empty
// workspace has nothing to close either way.
function planSetupOpen(targetWindows, mode) {
  var windows = targetWindows || []
  if (mode !== "replace") return []
  var addresses = []
  for (var i = 0; i < windows.length; i++) {
    var address = windows[i] && windows[i].address
    if (address) addresses.push(String(address))
  }
  return addresses
}

// Which of the addresses a `replace` drop asked to close are still actually
// open, checked against Hyprland's current toplevel list - the caller waits
// on this (with a timeout, since an app can sit on a "save changes?" dialog
// forever) before opening the setup, so its windows don't have to share the
// workspace with the ones being replaced even for a moment.
function remainingCloseTargets(pending, currentAddresses) {
  var open = {}
  var current = currentAddresses || []
  for (var i = 0; i < current.length; i++) open[String(current[i])] = true
  var list = pending || []
  var remaining = []
  for (var p = 0; p < list.length; p++)
    if (open[String(list[p])]) remaining.push(String(list[p]))
  return remaining
}

// Assigns (or clears, for a falsy/out-of-range workspaceId) which workspace
// a setup opens on at boot. At most one setup per workspace: handing this
// one a workspace another setup already had takes it away from that one,
// rather than leaving two setups racing for the same slot at boot - the
// friendlier resolution over just refusing the change.
function assignBootWorkspace(setups, name, workspaceId) {
  var current = setups || {}
  var target = Number(workspaceId) || 0
  if (target < 1 || target > 10) target = 0

  var next = {}
  for (var key in current) {
    var entry = current[key] || {}
    var copy = {}
    for (var field in entry) copy[field] = entry[field]
    if (target > 0 && key !== name && copy.bootWorkspace === target)
      copy.bootWorkspace = null
    next[key] = copy
  }
  if (next[name]) next[name].bootWorkspace = target > 0 ? target : null
  return next
}

// Whether the boot service should actually run: only once per Hyprland
// session, so `omarchy restart shell` (which restarts this service along
// with everything else) doesn't reopen every boot setup a second time. The
// guard file holds the signature of whichever session already ran it; a
// session with no signature at all (Hyprland not actually running yet, or
// the env var missing) never runs rather than guessing.
function shouldRunBoot(guardContent, signature) {
  var sig = String(signature || "")
  if (!sig) return false
  return String(guardContent || "") !== sig
}

// Which setups to open at boot, and in what order: every setup with a valid
// `bootWorkspace` (1-10), lowest workspace first so a multi-monitor layout
// fills in a stable order. `assignBootWorkspace` already keeps this
// one-setup-per-workspace, but the file is hand-editable, so a duplicate is
// still resolved here rather than opening two setups onto the same
// workspace - alphabetically first name wins, same tie-break `setupNames`
// already uses elsewhere.
function bootEntries(setups) {
  var all = setups || {}
  var names = Object.keys(all).sort()
  var seenWorkspace = {}
  var entries = []
  for (var i = 0; i < names.length; i++) {
    var name = names[i]
    var entry = all[name] || {}
    var workspaceId = entry.bootWorkspace
    if (typeof workspaceId !== "number" || workspaceId < 1 || workspaceId > 10) continue
    if (seenWorkspace[workspaceId]) continue
    seenWorkspace[workspaceId] = true
    entries.push({ name: name, workspaceId: workspaceId })
  }
  entries.sort(function (a, b) { return a.workspaceId - b.workspaceId })
  return entries
}

// A window's rectangle scaled into 0..1 relative to the workspace area it
// was saved from, so the saved position survives a different monitor
// resolution or a workspace that moves to another monitor later. Clamped to
// the area for the same reason `cardWindowRect` is: a window Hyprland
// reports hanging off the edge shouldn't produce an unusable (negative or
// >1) rect. An area with no usable size (nothing measured yet) comes back
// as "the whole workspace" rather than all zeros, which would collapse
// every window's saved position to a single point.
function relativeRect(rect, area) {
  var r = rect || {}
  var a = area || {}
  var areaWidth = Number(a.width) || 0
  var areaHeight = Number(a.height) || 0
  if (areaWidth <= 0 || areaHeight <= 0) return { x: 0, y: 0, width: 1, height: 1 }

  var x = ((Number(r.x) || 0) - (Number(a.x) || 0)) / areaWidth
  var y = ((Number(r.y) || 0) - (Number(a.y) || 0)) / areaHeight
  var width = (Number(r.width) || 0) / areaWidth
  var height = (Number(r.height) || 0) / areaHeight

  return {
    x: Math.min(1, Math.max(0, x)),
    y: Math.min(1, Math.max(0, y)),
    width: Math.min(1, Math.max(0, width)),
    height: Math.min(1, Math.max(0, height))
  }
}

// Turns a workspace's current windows into a setup's `windows` array - the
// one part of saving that isn't just a straight read of Hyprland's state.
//
// `items` is one entry per window, in the order to restore them, already
// carrying whatever needed a live lookup: `desktopEntryId` (the best
// matching installed app's desktop id, or "" for none) and `argv` (the
// process's actual command line, read from /proc/<pid>/cmdline, or null if
// that failed). A desktop entry beats a raw command line whenever both are
// available - it survives the app itself changing how it's launched, where
// a frozen argv wouldn't. A window with neither has no way to be started
// again and is left out rather than saved half-broken.
function captureSetupWindows(items) {
  var list = items || []
  var windows = []
  for (var i = 0; i < list.length; i++) {
    var item = list[i] || {}
    var recipe = null
    if (item.desktopEntryId)
      recipe = { type: "desktop-entry", id: String(item.desktopEntryId) }
    else if (Array.isArray(item.argv) && item.argv.length > 0)
      recipe = { type: "argv", argv: item.argv.map(String) }
    if (!recipe) continue

    windows.push({
      recipe: recipe,
      class: String(item.class || ""),
      floating: !!item.floating,
      fullscreen: !!item.fullscreen,
      rect: relativeRect(item.rect, item.area)
    })
  }
  return windows
}

// `/proc/<pid>/cmdline` is the process's real argv, NUL-separated with a
// trailing NUL - read as text (not bytes: a QString round-trips an embedded
// NUL as a plain character, unlike a C string, so nothing is lost splitting
// on it). Empty input - the read failed, or the pid is already gone by the
// time it's read - comes back as no argv at all rather than one empty one.
function parseProcCmdline(raw) {
  var text = String(raw || "")
  if (text.length === 0) return []
  var parts = text.split(String.fromCharCode(0))
  if (parts.length > 0 && parts[parts.length - 1] === "") parts.pop()
  return parts
}

// Node, for the unit tests. In QML this branch is never taken - the file is
// imported as a plain JavaScript resource, and `module` doesn't exist there.
if (typeof module !== "undefined") {
  module.exports = {
    SETUP_SCHEMA_VERSION: SETUP_SCHEMA_VERSION,
    setupNameStatus: setupNameStatus,
    validateSetupWindow: validateSetupWindow,
    validateSetupEntry: validateSetupEntry,
    validateSetupFile: validateSetupFile,
    renameSetup: renameSetup,
    planSetupOpen: planSetupOpen,
    remainingCloseTargets: remainingCloseTargets,
    assignBootWorkspace: assignBootWorkspace,
    shouldRunBoot: shouldRunBoot,
    bootEntries: bootEntries,
    relativeRect: relativeRect,
    captureSetupWindows: captureSetupWindows,
    parseProcCmdline: parseProcCmdline
  }
}
