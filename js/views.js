// Which view the one overlay surface shows, and what Escape does there. The
// payload comes from the `omarchy-shell shell toggle better-workspaces`
// command, so it is whatever the user typed into a keybinding.
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

// What the overlay shows, from the payload it was summoned with. `base` is
// the view that owns the surface; `settingsOpen`/`saveOpen` say whether that
// card is on top of it. Asking for the settings or the save dialog directly
// opens them on their own, with no overview behind - that is the difference
// Escape turns on.
function overlayState(payloadJson) {
  var view = parseOverlayPayload(payloadJson).view
  var settingsOpen = view === "settings"
  var saveOpen = view === "save"
  return {
    base: settingsOpen ? "settings" : (saveOpen ? "save" : "overview"),
    settingsOpen: settingsOpen,
    saveOpen: saveOpen
  }
}

// What Escape (or a click on the backdrop) does next. Reaching the settings
// or the save dialog through the overview (its gear, or a card's own save
// button) is a step in, so the first Escape is a step back out to the
// overview rather than closing everything - both cards change what the
// overview shows, and going back is how you see it.
function overlayEscape(base, cardOpen) {
  return cardOpen && base === "overview" ? "back" : "close"
}

// One overlay serves every summonable view of this plugin, so the payload
// picks which one. A bare `{}` - what the documented toggle command and the
// bar click both send - means the overview; the settings form and the save
// dialog (for whichever workspace is focused) have to be asked for by name.
// Anything unreadable falls back to the overview too.
function parseOverlayPayload(payloadJson) {
  var view = "overview"
  try {
    var payload = JSON.parse(String(payloadJson || "{}"))
    if (payload && typeof payload.view === "string" && payload.view.length > 0)
      view = payload.view
  } catch (error) {}
  return { view: view }
}

// Node, for the unit tests. In QML this branch is never taken - the file is
// imported as a plain JavaScript resource, and `module` doesn't exist there.
if (typeof module !== "undefined") {
  module.exports = {
    overlayState: overlayState,
    overlayEscape: overlayEscape,
    parseOverlayPayload: parseOverlayPayload
  }
}
