// The setups.json contract: what a valid file holds, what a name may be, what
// is captured from a live workspace, and what boot does with it all.

const test = require("node:test")
const assert = require("node:assert/strict")

const {
  SETUP_SCHEMA_VERSION,
  setupNameStatus,
  validateSetupWindow,
  validateSetupEntry,
  validateSetupFile,
  renameSetup,
  planSetupOpen,
  remainingCloseTargets,
  assignBootWorkspace,
  shouldRunBoot,
  bootEntries,
  relativeRect,
  captureSetupWindows,
  parseProcCmdline
} = require("../js/setups.js")

function aWindow(overrides) {
  return Object.assign({
    recipe: { type: "desktop-entry", id: "firefox.desktop" },
    class: "firefox",
    floating: false,
    fullscreen: false,
    rect: { x: 0, y: 0, width: 1, height: 1 }
  }, overrides)
}

function aSetup(windows, overrides) {
  return Object.assign({ windows: windows || [aWindow()] }, overrides)
}

function aSetupFile(setups) {
  return JSON.stringify({ schemaVersion: SETUP_SCHEMA_VERSION, setups: setups })
}

const twoSetups = () => ({
  Work: { windows: [aWindow()], bootWorkspace: 2 },
  Games: { windows: [aWindow()], bootWorkspace: null }
})

function anItem(overrides) {
  return Object.assign({
    desktopEntryId: "firefox.desktop",
    argv: null,
    class: "firefox",
    floating: false,
    fullscreen: false,
    rect: { x: 0, y: 0, width: 1920, height: 1080 },
    area: { x: 0, y: 0, width: 1920, height: 1080 }
  }, overrides)
}

function rect(x, y, width, height, floating) {
  return { rect: { x, y, width, height }, floating: !!floating }
}

test("setupNameStatus rejects a blank or whitespace-only name", () => {
  assert.equal(setupNameStatus("", []), "empty")
  assert.equal(setupNameStatus("   ", []), "empty")
  assert.equal(setupNameStatus(null, []), "empty")
})

test("setupNameStatus flags an existing name instead of rejecting it", () => {
  assert.equal(setupNameStatus("Work", ["Work", "Games"]), "duplicate")
  assert.equal(setupNameStatus("games", ["Work", "Games"]), "ok")
})

test("setupNameStatus accepts special characters and unicode - it is a label, not a filename", () => {
  assert.equal(setupNameStatus("🎮 Gaming / Night-Shift!", []), "ok")
  assert.equal(setupNameStatus("日本語", []), "ok")
})

test("renameSetup moves a setup to its new name, keeping everything it holds", () => {
  const renamed = renameSetup(twoSetups(), "Work", "Office")
  assert.deepEqual(Object.keys(renamed).sort(), ["Games", "Office"])
  assert.equal(renamed.Office.bootWorkspace, 2)
  assert.deepEqual(renamed.Office.windows, [aWindow()])
  assert.equal("Work" in renamed, false)
})

test("renameSetup trims the new name, the way saving one does", () => {
  const renamed = renameSetup(twoSetups(), "Work", "   Office   ")
  assert.ok("Office" in renamed)
})

test("renameSetup refuses anything that isn't a rename it can carry out", () => {
  // Unknown setup, blank name, the name it already has, and a name another
  // setup is using - that last one would otherwise swallow "Games".
  assert.equal(renameSetup(twoSetups(), "Nope", "Office"), null)
  assert.equal(renameSetup(twoSetups(), "Work", "   "), null)
  assert.equal(renameSetup(twoSetups(), "Work", ""), null)
  assert.equal(renameSetup(twoSetups(), "Work", "Work"), null)
  assert.equal(renameSetup(twoSetups(), "Work", "Games"), null)
})

test("renameSetup leaves the setups it was given untouched", () => {
  const before = twoSetups()
  renameSetup(before, "Work", "Office")
  assert.deepEqual(Object.keys(before).sort(), ["Games", "Work"])
})

test("renameSetup copes with nothing usable passed in", () => {
  assert.equal(renameSetup(null, "Work", "Office"), null)
  assert.equal(renameSetup({}, "Work", "Office"), null)
  // An inherited name is not a setup that exists, and not one that collides.
  assert.equal(renameSetup(twoSetups(), "constructor", "Office"), null)
  assert.ok("toString" in renameSetup(twoSetups(), "Work", "toString"))
})

