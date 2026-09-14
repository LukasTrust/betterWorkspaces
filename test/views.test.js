// Which view the overlay shows, and what Escape does there.

const test = require("node:test")
const assert = require("node:assert/strict")

const {
  overlayState,
  overlayEscape,
  parseOverlayPayload
} = require("../js/views.js")

test("parseOverlayPayload picks the view, defaulting to the overview", () => {
  assert.deepEqual(parseOverlayPayload('{"view":"settings"}'), { view: "settings" })
  assert.deepEqual(parseOverlayPayload("{}"), { view: "overview" })
  assert.deepEqual(parseOverlayPayload(""), { view: "overview" })
  assert.deepEqual(parseOverlayPayload("not json"), { view: "overview" })
  assert.deepEqual(parseOverlayPayload('{"view":42}'), { view: "overview" })
})

test("overlayState opens the overview, or the settings/save dialog on their own", () => {
  assert.deepEqual(overlayState("{}"), { base: "overview", settingsOpen: false, saveOpen: false })
  assert.deepEqual(overlayState('{"view":"settings"}'), { base: "settings", settingsOpen: true, saveOpen: false })
  assert.deepEqual(overlayState('{"view":"save"}'), { base: "save", settingsOpen: false, saveOpen: true })
  assert.deepEqual(overlayState("not json"), { base: "overview", settingsOpen: false, saveOpen: false })
})

test("overlayEscape steps back to the overview, or closes", () => {
  // Reached through the overview's gear: the first Escape goes back.
  assert.equal(overlayEscape("overview", true), "back")
  // Summoned straight to the settings: there is nothing behind them.
  assert.equal(overlayEscape("settings", true), "close")
  // Plain overview, and the settings once they are already closed.
  assert.equal(overlayEscape("overview", false), "close")
})
