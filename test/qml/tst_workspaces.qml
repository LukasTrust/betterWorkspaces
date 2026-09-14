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
    id: waylandComponent
    Toplevel {}
  }

  function init() {
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
    var widget = createWidget()
    mouseClick(cellFor(widget, 3))
    compare(fakeBar.testCommands, ["hyprctl dispatch 'hl.dsp.focus({ workspace = \"3\" })'"])
  }

  // Clicking the workspace you are already on has nothing to switch to, so
  // it opens the overview instead - the one entry point that needs no setup.
  function test_clickingTheWorkspaceYouAreOnOpensTheOverview() {
    var focusedWorkspace = makeWorkspace(3)
    Hyprland.workspaces.values = [focusedWorkspace]
    Hyprland.focusedWorkspace = focusedWorkspace
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
    Hyprland.focusedWorkspace = focusedWorkspace
    var widget = createWidget({
      overviewEnabled: false
    })

    mouseClick(cellFor(widget, 3))
    compare(fakeShell.testToggled, [])
    compare(fakeBar.testCommands, ["hyprctl dispatch 'hl.dsp.focus({ workspace = \"3\" })'"])
  }

  // Only the workspace you are on; every other one still just switches.
  function test_clickingAnotherWorkspaceNeverOpensTheOverview() {
    var focusedWorkspace = makeWorkspace(3)
    Hyprland.workspaces.values = [focusedWorkspace]
    Hyprland.focusedWorkspace = focusedWorkspace
    var widget = createWidget()

    mouseClick(cellFor(widget, 1))
    compare(fakeShell.testToggled, [])
    compare(fakeBar.testCommands, ["hyprctl dispatch 'hl.dsp.focus({ workspace = \"1\" })'"])
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
    var widget = createWidget()
    mouseClick(findChild(cellFor(widget, 3), "workspaceLabel"))
    compare(fakeBar.testCommands, ["hyprctl dispatch 'hl.dsp.focus({ workspace = \"3\" })'"])
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