test("validateSetupWindow accepts a desktop-entry or argv recipe", () => {
  assert.equal(validateSetupWindow(aWindow()), true)
  assert.equal(validateSetupWindow(aWindow({ recipe: { type: "argv", argv: ["code", "--new-window"] } })), true)
})

test("validateSetupWindow rejects a broken recipe", () => {
  assert.equal(validateSetupWindow(aWindow({ recipe: { type: "desktop-entry", id: "" } })), false)
  assert.equal(validateSetupWindow(aWindow({ recipe: { type: "argv", argv: [] } })), false)
  assert.equal(validateSetupWindow(aWindow({ recipe: { type: "argv", argv: ["code", 7] } })), false, "non-string argv")
  assert.equal(validateSetupWindow(aWindow({ recipe: { type: "unknown" } })), false)
  assert.equal(validateSetupWindow(aWindow({ recipe: null })), false)
})

test("validateSetupWindow rejects wrong-typed fields and an unusable rect", () => {
  assert.equal(validateSetupWindow(aWindow({ floating: "false" })), false)
  assert.equal(validateSetupWindow(aWindow({ class: 3 })), false)
  assert.equal(validateSetupWindow(aWindow({ rect: { x: 0, y: 0, width: "1", height: 1 } })), false)
  assert.equal(validateSetupWindow(null), false)
})

test("validateSetupEntry needs at least one valid window", () => {
  assert.equal(validateSetupEntry(aSetup([aWindow()])), true)
  assert.equal(validateSetupEntry(aSetup([])), false)
  assert.equal(validateSetupEntry(aSetup([aWindow(), aWindow({ class: 3 })])), false)
  assert.equal(validateSetupEntry(null), false)
})

test("validateSetupEntry accepts a boot workspace 1-10 or none, rejects anything else", () => {
  assert.equal(validateSetupEntry(aSetup([aWindow()], { bootWorkspace: 3 })), true)
  assert.equal(validateSetupEntry(aSetup([aWindow()], { bootWorkspace: null })), true)
  assert.equal(validateSetupEntry(aSetup([aWindow()])), true, "absent is fine too")
  assert.equal(validateSetupEntry(aSetup([aWindow()], { bootWorkspace: 0 })), false)
  assert.equal(validateSetupEntry(aSetup([aWindow()], { bootWorkspace: 11 })), false)
  assert.equal(validateSetupEntry(aSetup([aWindow()], { bootWorkspace: "3" })), false)
})

test("validateSetupEntry accepts a boot monitor name or none, rejects anything else", () => {
  assert.equal(validateSetupEntry(aSetup([aWindow()], { bootWorkspace: 3, bootMonitor: "DP-5" })), true)
  assert.equal(validateSetupEntry(aSetup([aWindow()], { bootWorkspace: 3, bootMonitor: null })), true)
  assert.equal(validateSetupEntry(aSetup([aWindow()], { bootWorkspace: 3 })), true, "a file from before per-monitor workspaces")
  assert.equal(validateSetupEntry(aSetup([aWindow()], { bootWorkspace: 3, bootMonitor: 5 })), false)
  assert.equal(validateSetupEntry(aSetup([aWindow()], { bootWorkspace: 3, bootMonitor: ["DP-5"] })), false)
})

test("validateSetupFile reads back exactly the valid setups", () => {
  const file = aSetupFile({ Work: aSetup([aWindow()]), Games: aSetup([aWindow({ class: "steam" })]) })
  assert.deepEqual(Object.keys(validateSetupFile(file)).sort(), ["Games", "Work"])
})

test("validateSetupFile drops one broken entry without losing the rest", () => {
  const file = aSetupFile({ Work: aSetup([aWindow()]), Broken: aSetup([]) })
  const result = validateSetupFile(file)
  assert.deepEqual(Object.keys(result), ["Work"])
})

test("validateSetupFile rejects a corrupt file rather than throwing", () => {
  assert.deepEqual(validateSetupFile("{not json"), {})
  assert.deepEqual(validateSetupFile("[]"), {})
  assert.deepEqual(validateSetupFile("null"), {})
  assert.deepEqual(validateSetupFile(""), {})
  assert.deepEqual(validateSetupFile(undefined), {})
})

test("validateSetupFile rejects an unknown schemaVersion", () => {
  const file = JSON.stringify({ schemaVersion: SETUP_SCHEMA_VERSION + 1, setups: { Work: aSetup([aWindow()]) } })
  assert.deepEqual(validateSetupFile(file), {})
  assert.deepEqual(validateSetupFile(JSON.stringify({ setups: {} })), {})
})

