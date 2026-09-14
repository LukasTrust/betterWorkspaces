import QtQuick
import QtTest
import Quickshell
import Quickshell.Hyprland
import "helpers"
import "../../qml" as Plugin

// The boot service: opens whichever saved setups are assigned a boot
// workspace, once per Hyprland session. No real filesystem or process here -
// the FileView/Process stand-ins record what they were asked to do, and
// `Quickshell.testExecuted` records what actually launched.
TestCase {
  id: testCase
  name: "Service"
  width: 200
  height: 200
  visible: true
  when: windowShown

  Component {
    id: serviceComponent
    // A tiny settleMs so the debounce timer fires fast in tests; the real
    // default (1000ms) is only about surviving a slow multi-monitor boot.
    Plugin.Service {
      settleMs: 10
      runtimeDir: "/tmp/better-workspaces-test"
      signature: "sig-a"
    }
  }

  Component {
    id: monitorComponent
    HyprlandMonitor {}
  }

  Component {
    id: toplevelComponent
    HyprlandToplevel {}
  }

  function init() {
    Hyprland.testReset()
    Quickshell.testReset()
  }

  function makeMonitor() {
    return createTemporaryObject(monitorComponent, testCase, {
      id: 0,
      name: "DP-1",
      x: 0,
      y: 0,
      width: 1920,
      height: 1080
    })
  }

  function makeService(extraProps) {
    return createTemporaryObject(serviceComponent, testCase, extraProps || {})
  }

  function seedSetups(service, setups) {
    findChild(service, "setupsFile").testSetContent(JSON.stringify({
      schemaVersion: 1,
      setups: setups
    }))
  }

  function anArgvSetup(argv, bootWorkspace) {
    return {
      windows: [
        {
          recipe: {
            type: "argv",
            argv: argv
          },
          class: "x",
          floating: false,
          fullscreen: false,
          rect: {
            x: 0,
            y: 0,
            width: 1,
            height: 1
          }
        }
      ],
      bootWorkspace: bootWorkspace
    }
  }

  function guardOf(service) {
    return findChild(service, "guardFile")
  }

  // A toplevel that isn't attached to any workspace fixture - all the
  // opener reads off it is an address.
  function insertToplevel(address) {
    var toplevel = createTemporaryObject(toplevelComponent, testCase, {
      address: address
    })
    Hyprland.toplevels.testInsert(toplevel)
    return toplevel
  }

  // ---- whether it runs at all ------------------------------------------------

  function test_neverBootsWithoutASignature() {
    var service = makeService({
      signature: ""
    })
    seedSetups(service, {
      Work: anArgvSetup(["work-app"], 1)
    })

    wait(50)
    compare(Quickshell.testExecuted, [])
    compare(guardOf(service).testWrites, [])
  }

  function test_firstBootWritesTheGuardAndOpensTheAssignedSetup() {
    var service = makeService()
    seedSetups(service, {
      Work: anArgvSetup(["work-app"], 1)
    })

    tryCompare(Quickshell, "testExecuted", [["work-app"]])
    tryCompare(guardOf(service), "testWrites", ["sig-a"])
  }

  // A launched process lands on whichever workspace is focused when it
  // maps, not wherever it was launched "for" - found live (test/e2e/run.sh):
  // without this, every boot setup opened wherever Hyprland already
  // happened to be focused instead of its own assigned workspace.
  function test_focusesTheAssignedWorkspaceBeforeOpeningEachSetup() {
    var service = makeService()
    seedSetups(service, {
      Work: anArgvSetup(["work-app"], 3)
    })

    tryCompare(Hyprland, "testDispatched", ["hl.dsp.focus({ workspace = \"3\" })"])
    compare(Quickshell.testExecuted, [["work-app"]])
  }

  function test_focusesEachSetupsOwnWorkspaceInTurn() {
    var service = makeService()
    seedSetups(service, {
      Games: anArgvSetup(["games-app"], 5),
      Work: anArgvSetup(["work-app"], 1)
    })

    tryCompare(Hyprland, "testDispatched", ["hl.dsp.focus({ workspace = \"1\" })"])
    insertToplevel("1")
    tryCompare(Hyprland, "testDispatched", ["hl.dsp.focus({ workspace = \"1\" })", "hl.dsp.focus({ workspace = \"5\" })"])
  }

  // `omarchy restart shell` recreates the service, but the real guard file
  // on disk already holds this session's signature. The stand-in FileView
  // has no real filesystem behind it - a fresh service in these tests always
  // starts with an empty guard, the same way a fresh `FileView` object would
  // if `setups.json` didn't already carry state through it either - so this
  // exercises the same check on one running service instead: call `runBoot`
  // again once the guard from the first run is on record, same as the
  // service would if something else re-triggered it mid-session.
  function test_runningBootAgainWithTheSameGuardDoesNothing() {
    var service = makeService()
    seedSetups(service, {
      Work: anArgvSetup(["work-app"], 1)
    })

    tryCompare(Quickshell, "testExecuted", [["work-app"]])
    // Let the opener actually finish before asking it to open anything else.
    insertToplevel("1")
    tryCompare(findChild(service, "setupOpener"), "running", false)

    service.runBoot()
    wait(50)
    compare(Quickshell.testExecuted, [["work-app"]])
  }

  // A fresh login gets a fresh HYPRLAND_INSTANCE_SIGNATURE, so last
  // session's guard content doesn't suppress this one.
  function test_aDifferentSignatureBootsAgain() {
    var service = makeService()
    seedSetups(service, {
      Work: anArgvSetup(["work-app"], 1)
    })

    tryCompare(Quickshell, "testExecuted", [["work-app"]])
    insertToplevel("1")
    tryCompare(findChild(service, "setupOpener"), "running", false)

    service.signature = "sig-new"
    service.runBoot()

    tryCompare(Quickshell, "testExecuted", [["work-app"], ["work-app"]])
  }

  // ---- ordering ---------------------------------------------------------------

  function test_opensEverySetupLowestWorkspaceFirst() {
    var service = makeService()
    seedSetups(service, {
      Games: anArgvSetup(["games-app"], 5),
      Work: anArgvSetup(["work-app"], 1)
    })

    // Work (workspace 1) launches first...
    tryCompare(Quickshell, "testExecuted", [["work-app"]])
    // ...and Games only once Work's own window has appeared and the opener
    // has moved on - the two setups share one SetupOpener, one at a time.
    insertToplevel("1")
    tryCompare(Quickshell, "testExecuted", [["work-app"], ["games-app"]])
  }

  function test_ignoresSetupsWithNoBootWorkspaceAssigned() {
    var service = makeService()
    seedSetups(service, {
      Work: anArgvSetup(["work-app"], null)
    })

    wait(50)
    compare(Quickshell.testExecuted, [])
    // The guard still gets written - the check happened, there was just
    // nothing to open.
    tryCompare(guardOf(service), "testWrites", ["sig-a"])
  }

  // ---- waiting for monitor geometry to settle ---------------------------------

  // A monitor appearing mid-debounce restarts the wait rather than letting a
  // boot start against a layout that's still being discovered.
  function test_aMonitorAppearingRestartsTheWait() {
    var service = makeService()
    seedSetups(service, {
      Work: anArgvSetup(["work-app"], 1)
    })

    Hyprland.monitors.testInsert(makeMonitor())
    // Nothing has run yet - a Timer never fires synchronously off the
    // signal that restarts it.
    compare(Quickshell.testExecuted, [])
    verify(findChild(service, "settleTimer").running)

    tryCompare(Quickshell, "testExecuted", [["work-app"]])
  }
}
