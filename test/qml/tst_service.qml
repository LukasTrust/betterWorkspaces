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

  Component {
    id: workspaceComponent
    HyprlandWorkspace {}
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

  function makeNamedMonitor(name, x) {
    return createTemporaryObject(monitorComponent, testCase, {
      name: name,
      x: x,
      width: 1920,
      height: 1080
    })
  }

  // What Hyprland writes to $XDG_STATE_HOME/omarchy/monitor-workspaces.
  function seedBlocks(service, text) {
    findChild(service, "monitorBlocksFile").testSetContent(text)
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

  // ---- one block of workspaces per monitor ------------------------------------
  //
  // A boot workspace is a slot 1-10 of a monitor's block of ten (1-10 on the
  // first monitor, 11-20 on the second, ...), so which Hyprland workspace to
  // focus depends on the monitor the setup was assigned to.

  function test_focusesTheSlotInTheBlockOfTheMonitorTheSetupWasAssignedTo() {
    Hyprland.monitors.values = [makeNamedMonitor("DP-1", 0), makeNamedMonitor("DP-2", 1920)]
    var service = makeService()
    seedBlocks(service, "0\tDP-1\tMaker one\n1\tDP-2\tMaker two\n")
    var work = anArgvSetup(["work-app"], 3)
    work.bootMonitor = "DP-2"
    seedSetups(service, {
      Work: work
    })

    tryCompare(Hyprland, "testDispatched", ["o.workspaces.focus(3, \"DP-2\")"])
    compare(Quickshell.testExecuted, [["work-app"]])
  }

  function test_eachMonitorsSetupGoesToItsOwnBlock() {
    Hyprland.monitors.values = [makeNamedMonitor("DP-1", 0), makeNamedMonitor("DP-2", 1920)]
    var service = makeService()
    seedBlocks(service, "0\tDP-1\tMaker one\n1\tDP-2\tMaker two\n")
    var left = anArgvSetup(["left-app"], 1)
    left.bootMonitor = "DP-1"
    var right = anArgvSetup(["right-app"], 1)
    right.bootMonitor = "DP-2"
    seedSetups(service, {
      Left: left,
      Right: right
    })

    tryCompare(Hyprland, "testDispatched", ["o.workspaces.focus(1, \"DP-1\")"])
    insertToplevel("1")
    tryCompare(Hyprland, "testDispatched", ["o.workspaces.focus(1, \"DP-1\")", "o.workspaces.focus(1, \"DP-2\")"])
  }

  function test_aSetupWithNoMonitorGoesToTheFocusedMonitor() {
    var first = makeNamedMonitor("DP-1", 0)
    var second = makeNamedMonitor("DP-2", 1920)
    Hyprland.monitors.values = [first, second]
    Hyprland.focusedMonitor = second
    var service = makeService()
    seedBlocks(service, "0\tDP-1\tMaker one\n1\tDP-2\tMaker two\n")
    seedSetups(service, {
      Work: anArgvSetup(["work-app"], 2)
    })

    tryCompare(Hyprland, "testDispatched", ["o.workspaces.focus(2, \"DP-2\")"])
  }

  // The connector in a saved setup goes stale when the monitor moves to
  // another port; the identity in the state file does not.
  function test_aBootMonitorGivenByIdentityFindsItsMonitorOnAnotherConnector() {
    var first = makeNamedMonitor("DP-1", 0)
    var second = makeNamedMonitor("DP-7", 1920)
    Hyprland.monitors.values = [first, second]
    Hyprland.focusedMonitor = first
    var service = makeService()
    seedBlocks(service, "0\tDP-1\tMaker one\n1\tDP-7\tMaker two\n")
    var work = anArgvSetup(["work-app"], 3)
    work.bootMonitor = "Maker two"
    seedSetups(service, {
      Work: work
    })

    tryCompare(Hyprland, "testDispatched", ["o.workspaces.focus(3, \"DP-7\")"])
    compare(service.monitorFor({ monitor: "Maker two", slot: 3 }), second)
    compare(service.monitorFor({ monitor: "DP-1", slot: 3 }), first)
  }

  // On an Omarchy without the state file `o.workspaces` does not exist, so
  // boot focuses by id as it always did.
  function test_withoutTheStateFileBootFocusesByIdNotByOWorkspaces() {
    var monitor = makeNamedMonitor("DP-1", 0)
    Hyprland.monitors.values = [monitor]
    Hyprland.focusedMonitor = monitor
    var service = makeService()
    var work = anArgvSetup(["work-app"], 4)
    work.bootMonitor = "DP-1"
    seedSetups(service, {
      Work: work
    })

    tryCompare(Hyprland, "testDispatched", ["hl.dsp.focus({ workspace = \"4\" })"])
  }

  function test_aMonitorThatIsNotPluggedInFallsBackToTheFocusedOne() {
    var first = makeNamedMonitor("DP-1", 0)
    Hyprland.monitors.values = [first]
    Hyprland.focusedMonitor = first
    var service = makeService()
    seedBlocks(service, "0\tDP-1\tMaker one\n1\tDP-2\tMaker two\n")
    var work = anArgvSetup(["work-app"], 3)
    work.bootMonitor = "DP-2"
    seedSetups(service, {
      Work: work
    })

    tryCompare(Hyprland, "testDispatched", ["o.workspaces.focus(3, \"DP-1\")"])
    compare(service.monitorFor({ monitor: "DP-2", slot: 3 }), first)
  }

  // Before the state file exists the block of the monitor's own active
  // workspace is the best there is.
  function test_withoutTheStateFileItUsesTheBlockOfTheMonitorsActiveWorkspace() {
    var monitor = makeNamedMonitor("DP-2", 0)
    monitor.activeWorkspace = createTemporaryObject(workspaceComponent, testCase, {
      id: 24,
      name: "24"
    })
    Hyprland.monitors.values = [monitor]
    Hyprland.focusedMonitor = monitor
    var service = makeService()
    seedSetups(service, {
      Work: anArgvSetup(["work-app"], 2)
    })

    tryCompare(Hyprland, "testDispatched", ["hl.dsp.focus({ workspace = \"22\" })"])
  }

  function test_withNoMonitorAtAllItIsBlockZero() {
    var service = makeService()
    compare(service.workspaceIdFor({ monitor: "", slot: 7 }, null), 7)
    compare(service.monitorFor({ monitor: "", slot: 7 }), null)
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
