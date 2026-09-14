import QtQuick
import QtTest
import Quickshell
import Quickshell.Hyprland
import Quickshell.Wayland
import qs.Commons
import "helpers"
import "../../qml" as Plugin

// The overview. The layer-shell window around it isn't covered here - a
// layer-shell surface can't be driven headless, which is why the view itself
// is windowless.
TestCase {
  id: testCase
  name: "Overview"
  width: 1280
  height: 800
  visible: true
  when: windowShown

  property int windowCounter: 0

  FakeShell {
    id: fakeShell
  }

  Component {
    id: overviewComponent
    Plugin.Overview {}
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
    id: waylandComponent
    Toplevel {}
  }

  Component {
    id: monitorComponent
    HyprlandMonitor {}
  }

  Component {
    id: storeComponent
    Plugin.SetupStore {}
  }

  Component {
    id: openerComponent
    Plugin.SetupOpener { timeoutMs: 30; settleMs: 1 }
  }

  SignalSpy {
    id: closeSpy
    signalName: "closeRequested"
  }

  Component {
    id: spyComponent
    SignalSpy {}
  }

  function init() {
    Hyprland.testReset()
    DesktopEntries.testReset()
    Quickshell.testReset()
    fakeShell.testReset()
    closeSpy.clear()
  }

  // ---- fixtures -------------------------------------------------------------

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

  // A window Hyprland reports at a real place on the screen, which is what
  // both the cards and the spread are worked out from.
  function makeWindow(windowClass, title, at, size) {
    windowCounter++
    var wayland = createTemporaryObject(waylandComponent, testCase, {
      appId: windowClass,
      title: title || windowClass
    })
    return createTemporaryObject(toplevelComponent, testCase, {
      // No "0x": that is how Quickshell reports an address, and putting it
      // back is exactly what the dispatch has to get right.
      address: windowCounter.toString(16),
      title: title || windowClass,
      wayland: wayland,
      lastIpcObject: {
        "class": windowClass,
        "initialClass": windowClass,
        "at": at || [0, 0],
        "size": size || [960, 1080]
      }
    })
  }

  function makeWorkspace(id, windows, monitor) {
    var list = windows || []
    var workspace = createTemporaryObject(workspaceComponent, testCase, {
      id: id,
      name: String(id),
      monitor: monitor || null
    })
    workspace.toplevels.values = list
    for (var i = 0; i < list.length; i++)
      list[i].workspace = workspace
    return workspace
  }

  // The usual fixture: three workspaces on one monitor, 2 being the one you
  // are on, with two windows side by side.
  function threeWorkspaces() {
    var monitor = makeMonitor()
    Hyprland.focusedMonitor = monitor
    Hyprland.monitors.values = [monitor]

    var first = makeWorkspace(1, [makeWindow("foot", "A Terminal", [0, 0], [1920, 1080])], monitor)
    var second = makeWorkspace(2, [
      makeWindow("firefox", "A Browser", [0, 0], [960, 1080]),
      makeWindow("code", "An Editor", [960, 0], [960, 1080])
    ], monitor)
    var third = makeWorkspace(3, [], monitor)

    Hyprland.workspaces.values = [first, second, third]
    Hyprland.focusedWorkspace = second
    return { monitor: monitor, first: first, second: second, third: third }
  }

  function makeStore(setups) {
    var store = createTemporaryObject(storeComponent, testCase)
    findChild(store, "setupsFile").testSetContent(JSON.stringify({
      schemaVersion: 1,
      setups: setups || {}
    }))
    return store
  }

  function makeOpener() {
    return createTemporaryObject(openerComponent, testCase)
  }

  function anArgvSetup(argv, windowClass) {
    return {
      windows: [{
        recipe: { type: "argv", argv: argv },
        class: windowClass || "x",
        floating: false,
        fullscreen: false,
        rect: { x: 0, y: 0, width: 1, height: 1 }
      }]
    }
  }

  function createOverview(settings, extra) {
    var props = {
      shell: fakeShell,
      settings: settings || {},
      width: testCase.width,
      height: testCase.height,
      active: true
    }
    var overrides = extra || {}
    for (var key in overrides) props[key] = overrides[key]
    var view = createTemporaryObject(overviewComponent, testCase, props)
    verify(view !== null, "overview should be created")
    // The opening animation is running; wait it out so positions are final.
    wait(view.animationDuration + 60)
    return view
  }

  // ---- reading the view -----------------------------------------------------

  function cardRepeater(view) {
    return findChild(view, "workspaceCardRepeater")
  }

  function cardIds(view) {
    var repeater = cardRepeater(view)
    var ids = []
    for (var i = 0; i < repeater.count; i++)
      ids.push(repeater.itemAt(i).modelData)
    return ids
  }

  function cardFor(view, id) {
    var repeater = cardRepeater(view)
    for (var i = 0; i < repeater.count; i++)
      if (repeater.itemAt(i).modelData === id)
        return repeater.itemAt(i)
    return null
  }

  function cardWindows(view, id) {
    return findChild(cardFor(view, id), "cardWindowRepeater")
  }

  function cardWindow(view, id, index) {
    return cardWindows(view, id).itemAt(index)
  }

  function captureOf(item) {
    var loader = findChild(item, "thumbCapture")
    return loader ? loader.item : null
  }

  // ---- the strip ------------------------------------------------------------

  function test_showsTheSameWorkspacesTheBarDoes() {
    threeWorkspaces()
    var view = createOverview()
    compare(cardIds(view), [1, 2, 3, 4, 5])
  }

  function test_followsTheBarsOwnSettings() {
    threeWorkspaces()
    var view = createOverview({
      hideEmpty: true,
      minWorkspaces: 10
    })
    compare(cardIds(view), [1, 2])
  }

  function test_marksTheWorkspaceYouAreOn() {
    threeWorkspaces()
    var view = createOverview()
    compare(cardFor(view, 2).focused, true)
    compare(cardFor(view, 1).focused, false)
    compare(findChild(cardFor(view, 2), "cardCaption").text, "2")
  }

  function test_labelsWorkspaceTenAsZero() {
    threeWorkspaces()
    var view = createOverview({
      minWorkspaces: 10
    })
    compare(findChild(cardFor(view, 10), "cardCaption").text, "0")
  }

  // ---- the grid -------------------------------------------------------------

  // The cards fill the screen rather than sitting in a strip, so a window
  // inside one is big enough to recognise. That means a real grid, and the
  // "+" card is one of its cells.
  function test_laysTheCardsOutAsAGridThatFillsTheScreen() {
    threeWorkspaces()
    var view = createOverview()
    compare(view.cellCount, 6)
    verify(view.layout.columns > 1 && view.layout.rows > 1, "6 cells should not end up in a single row or column")

    var card = cardFor(view, 1)
    verify(card.width > testCase.width / 4, "cards are too small to recognise a window in")
  }

  function test_noCardOverlapsAnotherOrLeavesTheScreen() {
    threeWorkspaces()
    var view = createOverview()
    var cells = []
    for (var i = 0; i < cardRepeater(view).count; i++)
      cells.push(cardRepeater(view).itemAt(i))
    cells.push(findChild(view, "addWorkspaceCard"))

    for (var c = 0; c < cells.length; c++) {
      var cell = cells[c]
      verify(cell.width > 0 && cell.height > 0, "a cell was laid out with no size")
      verify(cell.x >= -1 && cell.y >= -1, "a cell was laid out off the top or left")
      verify(cell.x + cell.width <= testCase.width + 1, "a cell was laid out past the right edge")
      verify(cell.y + cell.height <= testCase.height + 1, "a cell was laid out past the bottom edge")
    }

    for (var a = 0; a < cells.length; a++) {
      for (var b = a + 1; b < cells.length; b++) {
        var one = cells[a]
        var two = cells[b]
        var apart = one.x + one.width <= two.x + 1 || two.x + two.width <= one.x + 1
          || one.y + one.height <= two.y + 1 || two.y + two.height <= one.y + 1
        verify(apart, "cells " + a + " and " + b + " overlap")
      }
    }
  }

  // The whole point of the redesign: both windows of a workspace show up,
  // side by side, exactly where they are on the real screen.
  function test_drawsEveryWindowOfAWorkspaceWhereItReallyIs() {
    threeWorkspaces()
    var view = createOverview()
    var surface = findChild(cardFor(view, 2), "cardSurface")
    compare(Math.round(surface.width / surface.height * 100), Math.round(1920 / 1080 * 100))

    compare(cardWindows(view, 2).count, 2)
    var left = cardWindow(view, 2, 0)
    var right = cardWindow(view, 2, 1)
    verify(left.visible && right.visible, "a window was not drawn at all")
    compare(Math.round(left.x), 0)
    verify(Math.abs(left.width - right.width) <= 1, "the two halves are not the same width")
    verify(Math.abs(right.x - left.width) <= 1, "the right window does not start where the left one ends")
    verify(Math.abs(left.height - surface.height) <= 1, "a full-height window is not drawn full height")
  }

  // A workspace on the second monitor is measured against that monitor, not
  // against whichever one the overview happens to be open on.
  function test_measuresAWorkspaceAgainstItsOwnMonitor() {
    var fixture = threeWorkspaces()
    var second = createTemporaryObject(monitorComponent, testCase, {
      id: 1,
      name: "DP-3",
      x: 1920,
      y: 0,
      width: 1920,
      height: 1080
    })
    Hyprland.monitors.values = [fixture.monitor, second]
    fixture.third.monitor = second
    fixture.third.toplevels.values = [makeWindow("foot", "Far Terminal", [2880, 0], [960, 1080])]

    var view = createOverview()
    var surface = findChild(cardFor(view, 3), "cardSurface")
    var window = cardWindow(view, 3, 0)
    verify(window.visible, "a window on the second monitor was dropped")
    // Global x 2880 is the right half of a monitor that starts at 1920.
    verify(Math.abs(window.x - surface.width / 2) <= 1, "the window was not placed on its own monitor")
  }

  // Where a window sits comes from its `hyprctl clients` entry, which
  // Hyprland can deliver later than the window itself. Without it a window
  // has no rectangle and would silently not be drawn, so the overview asks
  // for a fresh one on the way in.
  function test_asksHyprlandForFreshGeometryWhenItOpens() {
    threeWorkspaces()
    var view = createOverview()
    compare(Hyprland.testToplevelRefreshes, 1)

    view.active = false
    view.active = true
    compare(Hyprland.testToplevelRefreshes, 2)
  }

  function test_leavesOutAWindowHyprlandHasNoGeometryFor() {
    var fixture = threeWorkspaces()
    // A window that has only just mapped: Quickshell knows the toplevel, but
    // its clients entry - and so its rectangle - hasn't arrived yet.
    var fresh = makeWindow("foot", "Just Opened")
    fresh.lastIpcObject = {}
    fixture.third.toplevels.values = [fresh]

    var view = createOverview()
    compare(cardWindows(view, 3).count, 1)
    verify(!cardWindow(view, 3, 0).visible, "a window with no geometry was drawn somewhere arbitrary")
  }

  function test_showsAnEmptyWorkspaceAsAnEmptyCard() {
    threeWorkspaces()
    var view = createOverview()
    compare(cardWindows(view, 4).count, 0)
    verify(cardFor(view, 4).visible, "an empty workspace still gets a card")
  }

  // ---- the "+" card ---------------------------------------------------------

  // Not the first gap - the next one along, so emptying a workspace doesn't
  // make "+" reopen the one you just cleared.
  function test_plusCardOffersTheNextWorkspaceAlong() {
    threeWorkspaces()
    var view = createOverview()
    compare(view.newWorkspaceId, 6)
    compare(findChild(findChild(view, "addCardSurface"), "cardCaption").text, "6")

    Hyprland.workspaces.values = Hyprland.workspaces.values.concat([makeWorkspace(8, [makeWindow("foot")])])
    compare(view.newWorkspaceId, 9)
  }

  function test_clickingPlusOpensThatWorkspaceAndCloses() {
    threeWorkspaces()
    var view = createOverview()
    closeSpy.target = view

    mouseClick(findChild(view, "addCardMouseArea"))
    compare(Hyprland.testDispatched, ["hl.dsp.focus({ workspace = \"6\" })"])
    tryCompare(closeSpy, "count", 1)
  }

  function test_plusCardBowsOutOnceTenIsTaken() {
    threeWorkspaces()
    var view = createOverview({
      minWorkspaces: 10
    })
    compare(view.newWorkspaceId, 0)
    verify(!findChild(view, "addWorkspaceCard").available)

    mouseClick(findChild(view, "addCardMouseArea"))
    compare(Hyprland.testDispatched, [])
  }

  // ---- previews -------------------------------------------------------------

  function test_capturesOnlyWhileTheOverviewIsOpen() {
    var fixture = threeWorkspaces()
    var view = createOverview()
    var thumb = findChild(cardWindow(view, 2, 0), "cardThumb")
    var capture = captureOf(thumb)
    verify(capture !== null, "no screencopy while the overview is open")
    compare(capture.captureSource, fixture.second.toplevels.values[0].wayland)

    view.active = false
    compare(captureOf(thumb), null)

    view.active = true
    verify(captureOf(thumb) !== null, "the screencopy did not come back")
  }

  // The workspace you are looking at keeps updating; every other card takes
  // one frame and then leaves the compositor alone.
  function test_onlyTheWorkspaceYouAreOnKeepsUpdating() {
    threeWorkspaces()
    var view = createOverview()

    var still = captureOf(findChild(cardWindow(view, 1, 0), "cardThumb"))
    verify(still.live, "a still card never captures its one frame")
    still.hasContent = true
    compare(still.live, false)

    // Workspace 2 is the one being looked at, so its card keeps updating.
    var current = captureOf(findChild(cardWindow(view, 2, 0), "cardThumb"))
    compare(current.live, true)
    current.hasContent = true
    compare(current.live, true)
  }

  function test_showsTheAppIconUntilThereIsAFrame() {
    DesktopEntries.testSetEntries({
      firefox: {
        id: "firefox",
        icon: "firefox"
      }
    })
    Quickshell.testThemeIcons = {
      "application-x-executable": "image://test/application-x-executable",
      firefox: "image://test/firefox"
    }
    threeWorkspaces()
    var view = createOverview()
    var thumb = findChild(cardWindow(view, 2, 0), "cardThumb")

    verify(findChild(thumb, "thumbFallback").visible, "no fallback while there is no frame")
    compare(findChild(thumb, "thumbFallbackImage").source, "image://test/firefox")
    verify(!findChild(thumb, "thumbCapture").visible)

    captureOf(thumb).hasContent = true
    verify(!findChild(thumb, "thumbFallback").visible, "the fallback outlived the first frame")
    verify(findChild(thumb, "thumbCapture").visible)
  }

  // A screenshot of a window doesn't always say which app it is: an empty
  // terminal is a black rectangle. The icon stays in the corner regardless.
  function test_keepsTheAppIconOnTheWindowOnceItHasAFrame() {
    DesktopEntries.testSetEntries({
      firefox: {
        id: "firefox",
        icon: "firefox"
      }
    })
    Quickshell.testThemeIcons = {
      "application-x-executable": "image://test/application-x-executable",
      firefox: "image://test/firefox"
    }
    threeWorkspaces()
    var view = createOverview()
    var thumb = findChild(cardWindow(view, 2, 0), "cardThumb")

    captureOf(thumb).hasContent = true
    verify(findChild(thumb, "thumbBadge").visible, "no app icon on a window showing its contents")
    compare(findChild(thumb, "thumbBadgeImage").source, "image://test/firefox")
  }

  function test_usesTheSameIconOverridesTheBarDoes() {
    threeWorkspaces()
    var view = createOverview({
      icons: {
        firefox: "🦊"
      }
    })
    var thumb = findChild(cardWindow(view, 2, 0), "cardThumb")
    compare(findChild(thumb, "thumbFallbackText").text, "🦊")
    verify(findChild(thumb, "thumbFallbackText").visible)
    verify(!findChild(thumb, "thumbFallbackImage").visible)
  }

  // ---- clicking -------------------------------------------------------------

  function test_clickingAWindowFocusesThatWindowAndCloses() {
    var fixture = threeWorkspaces()
    var view = createOverview()
    closeSpy.target = view

    var editor = fixture.second.toplevels.values[1]
    mouseClick(findChild(cardWindow(view, 2, 1), "windowMouseArea"))
    compare(Hyprland.testDispatched, [focusRequest(editor)])

    tryCompare(closeSpy, "count", 1)
  }

  // Same middle-click-to-close the bar's icons already have, so closing a
  // window doesn't require focusing it first. The overview stays open - it
  // is the workspace layout, not the window, that middle-click acts on.
  function test_middleClickingAWindowClosesItAndKeepsTheOverviewOpen() {
    var fixture = threeWorkspaces()
    var view = createOverview()
    closeSpy.target = view

    var editor = fixture.second.toplevels.values[1]
    var terminal = fixture.first.toplevels.values[0]
    var slot = findChild(cardWindow(view, 2, 1), "windowMouseArea")
    mouseClick(slot, slot.width / 2, slot.height / 2, Qt.MiddleButton)

    compare(editor.wayland.testCloseCalls, 1)
    compare(terminal.wayland.testCloseCalls, 0)
    compare(Hyprland.testDispatched, [])
    compare(closeSpy.count, 0)
  }

  // A window on a card you are not on: clicking it goes straight there,
  // workspace and window in one. The wlr activate request would not do that
  // - it marks the window active and leaves you on the workspace you were
  // on - so it is deliberately not what this uses.
  function test_clickingAWindowOnAnotherWorkspaceGoesStraightToIt() {
    var fixture = threeWorkspaces()
    var view = createOverview()
    var terminal = fixture.first.toplevels.values[0]

    mouseClick(findChild(cardWindow(view, 1, 0), "windowMouseArea"))
    compare(Hyprland.testDispatched, [focusRequest(terminal)])
    compare(terminal.wayland.testActivateCalls, 0)
  }

  // A toplevel Hyprland has given no address can't be named to the
  // dispatcher, so the wlr request is what is left.
  function test_clickingAWindowWithoutAnAddressFallsBackToTheWlrRequest() {
    var fixture = threeWorkspaces()
    var window = fixture.second.toplevels.values[0]
    window.address = ""
    var view = createOverview()

    mouseClick(findChild(cardWindow(view, 2, 0), "windowMouseArea"))
    compare(window.wayland.testActivateCalls, 1)
    compare(Hyprland.testDispatched, [])
  }

  function test_clickingACardOpensThatWorkspaceAndCloses() {
    threeWorkspaces()
    var view = createOverview()
    closeSpy.target = view

    mouseClick(findChild(cardFor(view, 3), "cardMouseArea"))
    compare(Hyprland.testDispatched, ["hl.dsp.focus({ workspace = \"3\" })"])
    tryCompare(closeSpy, "count", 1)
  }

  // Clicking the one you are already on has nothing to switch to, but it is
  // still a way out of the overview. Workspace 3 rather than 2, because 2's
  // windows cover every pixel of its card - a click there lands on a window,
  // which is a different thing entirely.
  function test_clickingTheWorkspaceYouAreOnJustCloses() {
    var fixture = threeWorkspaces()
    Hyprland.focusedWorkspace = fixture.third
    var view = createOverview()
    closeSpy.target = view

    mouseClick(findChild(cardFor(view, 3), "cardMouseArea"))
    compare(Hyprland.testDispatched, [])
    tryCompare(closeSpy, "count", 1)
  }

  function test_clickingPastTheCardsCloses() {
    threeWorkspaces()
    var view = createOverview()
    closeSpy.target = view

    mouseClick(findChild(view, "backdropMouseArea"), 2, view.height - 2)
    tryCompare(closeSpy, "count", 1)
  }

  // ---- the keyboard ---------------------------------------------------------

  function test_escapeCloses() {
    threeWorkspaces()
    var view = createOverview()
    closeSpy.target = view

    keyClick(Qt.Key_Escape)
    tryCompare(closeSpy, "count", 1)
  }

  function test_arrowsAndHjklWalkTheCardsAndEnterOpensOne() {
    threeWorkspaces()
    var view = createOverview()
    closeSpy.target = view
    compare(view.selectedIndex, 0)

    keyClick(Qt.Key_Right)
    compare(view.selectedIndex, 1)
    keyClick(Qt.Key_H)
    compare(view.selectedIndex, 0)
    keyClick(Qt.Key_L)
    compare(view.selectedIndex, 1)
    keyClick(Qt.Key_Down)
    compare(view.selectedIndex, 1 + view.layout.columns)
    keyClick(Qt.Key_K)
    compare(view.selectedIndex, 1)
    // Cell 2 is workspace 3 - somewhere other than the one already focused,
    // so Enter has something to ask for.
    keyClick(Qt.Key_L)
    compare(view.selectedIndex, 2)

    keyClick(Qt.Key_Return)
    compare(Hyprland.testDispatched, ["hl.dsp.focus({ workspace = \"3\" })"])
    tryCompare(closeSpy, "count", 1)
  }

  // The last cell is the "+" card, so Enter there makes the next workspace.
  function test_enterOnThePlusCardMakesTheNextWorkspace() {
    threeWorkspaces()
    var view = createOverview()
    view.selectedIndex = view.cellCount - 1

    keyClick(Qt.Key_Return)
    compare(Hyprland.testDispatched, ["hl.dsp.focus({ workspace = \"6\" })"])
  }

  function test_showsWhichCardIsSelected() {
    threeWorkspaces()
    var view = createOverview()
    verify(findChild(cardFor(view, 1), "cardSurface").selected)
    verify(!findChild(cardFor(view, 2), "cardSurface").selected)

    keyClick(Qt.Key_Right)
    verify(!findChild(cardFor(view, 1), "cardSurface").selected)
    verify(findChild(cardFor(view, 2), "cardSurface").selected)
  }

  // Hiding empty workspaces can take the selected card away underneath it.
  function test_selectionSurvivesTheCardsChanging() {
    threeWorkspaces()
    var view = createOverview({
      minWorkspaces: 10
    })
    view.selectedIndex = view.cellCount - 1
    compare(view.selectedIndex, 10)

    view.settings = {
      hideEmpty: true
    }
    compare(view.cellCount, 3)
    compare(view.selectedIndex, 2)
  }

  // ---- search -----------------------------------------------------------

  // The field is on screen from the start - there's nothing to open - "/"
  // only moves keyboard focus into it, same as a page that already has a
  // search box sitting on it.
  function test_theSearchFieldIsAlwaysThereAndSlashFocusesIt() {
    threeWorkspaces()
    var view = createOverview()
    var search = findChild(view, "searchInput")
    verify(findChild(view, "searchBar").visible)
    verify(!search.activeFocus)

    keyClick(Qt.Key_Slash)
    verify(search.activeFocus)
  }

  function test_typingInSearchDimsNonMatchingWindows() {
    threeWorkspaces()
    var view = createOverview()

    keyClick(Qt.Key_Slash)
    findChild(view, "searchInput").text = "firefox"

    verify(cardWindow(view, 2, 0).matchesSearch)
    verify(!cardWindow(view, 2, 1).matchesSearch)
  }

  function test_emptyQueryMatchesEveryWindow() {
    threeWorkspaces()
    var view = createOverview()

    verify(cardWindow(view, 2, 0).matchesSearch)
    verify(cardWindow(view, 2, 1).matchesSearch)
  }

  function test_enterInSearchOpensTheFirstMatchInWorkspaceOrderAndCloses() {
    var fixture = threeWorkspaces()
    var view = createOverview()
    closeSpy.target = view

    keyClick(Qt.Key_Slash)
    findChild(view, "searchInput").text = "A "
    findChild(view, "searchInput").accepted()

    // "A Terminal" is on workspace 1, "A Browser" on 2 - workspace order
    // puts the terminal first even though both match.
    var terminal = fixture.first.toplevels.values[0]
    compare(Hyprland.testDispatched, [focusRequest(terminal)])
    tryCompare(closeSpy, "count", 1)
  }

  function test_enterWithNoMatchDoesNothing() {
    threeWorkspaces()
    var view = createOverview()
    closeSpy.target = view

    keyClick(Qt.Key_Slash)
    findChild(view, "searchInput").text = "nothing-open-matches-this"
    findChild(view, "searchInput").accepted()

    compare(Hyprland.testDispatched, [])
    compare(closeSpy.count, 0)
  }

  // Escape while the field is focused only clears it and hands focus back
  // to the grid - the field itself stays right where it was. A second
  // Escape, now that the grid has focus again, closes the overview.
  function test_escapeInSearchClearsItAndHandsFocusBackWithoutClosing() {
    threeWorkspaces()
    var view = createOverview()
    closeSpy.target = view
    var search = findChild(view, "searchInput")

    keyClick(Qt.Key_Slash)
    search.text = "firefox"

    keyClick(Qt.Key_Escape)
    compare(view.searchQuery, "")
    compare(closeSpy.count, 0)

    // Focus is really back on the grid, not still sitting in the search
    // field waiting to swallow the next key as more text - an arrow key
    // now walks the cards instead.
    compare(view.selectedIndex, 0)
    keyClick(Qt.Key_Right)
    compare(view.selectedIndex, 1)

    keyClick(Qt.Key_Escape)
    tryCompare(closeSpy, "count", 1)
  }

  // ---- the settings button --------------------------------------------------

  function test_theGearAsksForTheSettings() {
    threeWorkspaces()
    var view = createOverview()
    var asked = createTemporaryObject(spyComponent, testCase, {
      target: view,
      signalName: "settingsRequested"
    })

    mouseClick(findChild(view, "settingsMouseArea"))
    compare(asked.count, 1)
    // Asking is not leaving: the overlay keeps the cards behind the form.
    compare(closeSpy.count, 0)
  }

  function test_theGearShowsAThemedIconWhenThereIsOne() {
    Quickshell.testThemeIcons = {
      "application-x-executable": "image://test/application-x-executable",
      "preferences-system": "image://test/preferences-system"
    }
    threeWorkspaces()
    var view = createOverview()
    verify(findChild(view, "settingsIcon").visible)
    compare(findChild(view, "settingsIcon").source, "image://test/preferences-system")
    verify(!findChild(view, "settingsGlyph").visible)
  }

  // A Nerd Font glyph would silently render as a tofu box on a theme font
  // that doesn't carry one, so an unthemed system falls back to a character
  // every font has.
  function test_theGearFallsBackToAPlainGearCharacter() {
    threeWorkspaces()
    var view = createOverview()
    verify(findChild(view, "settingsGlyph").visible)
    compare(findChild(view, "settingsGlyph").text, "\u2699")
    verify(!findChild(view, "settingsIcon").visible)
  }

  // ---- each workspace's own save button --------------------------------------

  // Every card gets its own button - not just the focused workspace's - so
  // saving one doesn't require switching to it first.
  function test_everyCardHasItsOwnSaveButtonAndReportsItsOwnWorkspace() {
    threeWorkspaces()
    var view = createOverview()
    var asked = createTemporaryObject(spyComponent, testCase, {
      target: view,
      signalName: "saveRequested"
    })

    mouseClick(findChild(cardFor(view, 1), "saveMouseArea"))
    compare(asked.count, 1)
    compare(asked.signalArguments[0][0], 1)

    mouseClick(findChild(cardFor(view, 3), "saveMouseArea"))
    compare(asked.count, 2)
    compare(asked.signalArguments[1][0], 3)
  }

  // Asking to save is not leaving, same as the gear: the overlay keeps the
  // cards on screen and doesn't switch workspace either - clicking a save
  // button is not the same as clicking the rest of the card.
  function test_theSaveButtonDoesNotCloseOrSwitchWorkspace() {
    var fixture = threeWorkspaces()
    var view = createOverview()
    closeSpy.target = view

    mouseClick(findChild(cardFor(view, 1), "saveMouseArea"))
    compare(closeSpy.count, 0)
    compare(Hyprland.testDispatched, [])
  }

  function test_theSaveButtonShowsAThemedIconWhenThereIsOne() {
    Quickshell.testThemeIcons = {
      "application-x-executable": "image://test/application-x-executable",
      "document-save": "image://test/document-save"
    }
    threeWorkspaces()
    var view = createOverview()
    var button = cardFor(view, 1)
    verify(findChild(button, "saveIcon").visible)
    compare(findChild(button, "saveIcon").source, "image://test/document-save")
    verify(!findChild(button, "saveGlyph").visible)
  }

  // Same reasoning as the gear: a Nerd Font glyph would silently render as a
  // tofu box on a theme font that doesn't carry one.
  function test_theSaveButtonFallsBackToAFloppyDiskCharacter() {
    threeWorkspaces()
    var view = createOverview()
    var button = cardFor(view, 1)
    verify(findChild(button, "saveGlyph").visible)
    compare(findChild(button, "saveGlyph").text, "💾")
    verify(!findChild(button, "saveIcon").visible)
  }

  // ---- the setups strip -------------------------------------------------------

  function chipFor(view, name) {
    return findChild(view, "setupChipSlot-" + name)
  }

  function test_noStripWithoutAnySavedSetups() {
    threeWorkspaces()
    var view = createOverview()
    verify(!findChild(view, "setupsStrip").visible)
  }

  function test_showsOneChipPerSavedSetupSortedByName() {
    threeWorkspaces()
    var store = makeStore({ Zeta: anArgvSetup(["z"]), Alpha: anArgvSetup(["a"]) })
    var view = createOverview({}, { store: store })

    verify(findChild(view, "setupsStrip").visible)
    compare(findChild(view, "setupChipRepeater").count, 2)
    verify(chipFor(view, "Alpha") !== null)
    verify(chipFor(view, "Zeta") !== null)
  }

  function test_clickingAChipOpensItOnTheWorkspaceActiveWhenOverviewOpened() {
    threeWorkspaces() // focused workspace is 2
    var store = makeStore({ Work: anArgvSetup(["some-tool", "--flag"]) })
    var opener = makeOpener()
    var view = createOverview({}, { store: store, opener: opener })
    closeSpy.target = view

    mouseClick(chipFor(view, "Work"))

    // Already on workspace 2 - nothing to focus, but the setup still opens.
    compare(Hyprland.testDispatched, [])
    compare(Quickshell.testExecuted, [["some-tool", "--flag"]])
    tryCompare(closeSpy, "count", 1)
  }

  function test_draggingAChipOntoACardOpensItThere() {
    threeWorkspaces()
    var store = makeStore({ Work: anArgvSetup(["some-tool"]) })
    var opener = makeOpener()
    var view = createOverview({}, { store: store, opener: opener })
    closeSpy.target = view

    dragOnto(findChild(chipFor(view, "Work"), "setupChipHandle"), cardFor(view, 3))

    compare(Hyprland.testDispatched, ["hl.dsp.focus({ workspace = \"3\" })"])
    compare(Quickshell.testExecuted, [["some-tool"]])
    // Default focusAfterSetupDrop is true.
    tryCompare(closeSpy, "count", 1)
  }

  function test_draggingAChipOntoPlusOpensOnANewWorkspace() {
    threeWorkspaces()
    var store = makeStore({ Work: anArgvSetup(["some-tool"]) })
    var opener = makeOpener()
    var view = createOverview({}, { store: store, opener: opener })
    compare(view.newWorkspaceId, 6)

    dragOnto(findChild(chipFor(view, "Work"), "setupChipHandle"), findChild(view, "addWorkspaceCard"))

    compare(Hyprland.testDispatched, ["hl.dsp.focus({ workspace = \"6\" })"])
    compare(Quickshell.testExecuted, [["some-tool"]])
  }

  // The default: dropping a setup onto an occupied workspace adds its
  // windows alongside the existing ones, closing nothing.
  function test_addModeDropsAlongsideExistingWindowsByDefault() {
    var fixture = threeWorkspaces() // workspace 2 already has two windows
    var store = makeStore({ Work: anArgvSetup(["some-tool"]) })
    var opener = makeOpener()
    var view = createOverview({}, { store: store, opener: opener })

    dragOnto(findChild(chipFor(view, "Work"), "setupChipHandle"), cardFor(view, 2))

    compare(fixture.second.toplevels.values[0].wayland.testCloseCalls, 0)
    compare(fixture.second.toplevels.values[1].wayland.testCloseCalls, 0)
  }

  function test_replaceModeClosesTheExistingWindowsFirst() {
    var fixture = threeWorkspaces()
    var store = makeStore({ Work: anArgvSetup(["some-tool"]) })
    var opener = makeOpener()
    var view = createOverview({ setupTargetMode: "replace" }, { store: store, opener: opener })

    dragOnto(findChild(chipFor(view, "Work"), "setupChipHandle"), cardFor(view, 2))

    compare(fixture.second.toplevels.values[0].wayland.testCloseCalls, 1)
    compare(fixture.second.toplevels.values[1].wayland.testCloseCalls, 1)
    compare(Quickshell.testExecuted, [["some-tool"]])
  }

  // A close() is only a request - the setup shouldn't open onto a workspace
  // that (as far as anyone can tell) still has the windows being replaced on
  // it. `threeWorkspaces()` never bothers with the global toplevel list
  // elsewhere in this file (nothing needed it to be real before), so these
  // populate it themselves to give the wait something to actually wait on.
  function test_replaceWaitsForTheWindowsToActuallyCloseBeforeOpening() {
    var fixture = threeWorkspaces()
    Hyprland.toplevels.values = fixture.second.toplevels.values
    var store = makeStore({ Work: anArgvSetup(["some-tool"]) })
    var opener = makeOpener()
    var view = createOverview({ setupTargetMode: "replace" }, { store: store, opener: opener })

    dragOnto(findChild(chipFor(view, "Work"), "setupChipHandle"), cardFor(view, 2))

    compare(fixture.second.toplevels.values[0].wayland.testCloseCalls, 1)
    compare(fixture.second.toplevels.values[1].wayland.testCloseCalls, 1)
    // Not open yet - both windows are still there as far as Hyprland knows.
    compare(Quickshell.testExecuted, [])

    Hyprland.toplevels.testRemove(fixture.second.toplevels.values[0])
    compare(Quickshell.testExecuted, [])

    Hyprland.toplevels.testRemove(fixture.second.toplevels.values[1])
    compare(Quickshell.testExecuted, [["some-tool"]])
  }

  // An app stuck on "save changes?" (or just slow) can't hold a setup open
  // hostage forever - past `closeWaitMs` it opens anyway.
  function test_replaceOpensAfterATimeoutEvenIfTheWindowsNeverClose() {
    var fixture = threeWorkspaces()
    Hyprland.toplevels.values = fixture.second.toplevels.values
    var store = makeStore({ Work: anArgvSetup(["some-tool"]) })
    var opener = makeOpener()
    var view = createOverview({ setupTargetMode: "replace" }, { store: store, opener: opener, closeWaitMs: 20 })

    dragOnto(findChild(chipFor(view, "Work"), "setupChipHandle"), cardFor(view, 2))

    compare(Quickshell.testExecuted, [])
    tryCompare(Quickshell, "testExecuted", [["some-tool"]])
  }

  // `add` never asks anything to close, so there is nothing to wait for -
  // even with the same windows genuinely still sitting there.
  function test_addModeNeverWaitsEvenWithTheSameWindowsStillThere() {
    var fixture = threeWorkspaces()
    Hyprland.toplevels.values = fixture.second.toplevels.values
    var store = makeStore({ Work: anArgvSetup(["some-tool"]) })
    var opener = makeOpener()
    var view = createOverview({}, { store: store, opener: opener })

    dragOnto(findChild(chipFor(view, "Work"), "setupChipHandle"), cardFor(view, 2))

    compare(Quickshell.testExecuted, [["some-tool"]])
  }

  // Building the layout needs focus on the target workspace throughout -
  // preselect has no other way to know what to split - so `false` only
  // means the focus jumps back once the setup has finished opening, not
  // that it never moves at all.
  function test_focusAfterSetupDropFalseJumpsBackOnceItFinishesOpening() {
    var fixture = threeWorkspaces() // focused workspace is 2
    var store = makeStore({ Work: anArgvSetup(["some-tool"]) })
    var opener = makeOpener()
    var view = createOverview({ focusAfterSetupDrop: false }, { store: store, opener: opener })
    closeSpy.target = view

    dragOnto(findChild(chipFor(view, "Work"), "setupChipHandle"), cardFor(view, 3))
    compare(Hyprland.testDispatched, ["hl.dsp.focus({ workspace = \"3\" })"])
    compare(closeSpy.count, 0)

    // The compositor answers the focus dispatch above - the stub doesn't
    // simulate that on its own, so it's set directly, the same as a real
    // Hyprland would have already done by the time a launched window maps.
    Hyprland.focusedWorkspace = fixture.third

    // The launched window appears - the plan (one window, no preselect)
    // finishes, and only now does the jump back happen.
    var launched = createTemporaryObject(toplevelComponent, testCase, { address: "deadbeef" })
    Hyprland.toplevels.testInsert(launched)

    // `finished` only fires after the opener's settle pause past the last
    // (only) window - see `settleMs` on SetupOpener.
    tryCompare(Hyprland, "testDispatched", [
      "hl.dsp.focus({ workspace = \"3\" })",
      "hl.dsp.focus({ workspace = \"2\" })"
    ])
    compare(closeSpy.count, 0)
  }

  function test_deletingASetupAsksForConfirmationFirst() {
    threeWorkspaces()
    var store = makeStore({ Work: anArgvSetup(["some-tool"]) })
    var view = createOverview({}, { store: store })

    mouseClick(findChild(chipFor(view, "Work"), "setupDeleteMouseArea"))

    verify(findChild(view, "deleteConfirmDialog").opened)
    verify(Object.keys(store.setups).indexOf("Work") !== -1)
  }

  function test_confirmingDeleteRemovesTheSetup() {
    threeWorkspaces()
    var store = makeStore({ Work: anArgvSetup(["some-tool"]) })
    var view = createOverview({}, { store: store })

    mouseClick(findChild(chipFor(view, "Work"), "setupDeleteMouseArea"))
    mouseClick(findChild(findChild(view, "deleteConfirmDialog"), "confirmButton"))

    verify(!findChild(view, "deleteConfirmDialog").opened)
    compare(Object.keys(store.setups).indexOf("Work"), -1)
  }

  function test_cancelingDeleteKeepsTheSetup() {
    threeWorkspaces()
    var store = makeStore({ Work: anArgvSetup(["some-tool"]) })
    var view = createOverview({}, { store: store })

    mouseClick(findChild(chipFor(view, "Work"), "setupDeleteMouseArea"))
    mouseClick(findChild(findChild(view, "deleteConfirmDialog"), "cancelButton"))

    verify(!findChild(view, "deleteConfirmDialog").opened)
    verify(Object.keys(store.setups).indexOf("Work") !== -1)
  }

  // ---- assigning a setup's boot workspace from its chip ----------------------

  function test_bootButtonFallsBackToARocketCharacterWhileOff() {
    threeWorkspaces()
    var store = makeStore({ Work: anArgvSetup(["some-tool"]) })
    var view = createOverview({}, { store: store })

    var chip = chipFor(view, "Work")
    verify(findChild(chip, "bootGlyph").visible)
    compare(findChild(chip, "bootGlyph").text, "🚀")
    verify(!findChild(chip, "bootIcon").visible)
    verify(!findChild(chip, "bootNumber").visible)
  }

  function test_bootButtonShowsAThemedIconWhileOff() {
    Quickshell.testThemeIcons = {
      "application-x-executable": "image://test/application-x-executable",
      "system-run": "image://test/system-run"
    }
    threeWorkspaces()
    var store = makeStore({ Work: anArgvSetup(["some-tool"]) })
    var view = createOverview({}, { store: store })

    var chip = chipFor(view, "Work")
    verify(findChild(chip, "bootIcon").visible)
    compare(findChild(chip, "bootIcon").source, "image://test/system-run")
    verify(!findChild(chip, "bootGlyph").visible)
  }

  // Workspace 10 shows as "0" everywhere else in this widget - the boot
  // button follows the same convention rather than showing the raw id.
  function test_bootButtonShowsTheAssignedWorkspaceNumber() {
    threeWorkspaces()
    var store = makeStore({ Work: { windows: anArgvSetup(["some-tool"]).windows, bootWorkspace: 10 } })
    var view = createOverview({}, { store: store })

    var chip = chipFor(view, "Work")
    verify(findChild(chip, "bootNumber").visible)
    compare(findChild(chip, "bootNumber").text, "0")
    verify(!findChild(chip, "bootGlyph").visible)
    verify(!findChild(chip, "bootIcon").visible)
  }

  function test_clickingTheBootButtonOpensAPickerWithOffAndEveryWorkspace() {
    threeWorkspaces()
    var store = makeStore({ Work: anArgvSetup(["some-tool"]) })
    var view = createOverview({}, { store: store })
    var chip = chipFor(view, "Work")

    verify(!findChild(chip, "setupBootPopover").visible)
    mouseClick(findChild(chip, "setupBootMouseArea"))
    verify(findChild(chip, "setupBootPopover").visible)
    compare(findChild(chip, "setupBootOptionRepeater").count, 11)
  }

  function test_pickingAWorkspaceAssignsBootAndClosesThePicker() {
    threeWorkspaces()
    var store = makeStore({ Work: anArgvSetup(["some-tool"]) })
    var view = createOverview({}, { store: store })
    var chip = chipFor(view, "Work")

    mouseClick(findChild(chip, "setupBootMouseArea"))
    mouseClick(findChild(chip, "setupBootOption-5"))

    compare(store.setups.Work.bootWorkspace, 5)
    verify(!findChild(chip, "setupBootPopover").visible)
  }

  function test_pickingOffClearsAnExistingBootAssignment() {
    threeWorkspaces()
    var store = makeStore({ Work: { windows: anArgvSetup(["some-tool"]).windows, bootWorkspace: 4 } })
    var view = createOverview({}, { store: store })
    var chip = chipFor(view, "Work")

    mouseClick(findChild(chip, "setupBootMouseArea"))
    mouseClick(findChild(chip, "setupBootOption-0"))

    compare(store.setups.Work.bootWorkspace, null)
  }

  // Assigning a workspace another setup already had takes it away from that
  // one - same rule the settings form's boot section already follows
  // (`Logic.assignBootWorkspace`), reused here rather than re-implemented.
  function test_assigningAWorkspaceAlreadyTakenTakesItFromTheOtherSetup() {
    threeWorkspaces()
    var store = makeStore({
      Work: { windows: anArgvSetup(["work"]).windows, bootWorkspace: 3 },
      Games: { windows: anArgvSetup(["games"]).windows }
    })
    var view = createOverview({}, { store: store })

    mouseClick(findChild(chipFor(view, "Games"), "setupBootMouseArea"))
    mouseClick(findChild(chipFor(view, "Games"), "setupBootOption-3"))

    compare(store.setups.Games.bootWorkspace, 3)
    compare(store.setups.Work.bootWorkspace, null)
  }

  // Only one picker at a time - opening another chip's closes whichever was
  // already up, same as the settings/save cards only ever show one at once.
  function test_openingAnotherChipsPickerClosesTheFirst() {
    threeWorkspaces()
    var store = makeStore({ Games: anArgvSetup(["games"]), Work: anArgvSetup(["work"]) })
    var view = createOverview({}, { store: store })

    mouseClick(findChild(chipFor(view, "Work"), "setupBootMouseArea"))
    verify(findChild(chipFor(view, "Work"), "setupBootPopover").visible)

    mouseClick(findChild(chipFor(view, "Games"), "setupBootMouseArea"))
    verify(!findChild(chipFor(view, "Work"), "setupBootPopover").visible)
    verify(findChild(chipFor(view, "Games"), "setupBootPopover").visible)
  }

  function test_clickingTheBootButtonAgainClosesItsOwnPicker() {
    threeWorkspaces()
    var store = makeStore({ Work: anArgvSetup(["some-tool"]) })
    var view = createOverview({}, { store: store })
    var chip = chipFor(view, "Work")

    mouseClick(findChild(chip, "setupBootMouseArea"))
    mouseClick(findChild(chip, "setupBootMouseArea"))

    verify(!findChild(chip, "setupBootPopover").visible)
  }

  // Clicking anywhere else dismisses the picker without touching the
  // assignment - same pattern as the settings/save card's own backdrop.
  function test_clickingOutsideClosesThePickerWithoutChangingTheAssignment() {
    threeWorkspaces()
    var store = makeStore({ Work: anArgvSetup(["some-tool"]) })
    var view = createOverview({}, { store: store })
    var chip = chipFor(view, "Work")

    mouseClick(findChild(chip, "setupBootMouseArea"))
    mouseClick(findChild(view, "bootPopoverDismissArea"))

    verify(!findChild(chip, "setupBootPopover").visible)
    compare(store.setups.Work.bootWorkspace, undefined)
  }

  // Clicking inside the picker itself must not fall through to the dismiss
  // layer behind it and close it before the option click registers.
  function test_thePickerSwallowsClicksOnItsOwnSurface() {
    threeWorkspaces()
    var store = makeStore({ Work: anArgvSetup(["some-tool"]) })
    var view = createOverview({}, { store: store })
    var chip = chipFor(view, "Work")

    mouseClick(findChild(chip, "setupBootMouseArea"))
    mouseClick(findChild(chip, "setupBootPopover"))

    verify(findChild(chip, "setupBootPopover").visible)
  }

  // With the settings card over it the overview stays on screen, previews
  // and all, but must not act on anything behind the form.
  function test_suspendedStopsTakingClicksAndKeys() {
    threeWorkspaces()
    var view = createOverview()
    closeSpy.target = view
    view.suspended = true

    mouseClick(findChild(cardFor(view, 3), "cardMouseArea"))
    keyClick(Qt.Key_Right)
    keyClick(Qt.Key_Escape)
    compare(Hyprland.testDispatched, [])
    compare(view.selectedIndex, 0)
    compare(closeSpy.count, 0)

    // And picks straight back up once the form is gone.
    view.suspended = false
    keyClick(Qt.Key_Right)
    compare(view.selectedIndex, 1)
  }

  function test_suspendedKeepsThePreviewsRunning() {
    threeWorkspaces()
    var view = createOverview()
    view.suspended = true
    verify(captureOf(findChild(cardWindow(view, 2, 0), "cardThumb")) !== null,
      "the previews were torn down behind the settings form")
  }

  // ---- drag and drop --------------------------------------------------------

  // What moving one window to another workspace looks like on the wire.
  // Omarchy runs Hyprland on a Lua config, where a dispatch request is
  // evaluated as Lua, so the classic "movetoworkspacesilent 3,address:0x..."
  // would be a syntax error rather than a move - this asserts on the form
  // that actually works there.
  // What focusing one window looks like on the wire. Hyprland's own focus
  // dispatcher, not the wlr activate request: measured on a live Hyprland,
  // `wayland.activate()` marks the window active but leaves the focused
  // workspace where it was, so clicking a window on another card did nothing
  // you could see.
  function focusRequest(toplevel) {
    return "hl.dsp.focus({ window = \"address:0x" + toplevel.address + "\" })"
  }

  function moveRequest(toplevel, workspaceId) {
    return "hl.dsp.window.move({ workspace = \"" + workspaceId + "\", window = \"address:0x" + toplevel.address + "\", follow = false })"
  }

  // Presses the middle of `source` and releases it over the middle of
  // `target`. The first move only gets the drag recognised - the item starts
  // following from there, not from the press - so that much of the travel is
  // added back on, and the item really does end up centred on the target.
  readonly property int dragNudge: 12

  function dragOnto(source, target) {
    var from = source.mapToItem(testCase, source.width / 2, source.height / 2)
    var to = target.mapToItem(testCase, target.width / 2, target.height / 2)
    mousePress(testCase, from.x, from.y)
    mouseMove(testCase, from.x + testCase.dragNudge, from.y + testCase.dragNudge)
    mouseMove(testCase, to.x + testCase.dragNudge, to.y + testCase.dragNudge)
    mouseRelease(testCase, to.x + testCase.dragNudge, to.y + testCase.dragNudge)
  }

  // Every window is a drag source, and a click is a press and a release with
  // a hand that is never perfectly still. A wobble under the drag threshold
  // has to stay a click, or clicking a window - which on a busy card is the
  // only thing there is to click - would just never do anything.
  function test_aSmallWobbleIsStillAClickNotADrag() {
    var fixture = threeWorkspaces()
    var view = createOverview()
    var handle = findChild(cardWindow(view, 2, 1), "windowDragHandle")
    var at = handle.mapToItem(testCase, handle.width / 2, handle.height / 2)

    mousePress(testCase, at.x, at.y)
    mouseMove(testCase, at.x + 2, at.y + 2)
    mouseRelease(testCase, at.x + 2, at.y + 2)
    compare(Hyprland.testDispatched, [focusRequest(fixture.second.toplevels.values[1])])
  }

  function test_draggingAWindowOutOfItsCardOntoAnotherMovesItThere() {
    var fixture = threeWorkspaces()
    var view = createOverview()
    var editor = fixture.second.toplevels.values[1]

    dragOnto(findChild(cardWindow(view, 2, 1), "windowDragHandle"), cardFor(view, 3))
    compare(Hyprland.testDispatched, [moveRequest(editor, 3)])
  }

  // Dragging a window is not clicking it: the drag threshold separates them,
  // and a drag must never also focus the window it moved.
  function test_draggingAWindowNeitherFocusesItNorCloses() {
    var fixture = threeWorkspaces()
    var view = createOverview()
    closeSpy.target = view

    dragOnto(findChild(cardWindow(view, 2, 1), "windowDragHandle"), cardFor(view, 3))
    compare(fixture.second.toplevels.values[1].wayland.testActivateCalls, 0)
    compare(closeSpy.count, 0)
  }

  // The card clips - it must, for the wallpaper and its rounded corners - so
  // a window drawn inside it would be cut off at the edge the moment it was
  // dragged towards another workspace, and simply disappear. The windows
  // therefore live in their own unclipped layer over the card.
  function test_aDraggedWindowIsNotClippedToItsCard() {
    threeWorkspaces()
    var view = createOverview()

    verify(findChild(findChild(cardFor(view, 2), "cardSurface"), "cardSurfaceBody").clip,
      "the card should still clip its wallpaper")
    verify(!findChild(cardFor(view, 2), "cardWindowLayer").clip,
      "the windows are clipped to their card and would vanish when dragged off it")
  }

  function test_droppingAWindowBackOnItsOwnCardAsksForNothing() {
    threeWorkspaces()
    var view = createOverview()

    dragOnto(findChild(cardWindow(view, 2, 0), "windowDragHandle"), cardWindow(view, 2, 1))
    compare(Hyprland.testDispatched, [])
  }

  function test_draggingAWindowOntoPlusGivesItTheNextWorkspace() {
    var fixture = threeWorkspaces()
    var view = createOverview()
    var editor = fixture.second.toplevels.values[1]
    compare(view.newWorkspaceId, 6)

    dragOnto(findChild(cardWindow(view, 2, 1), "windowDragHandle"), findChild(view, "addWorkspaceCard"))
    compare(Hyprland.testDispatched, [moveRequest(editor, 6)])
  }

  function test_draggingAWorkspaceCardMovesTheWindowsInstead() {
    var fixture = threeWorkspaces()
    var view = createOverview()
    var terminal = fixture.first.toplevels.values[0]
    var browser = fixture.second.toplevels.values[0]
    var editor = fixture.second.toplevels.values[1]

    // Card 2 dropped onto card 1: 2's windows land on 1, 1's on 2.
    dragOnto(findChild(cardFor(view, 2), "cardHandleMouseArea"), cardFor(view, 1))
    compare(Hyprland.testDispatched, [
      moveRequest(browser, 1),
      moveRequest(editor, 1),
      moveRequest(terminal, 2)
    ])
  }

  function test_droppingACardOnItselfMovesNothing() {
    threeWorkspaces()
    var view = createOverview()
    dragOnto(findChild(cardFor(view, 2), "cardHandleMouseArea"), cardFor(view, 2))
    compare(Hyprland.testDispatched, [])
  }
}