test("planSetupOpen closes nothing to add, and exactly what is there to replace", () => {
  const windows = [{ address: "a" }, { address: "b" }]
  assert.deepEqual(planSetupOpen(windows, "add"), [])
  assert.deepEqual(planSetupOpen(windows, "replace"), ["a", "b"])
})

test("planSetupOpen behaves the same in both modes on an empty workspace", () => {
  assert.deepEqual(planSetupOpen([], "add"), [])
  assert.deepEqual(planSetupOpen([], "replace"), [])
  assert.deepEqual(planSetupOpen(null, "replace"), [])
})

test("remainingCloseTargets keeps only the addresses still actually open", () => {
  assert.deepEqual(remainingCloseTargets(["a", "b"], ["a", "c"]), ["a"])
  assert.deepEqual(remainingCloseTargets(["a", "b"], ["c", "d"]), [])
  assert.deepEqual(remainingCloseTargets(["a", "b"], ["a", "b"]), ["a", "b"])
})

test("remainingCloseTargets copes with nothing pending or nothing open", () => {
  assert.deepEqual(remainingCloseTargets([], ["a"]), [])
  assert.deepEqual(remainingCloseTargets(["a"], []), [])
  assert.deepEqual(remainingCloseTargets(null, null), [])
})

test("assignBootWorkspace sets a setup's boot workspace", () => {
  const setups = { Work: { windows: [], bootWorkspace: null }, Games: { windows: [] } }
  const next = assignBootWorkspace(setups, "Work", 3)
  assert.equal(next.Work.bootWorkspace, 3)
  assert.equal(next.Work.bootMonitor, null, "no monitor given: the one with focus at boot")
  assert.equal(next.Games.bootWorkspace, undefined)
})

test("assignBootWorkspace remembers which monitor the slot is on", () => {
  const setups = { Work: { windows: [], bootWorkspace: null } }
  const next = assignBootWorkspace(setups, "Work", 3, "DP-5")
  assert.equal(next.Work.bootWorkspace, 3)
  assert.equal(next.Work.bootMonitor, "DP-5")
})

test("assignBootWorkspace clears whoever else already had that workspace on that monitor", () => {
  const setups = { Work: { windows: [], bootWorkspace: 3 }, Games: { windows: [], bootWorkspace: null } }
  const next = assignBootWorkspace(setups, "Games", 3)
  assert.equal(next.Games.bootWorkspace, 3)
  assert.equal(next.Work.bootWorkspace, null)

  const named = { Work: { windows: [], bootWorkspace: 3, bootMonitor: "DP-5" }, Games: { windows: [] } }
  const taken = assignBootWorkspace(named, "Games", 3, "DP-5")
  assert.equal(taken.Games.bootMonitor, "DP-5")
  assert.equal(taken.Work.bootWorkspace, null)
  assert.equal(taken.Work.bootMonitor, null)
})

test("assignBootWorkspace leaves the same slot on another named monitor alone", () => {
  const setups = {
    Work: { windows: [], bootWorkspace: 3, bootMonitor: "DP-5" },
    Chat: { windows: [], bootWorkspace: 3, bootMonitor: "DP-6" },
    Games: { windows: [] }
  }
  const next = assignBootWorkspace(setups, "Games", 3, "DP-4")
  assert.equal(next.Games.bootMonitor, "DP-4")
  assert.equal(next.Work.bootWorkspace, 3)
  assert.equal(next.Work.bootMonitor, "DP-5")
  assert.equal(next.Chat.bootWorkspace, 3)
})

// "No monitor" is the one with focus at boot, which could be any of them.
test("assignBootWorkspace treats a setup with no monitor as competing for the slot on every monitor", () => {
  const legacy = { Old: { windows: [], bootWorkspace: 3 }, Games: { windows: [] } }
  const named = assignBootWorkspace(legacy, "Games", 3, "DP-4")
  assert.equal(named.Games.bootWorkspace, 3)
  assert.equal(named.Old.bootWorkspace, null)

  const other = { Work: { windows: [], bootWorkspace: 3, bootMonitor: "DP-5" }, Games: { windows: [] } }
  const unnamed = assignBootWorkspace(other, "Games", 3)
  assert.equal(unnamed.Games.bootWorkspace, 3)
  assert.equal(unnamed.Work.bootWorkspace, null)
})

