import QtQuick
import QtTest
import Quickshell
import Quickshell.Hyprland
import Quickshell.Wayland
import qs.Commons
import "helpers"
import "../../qml" as Plugin

// Baseline behaviour of the bar widget as it ships today. Runs against the
// stand-in modules in stubs/, see run.sh.
TestCase {
  id: testCase
  name: "Workspaces"
  width: 800
  height: 40
  // TestCase is invisible by default; the widget has to be really visible
  // for visibility checks and mouse clicks to mean anything.
  visible: true
  when: windowShown

  property int windowCounter: 0

  FakeShell {
    id: fakeShell
  }

  FakeBar {
    id: fakeBar
    shell: fakeShell
  }

  Component {
    id: widgetComponent
    Plugin.Workspaces {}
  }

  Component {
    id: workspaceComponent
    HyprlandWorkspace {}
  }

  Component {
    id: toplevelComponent
    HyprlandToplevel {}
  }

  Component {
    id: monitorComponent
    HyprlandMonitor {}
  }

  Component {
    id: waylandComponent
    Toplevel {}
  }

  function init() {
    QsWindow.testReset()
    Hyprland.testReset()
    DesktopEntries.testReset()
    Quickshell.testReset()
    fakeBar.testReset()
    fakeShell.testReset()
  }

  // ---- fixtures -----------------------------------------------------------

  function makeWindow(windowClass, title) {
    windowCounter++
    var wayland = createTemporaryObject(waylandComponent, testCase, {
      appId: windowClass,
      title: title || windowClass
    })
    return createTemporaryObject(toplevelComponent, testCase, {
      // No "0x" - that is how Quickshell reports an address, and the
      // dispatch has to put it back for Hyprland to match anything.
      address: windowCounter.toString(16),
      title: title || windowClass,
      wayland: wayland,
      lastIpcObject: {
        "class": windowClass,
        "initialClass": windowClass
      }
    })
  }

  function makeWorkspace(id, windows) {
    var list = windows || []
    var workspace = createTemporaryObject(workspaceComponent, testCase, {
      id: id,
      name: String(id)
    })
    workspace.toplevels.values = list
    for (var i = 0; i < list.length; i++)
      list[i].workspace = workspace
    return workspace
  }

  // A monitor on Hyprland's side. `active` is the workspace it is showing;
  // the focused one also becomes Hyprland's focused workspace, the way it is
  // for real.
  function makeMonitor(name, active, focused) {
    var monitor = createTemporaryObject(monitorComponent, testCase, {
      name: name,
      activeWorkspace: active || null,
      focused: !!focused
    })
    if (focused) {
      Hyprland.focusedMonitor = monitor
      Hyprland.focusedWorkspace = active || null
    }
    return monitor
  }

  // Puts a workspace on a monitor, the way Hyprland reports it.
  function onMonitor(workspace, monitor) {
    workspace.monitor = monitor
    return workspace
  }

  // Which bar the widget under test is: the screen of the window it sits in.
  function barOnScreen(name) {
    QsWindow.window = {
      screen: {
        name: name
      }
    }
  }

  // What Hyprland writes to $XDG_STATE_HOME/omarchy/monitor-workspaces.
  function blocksFile(widget) {
    return findChild(widget, "monitorBlocksFile")
  }

  function stateLine(block, connector) {
    return block + "\t" + connector + "\tMaker " + connector + " serial\n"
  }

  function withThemeIcons(extra) {
    var icons = {
      "application-x-executable": "image://test/application-x-executable"
    }
    for (var name in extra)
      icons[name] = extra[name]
    return icons
  }

  function createWidget(settings) {
    var widget = createTemporaryObject(widgetComponent, testCase, {
      bar: fakeBar,
      settings: settings || {}
    })
    verify(widget !== null, "widget should be created")
    return widget
  }

  function shownIds(widget) {
    var repeater = findChild(widget, "workspaceRepeater")
    var ids = []
    for (var i = 0; i < repeater.count; i++)
      ids.push(repeater.itemAt(i).modelData)
    return ids
  }

  function cellFor(widget, id) {
    var repeater = findChild(widget, "workspaceRepeater")
    for (var i = 0; i < repeater.count; i++) {
      if (repeater.itemAt(i).modelData === id)
        return repeater.itemAt(i)
    }
    return null
  }

  function iconRepeater(widget, id) {
    return findChild(cellFor(widget, id), "iconRepeater")
  }

  function iconSlot(widget, id, index) {
    return iconRepeater(widget, id).itemAt(index)
  }

  // What focusing one window looks like on the wire. Hyprland's own focus
  // dispatcher, not the wlr activate request: measured on a live Hyprland,
  // `wayland.activate()` marks the window active but leaves the focused
  // workspace where it was, so an icon for a window on another workspace did
  // nothing visible.
  function focusRequest(window) {
    return "hyprctl dispatch 'hl.dsp.focus({ window = \"address:0x" + window.address + "\" })'"
  }

  // ---- workspace list ---------------------------------------------------

  function test_showsWorkspacesOneToFiveByDefault() {
    var widget = createWidget()
    compare(shownIds(widget), [1, 2, 3, 4, 5])
  }

  // ---- how many workspaces are shown ------------------------------------

  function test_showsAsManyEmptyWorkspacesAsMinWorkspaces_data() {
    return [
      {
        tag: "none",
        minWorkspaces: 0,
        expected: [7]
      },
      {
        tag: "one",
        minWorkspaces: 1,
        expected: [1, 7]
      },
      {
        tag: "all ten",
        minWorkspaces: 10,
        expected: [1, 2, 3, 4, 5, 6, 7, 8, 9, 10]
      },
      {
        tag: "unusable",
        minWorkspaces: "abc",
        expected: [1, 2, 3, 4, 5, 7]
      }
    ]
  }

  function test_showsAsManyEmptyWorkspacesAsMinWorkspaces(data) {
    Hyprland.workspaces.values = [makeWorkspace(7, [makeWindow("foot")])]
    var widget = createWidget({
      minWorkspaces: data.minWorkspaces
    })
    compare(shownIds(widget), data.expected)
    compare(findChild(widget, "workspaceRepeater").count, data.expected.length)
  }

  function test_followsAnEditedMinWorkspaces() {
    var widget = createWidget({
      minWorkspaces: 2
    })
    compare(shownIds(widget), [1, 2])

    widget.settings = {
      minWorkspaces: 4
    }
    compare(shownIds(widget), [1, 2, 3, 4])
  }

  function test_hideEmptyShowsOnlyWorkspacesWithWindows() {
    Hyprland.workspaces.values = [makeWorkspace(2), makeWorkspace(4, [makeWindow("foot")])]
    var widget = createWidget({
      hideEmpty: true,
      minWorkspaces: 10
    })
    compare(shownIds(widget), [4])
  }

  function test_hideEmptyKeepsTheWorkspaceYouAreOn() {
    var empty = makeWorkspace(2)
    Hyprland.workspaces.values = [empty, makeWorkspace(4, [makeWindow("foot")])]
    Hyprland.focusedWorkspace = empty
    var widget = createWidget({
      hideEmpty: true
    })
    compare(shownIds(widget), [2, 4])
  }

  function test_hideEmptyFollowsWindowsOpeningAndClosing() {
    var workspace = makeWorkspace(3)
    Hyprland.workspaces.values = [workspace]
    var widget = createWidget({
      hideEmpty: true
    })
    compare(shownIds(widget), [])

    workspace.toplevels.values = [makeWindow("foot")]
    compare(shownIds(widget), [3])

    workspace.toplevels.values = []
    compare(shownIds(widget), [])
  }

  // The cells are rebuilt whenever the list of ids changes, which with
  // hideEmpty on would otherwise happen on every window that opens.
  function test_keepsItsCellsWhenTheWorkspacesAreUnchanged() {
    var workspace = makeWorkspace(3, [makeWindow("foot")])
    Hyprland.workspaces.values = [workspace]
    var widget = createWidget({
      hideEmpty: true
    })

    var cell = cellFor(widget, 3)
    workspace.toplevels.values = workspace.toplevels.values.concat([makeWindow("firefox")])
    compare(shownIds(widget), [3])
    compare(cellFor(widget, 3), cell)
    compare(iconRepeater(widget, 3).count, 2)
  }

  function test_showsNoWorkspacesAtAllWithoutBreakingTheLayout() {
    var widget = createWidget({
      minWorkspaces: 0
    })
    compare(shownIds(widget), [])
    compare(findChild(widget, "workspaceGrid").columns, 1)
  }

  function test_showsOccupiedWorkspacesAboveFive() {
    Hyprland.workspaces.values = [makeWorkspace(7, [makeWindow("foot")]), makeWorkspace(2)]
    var widget = createWidget()
    compare(shownIds(widget), [1, 2, 3, 4, 5, 7])
  }

  function test_followsWorkspacesAppearingLater() {
    var widget = createWidget()
    Hyprland.workspaces.values = [makeWorkspace(9)]
    compare(shownIds(widget), [1, 2, 3, 4, 5, 9])
  }

  function test_labelsWorkspaceTenAsZero() {
    Hyprland.workspaces.values = [makeWorkspace(10)]
    var widget = createWidget()
    compare(findChild(cellFor(widget, 10), "workspaceLabel").text, "0")
    compare(findChild(cellFor(widget, 3), "workspaceLabel").text, "3")
  }

  function test_labelsWorkspacesFromTheLabelList() {
    Hyprland.workspaces.values = [makeWorkspace(10)]
    var widget = createWidget({
      workspaceLabels: "a, 1,$"
    })
    compare(findChild(cellFor(widget, 1), "workspaceLabel").text, "a")
    compare(findChild(cellFor(widget, 2), "workspaceLabel").text, "1")
    compare(findChild(cellFor(widget, 3), "workspaceLabel").text, "$")
    compare(findChild(cellFor(widget, 4), "workspaceLabel").text, "4")
    compare(findChild(cellFor(widget, 10), "workspaceLabel").text, "0")
    compare(stateOf(widget).workspaces[0].label, "a")
  }

  function test_clearedLabelsGoBackToNumbers() {
    for (var value of ["", "   ", ", ,", null]) {
      var widget = createWidget({
        workspaceLabels: value
      })
      compare(findChild(cellFor(widget, 1), "workspaceLabel").text, "1", JSON.stringify(value))
      compare(findChild(cellFor(widget, 4), "workspaceLabel").text, "4", JSON.stringify(value))
    }
  }

  function test_highlightsFocusedWorkspace() {
    var focusedWorkspace = makeWorkspace(3)
    Hyprland.workspaces.values = [focusedWorkspace]
    Hyprland.focusedWorkspace = focusedWorkspace
    var widget = createWidget()

    var focused = findChild(cellFor(widget, 3), "workspaceLabel")
    var other = findChild(cellFor(widget, 2), "workspaceLabel")
    verify(focused.font.bold)
    verify(Qt.colorEqual(focused.color, Color.bar.active))
    verify(!other.font.bold)
    verify(Qt.colorEqual(other.color, fakeBar.barForeground))
  }

  function test_dimsEmptyUnfocusedWorkspaces() {
    Hyprland.workspaces.values = [makeWorkspace(1, [makeWindow("foot")])]
    var widget = createWidget()
    tryCompare(cellFor(widget, 1), "opacity", 1)
    tryCompare(cellFor(widget, 2), "opacity", 0.5)
  }

  function test_clickingAWorkspaceFocusesIt() {
    makeMonitor("DP-1", null, true)
    var widget = createWidget()
    blocksFile(widget).testSetContent(stateLine(0, "DP-1"))
    mouseClick(cellFor(widget, 3))
    compare(fakeBar.testCommands, ["hyprctl dispatch 'o.workspaces.focus(3, \"DP-1\")'"])
  }

  // Clicking the workspace you are already on has nothing to switch to, so
  // it opens the overview instead - the one entry point that needs no setup.
  function test_clickingTheWorkspaceYouAreOnOpensTheOverview() {
    var focusedWorkspace = makeWorkspace(3)
    Hyprland.workspaces.values = [focusedWorkspace]
    makeMonitor("DP-1", focusedWorkspace, true)
    var widget = createWidget()

    mouseClick(cellFor(widget, 3))
    compare(fakeShell.testToggled, [
      {
        id: "better-workspaces",
        payload: "{}"
      }
    ])
    compare(fakeBar.testCommands, [])
  }

  function test_overviewEnabledOffLeavesTheClickAsAPlainSwitch() {
    var focusedWorkspace = makeWorkspace(3)
    Hyprland.workspaces.values = [focusedWorkspace]
    makeMonitor("DP-1", focusedWorkspace, true)
    var widget = createWidget({
      overviewEnabled: false
    })
    blocksFile(widget).testSetContent(stateLine(0, "DP-1"))

    mouseClick(cellFor(widget, 3))
    compare(fakeShell.testToggled, [])
    compare(fakeBar.testCommands, ["hyprctl dispatch 'o.workspaces.focus(3, \"DP-1\")'"])
  }

  // Omarchy before 4.5 has no state file and no `o.workspaces`, so focusing
  // has to stay a plain workspace focus by id.
  function test_withoutTheStateFileClickingFocusesByIdNotByOWorkspaces() {
    makeMonitor("DP-1", null, true)
    var widget = createWidget()
    mouseClick(cellFor(widget, 3))
    compare(fakeBar.testCommands, ["hyprctl dispatch 'hl.dsp.focus({ workspace = \"3\" })'"])
  }

  // Only the workspace you are on; every other one still just switches.
  function test_clickingAnotherWorkspaceNeverOpensTheOverview() {
    var focusedWorkspace = makeWorkspace(3)
    Hyprland.workspaces.values = [focusedWorkspace]
    makeMonitor("DP-1", focusedWorkspace, true)
    var widget = createWidget()
    blocksFile(widget).testSetContent(stateLine(0, "DP-1"))

    mouseClick(cellFor(widget, 1))
    compare(fakeShell.testToggled, [])
    compare(fakeBar.testCommands, ["hyprctl dispatch 'o.workspaces.focus(1, \"DP-1\")'"])
  }

  function test_clickingTheWorkspaceYouAreOnWithoutAShellDoesNothingRash() {
    var focusedWorkspace = makeWorkspace(3)
    Hyprland.workspaces.values = [focusedWorkspace]
    Hyprland.focusedWorkspace = focusedWorkspace
    fakeBar.shell = null
    var widget = createWidget()

    mouseClick(cellFor(widget, 3))
    compare(fakeBar.testCommands, [])
    fakeBar.shell = fakeShell
  }

  function test_clickingTheLabelStillFocusesTheWorkspace() {
    Hyprland.workspaces.values = [makeWorkspace(3, [makeWindow("foot")])]
    makeMonitor("DP-1", null, true)
    var widget = createWidget()
    blocksFile(widget).testSetContent(stateLine(0, "DP-1"))
    mouseClick(findChild(cellFor(widget, 3), "workspaceLabel"))
    compare(fakeBar.testCommands, ["hyprctl dispatch 'o.workspaces.focus(3, \"DP-1\")'"])
  }

  // ---- one block of workspaces per monitor ----------------------------------
  //
  // Omarchy 4.5: monitor block 0 is workspaces 1-10, block 1 is 11-20, and so
  // on. Each bar shows its own monitor's block, numbered 1-10 again.

  // Clicks the number itself: the cell's middle can be a window icon, which
  // has an action of its own. The cells are laid out on the next polish, and
  // the strip was rebuilt just before.
  function clickLabel(widget, id) {
    wait(20)
    mouseClick(findChild(cellFor(widget, id), "workspaceLabel"))
  }

  function test_showsTheBlockTheStateFileGivesItsMonitor() {
    var first = makeMonitor("DP-1", null, true)
    var second = makeMonitor("DP-2", null, false)
    Hyprland.monitors.values = [first, second]
    barOnScreen("DP-2")
    var widget = createWidget()
    blocksFile(widget).testSetContent(stateLine(0, "DP-1") + stateLine(2, "DP-2"))

    tryCompare(widget, "block", 2)
    compare(shownIds(widget), [21, 22, 23, 24, 25])
  }

  function test_numbersTheMonitorsWorkspacesFromOne() {
    var second = makeMonitor("DP-2", null, true)
    Hyprland.monitors.values = [second]
    var widget = createWidget({
      minWorkspaces: 10
    })
    blocksFile(widget).testSetContent(stateLine(1, "DP-2"))

    tryCompare(widget, "block", 1)
    compare(shownIds(widget), [11, 12, 13, 14, 15, 16, 17, 18, 19, 20])
    compare(findChild(cellFor(widget, 11), "workspaceLabel").text, "1")
    compare(findChild(cellFor(widget, 15), "workspaceLabel").text, "5")
    compare(findChild(cellFor(widget, 20), "workspaceLabel").text, "0")
  }

  function test_theWorkspaceLabelsListNamesEveryMonitorsWorkspacesBySlot() {
    var second = makeMonitor("DP-2", null, true)
    Hyprland.monitors.values = [second]
    var widget = createWidget({
      workspaceLabels: "a, b, c"
    })
    blocksFile(widget).testSetContent(stateLine(1, "DP-2"))

    tryCompare(widget, "block", 1)
    compare(findChild(cellFor(widget, 11), "workspaceLabel").text, "a")
    compare(findChild(cellFor(widget, 13), "workspaceLabel").text, "c")
    compare(findChild(cellFor(widget, 14), "workspaceLabel").text, "4")
  }

  function test_followsTheStateFileWhenItChanges() {
    var first = makeMonitor("DP-1", null, true)
    Hyprland.monitors.values = [first]
    var widget = createWidget()
    blocksFile(widget).testSetContent(stateLine(0, "DP-1"))
    tryCompare(widget, "block", 0)
    compare(shownIds(widget), [1, 2, 3, 4, 5])

    blocksFile(widget).testSetContent(stateLine(3, "DP-1"))
    tryCompare(widget, "block", 3)
    compare(shownIds(widget), [31, 32, 33, 34, 35])

    // A file that goes missing leaves the monitor's own active workspace to say.
    blocksFile(widget).testSetMissing()
    tryCompare(widget, "block", 0)
    compare(shownIds(widget), [1, 2, 3, 4, 5])
  }

  // Before Hyprland has written the file, the monitor's block is the one its
  // active workspace is in.
  function test_beforeTheStateFileExistsItUsesTheBlockOfTheActiveWorkspace() {
    var active = makeWorkspace(23)
    Hyprland.workspaces.values = [active]
    var first = makeMonitor("DP-1", active, true)
    Hyprland.monitors.values = [first]
    var widget = createWidget()

    compare(widget.block, 2)
    compare(shownIds(widget), [21, 22, 23, 24, 25])
  }

  function test_aMonitorTheFileDoesNotListFallsBackToItsActiveWorkspace() {
    var active = makeWorkspace(12)
    Hyprland.workspaces.values = [active]
    var second = makeMonitor("DP-2", active, true)
    Hyprland.monitors.values = [second]
    var widget = createWidget()
    blocksFile(widget).testSetContent(stateLine(0, "DP-1"))

    wait(10)
    compare(widget.block, 1)
    compare(shownIds(widget), [11, 12, 13, 14, 15])
  }

  function test_withNoMonitorAtAllItShowsBlockZero() {
    var widget = createWidget()
    compare(widget.monitorName, "")
    compare(widget.block, 0)
    compare(shownIds(widget), [1, 2, 3, 4, 5])
  }

  function test_readsTheStateFileFromTheStateHome() {
    Quickshell.testEnv = {
      XDG_STATE_HOME: "/state"
    }
    var widget = createWidget()
    compare(blocksFile(widget).path, "/state/omarchy/monitor-workspaces")
    Quickshell.testEnv = {
      HOME: "/home/me"
    }
    var other = createWidget()
    compare(blocksFile(other).path, "/home/me/.local/state/omarchy/monitor-workspaces")
  }

  // The bar sits in a window on one screen, so it is that screen's monitor it
  // shows, not whichever one has focus.
  function test_showsTheMonitorOfItsOwnWindowNotTheFocusedOne() {
    var first = makeMonitor("DP-1", null, true)
    var second = makeMonitor("DP-2", null, false)
    Hyprland.monitors.values = [first, second]
    barOnScreen("DP-2")
    var widget = createWidget()
    blocksFile(widget).testSetContent(stateLine(0, "DP-1") + stateLine(1, "DP-2"))

    tryCompare(widget, "monitorName", "DP-2")
    tryCompare(widget, "block", 1)
    compare(shownIds(widget), [11, 12, 13, 14, 15])
  }

  function test_aBarWithNoWindowYetShowsTheFocusedMonitor() {
    var first = makeMonitor("DP-1", null, false)
    var second = makeMonitor("DP-2", null, true)
    Hyprland.monitors.values = [first, second]
    var widget = createWidget()

    compare(widget.monitorName, "DP-2")
  }

  function test_aBarWhoseWindowHasNoScreenYetShowsTheFocusedMonitor() {
    makeMonitor("DP-1", null, true)
    QsWindow.window = {
      screen: null
    }
    var widget = createWidget()

    compare(widget.monitorName, "DP-1")
  }

  function test_eachBarHighlightsTheWorkspaceItsOwnMonitorShows() {
    var firstActive = makeWorkspace(3)
    var secondActive = makeWorkspace(12)
    Hyprland.workspaces.values = [firstActive, secondActive]
    var first = makeMonitor("DP-1", firstActive, true)
    var second = makeMonitor("DP-2", secondActive, false)
    Hyprland.monitors.values = [first, second]
    barOnScreen("DP-2")
    var widget = createWidget()
    blocksFile(widget).testSetContent(stateLine(0, "DP-1") + stateLine(1, "DP-2"))

    tryCompare(widget, "block", 1)
    verify(cellFor(widget, 12).focused)
    verify(!cellFor(widget, 11).focused)
    verify(findChild(cellFor(widget, 12), "workspaceLabel").font.bold)
    tryCompare(cellFor(widget, 12), "opacity", 1)
  }

  function test_theHighlightFollowsTheMonitorsActiveWorkspace() {
    var one = makeWorkspace(11)
    var two = makeWorkspace(12)
    Hyprland.workspaces.values = [one, two]
    var second = makeMonitor("DP-2", one, true)
    Hyprland.monitors.values = [second]
    var widget = createWidget()
    blocksFile(widget).testSetContent(stateLine(1, "DP-2"))
    tryCompare(widget, "block", 1)
    verify(cellFor(widget, 11).focused)

    second.activeWorkspace = two
    tryCompare(cellFor(widget, 12), "focused", true)
    verify(!cellFor(widget, 11).focused)
  }

  function test_aMonitorsActiveWorkspaceIsShownEvenWhenEmptyAndHidden() {
    var active = makeWorkspace(18)
    Hyprland.workspaces.values = [active, makeWorkspace(14, [makeWindow("foot")])]
    var second = makeMonitor("DP-2", active, true)
    Hyprland.monitors.values = [second]
    var widget = createWidget({
      hideEmpty: true
    })
    blocksFile(widget).testSetContent(stateLine(1, "DP-2"))

    tryCompare(widget, "block", 1)
    compare(shownIds(widget), [14, 18])
  }

  function test_listsOnlyTheMonitorsOwnWorkspacesWithWindows() {
    var first = makeMonitor("DP-1", null, true)
    var second = makeMonitor("DP-2", null, false)
    Hyprland.monitors.values = [first, second]
    Hyprland.workspaces.values = [onMonitor(makeWorkspace(2, [makeWindow("foot")]), first), onMonitor(makeWorkspace(18, [makeWindow("foot")]), second), onMonitor(makeWorkspace(27, [makeWindow("foot")]), second)]
    barOnScreen("DP-2")
    var widget = createWidget()
    blocksFile(widget).testSetContent(stateLine(0, "DP-1") + stateLine(1, "DP-2"))

    tryCompare(widget, "block", 1)
    // 2 belongs to the other monitor; 27 is a visitor on this one.
    compare(shownIds(widget), [11, 12, 13, 14, 15, 18, 27])
  }

  // What is left of an unplugged monitor's workspaces lands on a monitor
  // that is still there, after that monitor's own.
  function test_visitingWorkspacesComeAfterTheMonitorsOwn() {
    var first = makeMonitor("DP-1", null, true)
    Hyprland.monitors.values = [first]
    Hyprland.workspaces.values = [onMonitor(makeWorkspace(21, [makeWindow("foot")]), first), onMonitor(makeWorkspace(13, [makeWindow("foot")]), first), onMonitor(makeWorkspace(2, [makeWindow("foot")]), first)]
    var widget = createWidget()
    blocksFile(widget).testSetContent(stateLine(0, "DP-1"))

    tryCompare(widget, "block", 0)
    compare(shownIds(widget), [1, 2, 3, 4, 5, 13, 21])
    // Labelled by slot, like everything else.
    compare(findChild(cellFor(widget, 13), "workspaceLabel").text, "3")
    compare(findChild(cellFor(widget, 21), "workspaceLabel").text, "1")
  }

  function test_aVisitorThatHasGoneIsDroppedFromTheStrip() {
    var first = makeMonitor("DP-1", null, true)
    Hyprland.monitors.values = [first]
    var visitor = onMonitor(makeWorkspace(21, [makeWindow("foot")]), first)
    Hyprland.workspaces.values = [visitor]
    var widget = createWidget()
    blocksFile(widget).testSetContent(stateLine(0, "DP-1"))
    tryCompare(widget, "block", 0)
    compare(shownIds(widget), [1, 2, 3, 4, 5, 21])

    Hyprland.workspaces.values = []
    tryCompare(widget, "workspaceIds", [1, 2, 3, 4, 5])
  }

  function test_clickingAnOwnWorkspaceFocusesItBySlotOnThisMonitor() {
    var second = makeMonitor("DP-2", null, false)
    Hyprland.monitors.values = [second]
    barOnScreen("DP-2")
    var widget = createWidget()
    blocksFile(widget).testSetContent(stateLine(1, "DP-2"))
    tryCompare(widget, "block", 1)

    clickLabel(widget, 13)
    compare(fakeBar.testCommands, ["hyprctl dispatch 'o.workspaces.focus(3, \"DP-2\")'"])
  }

  function test_clickingAVisitingWorkspaceFocusesItByItsHyprlandId() {
    var first = makeMonitor("DP-1", null, true)
    Hyprland.monitors.values = [first]
    Hyprland.workspaces.values = [onMonitor(makeWorkspace(21, [makeWindow("foot")]), first)]
    var widget = createWidget()
    blocksFile(widget).testSetContent(stateLine(0, "DP-1"))
    tryCompare(widget, "block", 0)

    clickLabel(widget, 21)
    compare(fakeBar.testCommands, ["hyprctl dispatch 'hl.dsp.focus({ workspace = \"21\" })'"])
  }

  function test_clickingTheShownWorkspaceOfTheFocusedMonitorOpensTheOverview() {
    var active = makeWorkspace(12)
    Hyprland.workspaces.values = [active]
    var second = makeMonitor("DP-2", active, true)
    Hyprland.monitors.values = [second]
    barOnScreen("DP-2")
    var widget = createWidget()
    blocksFile(widget).testSetContent(stateLine(1, "DP-2"))
    tryCompare(widget, "block", 1)

    clickLabel(widget, 12)
    compare(fakeShell.testToggled, [
      {
        id: "better-workspaces",
        payload: "{}"
      }
    ])
    compare(fakeBar.testCommands, [])
  }

  // The overview opens on the focused monitor, so a click on the shown
  // workspace of another monitor brings focus there instead; the next click
  // opens it.
  function test_clickingTheShownWorkspaceOfAnotherMonitorFocusesItFirst() {
    var firstActive = makeWorkspace(3)
    var secondActive = makeWorkspace(12)
    Hyprland.workspaces.values = [firstActive, secondActive]
    var first = makeMonitor("DP-1", firstActive, true)
    var second = makeMonitor("DP-2", secondActive, false)
    Hyprland.monitors.values = [first, second]
    barOnScreen("DP-2")
    var widget = createWidget()
    blocksFile(widget).testSetContent(stateLine(0, "DP-1") + stateLine(1, "DP-2"))
    tryCompare(widget, "block", 1)

    clickLabel(widget, 12)
    compare(fakeShell.testToggled, [])
    compare(fakeBar.testCommands, ["hyprctl dispatch 'o.workspaces.focus(2, \"DP-2\")'"])
  }

  function test_theWorkspaceOnAnotherMonitorIsNotAlreadyThere() {
    var firstActive = makeWorkspace(3)
    var secondActive = makeWorkspace(12)
    Hyprland.workspaces.values = [firstActive, secondActive]
    var first = makeMonitor("DP-1", firstActive, true)
    var second = makeMonitor("DP-2", secondActive, false)
    Hyprland.monitors.values = [first, second]
    barOnScreen("DP-2")
    var widget = createWidget()
    blocksFile(widget).testSetContent(stateLine(0, "DP-1") + stateLine(1, "DP-2"))
    tryCompare(widget, "block", 1)

    // Workspace 13 is not what this monitor shows, so it is a plain switch,
    // overview or not.
    clickLabel(widget, 13)
    compare(fakeShell.testToggled, [])
    compare(fakeBar.testCommands, ["hyprctl dispatch 'o.workspaces.focus(3, \"DP-2\")'"])
  }

  function test_stateReportsTheMonitorBlockAndSlots() {
    var active = makeWorkspace(12)
    Hyprland.workspaces.values = [active]
    var second = makeMonitor("DP-2", active, true)
    Hyprland.monitors.values = [second]
    var widget = createWidget()
    blocksFile(widget).testSetContent(stateLine(1, "DP-2"))
    tryCompare(widget, "block", 1)

    var state = stateOf(widget)
    compare(state.monitor, "DP-2")
    compare(state.block, 1)
    compare(state.workspaces.map(workspace => workspace.id), [11, 12, 13, 14, 15])
    compare(state.workspaces.map(workspace => workspace.slot), [1, 2, 3, 4, 5])
    compare(state.workspaces.map(workspace => workspace.label), ["1", "2", "3", "4", "5"])
    compare(state.workspaces.map(workspace => workspace.focused), [false, true, false, false, false])
  }

  // ---- hovering and clicking an icon --------------------------------------

  function test_hoveringAnIconShowsItsTitleAndLeavingHidesIt() {
    Hyprland.workspaces.values = [makeWorkspace(1, [makeWindow("foot", "My Terminal")])]
    var widget = createWidget()
    var slot = iconSlot(widget, 1, 0)

    mouseMove(slot, slot.width / 2, slot.height / 2)
    compare(fakeBar.testTooltipLog, [
      {
        action: "show",
        target: slot,
        text: "My Terminal"
      }
    ])

    mouseMove(widget, -10, -10)
    compare(fakeBar.testTooltipLog[1], {
      action: "hide",
      target: slot,
      text: ""
    })
  }

  function test_titleChangeUpdatesTheOpenTooltip() {
    var window = makeWindow("foot", "First Title")
    Hyprland.workspaces.values = [makeWorkspace(1, [window])]
    var widget = createWidget()
    var slot = iconSlot(widget, 1, 0)

    mouseMove(slot, slot.width / 2, slot.height / 2)
    window.title = "Second Title"

    var lastEntry = fakeBar.testTooltipLog[fakeBar.testTooltipLog.length - 1]
    compare(lastEntry, {
      action: "show",
      target: slot,
      text: "Second Title"
    })
  }

  function test_titleChangeWhileNotHoveredDoesNotShowATooltip() {
    var window = makeWindow("foot", "First Title")
    Hyprland.workspaces.values = [makeWorkspace(1, [window])]
    var widget = createWidget()

    window.title = "Second Title"
    compare(fakeBar.testTooltipLog, [])
  }

  function test_leftClickingAnIconActivatesExactlyThatWindow() {
    var windows = [makeWindow("foot"), makeWindow("firefox")]
    Hyprland.workspaces.values = [makeWorkspace(1, windows)]
    var widget = createWidget()

    mouseClick(iconSlot(widget, 1, 1))
    compare(fakeBar.testCommands, [focusRequest(windows[1])])
    compare(windows[1].wayland.testCloseCalls, 0)
    // The wlr request is not used for this: it wouldn't switch workspace.
    compare(windows[0].wayland.testActivateCalls, 0)
    compare(windows[1].wayland.testActivateCalls, 0)
  }

  // A toplevel Hyprland has given no address can't be named to the
  // dispatcher, so the wlr request is what is left.
  function test_leftClickFallsBackToTheWlrRequestWithoutAnAddress() {
    var window = makeWindow("foot")
    window.address = ""
    Hyprland.workspaces.values = [makeWorkspace(1, [window])]
    var widget = createWidget()

    mouseClick(iconSlot(widget, 1, 0))
    compare(window.wayland.testActivateCalls, 1)
    compare(fakeBar.testCommands, [])
  }

  function test_middleClickingAnIconClosesExactlyThatWindow() {
    var windows = [makeWindow("foot"), makeWindow("firefox")]
    Hyprland.workspaces.values = [makeWorkspace(1, windows)]
    var widget = createWidget()

    mouseClick(iconSlot(widget, 1, 0), iconSlot(widget, 1, 0).width / 2, iconSlot(widget, 1, 0).height / 2, Qt.MiddleButton)
    compare(windows[0].wayland.testCloseCalls, 1)
    compare(windows[1].wayland.testCloseCalls, 0)
    compare(windows[0].wayland.testActivateCalls, 0)
  }

  function test_clickingAnIconDoesNotAlsoFocusTheWorkspace() {
    var window = makeWindow("foot")
    Hyprland.workspaces.values = [makeWorkspace(1, [window])]
    var widget = createWidget()

    mouseClick(iconSlot(widget, 1, 0))
    // The window, and only the window - not the cell's own workspace focus
    // underneath it.
    compare(fakeBar.testCommands, [focusRequest(window)])
  }

  // ---- window icons -------------------------------------------------------

  function test_showsOneIconPerWindow() {
    Hyprland.workspaces.values = [makeWorkspace(1, [makeWindow("foot"), makeWindow("firefox")])]
    var widget = createWidget()
    compare(iconRepeater(widget, 1).count, 2)
    compare(iconRepeater(widget, 2).count, 0)
    verify(!findChild(cellFor(widget, 1), "overflowLabel").visible)
  }

  function test_capsIconsAtMaxIconsWithOverflowCount() {
    var windows = []
    for (var i = 0; i < 7; i++)
      windows.push(makeWindow("foot"))
    Hyprland.workspaces.values = [makeWorkspace(1, windows)]
    var widget = createWidget({
      maxIcons: 5
    })

    compare(iconRepeater(widget, 1).count, 5)
    var overflow = findChild(cellFor(widget, 1), "overflowLabel")
    verify(overflow.visible)
    compare(overflow.text, "+2")
  }

  function test_clampsMaxIconsToAtLeastOne() {
    Hyprland.workspaces.values = [makeWorkspace(1, [makeWindow("a"), makeWindow("b")])]
    var widget = createWidget({
      maxIcons: 0
    })
    compare(iconRepeater(widget, 1).count, 1)
    compare(findChild(cellFor(widget, 1), "overflowLabel").text, "+1")
  }

  function test_appliesIconSizeWithMinimum() {
    Hyprland.workspaces.values = [makeWorkspace(1, [makeWindow("foot")])]
    var widget = createWidget({
      iconSize: 20
    })
    compare(iconSlot(widget, 1, 0).width, 20)

    widget.settings = {
      iconSize: 2
    }
    compare(iconSlot(widget, 1, 0).width, 8)
  }

  function test_usesGlyphOverrideFromSettings() {
    Hyprland.workspaces.values = [makeWorkspace(1, [makeWindow("Firefox")])]
    var widget = createWidget({
      icons: {
        firefox: "🦊"
      }
    })

    var slot = iconSlot(widget, 1, 0)
    compare(slot.icon.kind, "text")
    compare(findChild(slot, "iconText").text, "🦊")
    verify(findChild(slot, "iconText").visible)
    verify(!findChild(slot, "iconImage").visible)
  }

  // A text override too wide for its icon slot would spill over the
  // neighbouring icons (issue #10): the default icon shows instead, and the
  // tooltip says why, with the full text.
  function test_tooWideTextOverrideShowsDefaultIconAndWarns() {
    Hyprland.workspaces.values = [makeWorkspace(1, [makeWindow("Firefox")])]
    var widget = createWidget({
      icons: {
        firefox: "gibts-nicht"
      }
    })

    var slot = iconSlot(widget, 1, 0)
    verify(slot.textTooWide)
    verify(!findChild(slot, "iconText").visible)
    verify(findChild(slot, "iconImage").visible)
    compare(findChild(slot, "iconImage").source, "image://test/application-x-executable")
    verify(slot.tooltipText.indexOf("\"gibts-nicht\" is too wide") !== -1)
  }

  function test_resolvesIconFromDesktopEntryId() {
    DesktopEntries.testSetEntries({
      firefox: {
        id: "firefox",
        icon: "firefox"
      }
    })
    Quickshell.testThemeIcons = withThemeIcons({
      firefox: "image://test/firefox"
    })
    Hyprland.workspaces.values = [makeWorkspace(1, [makeWindow("firefox")])]
    var widget = createWidget()

    var slot = iconSlot(widget, 1, 0)
    compare(slot.icon.kind, "image")
    compare(findChild(slot, "iconImage").source, "image://test/firefox")
    verify(findChild(slot, "iconImage").visible)
    verify(!findChild(slot, "iconText").visible)
  }

  // Issue #10: a desktop entry whose icon isn't in the theme used to show
  // its icon name as text, spilling over the neighbouring icons.
  function test_unresolvedDesktopEntryIconFallsBackToImageNotText() {
    DesktopEntries.testSetEntries({
      mpv: {
        id: "mpv",
        icon: "mpv"
      }
    })
    Hyprland.workspaces.values = [makeWorkspace(1, [makeWindow("mpv")])]
    var widget = createWidget()

    var slot = iconSlot(widget, 1, 0)
    compare(slot.icon.kind, "image")
    compare(findChild(slot, "iconImage").source, "image://test/application-x-executable")
    verify(!findChild(slot, "iconText").visible)
  }

  function test_fallsBackToHeuristicDesktopEntryMatch() {
    DesktopEntries.testSetEntries({
      "org.mozilla.firefox": {
        id: "org.mozilla.firefox",
        startupClass: "firefox",
        icon: "firefox"
      }
    })
    Quickshell.testThemeIcons = withThemeIcons({
      firefox: "image://test/firefox"
    })
    Hyprland.workspaces.values = [makeWorkspace(1, [makeWindow("firefox")])]
    var widget = createWidget()
    compare(iconSlot(widget, 1, 0).icon.source, "image://test/firefox")
  }

  function test_usesGenericIconForUnknownApps() {
    Hyprland.workspaces.values = [makeWorkspace(1, [makeWindow("mystery-app")])]
    var widget = createWidget()
    compare(iconSlot(widget, 1, 0).icon.source, "image://test/application-x-executable")
  }

  function test_usesWaylandAppIdWhenHyprlandReportsNoClass() {
    var window = makeWindow("")
    window.wayland.appId = "firefox"
    Hyprland.workspaces.values = [makeWorkspace(1, [window])]
    var widget = createWidget({
      icons: {
        firefox: "🦊"
      }
    })
    compare(iconSlot(widget, 1, 0).icon.value, "🦊")
  }

  function test_usesSteamIconForSteamGameWindows() {
    Quickshell.testThemeIcons = withThemeIcons({
      "steam_icon_570": "image://test/steam_icon_570"
    })
    Hyprland.workspaces.values = [makeWorkspace(1, [makeWindow("steam_app_570")])]
    var widget = createWidget()
    compare(iconSlot(widget, 1, 0).icon.source, "image://test/steam_icon_570")
  }

  function test_gameIconsOffSkipsSteamLookupEntirely() {
    Quickshell.testThemeIcons = withThemeIcons({
      "steam_icon_570": "image://test/steam_icon_570"
    })
    Hyprland.workspaces.values = [makeWorkspace(1, [makeWindow("steam_app_570")])]
    var widget = createWidget({
      gameIcons: false
    })
    // No desktop entry and no override for "steam_app_570" either, so with
    // the lookup skipped this is indistinguishable from any other unknown
    // app: the generic fallback icon, and no lookup for the Steam name at
    // all - not even one that fails to resolve.
    compare(iconSlot(widget, 1, 0).icon.source, "image://test/application-x-executable")
    verify(!("steam_icon_570" in Quickshell.testIconPathCalls))
  }

  function test_userOverrideBeatsSteamIcon() {
    Quickshell.testThemeIcons = withThemeIcons({
      "steam_icon_570": "image://test/steam_icon_570"
    })
    Hyprland.workspaces.values = [makeWorkspace(1, [makeWindow("steam_app_570")])]
    var widget = createWidget({
      icons: {
        "steam_app_570": "🎮"
      }
    })
    compare(iconSlot(widget, 1, 0).icon.value, "🎮")
    verify(!("steam_icon_570" in Quickshell.testIconPathCalls))
  }

  function test_resolvesSteamIconOnlyOncePerClass() {
    Quickshell.testThemeIcons = withThemeIcons({
      "steam_icon_570": "image://test/steam_icon_570"
    })
    Hyprland.workspaces.values = [makeWorkspace(1, [makeWindow("steam_app_570"), makeWindow("steam_app_570")]), makeWorkspace(2, [makeWindow("steam_app_570")])]
    createWidget()
    compare(Quickshell.testIconPathCalls["steam_icon_570"], 1)
  }

  // ---- web apps and launcher games ------------------------------------------

  function test_resolvesWebAppIconFromTheLauncherOpeningItsSite() {
    DesktopEntries.testSetEntries({
      "chromium": {
        id: "chromium",
        name: "Chromium",
        icon: "chromium",
        execString: "/usr/bin/chromium %U"
      },
      "HEY": {
        id: "HEY",
        name: "HEY",
        icon: "hey",
        execString: "omarchy-launch-webapp \"https://app.hey.com\""
      }
    })
    Quickshell.testThemeIcons = withThemeIcons({
      hey: "image://test/hey",
      chromium: "image://test/chromium"
    })
    Hyprland.workspaces.values = [makeWorkspace(1, [makeWindow("chrome-app.hey.com__-Default"), makeWindow("brave-app.hey.com__-Default")])]
    var widget = createWidget()
    compare(iconSlot(widget, 1, 0).icon.source, "image://test/hey")
    compare(iconSlot(widget, 1, 1).icon.source, "image://test/hey")
  }

  function makeProcessWindow(windowClass, pid) {
    var window = makeWindow(windowClass)
    window.lastIpcObject = {
      "class": windowClass,
      "initialClass": windowClass,
      "pid": pid
    }
    return window
  }

  function environ(vars) {
    return vars.join(String.fromCharCode(0)) + String.fromCharCode(0)
  }

  // The widget reads a window's environment the moment it first draws it, so
  // a test seeds the reader afterwards and drops the caches to re-resolve.
  function seedFiles(widget, files) {
    var reader = findChild(findChild(widget, "iconResolver"), "fileReader")
    verify(reader !== null, "icon resolver should have a file reader")
    for (var path in files)
      reader.testSetContent(files[path], path)
    findChild(widget, "iconResolver").clearCache()
  }

  // Live, a window opened after the shell started has no `lastIpcObject`
  // (so no pid) until Hyprland's clients are fetched again.
  function test_asksHyprlandOnceForTheClientsOfWindowsWithoutAPid() {
    Hyprland.workspaces.values = [makeWorkspace(1, [makeWindow("foot"), makeWindow("foot")])]
    var widget = createWidget()
    tryCompare(Hyprland, "testToplevelRefreshes", 1)
    wait(50)
    compare(Hyprland.testToplevelRefreshes, 1)

    var off = createWidget({
      gameIcons: false
    })
    wait(50)
    compare(Hyprland.testToplevelRefreshes, 1)
  }

  function test_resolvesHeroicGameIconFromItsLaunchEnvironment() {
    Quickshell.testEnv = {
      HOME: "/home/u"
    }
    Hyprland.workspaces.values = [makeWorkspace(1, [makeProcessWindow("steam_app_default", 4242), makeProcessWindow("steam_app_default", 4343)])]
    var widget = createWidget()
    seedFiles(widget, {
      "/proc/4242/environ": environ(["PATH=/usr/bin", "HEROIC_APP_NAME=CrabEA"]),
      "/home/u/.config/heroic/icons/CrabEA.jpg": "jpeg bytes",
      "/proc/4343/environ": environ(["PATH=/usr/bin"])
    })
    tryCompare(iconSlot(widget, 1, 0).icon, "source", "file:///home/u/.config/heroic/icons/CrabEA.jpg")
    // Same class, but no launcher environment: the ordinary lookup.
    compare(iconSlot(widget, 1, 1).icon.source, "image://test/application-x-executable")
  }

  function test_resolvesLutrisGameIconFromItsMenuShortcut() {
    DesktopEntries.testSetEntries({
      "net.lutris.hoi4-3": {
        id: "net.lutris.hoi4-3",
        name: "Hearts of Iron IV",
        icon: "lutris_hearts-of-iron-iv",
        execString: "env LUTRIS_SKIP_INIT=1 lutris lutris:rungameid/3"
      }
    })
    Quickshell.testThemeIcons = withThemeIcons({
      "lutris_hearts-of-iron-iv": "image://test/lutris_hoi4"
    })
    Hyprland.workspaces.values = [makeWorkspace(1, [makeProcessWindow("hoi4", 77)])]
    var widget = createWidget()
    seedFiles(widget, {
      "/proc/77/environ": environ(["GAME_NAME=Hearts of Iron IV", "STORE=steam"])
    })
    tryCompare(iconSlot(widget, 1, 0).icon, "source", "image://test/lutris_hoi4")
  }

  function test_launcherGameIconsRespectOverridesAndTheGameIconsSetting() {
    Quickshell.testThemeIcons = withThemeIcons({
      "steam_icon_892970": "image://test/valheim"
    })
    Hyprland.workspaces.values = [makeWorkspace(1, [makeProcessWindow("valheim.x86_64", 5)])]
    var files = {
      "/proc/5/environ": environ(["SteamAppId=892970"])
    }

    var plain = createWidget()
    seedFiles(plain, files)
    tryCompare(iconSlot(plain, 1, 0).icon, "source", "image://test/valheim")

    var overridden = createWidget({
      icons: {
        "valheim.x86_64": "🪓"
      }
    })
    seedFiles(overridden, files)
    compare(iconSlot(overridden, 1, 0).icon.value, "🪓")

    var off = createWidget({
      gameIcons: false
    })
    seedFiles(off, files)
    compare(iconSlot(off, 1, 0).icon.source, "image://test/application-x-executable")
  }

  function test_resolvesEachWindowClassOnlyOnce() {
    DesktopEntries.testSetEntries({
      foot: {
        id: "foot",
        icon: "foot"
      }
    })
    Hyprland.workspaces.values = [makeWorkspace(1, [makeWindow("foot"), makeWindow("foot")]), makeWorkspace(2, [makeWindow("foot")])]
    createWidget()
    compare(DesktopEntries.testStats.lookups, 1)
  }

  function test_refreshesIconsWhenInstalledAppsChange() {
    DesktopEntries.testSetEntries({
      foot: {
        id: "foot",
        icon: "foot"
      }
    })
    Quickshell.testThemeIcons = withThemeIcons({
      "foot": "image://test/foot",
      "foot-new": "image://test/foot-new"
    })
    Hyprland.workspaces.values = [makeWorkspace(1, [makeWindow("foot")])]
    var widget = createWidget()
    compare(iconSlot(widget, 1, 0).icon.source, "image://test/foot")

    DesktopEntries.testSetEntries({
      foot: {
        id: "foot",
        icon: "foot-new"
      }
    })
    tryVerify(function () {
      return iconSlot(widget, 1, 0).icon.source === "image://test/foot-new"
    })
  }

  function test_appliesEditedOverridesWithoutRestart() {
    Hyprland.workspaces.values = [makeWorkspace(1, [makeWindow("foot")])]
    var widget = createWidget()
    compare(iconSlot(widget, 1, 0).icon.kind, "image")

    widget.settings = {
      icons: {
        foot: "🦶"
      }
    }
    tryVerify(function () {
      return iconSlot(widget, 1, 0).icon.kind === "text"
    })
  }

  // ---- grouping apps (groupApps) ------------------------------------------

  function groupBadge(slot) {
    return findChild(slot, "groupBadge")
  }

  function groupBadgeText(slot) {
    return findChild(slot, "groupBadgeText")
  }

  function test_groupAppsShowsOneIconPerAppWithABadgeFromTwoWindowsOn() {
    Hyprland.workspaces.values = [makeWorkspace(1, [makeWindow("code"), makeWindow("code"), makeWindow("firefox")])]
    var widget = createWidget({
      groupApps: true
    })

    compare(iconRepeater(widget, 1).count, 2)

    var codeSlot = iconSlot(widget, 1, 0)
    var firefoxSlot = iconSlot(widget, 1, 1)
    compare(codeSlot.count, 2)
    compare(firefoxSlot.count, 1)
    verify(groupBadge(codeSlot).visible)
    verify(groupBadgeText(codeSlot).visible)
    compare(groupBadgeText(codeSlot).text, "2")
    verify(!groupBadge(firefoxSlot).visible)
    verify(!groupBadgeText(firefoxSlot).visible)
  }

  // A badge circle over the icon can't fit a readable digit without
  // shrinking it to nothing at the default 14px icon size. The count has to
  // sit beside the icon, not on top of it, a shade under the icon's own
  // size so it labels rather than competes with it.
  function test_groupBadgeCountIsReadableAndDoesNotShrinkTheIcon() {
    Hyprland.workspaces.values = [makeWorkspace(1, [makeWindow("code"), makeWindow("code")])]
    var widget = createWidget({
      groupApps: true,
      iconSize: 14
    })
    var slot = iconSlot(widget, 1, 0)

    compare(findChild(slot, "iconImage").width, 14)
    compare(findChild(slot, "iconImage").height, 14)
    compare(groupBadgeText(slot).font.pixelSize, 10)
  }

  // The chip has to be bigger than a plain icon slot - not the same size -
  // precisely so the icon and the count inside it aren't cramped against
  // its edge; a plain (single-window) icon next to it stays untouched.
  function test_groupChipIsBiggerThanAPlainIconNextToIt() {
    Hyprland.workspaces.values = [makeWorkspace(1, [makeWindow("code"), makeWindow("code"), makeWindow("firefox")])]
    var widget = createWidget({
      groupApps: true,
      iconSize: 14
    })

    var groupedSlot = iconSlot(widget, 1, 0)
    var plainSlot = iconSlot(widget, 1, 1)

    compare(plainSlot.height, 14)
    verify(groupedSlot.height > plainSlot.height, "grouped chip (" + groupedSlot.height + ") should be taller than a plain icon (" + plainSlot.height + ")")
    compare(findChild(groupedSlot, "iconImage").width, 14)
    compare(findChild(groupedSlot, "iconImage").height, 14)
  }

  function test_groupAppsOffKeepsOneIconPerWindowEvenForTheSameApp() {
    Hyprland.workspaces.values = [makeWorkspace(1, [makeWindow("code"), makeWindow("code")])]
    var widget = createWidget({
      groupApps: false
    })

    compare(iconRepeater(widget, 1).count, 2)
    compare(iconSlot(widget, 1, 0).count, 1)
    verify(!groupBadge(iconSlot(widget, 1, 0)).visible)
  }

  function test_groupBadgeUpdatesLiveAsWindowsOpenAndClose() {
    var workspace = makeWorkspace(1, [makeWindow("code")])
    Hyprland.workspaces.values = [workspace]
    var widget = createWidget({
      groupApps: true
    })

    compare(iconRepeater(widget, 1).count, 1)
    verify(!groupBadge(iconSlot(widget, 1, 0)).visible)

    var second = makeWindow("code")
    workspace.toplevels.values = workspace.toplevels.values.concat([second])
    compare(iconRepeater(widget, 1).count, 1)
    verify(groupBadge(iconSlot(widget, 1, 0)).visible)
    compare(groupBadgeText(iconSlot(widget, 1, 0)).text, "2")

    workspace.toplevels.values = [second]
    verify(!groupBadge(iconSlot(widget, 1, 0)).visible)
  }

  function test_maxIconsAndOverflowCountGroupsNotWindows() {
    var windows = []
    for (var i = 0; i < 3; i++)
      windows.push(makeWindow("code"))
    for (var j = 0; j < 2; j++)
      windows.push(makeWindow("firefox"))
    Hyprland.workspaces.values = [makeWorkspace(1, windows)]
    var widget = createWidget({
      groupApps: true,
      maxIcons: 1
    })

    compare(iconRepeater(widget, 1).count, 1)
    compare(findChild(cellFor(widget, 1), "overflowLabel").text, "+1")
  }

  function test_groupTooltipListsAllWindowTitles() {
    Hyprland.workspaces.values = [makeWorkspace(1, [makeWindow("code", "Alpha"), makeWindow("code", "Beta")])]
    var widget = createWidget({
      groupApps: true
    })
    var slot = iconSlot(widget, 1, 0)

    mouseMove(slot, slot.width / 2, slot.height / 2)
    compare(fakeBar.testTooltipLog[0], {
      action: "show",
      target: slot,
      text: "Alpha\nBeta"
    })
  }

  function test_clickingAFreshGroupFocusesItsFirstWindow() {
    var w0 = makeWindow("code")
    var w1 = makeWindow("code")
    Hyprland.workspaces.values = [makeWorkspace(1, [w0, w1])]
    var widget = createWidget({
      groupApps: true
    })

    mouseClick(iconSlot(widget, 1, 0))
    compare(fakeBar.testCommands, [focusRequest(w0)])
  }

  function test_repeatedClicksOnAGroupCycleThroughItsWindows() {
    var w0 = makeWindow("code", "one")
    var w1 = makeWindow("code", "two")
    var w2 = makeWindow("code", "three")
    Hyprland.workspaces.values = [makeWorkspace(1, [w0, w1, w2])]
    var widget = createWidget({
      groupApps: true
    })
    var slot = iconSlot(widget, 1, 0)

    // Each click targets the window after whichever the group currently has
    // focused - simulated here the way Hyprland would report it back after
    // each activation, one window at a time.
    w0.activated = true
    mouseClick(slot)
    compare(fakeBar.testCommands, [focusRequest(w1)])

    w0.activated = false
    w1.activated = true
    mouseClick(slot)
    compare(fakeBar.testCommands[1], focusRequest(w2))

    w1.activated = false
    w2.activated = true
    mouseClick(slot)
    compare(fakeBar.testCommands[2], focusRequest(w0))
  }

  function test_clickingAGroupGoesToTheLastKnownFocusWhenNoneIsFocusedNow() {
    var w0 = makeWindow("code")
    var w1 = makeWindow("code")
    Hyprland.workspaces.values = [makeWorkspace(1, [w0, w1])]
    var widget = createWidget({
      groupApps: true
    })
    var slot = iconSlot(widget, 1, 0)

    // w1 was focused at some point, then focus moved away entirely (e.g. to
    // another workspace) - none of the group's windows is focused any more.
    w1.activated = true
    w1.activated = false

    mouseClick(slot)
    compare(fakeBar.testCommands, [focusRequest(w1)])
  }

  function test_middleClickOnAGroupClosesTheFocusedWindow() {
    var w0 = makeWindow("code")
    var w1 = makeWindow("code")
    Hyprland.workspaces.values = [makeWorkspace(1, [w0, w1])]
    var widget = createWidget({
      groupApps: true
    })
    var slot = iconSlot(widget, 1, 0)
    w1.activated = true

    mouseClick(slot, slot.width / 2, slot.height / 2, Qt.MiddleButton)
    compare(w1.wayland.testCloseCalls, 1)
    compare(w0.wayland.testCloseCalls, 0)
  }

  // ---- bar orientation ----------------------------------------------------

  function test_horizontalBarUsesOneColumnPerWorkspace() {
    var widget = createWidget()
    compare(findChild(widget, "workspaceGrid").columns, 5)
  }

  function test_verticalBarStacksWorkspacesInOneColumn() {
    fakeBar.vertical = true
    var widget = createWidget()
    compare(findChild(widget, "workspaceGrid").columns, 1)
  }

  function test_clampsSettingsToTheirMaximum() {
    var windows = []
    for (var i = 0; i < 12; i++)
      windows.push(makeWindow("foot"))
    Hyprland.workspaces.values = [makeWorkspace(1, windows)]
    var widget = createWidget({
      maxIcons: 99,
      iconSize: 999
    })

    compare(iconRepeater(widget, 1).count, 10)
    compare(findChild(cellFor(widget, 1), "overflowLabel").text, "+2")
    compare(iconSlot(widget, 1, 0).width, 32)
  }

  function test_fallsBackToDefaultsForUnusableSettingValues() {
    var windows = []
    for (var i = 0; i < 7; i++)
      windows.push(makeWindow("foot"))
    Hyprland.workspaces.values = [makeWorkspace(1, windows)]
    var widget = createWidget({
      maxIcons: "abc",
      iconSize: null
    })

    compare(iconRepeater(widget, 1).count, 5)
    compare(iconSlot(widget, 1, 0).width, 14)
  }

  // ---- introspection (omarchy-shell better-workspaces state) --------------

  function stateOf(widget) {
    return JSON.parse(findChild(widget, "ipcHandler").state())
  }

  function test_stateIsServedOnThePluginsIpcTarget() {
    var widget = createWidget()
    compare(findChild(widget, "ipcHandler").target, "better-workspaces")
  }

  function test_stateReportsWhatIsRendered() {
    var focusedWorkspace = makeWorkspace(2, [makeWindow("foot"), makeWindow("firefox")])
    Hyprland.workspaces.values = [focusedWorkspace, makeWorkspace(10)]
    Hyprland.focusedWorkspace = focusedWorkspace
    var state = stateOf(createWidget({
      maxIcons: 1,
      icons: {
        foot: "🦶"
      }
    }))

    compare(state.settings, {
      maxIcons: 1,
      iconSize: 14,
      minWorkspaces: 5,
      workspaceLabels: "",
      hideEmpty: false,
      groupApps: false,
      gameIcons: true,
      overviewEnabled: true
    })
    compare(state.workspaces.map(workspace => workspace.id), [1, 2, 3, 4, 5, 10])

    var two = state.workspaces[1]
    compare(two.label, "2")
    compare(two.focused, true)
    compare(two.occupied, true)
    compare(two.windows, 2)
    compare(two.overflow, 1)
    compare(two.icons.length, 1)
    compare(two.icons[0].key, "foot")
    compare(two.icons[0].kind, "text")
    compare(two.icons[0].icon, "🦶")
    verify(two.icons[0].address.length > 0)

    var one = state.workspaces[0]
    compare(one.focused, false)
    compare(one.occupied, false)
    compare(one.icons, [])
    compare(state.workspaces[5].label, "0")
  }

  function test_stateReportsTheWorkspaceSettings() {
    var state = stateOf(createWidget({
      minWorkspaces: 2,
      hideEmpty: "true"
    }))
    compare(state.settings.minWorkspaces, 2)
    compare(state.settings.hideEmpty, true)
    compare(state.workspaces, [])
  }

  function test_stateFollowsWorkspaceChanges() {
    var widget = createWidget()
    compare(stateOf(widget).workspaces.length, 5)

    Hyprland.workspaces.values = [makeWorkspace(7, [makeWindow("foot")])]
    var state = stateOf(widget)
    compare(state.workspaces.length, 6)
    compare(state.workspaces[5].id, 7)
    compare(state.workspaces[5].icons[0].key, "foot")
  }
}
