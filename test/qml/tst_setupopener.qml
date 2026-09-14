import QtQuick
import QtTest
import Quickshell
import Quickshell.Hyprland
import "helpers"
import "../../qml" as Plugin

// Opening a saved setup: the sequencing (launch, wait, preselect the next
// one) is tested here headless; the actual dispatch/launch calls only need
// to be the right strings, not real - see test/e2e for the live side.
TestCase {
  id: testCase
  name: "SetupOpener"
  when: windowShown

  property int windowCounter: 0

  Component {
    id: openerComponent
    Plugin.SetupOpener {
      timeoutMs: 300
      settleMs: 1
    }
  }

  Component {
    id: toplevelComponent
    HyprlandToplevel {}
  }

  SignalSpy {
    id: finishedSpy
    signalName: "finished"
  }

  function init() {
    Hyprland.testReset()
    DesktopEntries.testReset()
    Quickshell.testReset()
    finishedSpy.clear()
  }

  function makeOpener() {
    var opener = createTemporaryObject(openerComponent, testCase)
    finishedSpy.target = opener
    return opener
  }

  // A toplevel that isn't attached to any workspace fixture - all this
  // needs is an address, since that's all a launched-window step reads off
  // it.
  function insertToplevel(address) {
    var toplevel = createTemporaryObject(toplevelComponent, testCase, {
      address: address
    })
    Hyprland.toplevels.testInsert(toplevel)
    return toplevel
  }

  function desktopRecipe(id) {
    return {
      type: "desktop-entry",
      id: id
    }
  }

  function argvRecipe(argv) {
    return {
      type: "argv",
      argv: argv
    }
  }

  function tiledWindow(recipe, x, y, width, height) {
    return {
      recipe: recipe,
      floating: false,
      rect: {
        x: x,
        y: y,
        width: width,
        height: height
      }
    }
  }

  function floatingWindow(recipe, x, y, width, height) {
    return {
      recipe: recipe,
      floating: true,
      rect: {
        x: x,
        y: y,
        width: width,
        height: height
      }
    }
  }

  // ---- launching ------------------------------------------------------------

  function test_launchesAnArgvRecipeThroughExecDetached() {
    var opener = makeOpener()
    opener.open({
      windows: [tiledWindow(argvRecipe(["some-tool", "--flag"]), 0, 0, 1, 1)]
    }, {
      width: 1920,
      height: 1080
    })

    compare(Quickshell.testExecuted, [["some-tool", "--flag"]])
  }

  // logic.js's `captureSetupWindows` always stores the desktop entry's own
  // `id` field as the recipe, and `DesktopEntries.byId` looks entries up by
  // that same id - not by window class - so a recipe naming an id the
  // installed-app list still has resolves straight through.
  function test_desktopEntryRecipeResolvesByItsSavedId() {
    var calls = []
    DesktopEntries.testSetEntries({
      "firefox.desktop": {
        id: "firefox.desktop",
        execute: function () {
          calls.push("ran")
        }
      }
    })
    var opener = makeOpener()
    opener.open({
      windows: [tiledWindow(desktopRecipe("firefox.desktop"), 0, 0, 1, 1)]
    }, {
      width: 1920,
      height: 1080
    })
    compare(calls, ["ran"])
  }

  // An app that was uninstalled since the setup was saved has no entry to
  // execute - skip it rather than crash, same as any other step that never
  // produces a window.
  function test_aMissingDesktopEntryLaunchesNothingButStillTimesOutCleanly() {
    var opener = makeOpener()
    opener.open({
      windows: [tiledWindow(desktopRecipe("gone.desktop"), 0, 0, 1, 1)]
    }, {
      width: 1920,
      height: 1080
    })
    compare(Quickshell.testExecuted, [])
    tryCompare(finishedSpy, "count", 1)
    compare(finishedSpy.signalArguments[0][0], false)
  }

  // ---- sequencing -------------------------------------------------------------

  function test_aSingleWindowFinishesOnceItAppears() {
    DesktopEntries.testSetEntries({
      a: {
        id: "a",
        execute: function () {}
      }
    })
    var opener = makeOpener()
    opener.open({
      windows: [tiledWindow(desktopRecipe("a"), 0, 0, 1, 1)]
    }, {
      width: 1920,
      height: 1080
    })

    verify(opener.running)
    insertToplevel("1")

    // `finished` only fires after the settle pause past the last window -
    // see `settleMs` on SetupOpener.
    tryCompare(finishedSpy, "count", 1)
    compare(finishedSpy.signalArguments[0][0], true)
    verify(!opener.running)
  }

  // The second window can't be launched before the first one is actually
  // open - preselect only ever splits whatever is currently focused.
  function test_focusesAndPreselectsBeforeTheSecondWindow() {
    DesktopEntries.testSetEntries({
      a: {
        id: "a",
        execute: function () {}
      },
      b: {
        id: "b",
        execute: function () {}
      }
    })
    var opener = makeOpener()
    opener.open({
      windows: [tiledWindow(desktopRecipe("a"), 0, 0, 0.5, 1), tiledWindow(desktopRecipe("b"), 0.5, 0, 0.5, 1)]
    }, {
      width: 1920,
      height: 1080
    })

    compare(Hyprland.testDispatched, [])
    insertToplevel("1")

    // The focus/preselect for the second window only fire after the settle
    // pause past the first one - see `settleMs` on SetupOpener.
    tryCompare(Hyprland, "testDispatched", ["hl.dsp.focus({ window = \"address:0x1\" })", "hl.dsp.layout(\"preselect r\")"])

    insertToplevel("2")
    tryCompare(finishedSpy, "count", 1)
    compare(finishedSpy.signalArguments[0][0], true)
  }

  function test_preselectsDownForAStackedSplit() {
    DesktopEntries.testSetEntries({
      a: {
        id: "a",
        execute: function () {}
      },
      b: {
        id: "b",
        execute: function () {}
      }
    })
    var opener = makeOpener()
    opener.open({
      windows: [tiledWindow(desktopRecipe("a"), 0, 0, 1, 0.5), tiledWindow(desktopRecipe("b"), 0, 0.5, 1, 0.5)]
    }, {
      width: 1920,
      height: 1080
    })

    insertToplevel("1")
    tryCompare(Hyprland, "testDispatched", ["hl.dsp.focus({ window = \"address:0x1\" })", "hl.dsp.layout(\"preselect d\")"])
  }

  function test_floatingWindowsOpenAfterTheTiledOnes() {
    DesktopEntries.testSetEntries({
      a: {
        id: "a",
        execute: function () {}
      },
      b: {
        id: "b",
        execute: function () {}
      }
    })
    var opener = makeOpener()
    opener.open({
      windows: [floatingWindow(desktopRecipe("b"), 0.25, 0.25, 0.5, 0.5), tiledWindow(desktopRecipe("a"), 0, 0, 1, 1)]
    }, {
      width: 1920,
      height: 1080
    })

    // Tiled window ("a", index 1) is opened first regardless of save order.
    insertToplevel("1")
    verify(opener.running)
    insertToplevel("2")
    tryCompare(finishedSpy, "count", 1)
  }

  function test_anEmptySetupFinishesImmediately() {
    var opener = makeOpener()
    opener.open({
      windows: []
    }, {
      width: 1920,
      height: 1080
    })
    compare(finishedSpy.count, 1)
    compare(finishedSpy.signalArguments[0][0], true)
    compare(Hyprland.testDispatched, [])
    compare(Quickshell.testExecuted, [])
  }

  function test_doesNotStartASecondPlanWhileOneIsRunning() {
    var calls = []
    DesktopEntries.testSetEntries({
      a: {
        id: "a",
        execute: function () {
          calls.push("a")
        }
      }
    })
    var opener = makeOpener()
    opener.open({
      windows: [tiledWindow(desktopRecipe("a"), 0, 0, 1, 1)]
    }, {
      width: 1920,
      height: 1080
    })
    opener.open({
      windows: [tiledWindow(desktopRecipe("a"), 0, 0, 1, 1)]
    }, {
      width: 1920,
      height: 1080
    })

    compare(calls.length, 1)
  }

  // ---- timeout ------------------------------------------------------------

  function test_aStepThatNeverAppearsIsSkippedAfterTheTimeout() {
    DesktopEntries.testSetEntries({
      a: {
        id: "a",
        execute: function () {}
      },
      b: {
        id: "b",
        execute: function () {}
      }
    })
    var opener = makeOpener()
    opener.open({
      windows: [tiledWindow(desktopRecipe("a"), 0, 0, 0.5, 1), tiledWindow(desktopRecipe("b"), 0.5, 0, 0.5, 1)]
    }, {
      width: 1920,
      height: 1080
    })

    // "a" never appears - wait past the (300ms, for the test) timeout
    // rather than inserting a toplevel for it.
    tryVerify(function () {
      return finishedSpy.count === 1
    }, 2000)
    compare(finishedSpy.signalArguments[0][0], false)
  }
}