test("assignBootWorkspace clears with 0 or an out-of-range workspace", () => {
  const setups = { Work: { windows: [], bootWorkspace: 3, bootMonitor: "DP-5" } }
  assert.equal(assignBootWorkspace(setups, "Work", 0, "DP-5").Work.bootWorkspace, null)
  assert.equal(assignBootWorkspace(setups, "Work", 11, "DP-5").Work.bootWorkspace, null)
  assert.equal(assignBootWorkspace(setups, "Work", null, "DP-5").Work.bootWorkspace, null)
  assert.equal(assignBootWorkspace(setups, "Work", 0, "DP-5").Work.bootMonitor, null, "no monitor kept for a setup that does not boot")
})

test("assignBootWorkspace leaves every other field of the changed entries alone", () => {
  const setups = { Work: { windows: [{ recipe: { type: "argv", argv: ["x"] } }], bootWorkspace: null } }
  const next = assignBootWorkspace(setups, "Work", 5, "DP-5")
  assert.deepEqual(next.Work.windows, setups.Work.windows)
})

test("assignBootWorkspace copes with an unknown setup name and an empty store", () => {
  assert.deepEqual(assignBootWorkspace({}, "Ghost", 3), {})
  assert.deepEqual(assignBootWorkspace(null, "Ghost", 3), {})
  assert.deepEqual(assignBootWorkspace({ Work: null }, "Ghost", 3), { Work: {} })
})

test("shouldRunBoot runs once per signature, never with no signature at all", () => {
  assert.equal(shouldRunBoot("", "sig-a"), true)
  assert.equal(shouldRunBoot("sig-b", "sig-a"), true)
  assert.equal(shouldRunBoot("sig-a", "sig-a"), false)
  assert.equal(shouldRunBoot("", ""), false)
  assert.equal(shouldRunBoot("sig-a", ""), false)
  assert.equal(shouldRunBoot(null, "sig-a"), true)
})

test("bootEntries picks the setups with a valid boot workspace, lowest first", () => {
  const setups = {
    Games: { windows: [], bootWorkspace: 5 },
    Work: { windows: [], bootWorkspace: 1 },
    Scratch: { windows: [], bootWorkspace: null },
    Chat: { windows: [] }
  }
  assert.deepEqual(bootEntries(setups), [
    { name: "Work", slot: 1, monitor: "" },
    { name: "Games", slot: 5, monitor: "" }
  ])
})

test("bootEntries carries each setup's monitor, unnamed first and then by name", () => {
  const setups = {
    A: { windows: [], bootWorkspace: 2, bootMonitor: "DP-5" },
    B: { windows: [], bootWorkspace: 4, bootMonitor: "DP-4" },
    C: { windows: [], bootWorkspace: 1, bootMonitor: "DP-5" },
    D: { windows: [], bootWorkspace: 9 },
    E: { windows: [], bootWorkspace: 3, bootMonitor: null }
  }
  assert.deepEqual(bootEntries(setups), [
    { name: "E", slot: 3, monitor: "" },
    { name: "D", slot: 9, monitor: "" },
    { name: "B", slot: 4, monitor: "DP-4" },
    { name: "C", slot: 1, monitor: "DP-5" },
    { name: "A", slot: 2, monitor: "DP-5" }
  ])
})

test("bootEntries lets two monitors each boot a setup onto the same slot", () => {
  const setups = {
    Left: { windows: [], bootWorkspace: 1, bootMonitor: "DP-4" },
    Right: { windows: [], bootWorkspace: 1, bootMonitor: "DP-5" }
  }
  assert.deepEqual(bootEntries(setups), [
    { name: "Left", slot: 1, monitor: "DP-4" },
    { name: "Right", slot: 1, monitor: "DP-5" }
  ])
})

test("bootEntries ignores an out-of-range or non-numeric boot workspace", () => {
  const setups = {
    A: { windows: [], bootWorkspace: 0 },
    B: { windows: [], bootWorkspace: 11 },
    C: { windows: [], bootWorkspace: "3" }
  }
  assert.deepEqual(bootEntries(setups), [])
})

test("bootEntries treats a monitor that is not a name as none", () => {
  const setups = { A: { windows: [], bootWorkspace: 2, bootMonitor: 7 } }
  assert.deepEqual(bootEntries(setups), [{ name: "A", slot: 2, monitor: "" }])
})

