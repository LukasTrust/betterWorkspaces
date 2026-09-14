// How a Hyprland dispatch names one particular window. Small on purpose and
// on its own: three different views build dispatches with it, and getting it
// wrong fails silently rather than loudly (see the comment below).
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

// How a Hyprland dispatch names one particular window.
//
// Hyprland's selector wants `address:0x55f...`, and Quickshell hands the
// address over *without* the `0x` - so pasting it straight in produces a
// selector that matches nothing. Hyprland still answers "ok", it just
// silently does nothing, which is a far worse failure than an error: every
// drag and every focus-by-address looks like it worked and doesn't.
function windowSelector(address) {
  var text = String(address || "").trim()
  if (text.length === 0) return ""
  return "address:" + (text.indexOf("0x") === 0 || text.indexOf("0X") === 0 ? text : "0x" + text)
}

// Node, for the unit tests. In QML this branch is never taken - the file is
// imported as a plain JavaScript resource, and `module` doesn't exist there.
if (typeof module !== "undefined") {
  module.exports = {
    windowSelector: windowSelector
  }
}
