import QtQuick
import QtTest
import Quickshell
import Quickshell.Hyprland
import Quickshell.Wayland
import "helpers"
import "../.." as Plugin

// The save dialog. No window of its own, so it's driven headless the same
// way Overview.qml and SettingsView.qml are.
TestCase {
  id: testCase
  name: "SaveSetupView"
  width: 500
  height: 500
  visible: true
  when: windowShown

  property int windowCounter: 0

  Component {
    id: viewComponent
    Plugin.SaveSetupView {}
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

  function init() {
    Hyprland.testReset()
    DesktopEntries.testReset()
    Quickshell.testReset()
  }

  // ---- fixtures ---------------------------------------------------------

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

  function makeWindow(windowClass, pid, at, size) {
    windowCounter++
    var wayland = createTemporaryObject(waylandComponent, testCase, {
      appId: windowClass,
      title: windowClass
    })
    var ipc = {
      "class": windowClass,
      "initialClass": windowClass,
      "at": at || [0, 0],
      "size": size || [960, 1080],
      "pid": pid || 0,
      "floating": false,
      "fullscreen": 0
    }
    return createTemporaryObject(toplevelComponent, testCase, {
      address: windowCounter.toString(16),
      title: windowClass,
      wayland: wayland,
      lastIpcObject: ipc
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

  // A workspace with one window whose class matches an installed desktop
  // entry, so the common case (no /proc read needed) is the default.
  function oneMatchedWindow(monitor) {
    DesktopEntries.testSetEntries({
      firefox: { id: "firefox.desktop", name: "Firefox", icon: "firefox" }
    })
    var m = monitor || makeMonitor()
    var window = makeWindow("firefox", 111, [0, 0], [1920, 1080])
    var workspace = makeWorkspace(5, [window], m)
    Hyprland.workspaces.values = [workspace]
    Hyprland.focusedWorkspace = workspace
    return { monitor: m, workspace: workspace, window: window }
  }

  function makeStore() {
    return createTemporaryObject(storeComponent, testCase)
  }

  function makeView(overrides) {
    var props = { width: testCase.width, workspaceId: 5 }
    var extra = overrides || {}
    for (var key in extra) props[key] = extra[key]
    return createTemporaryObject(viewComponent, testCase, props)
  }

  function fileOf(store) {
    return findChild(store, "setupsFile")
  }

  // ---- capturing ----------------------------------------------------------

  function test_emptyWorkspaceShowsTheNothingToSaveHintInsteadOfTheForm() {
    var workspace = makeWorkspace(5, [], makeMonitor())
    Hyprland.workspaces.values = [workspace]
    Hyprland.focusedWorkspace = workspace
    var view = makeView()
    verify(view.empty)
    verify(findChild(view, "emptyWorkspaceHint").visible)
    verify(!findChild(view, "saveForm").visible)
  }

  function test_capturesTheWindowWithADesktopEntryMatch() {
    oneMatchedWindow()
    var view = makeView()
    compare(view.capturedWindows.length, 1)
    compare(view.capturedWindows[0].recipe, { type: "desktop-entry", id: "firefox.desktop" })
    compare(view.capturedWindows[0].class, "firefox")
    verify(!view.empty)
    verify(findChild(view, "saveForm").visible)
  }

  function test_fallsBackToArgvWhenNoDesktopEntryMatches() {
    var monitor = makeMonitor()
    var window = makeWindow("some-tool", 222, [0, 0], [1920, 1080])
    var workspace = makeWorkspace(5, [window], monitor)
    Hyprland.workspaces.values = [workspace]
    Hyprland.focusedWorkspace = workspace

    var view = makeView()
    var reader = findChild(view, "cmdlineReader")
    reader.testSetContent(["some-tool", "--flag"].join(String.fromCharCode(0)) + String.fromCharCode(0), "/proc/222/cmdline")
    view.refreshCapture()

    compare(view.capturedWindows[0].recipe, { type: "argv", argv: ["some-tool", "--flag"] })
  }

  function test_scalesTheRectRelativeToTheWorkspacesMonitor() {
    var monitor = makeMonitor()
    var window = makeWindow("firefox", 111, [960, 0], [960, 1080])
    DesktopEntries.testSetEntries({ firefox: { id: "firefox.desktop" } })
    var workspace = makeWorkspace(5, [window], monitor)
    Hyprland.workspaces.values = [workspace]
    Hyprland.focusedWorkspace = workspace

    var view = makeView()
    compare(view.capturedWindows[0].rect, { x: 0.5, y: 0, width: 0.5, height: 1 })
  }

  function test_workspaceIdZeroFallsBackToWhicheverIsFocused() {
    oneMatchedWindow()
    var view = makeView({ workspaceId: 0 })
    compare(view.resolvedWorkspaceId, 5)
    compare(view.capturedWindows.length, 1)
  }

  function test_refreshesWhenTheWorkspaceIdChanges() {
    var monitor = makeMonitor()
    DesktopEntries.testSetEntries({
      firefox: { id: "firefox.desktop" },
      code: { id: "code.desktop" }
    })
    var window5 = makeWindow("firefox", 111, [0, 0], [1920, 1080])
    var workspace5 = makeWorkspace(5, [window5], monitor)
    var window6 = makeWindow("code", 333, [0, 0], [1920, 1080])
    var workspace6 = makeWorkspace(6, [window6], monitor)
    // Both workspaces exist from the start - the stubbed Hyprland.workspaces
    // isn't reactively bindable the way the real one is, so what changes
    // during the test is only the view's own `workspaceId`.
    Hyprland.workspaces.values = [workspace5, workspace6]
    Hyprland.focusedWorkspace = workspace5

    var view = makeView({ workspaceId: 5 })
    compare(view.capturedWindows[0].class, "firefox")

    // The recapture is deferred (Qt.callLater), so it lands on a later
    // event-loop pass rather than synchronously with the assignment.
    view.workspaceId = 6
    wait(10)
    compare(view.capturedWindows[0].class, "code")
  }

  // ---- naming and saving ---------------------------------------------------

  function test_pressingEnterWithNoNameShowsARequiredHintAndDoesNotSave() {
    oneMatchedWindow()
    var store = makeStore()
    fileOf(store).testSetMissing()
    var view = makeView({ store: store })

    findChild(view, "nameField").accepted()

    verify(view.triedEmptySubmit)
    verify(findChild(view, "emptyNameHint").visible)
    compare(fileOf(store).testWrites.length, 0)
  }

  function test_pressingEnterWithANewNameSavesImmediately() {
    oneMatchedWindow()
    var store = makeStore()
    fileOf(store).testSetMissing()
    var view = makeView({ store: store })

    var field = findChild(view, "nameField")
    field.text = "Work"
    field.accepted()

    compare(fileOf(store).testWrites.length, 1)
    verify(!findChild(view, "overwriteHint").visible)
    verify(Object.keys(store.setups).indexOf("Work") !== -1)
  }

  // Trims the name, same as `Logic.setupNameStatus` expects.
  function test_trimsWhitespaceAroundTheName() {
    oneMatchedWindow()
    var store = makeStore()
    fileOf(store).testSetMissing()
    var view = makeView({ store: store })

    var field = findChild(view, "nameField")
    field.text = "  Work  "
    field.accepted()

    compare(Object.keys(store.setups), ["Work"])
  }

  function test_savingAnExistingNameAsksToConfirmFirst() {
    oneMatchedWindow()
    var store = makeStore()
    fileOf(store).testSetContent(JSON.stringify({
      schemaVersion: 1,
      setups: { Work: { windows: [{ recipe: { type: "desktop-entry", id: "x" }, class: "x", floating: false, fullscreen: false, rect: { x: 0, y: 0, width: 1, height: 1 } }] } }
    }))
    var view = makeView({ store: store })

    var field = findChild(view, "nameField")
    field.text = "Work"
    field.accepted()

    verify(view.confirmingOverwrite)
    verify(findChild(view, "overwriteHint").visible)
    compare(fileOf(store).testWrites.length, 0)

    // Pressing Enter again overwrites it.
    field.accepted()
    compare(fileOf(store).testWrites.length, 1)
  }

  // Editing the name after being asked to confirm starts over - the
  // confirmation was for the old name, not whatever is typed next.
  function test_editingTheNameAfterAskingToConfirmDropsTheConfirmation() {
    oneMatchedWindow()
    var store = makeStore()
    fileOf(store).testSetContent(JSON.stringify({
      schemaVersion: 1,
      setups: { Work: { windows: [{ recipe: { type: "desktop-entry", id: "x" }, class: "x", floating: false, fullscreen: false, rect: { x: 0, y: 0, width: 1, height: 1 } }] } }
    }))
    var view = makeView({ store: store })

    var field = findChild(view, "nameField")
    field.text = "Work"
    field.accepted()
    verify(view.confirmingOverwrite)

    field.text = "Work2"
    verify(!view.confirmingOverwrite)
  }

  function test_aFailedSaveShowsAnErrorHint() {
    oneMatchedWindow()
    var store = makeStore()
    fileOf(store).testSetMissing()
    findChild(store, "mkdirProcess").testExitCode = 1
    var view = makeView({ store: store })

    var field = findChild(view, "nameField")
    field.text = "Work"
    field.accepted()

    tryCompare(view, "saveErrored", true)
    verify(findChild(view, "saveErrorHint").visible)
  }

  // Opening the dialog fresh (becoming visible) clears whatever the last
  // save attempt left behind, so reopening it never shows stale state.
  function test_becomingVisibleResetsTheFormAndRecapturesTheWindows() {
    oneMatchedWindow()
    var view = makeView({ visible: false })
    var field = findChild(view, "nameField")
    field.text = "Work"
    field.accepted()
    view.triedEmptySubmit = true

    view.visible = true

    compare(field.text, "")
    verify(!view.triedEmptySubmit)
    compare(view.capturedWindows.length, 1)
  }
}