test("bootEntries resolves a hand-edited duplicate workspace alphabetically", () => {
  const setups = {
    Zeta: { windows: [], bootWorkspace: 2 },
    Alpha: { windows: [], bootWorkspace: 2 }
  }
  assert.deepEqual(bootEntries(setups), [{ name: "Alpha", slot: 2, monitor: "" }])
})

test("bootEntries copes with nothing to open", () => {
  assert.deepEqual(bootEntries({}), [])
  assert.deepEqual(bootEntries(null), [])
})

test("relativeRect scales a window's rect into 0..1 of its workspace area", () => {
  assert.deepEqual(relativeRect({ x: 0, y: 0, width: 960, height: 1080 }, { x: 0, y: 0, width: 1920, height: 1080 }), {
    x: 0,
    y: 0,
    width: 0.5,
    height: 1
  })
  assert.deepEqual(relativeRect({ x: 960, y: 540, width: 960, height: 540 }, { x: 0, y: 0, width: 1920, height: 1080 }), {
    x: 0.5,
    y: 0.5,
    width: 0.5,
    height: 0.5
  })
})

test("relativeRect measures against the workspace's own monitor origin", () => {
  assert.deepEqual(relativeRect({ x: 2020, y: 100, width: 960, height: 1080 }, { x: 1920, y: 0, width: 1920, height: 1080 }), {
    x: 100 / 1920,
    y: 100 / 1080,
    width: 0.5,
    height: 1
  })
})

test("relativeRect clamps a window that hangs off its workspace", () => {
  assert.deepEqual(relativeRect({ x: -200, y: 0, width: 960, height: 2000 }, { x: 0, y: 0, width: 1920, height: 1080 }), {
    x: 0,
    y: 0,
    width: 0.5,
    height: 1
  })
})

test("relativeRect falls back to the whole workspace rather than dividing by zero", () => {
  assert.deepEqual(relativeRect({ x: 0, y: 0, width: 100, height: 100 }, { width: 0, height: 0 }), {
    x: 0,
    y: 0,
    width: 1,
    height: 1
  })
  assert.deepEqual(relativeRect({}, null), { x: 0, y: 0, width: 1, height: 1 })
})

test("captureSetupWindows prefers a desktop entry over a raw argv", () => {
  const windows = captureSetupWindows([anItem({ argv: ["firefox", "--new-window"] })])
  assert.deepEqual(windows[0].recipe, { type: "desktop-entry", id: "firefox.desktop" })
})

test("captureSetupWindows falls back to argv when there is no desktop entry match", () => {
  const windows = captureSetupWindows([anItem({ desktopEntryId: "", argv: ["some-tool", "--flag"] })])
  assert.deepEqual(windows[0].recipe, { type: "argv", argv: ["some-tool", "--flag"] })
})

test("captureSetupWindows leaves out a window with neither a desktop entry nor an argv", () => {
  const windows = captureSetupWindows([anItem({ desktopEntryId: "", argv: null }), anItem()])
  assert.equal(windows.length, 1)
  assert.equal(windows[0].class, "firefox")
})

test("captureSetupWindows carries class, floating, fullscreen and the relative rect", () => {
  const windows = captureSetupWindows([
    anItem({
      class: "code",
      floating: true,
      fullscreen: true,
      rect: { x: 960, y: 0, width: 960, height: 1080 },
      area: { x: 0, y: 0, width: 1920, height: 1080 }
    })
  ])
  assert.deepEqual(windows[0], {
    recipe: { type: "desktop-entry", id: "firefox.desktop" },
    class: "code",
    floating: true,
    fullscreen: true,
    rect: { x: 0.5, y: 0, width: 0.5, height: 1 }
  })
})

test("captureSetupWindows copes with nothing to capture", () => {
  assert.deepEqual(captureSetupWindows([]), [])
  assert.deepEqual(captureSetupWindows(null), [])
})

test("parseProcCmdline splits on the NUL separator and drops the trailing one", () => {
  const NUL = String.fromCharCode(0)
  assert.deepEqual(parseProcCmdline(["code", "--new-window", "/tmp"].join(NUL) + NUL), ["code", "--new-window", "/tmp"])
  assert.deepEqual(parseProcCmdline("firefox" + NUL), ["firefox"])
})

test("parseProcCmdline copes with a read that found nothing", () => {
  assert.deepEqual(parseProcCmdline(""), [])
  assert.deepEqual(parseProcCmdline(null), [])
  assert.deepEqual(parseProcCmdline(undefined), [])
})
