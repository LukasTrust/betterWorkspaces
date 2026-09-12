import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Widgets
import qs.Commons

import "logic.js" as Logic

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

  // The scoped shell facade the overlay was handed; unused so far, but the
  // saved setups in the next feature are read and written through it.
  property var shell: null
  // This widget's shell.json entry, so the overview shows the same
  // workspaces and the same icons the bar does.
  property var settings: ({})
  // False while the overlay is hidden: tears every screencopy down, so
  // nothing is captured off the screen in the background.
  property bool active: false

  // False while the settings card sits on top: the cards stay on screen and
  // keep their previews - the settings change what they show, so seeing them
  // change is the point - but they stop taking clicks and keys.
  property bool suspended: false

  signal closeRequested
  signal settingsRequested
  // Emitted for every Hyprland request, so the tests can read what a click
  // or a drop actually asked for.
  signal dispatched(string request)

  readonly property int minWorkspaces: Logic.clampSetting("minWorkspaces", Logic.settingValue(root.settings, "minWorkspaces"))
  readonly property bool hideEmpty: Logic.clampSetting("hideEmpty", Logic.settingValue(root.settings, "hideEmpty"))
  readonly property bool gameIcons: Logic.clampSetting("gameIcons", Logic.settingValue(root.settings, "gameIcons"))

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
    return Logic.computeWorkspaceIds(model, {
      minWorkspaces: root.minWorkspaces,
      hideEmpty: root.hideEmpty,
      focusedId: root.focusedId
    })
  }

  readonly property int newWorkspaceId: Logic.nextWorkspaceId(root.workspaceIds)

  // Geometry to measure window positions against. A workspace carries its
  // own monitor; the focused one stands in for a workspace Hyprland hasn't
  // placed yet.
  function monitorFor(id) {
    var workspace = root.workspaceById(id)
    return (workspace && workspace.monitor) || Hyprland.focusedMonitor
  }

  function monitorRect(monitor) {
    if (!monitor)
      return { x: 0, y: 0, width: root.width, height: root.height }
    return {
      x: monitor.x,
      y: monitor.y,
      width: monitor.width,
      height: monitor.height
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
  // out a window other than the focused one; logic.js builds that selector,
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
    return "hl.dsp.window.move({ workspace = \"" + id + "\", window = \"" + Logic.windowSelector(address) + "\", follow = false })"
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
      root.dispatch("hl.dsp.focus({ window = \"" + Logic.windowSelector(toplevel.address) + "\" })")
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

  // Hyprland can't renumber a workspace, so a card dragged onto another one
  // moves the windows instead; logic.js works out which window ends up where
  // before any of them moves.
  function reorderWorkspaces(fromIndex, toIndex) {
    var cards = []
    for (var i = 0; i < root.workspaceIds.length; i++) {
      var toplevels = root.toplevelsOf(root.workspaceIds[i])
      var addresses = []
      for (var w = 0; w < toplevels.length; w++)
        if (toplevels[w].address)
          addresses.push(String(toplevels[w].address))
      cards.push({ id: root.workspaceIds[i], addresses: addresses })
    }

    var moves = Logic.planReorder(cards, fromIndex, toIndex)
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
    closeTimer.restart()
  }

  onActiveChanged: {
    if (root.active) {
      root.closing = false
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

  // One cell per workspace plus one for the "+" card. A card is the shape of
  // the screen its workspace is on, so the windows drawn on it are the shape
  // they really are; the "+" card borrows the focused monitor's shape so it
  // sits in the grid like any other.
  readonly property var cellSizes: {
    var sizes = []
    for (var i = 0; i < root.workspaceIds.length; i++) {
      var monitor = root.monitorRect(root.monitorFor(root.workspaceIds[i]))
      sizes.push({ width: monitor.width, height: monitor.height })
    }
    var focused = root.monitorRect(Hyprland.focusedMonitor)
    sizes.push({ width: focused.width, height: focused.height })
    return sizes
  }

  // The grid maths lives in logic.js: it fits any number of rectangles of any
  // shape into the space without overlapping them and without distorting
  // them, which is exactly what a screen full of workspace cards needs.
  readonly property var layout: Logic.spreadLayout(root.cellSizes, {
    width: Math.max(0, root.width - root.gap * 2),
    height: Math.max(0, root.height - root.gap * 2)
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
    root.selectedIndex = Logic.navigateGrid(root.selectedIndex, root.cellCount, root.layout.columns, direction)
  }

  function openSelection() {
    var index = root.selectedIndex
    if (index < 0 || index >= root.cellCount)
      return
    root.openWorkspace(index < root.workspaceIds.length ? root.workspaceIds[index] : root.newWorkspaceId)
  }

  readonly property var settingsIcon: {
    var themed = Quickshell.iconPath("preferences-system", true)
    return themed.length > 0 ? { kind: "image", source: themed } : { kind: "text", value: "\u2699" }
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
      var direction = root.directionFor(event)
      if (direction.length > 0) {
        root.moveSelection(direction)
        event.accepted = true
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

    Item {
      id: grid
      objectName: "workspaceGrid"
      anchors.fill: parent
      anchors.margins: root.gap

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

                readonly property var rect: Logic.cardWindowRect(root.windowRect(windowSlot.modelData), card.monitor, {
                  width: cardSurface.width,
                  height: cardSurface.height
                })

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
                    cursorShape: Qt.PointingHandCursor
                    drag.target: windowDragHandle
                    drag.threshold: Style.space(8)
                    onPressed: {
                      root.selectedIndex = card.index
                      card.dragging = true
                    }
                    onClicked: root.openWindow(windowSlot.modelData)
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
            if (!payload || payload.kind !== "window" || !addCard.available)
              return
            root.moveWindowToWorkspace(payload.toplevel, root.newWorkspaceId)
            drop.accept()
          }
        }
      }
    }
  }
}
