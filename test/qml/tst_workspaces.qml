import QtQuick
import QtTest
import Quickshell
import Quickshell.Hyprland
import Quickshell.Wayland
import qs.Commons
import "helpers"
import "../.." as Plugin

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

  FakeBar {
    id: fakeBar
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
  }

  // ---- fixtures -----------------------------------------------------------

  function makeWindow(windowClass, title) {
    windowCounter++
    var wayland = createTemporaryObject(waylandComponent, testCase, {
      appId: windowClass,
      title: title || windowClass
    })
    return createTemporaryObject(toplevelComponent, testCase, {
      address: "0x" + windowCounter.toString(16),
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

  // ---- workspace list ---------------------------------------------------

  function test_showsWorkspacesOneToFiveByDefault() {
    var widget = createWidget()
    compare(shownIds(widget), [1, 2, 3, 4, 5])
  }

  // ---- how many workspaces are shown ------------------------------------

  function test_showsAsManyEmptyWorkspacesAsMinWorkspaces_data() {
    return [
      { tag: "none", minWorkspaces: 0, expected: [7] },
      { tag: "one", minWorkspaces: 1, expected: [1, 7] },
      { tag: "all ten", minWorkspaces: 10, expected: [1, 2, 3, 4, 5, 6, 7, 8, 9, 10] },
      { tag: "unusable", minWorkspaces: "abc", expected: [1, 2, 3, 4, 5, 7] }
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
      hideEmpty: false
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
