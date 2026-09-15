import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Widgets
import qs.Commons
import qs.Ui

import "../js/selector.js" as Selector
import "../js/icons.js" as Icons
import "../js/cards.js" as Cards
import "../js/settings.js" as Settings
import "../js/setups.js" as Setups

// The overview: every workspace as a card, laid out to fill the screen, with
// its windows drawn where they really sit. That is the whole view - the cards
// are big enough to recognise a window in, so there is nothing else to show.
//
// Windowless on purpose - Overlay.qml supplies the layer-shell surface - so
// the whole thing can be driven headless in the QML tests.
//
// Nothing here changes a Hyprland binding: the overview is opened by the
// plugin's own IPC toggle (which the user may bind to a key) or by clicking
// the workspace you are already on, and everything it does it does through
// Hyprland's IPC dispatchers.
Item {
  id: root

  // The scoped shell facade the overlay was handed; unused so far.
  property var shell: null
  // This widget's shell.json entry, so the overview shows the same
  // workspaces and the same icons the bar does.
  property var settings: ({})
  // The shared setup store and opener (Overlay.qml owns the one instance of
  // each) - what the setups strip lists and drags from, and what actually
  // opens one.
  property var store: null
  property var opener: null
  // False while the overlay is hidden: tears every screencopy down, so
  // nothing is captured off the screen in the background.
  property bool active: false

  // False while the settings card sits on top: the cards stay on screen and
  // keep their previews - the settings change what they show, so seeing them
  // change is the point - but they stop taking clicks and keys.
  property bool suspended: false

  signal closeRequested
  signal settingsRequested
  // A workspace's own save button, not the gear - which workspace is on the
  // caller, since it isn't necessarily the focused one.
  signal saveRequested(int workspaceId)
  // Emitted for every Hyprland request, so the tests can read what a click
  // or a drop actually asked for.
  signal dispatched(string request)

  readonly property int minWorkspaces: Settings.clampSetting("minWorkspaces", Settings.settingValue(root.settings, "minWorkspaces"))
  readonly property bool hideEmpty: Settings.clampSetting("hideEmpty", Settings.settingValue(root.settings, "hideEmpty"))
  readonly property bool gameIcons: Settings.clampSetting("gameIcons", Settings.settingValue(root.settings, "gameIcons"))
  readonly property string setupTargetMode: Settings.clampSetting("setupTargetMode", Settings.settingValue(root.settings, "setupTargetMode"))
  readonly property bool focusAfterSetupDrop: Settings.clampSetting("focusAfterSetupDrop", Settings.settingValue(root.settings, "focusAfterSetupDrop"))

  // ---- saved setups ---------------------------------------------------------

  readonly property var setupNames: {
    var names = []
    if (root.store)
      for (var key in root.store.setups)
        names.push(key)
    return names.sort()
  }

  // The workspace a click opens a setup on - captured once when the
  // overview opens, not read live, so it can't drift if focus moves while
  // the overview is up.
  property int openedOnWorkspaceId: 0

  function monitorAreaFor(workspaceId) {
    return root.monitorRect(root.monitorFor(workspaceId))
  }

  // Which of a workspace's current windows `setupTargetMode: "replace"`
  // closes, worked out by `Setups.planSetupOpen` - a plain `close()` each,
  // never a kill, same as the bar and this view's own middle-click.
  function closeExisting(targets, mode) {
    var addresses = Setups.planSetupOpen(targets, mode)
    for (var i = 0; i < targets.length; i++)
      if (addresses.indexOf(String(targets[i].address)) !== -1)
        root.closeWindow(targets[i])
    return addresses
  }

  // ---- waiting for a `replace`'s closes before opening -----------------------
  //
  // A plain `close()` is a request, not an instant removal - an app can ask
  // "save changes?" first. Opening the setup right away would land its
  // windows on a workspace that (for a moment, or a lot longer) still has
  // the ones being replaced on it too. `callback` runs once every address
  // asked to close is actually gone, or after `closeWaitMs` regardless - an
  // app stuck on a dialog forever can't hold a setup open hostage.
  property int closeWaitMs: 3000
  property var _pendingCloseAddresses: []
  property var _pendingCloseCallback: null

  function currentToplevelAddresses() {
    var values = Hyprland.toplevels.values
    var list = []
    for (var i = 0; i < values.length; i++)
      list.push(String(values[i].address))
    return list
  }

  function waitForClose(addresses, callback) {
    var pending = Setups.remainingCloseTargets(addresses, root.currentToplevelAddresses())
    if (pending.length === 0) {
      callback()
      return
    }
    root._pendingCloseAddresses = pending
    root._pendingCloseCallback = callback
    closeWaitTimer.restart()
  }

  function _checkPendingClose() {
    if (!root._pendingCloseCallback)
      return
    root._pendingCloseAddresses = Setups.remainingCloseTargets(root._pendingCloseAddresses, root.currentToplevelAddresses())
    if (root._pendingCloseAddresses.length === 0)
      root._settlePendingClose()
  }

  function _settlePendingClose() {
    closeWaitTimer.stop()
    var callback = root._pendingCloseCallback
    root._pendingCloseCallback = null
    root._pendingCloseAddresses = []
    if (callback)
      callback()
  }

  Connections {
    target: Hyprland.toplevels
    function onObjectRemovedPost() {
      root._checkPendingClose()
    }
  }

  Timer {
    id: closeWaitTimer
    objectName: "closeWaitTimer"
    interval: root.closeWaitMs
    onTriggered: root._settlePendingClose()
  }

  // > 0 while a drop's `focusAfterSetupDrop: false` owes a jump back to
  // wherever focus was before the drop - building the setup's layout still
  // needs focus on the target throughout, preselect has no other way to
  // know which window to split.
  property int _returnFocusId: 0

  // Opens `name` on `workspaceId`. `fromDrop` is false for a click (which
  // always opens where you already are and always closes the overview) and
  // true for a drag-drop (governed by `focusAfterSetupDrop` instead).
  function openSetup(name, workspaceId, fromDrop) {
    if (!root.store || !root.opener || workspaceId <= 0)
      return
    var setup = root.store.setups[name]
    if (!setup)
      return
    var targets = root.toplevelsOf(workspaceId)
    var closeAddresses = root.setupTargetMode === "replace" ? root.closeExisting(targets, root.setupTargetMode) : []

    var cameFrom = root.focusedId
    root.focusWorkspace(workspaceId)
    root._returnFocusId = (fromDrop && !root.focusAfterSetupDrop && cameFrom !== workspaceId) ? cameFrom : 0

    var area = root.monitorAreaFor(workspaceId)
    root.waitForClose(closeAddresses, function () {
      root.opener.open(setup, area)
    })
  }

  function openSetupFromChip(name) {
    root.openSetup(name, root.openedOnWorkspaceId, false)
    root.beginClose()
  }

  function dropSetup(name, workspaceId) {
    root.openSetup(name, workspaceId, true)
    if (root.focusAfterSetupDrop)
      root.beginClose()
  }

  Connections {
    target: root.opener
    function onFinished(completed) {
      if (root._returnFocusId > 0) {
        root.focusWorkspace(root._returnFocusId)
        root._returnFocusId = 0
      }
    }
  }

  // ---- deleting a setup -------------------------------------------------

  property string pendingDeleteName: ""

  function requestDeleteSetup(name) {
    root.pendingDeleteName = name
  }

  function confirmDeleteSetup() {
    if (root.store && root.pendingDeleteName.length > 0)
      root.store.remove(root.pendingDeleteName)
    root.pendingDeleteName = ""
  }

  function cancelDeleteSetup() {
    root.pendingDeleteName = ""
  }

  // ---- assigning a setup's boot workspace ------------------------------------

  // Which setup's boot picker is open, if any - one at a time, name-keyed so
  // opening another chip's closes whichever was already up.
  property string bootPopoverFor: ""

  function toggleBootPopover(name) {
    root.bootPopoverFor = root.bootPopoverFor === name ? "" : name
  }

  function setBootWorkspace(name, workspaceId) {
    if (root.store)
      root.store.replaceAll(Setups.assignBootWorkspace(root.store.setups, name, workspaceId))
    root.bootPopoverFor = ""
  }

  // ---- what Hyprland has --------------------------------------------------

  function workspaceById(id) {
    var values = Hyprland.workspaces.values
    for (var i = 0; i < values.length; i++)
      if (values[i].id === id)
        return values[i]
    return null
  }

  function toplevelsOf(id) {
    var workspace = root.workspaceById(id)
    return workspace && workspace.toplevels ? workspace.toplevels.values : []
  }

  readonly property int focusedId: Hyprland.focusedWorkspace ? Hyprland.focusedWorkspace.id : 0

  // The same workspaces the bar shows, from the same settings - the overview
  // is an expansion of the bar widget, not a second opinion on what exists.
  readonly property var workspaceIds: {
    var values = Hyprland.workspaces.values
    var model = []
    for (var i = 0; i < values.length; i++) {
      var workspace = values[i]
      if (!workspace || !workspace.toplevels)
        continue
      model.push({
        id: workspace.id,
        occupied: workspace.toplevels.values.length > 0
      })
    }
    return Settings.computeWorkspaceIds(model, {
      minWorkspaces: root.minWorkspaces,
      hideEmpty: root.hideEmpty,
      focusedId: root.focusedId
    })
  }

  readonly property int newWorkspaceId: Cards.nextWorkspaceId(root.workspaceIds)

  // Geometry to measure window positions against. A workspace carries its
  // own monitor; the focused one stands in for a workspace Hyprland hasn't
  // placed yet.
  function monitorFor(id) {
    var workspace = root.workspaceById(id)
    return (workspace && workspace.monitor) || Hyprland.focusedMonitor
  }

  function monitorRect(monitor) {
    if (!monitor)
      return {
        x: 0,
        y: 0,
        width: root.width,
        height: root.height
      }
    // Hyprland's monitor width/height are physical pixels, but window
    // rectangles from `hyprctl clients` (see windowRect() below) are in
    // logical/layout pixels, i.e. physical / scale. Convert so both share
    // the same coordinate space.
    var scale = monitor.scale > 0 ? monitor.scale : 1
    return {
      x: monitor.x,
      y: monitor.y,
      width: monitor.width / scale,
      height: monitor.height / scale
    }
  }

  // Hyprland reports a window's rectangle on `hyprctl clients`, which is
  // what `lastIpcObject` holds: `at` and `size` are [x, y] and [w, h].
  function windowRect(toplevel) {
    var ipc = (toplevel && toplevel.lastIpcObject) || {}
    var at = ipc.at || []
    var size = ipc.size || []
    return {
      x: Number(at[0]) || 0,
      y: Number(at[1]) || 0,
      width: Number(size[0]) || 0,
      height: Number(size[1]) || 0
    }
  }

  function windowTitle(toplevel) {
    if (!toplevel)
      return ""
    return String(toplevel.title || (toplevel.wayland ? toplevel.wayland.title : "") || "")
  }

  // ---- talking to Hyprland ------------------------------------------------
  //
  // Straight over Hyprland's request socket - no hyprctl process, no shell.
  // Omarchy configures Hyprland in Lua, and a dispatch request is evaluated
  // as Lua, so the classic `movetoworkspacesilent 3,address:0x...` form is a
  // syntax error rather than a move. `window = "address:0x..."` is what picks
  // out a window other than the focused one; selector.js builds that selector,
  // because the `0x` Quickshell leaves off is the difference between moving
  // the window and Hyprland answering "ok" and doing nothing.

  function dispatch(request) {
    Hyprland.dispatch(request)
    root.dispatched(request)
  }

  // Switching to a workspace Hyprland doesn't have yet is also how one is
  // made, which is all the "+" card does.
  function focusWorkspace(id) {
    if (id > 0 && id !== root.focusedId)
      root.dispatch("hl.dsp.focus({ workspace = \"" + id + "\" })")
  }

  function moveWindowRequest(address, id) {
    return "hl.dsp.window.move({ workspace = \"" + id + "\", window = \"" + Selector.windowSelector(address) + "\", follow = false })"
  }

  // Hyprland's own focus dispatcher, not the foreign-toplevel activate
  // request. Measured on a live Hyprland: `wayland.activate()` marks the
  // window active but leaves the focused workspace exactly where it was, so
  // clicking a window on another card looked like it did nothing at all.
  // Going somewhere else is most of what the overview is for, so it uses the
  // form that actually goes there. The wlr request is the fallback for a
  // toplevel Hyprland has given no address.
  function activateWindow(toplevel) {
    if (!toplevel)
      return
    if (toplevel.address) {
      root.dispatch("hl.dsp.focus({ window = \"" + Selector.windowSelector(toplevel.address) + "\" })")
      return
    }
    if (toplevel.wayland && typeof toplevel.wayland.activate === "function")
      toplevel.wayland.activate()
  }

  // `follow = false` so the view doesn't jump to the workspace a window was
  // dropped on: the drop says where the window goes, not where you want to be.
  function moveWindowToWorkspace(toplevel, id) {
    if (!toplevel || !toplevel.address || id <= 0)
      return
    root.dispatch(root.moveWindowRequest(toplevel.address, id))
    // The window is on another workspace now, and at another place on it.
    root.refreshGeometry()
  }

  function openWorkspace(id) {
    if (id <= 0)
      return
    root.focusWorkspace(id)
    root.beginClose()
  }

  function openWindow(toplevel) {
    root.activateWindow(toplevel)
    root.beginClose()
  }

  // Same close as the bar's middle-click on an icon: just the window, the
  // overview stays open.
  function closeWindow(toplevel) {
    if (toplevel && toplevel.wayland)
      toplevel.wayland.close()
  }

  // Hyprland can't renumber a workspace, so a card dragged onto another one
  // moves the windows instead; cards.js works out which window ends up where
  // before any of them moves.
  function reorderWorkspaces(fromIndex, toIndex) {
    var cards = []
    for (var i = 0; i < root.workspaceIds.length; i++) {
      var toplevels = root.toplevelsOf(root.workspaceIds[i])
      var addresses = []
      for (var w = 0; w < toplevels.length; w++)
        if (toplevels[w].address)
          addresses.push(String(toplevels[w].address))
      cards.push({
        id: root.workspaceIds[i],
        addresses: addresses
      })
    }

    var moves = Cards.planReorder(cards, fromIndex, toIndex)
    for (var m = 0; m < moves.length; m++)
      root.dispatch(root.moveWindowRequest(moves[m].address, moves[m].workspace))
    if (moves.length > 0)
      root.refreshGeometry()
  }

  // What a drop carries, whether it came from a window inside a card or from
  // a card itself. Reading it off the drag source in one place keeps the two
  // drop targets from each inventing their own shape.
  function payloadOf(drop) {
    return drop && drop.source && drop.source.payload ? drop.source.payload : null
  }

  // ---- closing ------------------------------------------------------------

  // Closing plays the opening animation backwards, so the cards shrink away
  // before the surface goes. `closing` drives both that and the guard that
  // keeps a second Escape from restarting it.
  property bool closing: false

  readonly property int animationDuration: 180

  function beginClose() {
    if (root.closing)
      return
    root.closing = true
    root.clearSearch()
    closeTimer.restart()
  }

  onActiveChanged: {
    if (root.active) {
      root.closing = false
      root.openedOnWorkspaceId = root.focusedId
      root.refreshGeometry()
      root.grabKeys()
    }
  }

  onSuspendedChanged: root.grabKeys()

  function grabKeys() {
    if (root.active && !root.suspended)
      keys.forceActiveFocus()
  }

  // Where a window sits comes from its `hyprctl clients` entry, and Hyprland
  // can hand Quickshell a new toplevel before that entry exists: a window
  // opened a moment ago has an empty `lastIpcObject`, so no rectangle, so
  // nothing to draw. The bar widget never noticed - it only ever reads the
  // window class, which the wlr handle also carries.
  //
  // Asking once as the overview opens is not polling: it is the one moment
  // the geometry matters, and it is the answer that fills the cards in.
  function refreshGeometry() {
    Hyprland.refreshToplevels()
  }

  Timer {
    id: closeTimer
    objectName: "closeTimer"
    interval: root.animationDuration
    onTriggered: {
      root.closing = false
      root.closeRequested()
    }
  }

  // ---- icons --------------------------------------------------------------

  IconResolver {
    id: iconResolver
    objectName: "iconResolver"
    settings: root.settings
    gameIcons: root.gameIcons
  }

  // ---- layout -------------------------------------------------------------

  readonly property int gap: Style.space(24)
  readonly property int captionHeight: Style.space(30)
  // Room for a row of setup chips along the bottom. With nothing saved yet
  // the strip collapses to a single line of text saying how to get one -
  // without it the whole feature is invisible until you happen to find the
  // save button on a card, and there is no other place that would mention
  // it.
  readonly property int setupsStripHeight: root.setupNames.length > 0 ? Style.space(96) : Style.space(26)

  // One cell per workspace plus one for the "+" card. A card is the shape of
  // the screen its workspace is on, so the windows drawn on it are the shape
  // they really are; the "+" card borrows the focused monitor's shape so it
  // sits in the grid like any other.
  readonly property var cellSizes: {
    var sizes = []
    for (var i = 0; i < root.workspaceIds.length; i++) {
      var monitor = root.monitorRect(root.monitorFor(root.workspaceIds[i]))
      sizes.push({
        width: monitor.width,
        height: monitor.height
      })
    }
    var focused = root.monitorRect(Hyprland.focusedMonitor)
    sizes.push({
      width: focused.width,
      height: focused.height
    })
    return sizes
  }

  // The grid maths lives in cards.js: it fits any number of rectangles of any
  // shape into the space without overlapping them and without distorting
  // them, which is exactly what a screen full of workspace cards needs.
  readonly property var layout: Cards.spreadLayout(root.cellSizes, {
    width: Math.max(0, root.width - root.gap * 2),
    height: Math.max(0, root.height - root.gap * 2 - root.setupsStripHeight)
  }, {
    spacing: root.gap,
    captionHeight: root.captionHeight
  })

  function placementAt(index) {
    return root.layout.items[index] || null
  }

  // ---- keyboard selection -------------------------------------------------
  //
  // The selection walks every cell, the "+" card included, so Enter either
  // opens a workspace or makes the next one.

  readonly property int cellCount: root.workspaceIds.length + 1

  property int selectedIndex: 0

  onCellCountChanged: {
    if (root.selectedIndex >= root.cellCount)
      root.selectedIndex = root.cellCount - 1
  }

  function directionFor(event) {
    if (event.key === Qt.Key_Left || event.key === Qt.Key_H)
      return "left"
    if (event.key === Qt.Key_Right || event.key === Qt.Key_L)
      return "right"
    if (event.key === Qt.Key_Up || event.key === Qt.Key_K)
      return "up"
    if (event.key === Qt.Key_Down || event.key === Qt.Key_J)
      return "down"
    return ""
  }

  function moveSelection(direction) {
    root.selectedIndex = Cards.navigateGrid(root.selectedIndex, root.cellCount, root.layout.columns, direction)
  }

  // One notch of the wheel, as a named step rather than only a handler body.
  //
  // Two reasons it is broken out: the suspend guard belongs with the action
  // itself rather than only on the FocusScope that happens to carry the
  // handler, and the QML tests can drive this directly - synthetic wheel
  // events reach the wrong window when qmltestrunner runs every test file in
  // one process, so the handler below can be checked for being wired up but
  // not actually fired.
  function scrollSelection(angleDelta) {
    if (root.suspended)
      return
    root.selectedIndex = Cards.navigateWheel(root.selectedIndex, root.cellCount, angleDelta)
  }

  function openSelection() {
    var index = root.selectedIndex
    if (index < 0 || index >= root.cellCount)
      return
    root.openWorkspace(index < root.workspaceIds.length ? root.workspaceIds[index] : root.newWorkspaceId)
  }

  // ---- search ---------------------------------------------------------------
  //
  // The query box sits over the cards always, not just once summoned - "/"
  // only moves keyboard focus into it, the way it would on a page with a
  // search field already on screen. Every window's own thumb dims unless
  // it matches, across every workspace at once, so a window you can't place
  // by eye is still findable by title or app. Enter goes straight to the
  // first match in workspace order - the same order the cards are laid out
  // in - without making the user click it.

  property string searchQuery: ""

  function focusSearch() {
    searchInput.forceActiveFocus()
  }

  // Clears the query and hands keyboard focus back to the grid - what Esc
  // does from inside the search field, and what closing the whole overview
  // does too, so reopening it always starts with a clean search.
  function clearSearch() {
    root.searchQuery = ""
    searchInput.text = ""
    // Explicitly giving up the field's own focus claim, not just asking
    // the scope to refocus itself: forceActiveFocus() on the scope alone
    // doesn't override a focus item something already forced directly.
    searchInput.focus = false
    root.grabKeys()
  }

  // Hyprland's own class (preferred by icon resolution too) rather than the
  // window title alone, so "firefox" finds every open Firefox window even
  // when none of their titles happen to say so.
  function windowClass(toplevel) {
    return iconResolver.windowKey(toplevel)
  }

  function windowMatchesSearch(toplevel) {
    return Icons.matchesSearchQuery(root.windowTitle(toplevel), root.windowClass(toplevel), root.searchQuery)
  }

  // The first match, in the same order the cards are laid out in, so Enter
  // goes wherever the eye would land first too.
  function firstSearchMatch() {
    if (String(root.searchQuery || "").trim().length === 0)
      return null
    for (var i = 0; i < root.workspaceIds.length; i++) {
      var windows = root.toplevelsOf(root.workspaceIds[i])
      for (var j = 0; j < windows.length; j++)
        if (root.windowMatchesSearch(windows[j]))
          return windows[j]
    }
    return null
  }

  function openFirstSearchMatch() {
    var match = root.firstSearchMatch()
    if (match)
      root.openWindow(match)
  }

  readonly property var settingsIcon: {
    var themed = Quickshell.iconPath("preferences-system", true)
    return themed.length > 0 ? {
      kind: "image",
      source: themed
    } : {
      kind: "text",
      value: "\u2699"
    }
  }

  readonly property var saveIcon: {
    var themed = Quickshell.iconPath("document-save", true)
    return themed.length > 0 ? {
      kind: "image",
      source: themed
    } : {
      kind: "text",
      value: "\ud83d\udcbe"
    }
  }

  readonly property var bootIcon: {
    var themed = Quickshell.iconPath("system-run", true)
    return themed.length > 0 ? {
      kind: "image",
      source: themed
    } : {
      kind: "text",
      value: "\ud83d\ude80"
    }
  }

  // Omarchy keeps a symlink pointing at the background in use; following it
  // is a plain file read, so the cards get the real wallpaper without a
  // process or a poll.
  readonly property string wallpaperUrl: {
    var home = String(Quickshell.env("HOME") || "")
    return home.length > 0 ? Util.fileUrl(home + "/.local/state/omarchy/current/background") : ""
  }

  // ---- the view -----------------------------------------------------------

  FocusScope {
    id: keys
    objectName: "overviewKeys"
    anchors.fill: parent
    // One switch for the whole view: with the settings on top, no card takes
    // a click and no arrow key moves the selection behind them.
    enabled: !root.suspended
    focus: !root.suspended

    Keys.onPressed: function (event) {
      if (event.key === Qt.Key_Escape) {
        root.beginClose()
        event.accepted = true
        return
      }
      if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
        root.openSelection()
        event.accepted = true
        return
      }
      // Reaching here at all means the search field isn't focused - once
      // it is, "/" just types a literal slash into it like anything else.
      if (event.key === Qt.Key_Slash) {
        root.focusSearch()
        event.accepted = true
        return
      }
      var direction = root.directionFor(event)
      if (direction.length > 0) {
        root.moveSelection(direction)
        event.accepted = true
      }
    }

    // The wheel walks the cards, one per notch - the pointer's version of the
    // arrow keys, for when the hand is already on the mouse.
    //
    // Only here, and deliberately not on the bar widget: a stray notch over
    // the bar would switch workspace outright, which is a far bigger surprise
    // than moving a selection you can still see before pressing Enter. For
    // the same reason this moves the selection rather than switching: the
    // overview's own model is "pick, then open".
    WheelHandler {
      objectName: "selectionWheelHandler"
      onWheel: function (event) {
        root.scrollSelection(event.angleDelta.y)
      }
    }

    // The real desktop is still right behind this surface, so it gets dimmed
    // well past the usual menu scrim: otherwise the actual windows compete
    // with their own previews and neither reads.
    Rectangle {
      objectName: "backdrop"
      anchors.fill: parent
      color: Color.background
      opacity: root.closing || !root.active ? 0 : 0.88

      Behavior on opacity {
        NumberAnimation {
          duration: root.animationDuration
          easing.type: Easing.OutCubic
        }
      }
    }

    // Clicking past the cards closes the overview, the same as Escape - and
    // the same way round, so the cards shrink away rather than blinking out.
    MouseArea {
      objectName: "backdropMouseArea"
      anchors.fill: parent
      onClicked: root.beginClose()
    }

    // Floats over the corner rather than taking a row of its own: the cards
    // are worth more space than a toolbar would be. It carries its own
    // background so it stays readable over whatever card ends up behind it.
    Rectangle {
      id: settingsButton
      objectName: "settingsButton"
      anchors.top: parent.top
      anchors.right: parent.right
      anchors.margins: root.gap
      z: 2
      width: Style.space(40)
      height: Style.space(40)
      radius: width / 2
      color: Color.menu.background
      border.width: Math.max(1, Style.space(2))
      border.color: settingsArea.containsMouse ? Color.bar.active : Color.menu.border
      opacity: root.closing || !root.active ? 0 : (settingsArea.containsMouse ? 1 : 0.75)

      Behavior on opacity {
        NumberAnimation {
          duration: root.animationDuration
          easing.type: Easing.OutCubic
        }
      }

      // A themed icon rather than a Nerd Font glyph, which would silently
      // fall back to a tofu box on a bar font that doesn't carry one; the
      // gear character is the fallback if the icon theme has no such entry.
      IconImage {
        objectName: "settingsIcon"
        anchors.centerIn: parent
        implicitSize: Math.round(parent.width * 0.55)
        width: implicitSize
        height: implicitSize
        asynchronous: true
        visible: root.settingsIcon.kind === "image"
        source: root.settingsIcon.kind === "image" ? root.settingsIcon.source : ""
      }

      Text {
        objectName: "settingsGlyph"
        anchors.centerIn: parent
        textFormat: Text.PlainText
        visible: root.settingsIcon.kind === "text"
        text: root.settingsIcon.kind === "text" ? root.settingsIcon.value : ""
        color: Color.menu.text
        font.family: Style.font.family
        font.pixelSize: Math.round(settingsButton.width * 0.5)
      }

      MouseArea {
        id: settingsArea
        objectName: "settingsMouseArea"
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: root.settingsRequested()
      }
    }

    // Always on screen, not just once summoned: "/" only moves keyboard
    // focus into it (same reasoning as the settings gear and save button
    // staying visible rather than needing a menu to find them first).
    // Every window's own thumb dims unless it matches, so a window that's
    // hard to place by eye is still findable by title or app.
    Rectangle {
      id: searchBar
      objectName: "searchBar"
      anchors.top: parent.top
      anchors.horizontalCenter: parent.horizontalCenter
      anchors.margins: root.gap
      z: 2
      width: Math.min(Style.space(360), parent.width - Style.space(96))
      height: Style.space(40)
      radius: height / 2
      color: Color.menu.background
      opacity: root.closing || !root.active ? 0 : 1
      border.width: Math.max(1, Style.space(2))
      border.color: searchInput.activeFocus ? Color.bar.active : Color.menu.border

      Behavior on opacity {
        NumberAnimation {
          duration: root.animationDuration
          easing.type: Easing.OutCubic
        }
      }

      TextField {
        id: searchInput
        objectName: "searchInput"
        anchors.fill: parent
        anchors.leftMargin: Style.space(16)
        anchors.rightMargin: Style.space(16)
        background: null
        placeholderText: "Search windows..."
        foreground: Color.menu.text
        onTextChanged: root.searchQuery = text
        onAccepted: root.openFirstSearchMatch()

        Keys.onPressed: function (event) {
          if (event.key === Qt.Key_Escape) {
            root.clearSearch()
            event.accepted = true
          }
        }
      }
    }

    Item {
      id: grid
      objectName: "workspaceGrid"
      anchors.fill: parent
      anchors.margins: root.gap
      anchors.bottomMargin: root.gap + root.setupsStripHeight

      Repeater {
        id: cardRepeater
        objectName: "workspaceCardRepeater"
        model: root.workspaceIds

        Item {
          id: card
          objectName: "workspaceCard-" + modelData
          required property int modelData
          required property int index

          readonly property var toplevels: root.toplevelsOf(card.modelData)
          readonly property bool focused: card.modelData === root.focusedId
          readonly property bool selected: root.selectedIndex === card.index
          readonly property var monitor: root.monitorRect(root.monitorFor(card.modelData))
          readonly property var placement: root.placementAt(card.index)
          readonly property string label: card.modelData === 10 ? "0" : String(card.modelData)
          // Cards are siblings, so the one being dragged out of has to come
          // to the front or its window travels underneath the later cards.
          property bool dragging: false
          z: card.dragging ? 1 : 0

          visible: card.placement !== null
          x: card.placement ? card.placement.cellX : 0
          y: card.placement ? card.placement.cellY : 0
          width: card.placement ? card.placement.cellWidth : 0
          height: card.placement ? card.placement.cellHeight : 0

          opacity: root.closing || !root.active ? 0 : 1
          scale: root.closing || !root.active ? 0.94 : 1

          Behavior on opacity {
            NumberAnimation {
              duration: root.animationDuration
              easing.type: Easing.OutCubic
            }
          }

          Behavior on scale {
            NumberAnimation {
              duration: root.animationDuration
              easing.type: Easing.OutCubic
            }
          }

          CardSurface {
            id: cardSurface
            objectName: "cardSurface"
            width: card.placement ? card.placement.width : 0
            height: card.placement ? card.placement.height : 0
            wallpaper: root.wallpaperUrl
            focused: card.focused
            selected: card.selected
            highlighted: cardDrop.containsDrag
            caption: card.label
            captionHeight: root.captionHeight

            // Underneath the windows on purpose, so a click that lands on a
            // window acts on that window, and only the rest of the card falls
            // through to "go to this workspace".
            MouseArea {
              id: cardArea
              objectName: "cardMouseArea"
              anchors.fill: parent
              cursorShape: Qt.PointingHandCursor
              onPressed: root.selectedIndex = card.index
              onClicked: root.openWorkspace(card.modelData)
            }
          }

          // The windows sit in their own layer over the card rather than
          // inside it: the card clips - it has to, for the wallpaper and its
          // rounded corners - and a window dragged towards another workspace
          // would be cut off at the card's edge and vanish. Nothing is lost
          // by not clipping here, because cardWindowRect already trims every
          // window to the card.
          Item {
            id: windowLayer
            objectName: "cardWindowLayer"
            width: cardSurface.width
            height: cardSurface.height

            Repeater {
              objectName: "cardWindowRepeater"
              model: card.toplevels

              Item {
                id: windowSlot
                objectName: "cardWindow"
                required property var modelData

                readonly property var rect: Cards.cardWindowRect(root.windowRect(windowSlot.modelData), card.monitor, {
                  width: cardSurface.width,
                  height: cardSurface.height
                })

                // True whenever the query is empty, so a search field
                // nobody has typed into yet never dims anything.
                readonly property bool matchesSearch: root.windowMatchesSearch(windowSlot.modelData)

                visible: windowSlot.rect !== null
                x: windowSlot.rect ? windowSlot.rect.x : 0
                y: windowSlot.rect ? windowSlot.rect.y : 0
                width: windowSlot.rect ? windowSlot.rect.width : 0
                height: windowSlot.rect ? windowSlot.rect.height : 0

                // The thing that actually moves under the pointer while
                // dragging; the slot itself stays put, bound to where the
                // window really is.
                Item {
                  id: windowDragHandle
                  objectName: "windowDragHandle"
                  width: windowSlot.width
                  height: windowSlot.height

                  property var payload: ({
                      kind: "window",
                      toplevel: windowSlot.modelData
                    })

                  Drag.active: windowArea.drag.active
                  Drag.source: windowDragHandle
                  Drag.hotSpot.x: width / 2
                  Drag.hotSpot.y: height / 2

                  // Dimmed rather than hidden while searching: a window
                  // still needs to be clickable and draggable even when it
                  // doesn't match, same as before search existed at all.
                  opacity: windowSlot.matchesSearch ? 1 : 0.25

                  Behavior on opacity {
                    NumberAnimation {
                      duration: 120
                      easing.type: Easing.OutCubic
                    }
                  }

                  WindowThumb {
                    objectName: "cardThumb"
                    anchors.fill: parent
                    radius: Math.max(2, Style.cornerRadius / 2)
                    toplevel: windowSlot.modelData
                    icon: iconResolver.iconFor(windowSlot.modelData)
                    capturing: root.active && windowSlot.visible
                    // Only the workspace you are on keeps updating; every
                    // other card takes a single frame and then stops.
                    live: card.focused
                    hovered: windowArea.containsMouse
                  }

                  MouseArea {
                    id: windowArea
                    objectName: "windowMouseArea"
                    anchors.fill: parent
                    hoverEnabled: true
                    acceptedButtons: Qt.LeftButton | Qt.MiddleButton
                    cursorShape: Qt.PointingHandCursor
                    drag.target: windowDragHandle
                    drag.threshold: Style.space(8)
                    onPressed: {
                      root.selectedIndex = card.index
                      card.dragging = true
                    }
                    onClicked: function (mouse) {
                      if (mouse.button === Qt.MiddleButton)
                        root.closeWindow(windowSlot.modelData)
                      else
                        root.openWindow(windowSlot.modelData)
                    }
                    onReleased: {
                      windowDragHandle.Drag.drop()
                      windowDragHandle.x = 0
                      windowDragHandle.y = 0
                      card.dragging = false
                    }
                  }
                }
              }
            }
          }

          // A workspace's own save button, in its corner - the gear top-right
          // of the whole screen is for this plugin's settings, not for saving
          // one particular workspace. Declared after the window layer, same
          // reasoning as the gear: it has to stay clickable no matter what a
          // busy card is showing underneath it.
          Rectangle {
            id: saveButton
            objectName: "saveButton"
            anchors.top: cardSurface.top
            anchors.left: cardSurface.left
            anchors.margins: Math.max(Style.space(6), Math.min(cardSurface.width, cardSurface.height) * 0.03)
            z: 1
            readonly property int size: Math.round(Math.max(Style.space(22), Math.min(cardSurface.width, cardSurface.height) * 0.12))
            width: size
            height: size
            radius: width / 2
            color: Color.menu.background
            border.width: Math.max(1, Style.space(2))
            border.color: saveArea.containsMouse ? Color.bar.active : Color.menu.border
            opacity: root.closing || !root.active ? 0 : (saveArea.containsMouse ? 1 : 0.75)

            Behavior on opacity {
              NumberAnimation {
                duration: root.animationDuration
                easing.type: Easing.OutCubic
              }
            }

            // A themed icon rather than a Nerd Font glyph, same reasoning as
            // the settings gear: a bar font with no such glyph would draw a
            // tofu box instead. A floppy disk is the fallback.
            IconImage {
              objectName: "saveIcon"
              anchors.centerIn: parent
              implicitSize: Math.round(parent.width * 0.55)
              width: implicitSize
              height: implicitSize
              asynchronous: true
              visible: root.saveIcon.kind === "image"
              source: root.saveIcon.kind === "image" ? root.saveIcon.source : ""
            }

            Text {
              objectName: "saveGlyph"
              anchors.centerIn: parent
              textFormat: Text.PlainText
              visible: root.saveIcon.kind === "text"
              text: root.saveIcon.kind === "text" ? root.saveIcon.value : ""
              font.family: Style.font.family
              font.pixelSize: Math.round(saveButton.width * 0.55)
            }

            MouseArea {
              id: saveArea
              objectName: "saveMouseArea"
              anchors.fill: parent
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              onClicked: root.saveRequested(card.modelData)
            }
          }

          // Dropping a window here moves it to this workspace; dropping
          // another card here reorders the workspaces.
          DropArea {
            id: cardDrop
            objectName: "cardDropArea"
            width: cardSurface.width
            height: cardSurface.height
            onDropped: function (drop) {
              var payload = root.payloadOf(drop)
              if (!payload)
                return
              if (payload.kind === "window") {
                // Dropped back where it came from: nothing to ask Hyprland.
                if (card.toplevels.indexOf(payload.toplevel) === -1)
                  root.moveWindowToWorkspace(payload.toplevel, card.modelData)
                drop.accept()
              } else if (payload.kind === "workspace") {
                root.reorderWorkspaces(payload.index, card.index)
                drop.accept()
              } else if (payload.kind === "setup") {
                root.dropSetup(payload.name, card.modelData)
                drop.accept()
              }
            }
          }

          // Reordering is dragged by the number under the card, not by the
          // card itself: on a busy workspace the windows cover every pixel of
          // it, leaving nothing to grab. The number is always free, and
          // dragging it can't be mistaken for dragging a window.
          MouseArea {
            objectName: "cardHandleMouseArea"
            x: cardSurface.captionArea.x
            y: cardSurface.y + cardSurface.height
            width: cardSurface.captionArea.width
            height: cardSurface.captionArea.height
            cursorShape: Qt.SizeAllCursor
            drag.target: cardDragHandle
            drag.threshold: Style.space(6)
            onPressed: {
              root.selectedIndex = card.index
              card.dragging = true
            }
            onClicked: root.openWorkspace(card.modelData)
            onReleased: {
              cardDragHandle.Drag.drop()
              cardDragHandle.x = 0
              cardDragHandle.y = 0
              card.dragging = false
            }

            // What actually travels under the pointer; the card stays pinned
            // to the grid.
            Item {
              id: cardDragHandle
              objectName: "cardDragHandle"
              width: cardSurface.width
              height: cardSurface.height

              property var payload: ({
                  kind: "workspace",
                  index: card.index,
                  id: card.modelData
                })

              Drag.active: parent.drag.active
              Drag.source: cardDragHandle
              Drag.hotSpot.x: width / 2
              Drag.hotSpot.y: height / 2
            }
          }
        }
      }

      // The "+" card, in the last cell: opens the next workspace along, and
      // takes a dropped window straight there.
      Item {
        id: addCard
        objectName: "addWorkspaceCard"

        readonly property var placement: root.placementAt(root.workspaceIds.length)
        readonly property bool selected: root.selectedIndex === root.workspaceIds.length
        readonly property bool available: root.newWorkspaceId > 0

        visible: addCard.placement !== null
        x: addCard.placement ? addCard.placement.cellX : 0
        y: addCard.placement ? addCard.placement.cellY : 0
        width: addCard.placement ? addCard.placement.cellWidth : 0
        height: addCard.placement ? addCard.placement.cellHeight : 0

        opacity: root.closing || !root.active ? 0 : (addCard.available ? 1 : 0.4)
        scale: root.closing || !root.active ? 0.94 : 1

        Behavior on opacity {
          NumberAnimation {
            duration: root.animationDuration
            easing.type: Easing.OutCubic
          }
        }

        Behavior on scale {
          NumberAnimation {
            duration: root.animationDuration
            easing.type: Easing.OutCubic
          }
        }

        CardSurface {
          id: addSurface
          objectName: "addCardSurface"
          width: addCard.placement ? addCard.placement.width : 0
          height: addCard.placement ? addCard.placement.height : 0
          empty: true
          selected: addCard.selected
          highlighted: addDrop.containsDrag
          // The number it will make, so it says where you are about to land
          // rather than just "somewhere new".
          caption: addCard.available ? String(root.newWorkspaceId === 10 ? "0" : root.newWorkspaceId) : ""
          captionHeight: root.captionHeight

          Text {
            objectName: "addCardLabel"
            anchors.centerIn: parent
            textFormat: Text.PlainText
            text: "+"
            color: Color.menu.text
            opacity: 0.8
            font.family: Style.font.family
            font.pixelSize: Math.max(Style.font.title, Math.round(addSurface.height * 0.3))
          }

          MouseArea {
            objectName: "addCardMouseArea"
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onPressed: root.selectedIndex = root.workspaceIds.length
            onClicked: root.openWorkspace(root.newWorkspaceId)
          }
        }

        DropArea {
          id: addDrop
          objectName: "addCardDropArea"
          width: addSurface.width
          height: addSurface.height
          onDropped: function (drop) {
            var payload = root.payloadOf(drop)
            if (!payload || !addCard.available)
              return
            if (payload.kind === "window") {
              root.moveWindowToWorkspace(payload.toplevel, root.newWorkspaceId)
              drop.accept()
              return
            }
            if (payload.kind !== "setup")
              return
            root.dropSetup(payload.name, root.newWorkspaceId)
            drop.accept()
          }
        }
      }
    }

    // Closes whichever boot picker is open on a click anywhere else. Declared
    // before the strip (and so painted, and hit-tested, under it) so a click
    // on a chip's own controls - including the picker's own surface, which
    // has its own click-swallowing MouseArea - reaches those instead of
    // closing the picker out from under it; same ordering Overlay.qml uses
    // for the settings/save card's backdrop.
    MouseArea {
      objectName: "bootPopoverDismissArea"
      anchors.fill: parent
      visible: root.bootPopoverFor.length > 0
      enabled: visible
      onClicked: root.bootPopoverFor = ""
    }

    // What the strip says before there is anything in it. Points at the one
    // control that fills it, rather than describing setups in the abstract.
    Text {
      objectName: "setupsEmptyHint"
      visible: root.setupNames.length === 0
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.bottom: parent.bottom
      anchors.margins: root.gap
      horizontalAlignment: Text.AlignHCenter
      elide: Text.ElideRight
      textFormat: Text.PlainText
      text: "Save a workspace with the button in a card's top-left corner, and it turns up here to reopen later."
      color: Color.menu.text
      opacity: root.closing || !root.active ? 0 : 0.6
      font.family: Style.font.family
      font.pixelSize: Style.font.caption

      Behavior on opacity {
        NumberAnimation {
          duration: root.animationDuration
          easing.type: Easing.OutCubic
        }
      }
    }

    // A row of saved setups along the bottom, each draggable onto a
    // workspace card or "+". Only takes screen space once something is
    // actually saved.
    Item {
      id: setupsStrip
      objectName: "setupsStrip"
      visible: root.setupNames.length > 0
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.bottom: parent.bottom
      anchors.margins: root.gap
      height: root.setupsStripHeight

      readonly property int chipSpacing: Style.space(10)

      // Chips divide up the room the strip has rather than each insisting on
      // the same fixed width. At a fixed width the strip simply runs past the
      // screen edge once there are more than about a dozen setups, and the
      // ones out there can't be clicked or dragged at all - they aren't on
      // screen. Sharing the width keeps every setup reachable.
      //
      // A Flickable would be the other way to do this, but not here: the boot
      // picker opens *above* the strip and a chip being dragged leaves it
      // entirely, so the clipping a Flickable needs would cut off both.
      //
      // The floor is where a name stops being readable; past that many setups
      // the strip does overflow again. That is a far higher ceiling than
      // before rather than no ceiling at all.
      readonly property int chipWidth: {
        var count = root.setupNames.length
        if (count <= 0)
          return Style.space(150)
        var available = setupsStrip.width - setupsStrip.chipSpacing * (count - 1)
        return Math.max(Style.space(72), Math.min(Style.space(150), Math.floor(available / count)))
      }

      // The app icons are the first thing to go when chips get tight: the
      // name is what tells two setups apart, the icons only hint at what is
      // in one. Dropping them keeps the name legible instead of squeezing
      // both into a chip too narrow for either.
      readonly property bool chipsShowIcons: setupsStrip.chipWidth >= Style.space(110)

      Row {
        anchors.fill: parent
        spacing: setupsStrip.chipSpacing

        Repeater {
          id: setupChipRepeater
          objectName: "setupChipRepeater"
          model: root.setupNames

          Item {
            id: chipSlot
            objectName: "setupChipSlot-" + chipSlot.modelData
            required property string modelData

            width: setupsStrip.chipWidth
            height: setupsStrip.height

            readonly property var setupEntry: root.store ? root.store.setups[chipSlot.modelData] : null
            readonly property var setupWindowClasses: {
              var list = []
              var windows = (chipSlot.setupEntry && chipSlot.setupEntry.windows) || []
              for (var i = 0; i < windows.length && i < 6; i++)
                list.push(windows[i].class)
              return list
            }
            readonly property int bootWorkspace: (chipSlot.setupEntry && chipSlot.setupEntry.bootWorkspace) || 0
            readonly property bool bootPopoverOpen: root.bootPopoverFor === chipSlot.modelData

            // The thing that actually moves under the pointer while
            // dragging; the slot itself stays put, same pattern as a
            // window or a workspace card.
            Item {
              id: chipHandle
              objectName: "setupChipHandle"
              width: chipSlot.width
              height: chipSlot.height

              property var payload: ({
                  kind: "setup",
                  name: chipSlot.modelData
                })

              Drag.active: chipArea.drag.active
              Drag.source: chipHandle
              Drag.hotSpot.x: width / 2
              Drag.hotSpot.y: height / 2

              Rectangle {
                id: chipSurface
                objectName: "setupChipSurface"
                anchors.fill: parent
                radius: Style.cornerRadius
                color: Color.menu.background
                border.width: Math.max(1, Style.space(2))
                border.color: chipArea.containsMouse ? Color.bar.active : Color.menu.border

                Column {
                  anchors.centerIn: parent
                  spacing: Style.space(4)

                  Text {
                    objectName: "setupChipName"
                    anchors.horizontalCenter: parent.horizontalCenter
                    textFormat: Text.PlainText
                    text: chipSlot.modelData
                    color: Color.menu.text
                    font.family: Style.font.family
                    font.pixelSize: Style.font.body
                    elide: Text.ElideRight
                    width: Math.min(implicitWidth, chipSlot.width - Style.space(16))
                  }

                  Row {
                    anchors.horizontalCenter: parent.horizontalCenter
                    spacing: Style.space(3)
                    visible: setupsStrip.chipsShowIcons

                    Repeater {
                      objectName: "setupChipIconRepeater"
                      model: setupsStrip.chipsShowIcons ? chipSlot.setupWindowClasses : []

                      Item {
                        id: iconSlot
                        required property string modelData
                        width: Style.space(14)
                        height: Style.space(14)

                        readonly property var icon: iconResolver.iconForKey(iconSlot.modelData)

                        IconImage {
                          anchors.fill: parent
                          implicitSize: parent.width
                          asynchronous: true
                          visible: iconSlot.icon.kind === "image"
                          source: iconSlot.icon.kind === "image" ? iconSlot.icon.source : ""
                        }

                        Text {
                          anchors.centerIn: parent
                          textFormat: Text.PlainText
                          visible: iconSlot.icon.kind === "text"
                          text: iconSlot.icon.kind === "text" ? iconSlot.icon.value : ""
                          font.family: Style.font.family
                          font.pixelSize: iconSlot.width
                          color: Color.menu.text
                        }
                      }
                    }
                  }
                }
              }
            }

            MouseArea {
              id: chipArea
              objectName: "setupChipMouseArea"
              anchors.fill: parent
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              drag.target: chipHandle
              drag.threshold: Style.space(8)
              onClicked: root.openSetupFromChip(chipSlot.modelData)
              onReleased: {
                chipHandle.Drag.drop()
                chipHandle.x = 0
                chipHandle.y = 0
              }
            }

            // Declared last so it stays clickable over the chip's own
            // drag/click area, same reasoning as every other corner button
            // here.
            Rectangle {
              id: deleteButton
              objectName: "setupDeleteButton"
              anchors.top: parent.top
              anchors.right: parent.right
              anchors.margins: Style.space(4)
              width: Style.space(20)
              height: Style.space(20)
              radius: width / 2
              color: deleteArea.containsMouse ? Color.urgent : Color.menu.background
              border.width: Math.max(1, Style.space(1))
              border.color: Color.menu.border

              Text {
                anchors.centerIn: parent
                textFormat: Text.PlainText
                text: "×"
                color: Color.menu.text
                font.family: Style.font.family
                font.pixelSize: Style.font.body
              }

              MouseArea {
                id: deleteArea
                objectName: "setupDeleteMouseArea"
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: root.requestDeleteSetup(chipSlot.modelData)
              }
            }

            // Mirrors the delete button on the opposite corner - shows the
            // workspace this setup opens on at boot, or a themed icon (with
            // a glyph fallback, same reasoning as the gear/save icons) while
            // it's off. Opens a picker instead of cycling through values
            // itself: which workspace to boot onto isn't a two-state thing.
            Rectangle {
              id: bootButton
              objectName: "setupBootButton"
              anchors.top: parent.top
              anchors.left: parent.left
              anchors.margins: Style.space(4)
              width: Style.space(20)
              height: Style.space(20)
              radius: width / 2
              color: chipSlot.bootPopoverOpen ? Color.accent : (bootArea.containsMouse ? Color.bar.active : Color.menu.background)
              border.width: Math.max(1, Style.space(1))
              border.color: Color.menu.border

              IconImage {
                objectName: "bootIcon"
                anchors.fill: parent
                anchors.margins: Style.space(3)
                asynchronous: true
                visible: chipSlot.bootWorkspace === 0 && root.bootIcon.kind === "image"
                source: chipSlot.bootWorkspace === 0 && root.bootIcon.kind === "image" ? root.bootIcon.source : ""
              }

              // A Nerd Font glyph would silently render as a tofu box on a
              // theme font that doesn't carry one - same reasoning as the
              // gear/save icons.
              Text {
                objectName: "bootGlyph"
                anchors.centerIn: parent
                textFormat: Text.PlainText
                visible: chipSlot.bootWorkspace === 0 && root.bootIcon.kind === "text"
                text: root.bootIcon.kind === "text" ? root.bootIcon.value : ""
                color: chipSlot.bootPopoverOpen ? Color.menu.background : Color.menu.text
                font.family: Style.font.family
                font.pixelSize: Style.font.caption
              }

              Text {
                objectName: "bootNumber"
                anchors.centerIn: parent
                textFormat: Text.PlainText
                visible: chipSlot.bootWorkspace > 0
                text: chipSlot.bootWorkspace === 10 ? "0" : String(chipSlot.bootWorkspace)
                color: chipSlot.bootPopoverOpen ? Color.menu.background : Color.menu.text
                font.family: Style.font.family
                font.pixelSize: Style.font.caption
              }

              MouseArea {
                id: bootArea
                objectName: "setupBootMouseArea"
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: root.toggleBootPopover(chipSlot.modelData)
              }
            }

            // The picker itself: "off" plus every workspace, above the chip
            // so it has room regardless of how full the card area below is.
            Rectangle {
              id: bootPopover
              objectName: "setupBootPopover"
              visible: chipSlot.bootPopoverOpen
              z: 50
              anchors.bottom: chipSlot.top
              anchors.horizontalCenter: chipSlot.horizontalCenter
              anchors.bottomMargin: Style.space(6)
              width: bootGrid.implicitWidth + Style.spacing.panelPadding
              height: bootGrid.implicitHeight + Style.spacing.panelPadding
              radius: Style.cornerRadius
              color: Color.menu.background
              border.width: Math.max(1, Style.space(2))
              border.color: Color.menu.border

              // Clicks inside must not reach the dismiss layer behind it.
              MouseArea {
                anchors.fill: parent
                onClicked: {}
              }

              Grid {
                id: bootGrid
                objectName: "setupBootGrid"
                anchors.centerIn: parent
                columns: 4
                spacing: Style.spacing.xs

                Repeater {
                  objectName: "setupBootOptionRepeater"
                  model: [0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10]

                  Rectangle {
                    id: bootOption
                    objectName: "setupBootOption-" + bootOption.modelData
                    required property int modelData
                    readonly property bool selected: chipSlot.bootWorkspace === bootOption.modelData

                    width: Style.space(26)
                    height: Style.space(26)
                    radius: Style.cornerRadius
                    color: bootOption.selected ? Color.accent : "transparent"
                    border.width: Math.max(1, Style.space(1))
                    border.color: bootOption.selected ? Color.accent : Color.menu.border

                    Text {
                      anchors.centerIn: parent
                      textFormat: Text.PlainText
                      text: bootOption.modelData === 0 ? "off" : (bootOption.modelData === 10 ? "0" : String(bootOption.modelData))
                      color: bootOption.selected ? Color.menu.background : Color.menu.text
                      font.family: Style.font.family
                      font.pixelSize: Style.font.caption
                    }

                    MouseArea {
                      anchors.fill: parent
                      cursorShape: Qt.PointingHandCursor
                      onClicked: root.setBootWorkspace(chipSlot.modelData, bootOption.modelData)
                    }
                  }
                }
              }
            }
          }
        }
      }
    }

    ConfirmDialog {
      id: deleteConfirm
      objectName: "deleteConfirmDialog"
      anchors.fill: parent
      opened: root.pendingDeleteName.length > 0
      message: "Delete “" + root.pendingDeleteName + "”? This can't be undone."
      confirmText: "Delete"
      onConfirmed: root.confirmDeleteSetup()
      onCanceled: root.cancelDeleteSetup()
    }
  }
}
