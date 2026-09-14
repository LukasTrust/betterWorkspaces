import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import Quickshell.Widgets
import qs.Commons
import qs.Ui

import "../js/selector.js" as Selector
import "../js/icons.js" as Icons
import "../js/settings.js" as Settings

// Drop-in replacement for omarchy.workspaces that also shows a small icon
// for every window open on each workspace - "what's actually in there" at
// a glance
//
// Everything here is plain property bindings driven by Hyprland's IPC event
// stream (no polling, no external processes), and icon lookups are resolved
// once per window class and cached, so this stays cheap even with many
// windows open across many workspaces.
BarWidget {
  id: root
  moduleName: "better-workspaces"

  function workspaceById(id) {
    var values = Hyprland.workspaces.values
    for (var i = 0; i < values.length; i++) {
      if (values[i].id === id)
        return values[i]
    }

    return null
  }

  // What Hyprland currently has, in the shape settings.js works on. Reading
  // each workspace's windows here is what lets `hideEmpty` follow windows
  // opening and closing without any polling: the binding below depends on
  // everything this touches and re-runs when any of it changes.
  function workspaceModel() {
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
    return model
  }

  readonly property var candidateWorkspaceIds: Settings.computeWorkspaceIds(root.workspaceModel(), {
    minWorkspaces: root.minWorkspaces,
    hideEmpty: root.hideEmpty,
    focusedId: Hyprland.focusedWorkspace ? Hyprland.focusedWorkspace.id : 0
  })

  // The ids actually rendered. Changing this list rebuilds every cell, so it
  // only changes when the ids really differ: with `hideEmpty` on, the
  // binding above re-runs for every window that opens or closes, and most of
  // those leave the strip exactly as it was.
  property var workspaceIds: []

  onCandidateWorkspaceIdsChanged: {
    if (!Settings.sameIds(root.candidateWorkspaceIds, root.workspaceIds))
      root.workspaceIds = root.candidateWorkspaceIds
  }

  function focusWorkspace(id) {
    if (!root.bar)
      return
    root.bar.run("hyprctl dispatch " + Util.shellQuote("hl.dsp.focus({ workspace = \"" + id + "\" })"))
  }

  // Clicking a workspace you are not on switches to it; clicking the one you
  // are already on has nothing to switch to, so it opens the overview
  // instead. That second click is the only entry point that needs no setup
  // at all - the key binding is the user's to add - which is why
  // `overviewEnabled` turns this back into a plain switch rather than
  // removing the overview itself.
  function activateWorkspace(id) {
    var alreadyThere = Hyprland.focusedWorkspace !== null && Hyprland.focusedWorkspace.id === id
    if (alreadyThere && root.overviewEnabled) {
      root.openOverview()
      return
    }
    root.focusWorkspace(id)
  }

  // The same summon the documented key binding sends, so both entry points
  // land on exactly one overlay: asking a second time while it is open
  // closes it again.
  // The scoped shell facade reaches this widget through the bar host, which
  // is also the only thing that knows this plugin's id.
  function openOverview() {
    var shell = root.bar ? root.bar.shell : null
    if (shell && typeof shell.toggle === "function")
      shell.toggle(root.moduleName, "{}")
  }

  // ---- per-window interaction -------------------------------------------

  function windowTitle(toplevel) {
    if (!toplevel)
      return ""
    return String(toplevel.title || (toplevel.wayland ? toplevel.wayland.title : "") || "")
  }

  // Hyprland's own focus dispatcher, naming the window by address - not the
  // foreign-toplevel activate request the other widgets use. Measured on a
  // live Hyprland: `wayland.activate()` marks the window active but leaves
  // the focused workspace where it was, so clicking the icon of a window on
  // another workspace did nothing you could see. The dispatcher switches.
  //
  // Omarchy configures Hyprland in Lua, where a dispatch is evaluated as
  // Lua, so this is the `hl.dsp` form: the classic `focuswindow address:...`
  // selector is a syntax error there rather than a focus. The selector comes
  // from selector.js, because Quickshell reports an address without the `0x`
  // Hyprland wants and one missing it matches nothing while still saying
  // "ok". The wlr request is the fallback for a toplevel with no address.
  function activateWindow(toplevel) {
    if (!toplevel)
      return
    if (root.bar && toplevel.address) {
      root.bar.run("hyprctl dispatch " + Util.shellQuote("hl.dsp.focus({ window = \"" + Selector.windowSelector(toplevel.address) + "\" })"))
      return
    }
    if (toplevel.wayland && typeof toplevel.wayland.activate === "function")
      toplevel.wayland.activate()
  }

  function closeWindow(toplevel) {
    if (toplevel && toplevel.wayland)
      toplevel.wayland.close()
  }

  // Joins every window's title in a group, for the group icon's tooltip. A
  // single-window group (or groupApps off, where every group has exactly
  // one window) reduces to just that window's title, same as before.
  function groupTitle(toplevels) {
    var list = toplevels || []
    var titles = []
    for (var i = 0; i < list.length; i++) {
      var title = root.windowTitle(list[i])
      if (title.length > 0)
        titles.push(title)
    }
    return titles.join("\n")
  }

  // The window a click on a group's icon should act on: the one after
  // whichever is currently focused, cycling through the group - so a
  // repeated click steps through its windows. `null` when none of the
  // group's windows is focused right now, so the caller falls back to
  // whichever it last saw focused.
  function nextGroupToplevel(toplevels) {
    var list = toplevels || []
    for (var i = 0; i < list.length; i++) {
      if (list[i].activated)
        return list[(i + 1) % list.length]
    }
    return null
  }

  // ---- settings -----------------------------------------------------------
  //
  // Ranges and fallbacks live in settings.js (SETTING_FIELDS), so the edit view
  // and this clamping can't drift apart.

  readonly property int maxIcons: Settings.clampSetting("maxIcons", setting("maxIcons", null))
  readonly property int iconSize: Settings.clampSetting("iconSize", setting("iconSize", null))
  readonly property int minWorkspaces: Settings.clampSetting("minWorkspaces", setting("minWorkspaces", null))
  readonly property bool hideEmpty: Settings.clampSetting("hideEmpty", setting("hideEmpty", null))
  readonly property bool groupApps: Settings.clampSetting("groupApps", setting("groupApps", null))
  readonly property bool gameIcons: Settings.clampSetting("gameIcons", setting("gameIcons", null))
  readonly property bool overviewEnabled: Settings.clampSetting("overviewEnabled", setting("overviewEnabled", null))

  // ---- icon resolution ----------------------------------------------------
  //
  // Shared with the overview so both show the same icon for the same window;
  // see IconResolver.qml for the lookup order and the per-class cache.

  IconResolver {
    id: iconResolver
    objectName: "iconResolver"
    settings: root.settings
    gameIcons: root.gameIcons
  }

  function windowKey(toplevel) {
    return iconResolver.windowKey(toplevel)
  }

  function iconForWindow(toplevel) {
    return iconResolver.iconFor(toplevel)
  }

  // ---- introspection ------------------------------------------------------
  //
  // `omarchy-shell better-workspaces state` prints what this widget is
  // showing right now, as JSON. It's read back from the rendered items
  // rather than recomputed, so the end-to-end tests in test/e2e check the
  // real output. Read-only; with one bar per monitor, whichever instance
  // owns the IPC target answers, and they all show the same thing.

  function renderedState() {
    var workspaces = []
    for (var i = 0; i < workspaceRepeater.count; i++) {
      var cell = workspaceRepeater.itemAt(i)
      if (!cell)
        continue
      var icons = []
      for (var j = 0; j < cell.iconItems.count; j++) {
        var slot = cell.iconItems.itemAt(j)
        if (!slot)
          continue
        icons.push({
          address: String((slot.representativeToplevel && slot.representativeToplevel.address) || ""),
          key: slot.modelData.key,
          kind: slot.icon.kind,
          icon: String(slot.icon.kind === "image" ? slot.icon.source : slot.icon.value),
          count: slot.count
        })
      }

      workspaces.push({
        id: cell.modelData,
        label: cell.label,
        focused: cell.focused,
        occupied: cell.occupied,
        windows: cell.toplevels.length,
        overflow: cell.overflowCount,
        icons: icons
      })
    }

    return {
      settings: {
        maxIcons: root.maxIcons,
        iconSize: root.iconSize,
        minWorkspaces: root.minWorkspaces,
        hideEmpty: root.hideEmpty,
        groupApps: root.groupApps,
        gameIcons: root.gameIcons,
        overviewEnabled: root.overviewEnabled
      },
      workspaces: workspaces
    }
  }

  IpcHandler {
    objectName: "ipcHandler"
    target: "better-workspaces"

    function state(): string {
      return JSON.stringify(root.renderedState())
    }
  }

  // ---- layout -------------------------------------------------------------

  readonly property real trailingGap: root.vertical ? 0 : Style.spaceReal(1.5)

  implicitWidth: grid.implicitWidth + trailingGap
  implicitHeight: grid.implicitHeight

  GridLayout {
    id: grid
    objectName: "workspaceGrid"
    anchors.fill: parent
    anchors.rightMargin: root.trailingGap
    columns: root.vertical ? 1 : Math.max(1, root.workspaceIds.length)
    // Matches the stock omarchy.workspaces spacing exactly - this widget sits
    // in the same bar, often right next to it, and a different gap between
    // workspace cells reads as a misalignment rather than a choice.
    columnSpacing: root.vertical ? 0 : Style.space(1)
    rowSpacing: root.vertical ? Style.space(2) : 0

    Repeater {
      id: workspaceRepeater
      objectName: "workspaceRepeater"
      model: root.workspaceIds

      Item {
        id: cell
        objectName: "workspaceCell-" + modelData
        required property int modelData

        readonly property var workspace: root.workspaceById(modelData)
        readonly property var toplevels: workspace ? workspace.toplevels.values : []
        readonly property bool occupied: toplevels.length > 0
        readonly property bool focused: Hyprland.focusedWorkspace !== null && Hyprland.focusedWorkspace.id === modelData
        // One entry per icon shown: a group of same-app windows with
        // `groupApps` on, otherwise every window as its own single-window
        // group - so maxIcons/overflow always count icons, not raw windows.
        readonly property var iconGroups: root.groupApps ? Icons.groupToplevels(toplevels, root.windowKey) : toplevels.map(function (toplevel) {
          return {
            key: root.windowKey(toplevel),
            toplevels: [toplevel]
          }
        })
        readonly property var shownGroups: iconGroups.slice(0, root.maxIcons)
        readonly property int overflowCount: Math.max(0, iconGroups.length - root.maxIcons)
        readonly property string label: modelData === 10 ? "0" : String(modelData)
        property alias iconItems: iconRepeater

        opacity: occupied || focused ? 1 : 0.5
        implicitWidth: root.vertical ? root.barSize : cellLayout.implicitWidth + Style.space(12)
        implicitHeight: root.vertical ? cellLayout.implicitHeight + Style.space(8) : root.barSize

        Behavior on opacity {
          NumberAnimation {
            duration: 140
            easing.type: Easing.OutCubic
          }
        }

        // Declared before cellLayout so it sits underneath in paint order:
        // it only receives clicks that fall through cellLayout's children
        // (the label, gaps, the overflow count), never ones an icon's own
        // MouseArea below already claimed.
        MouseArea {
          objectName: "workspaceMouseArea"
          anchors.fill: parent
          cursorShape: Qt.PointingHandCursor
          onClicked: root.activateWorkspace(cell.modelData)
        }

        GridLayout {
          id: cellLayout
          anchors.centerIn: parent
          flow: root.vertical ? GridLayout.TopToBottom : GridLayout.LeftToRight
          columnSpacing: Style.space(4)
          rowSpacing: Style.space(2)

          Text {
            objectName: "workspaceLabel"
            Layout.alignment: Qt.AlignCenter
            textFormat: Text.PlainText
            // A theme-color change rather than a swapped-in glyph: the
            // focus icon in the stock widget is a Nerd Font codepoint that
            // silently falls back to a tofu box on any bar font that
            // doesn't carry it (Style.font.family is themeable and not
            // guaranteed to be a Nerd Font). A color/weight change always
            // renders.
            text: cell.label
            color: cell.focused ? Color.bar.active : (root.bar ? root.bar.barForeground : Color.foreground)
            font.family: root.bar ? root.bar.fontFamily : Style.font.family
            font.pixelSize: Style.font.body
            font.bold: cell.focused
            renderType: Text.NativeRendering
          }

          RowLayout {
            Layout.alignment: Qt.AlignCenter
            // A plain Row top-aligns children, which would look off once
            // a grouped icon's chip grows taller than its plain neighbours
            // - RowLayout centers each child on the cross axis instead.
            spacing: Style.space(3)
            visible: cell.shownGroups.length > 0

            Repeater {
              id: iconRepeater
              objectName: "iconRepeater"
              model: cell.shownGroups

              Item {
                id: iconSlot
                objectName: "windowIcon"
                // { key, toplevels: [...] } - a single window unless
                // groupApps grouped it with others of the same app.
                required property var modelData
                readonly property var groupToplevels: modelData.toplevels
                readonly property int count: groupToplevels.length

                // Which of the group's windows is currently focused, if
                // any - and, since Hyprland only ever reports one window as
                // focused at a time, the last one this group had focused,
                // remembered across the focus moving elsewhere (another
                // workspace, another app). This is "the group's window" for
                // both the icon and the tooltip: focused when there is one,
                // else whichever was last, else just the first.
                readonly property var focusedToplevel: {
                  for (var i = 0; i < iconSlot.groupToplevels.length; i++) {
                    if (iconSlot.groupToplevels[i].activated)
                      return iconSlot.groupToplevels[i]
                  }
                  return null
                }
                property var lastFocusedToplevel: null
                onFocusedToplevelChanged: {
                  if (iconSlot.focusedToplevel)
                    iconSlot.lastFocusedToplevel = iconSlot.focusedToplevel
                }
                readonly property var representativeToplevel: {
                  if (iconSlot.focusedToplevel)
                    return iconSlot.focusedToplevel
                  if (iconSlot.lastFocusedToplevel && iconSlot.groupToplevels.indexOf(iconSlot.lastFocusedToplevel) !== -1)
                    return iconSlot.lastFocusedToplevel
                  return iconSlot.groupToplevels[0]
                }

                readonly property var icon: root.iconForWindow(iconSlot.representativeToplevel)
                readonly property string windowTitle: root.groupTitle(iconSlot.groupToplevels)
                // A corner circle over the icon can't fit a readable digit
                // at the default 14px icon size without shrinking it to
                // nothing. Instead, once grouped, the count sits next to
                // the icon (not on top of it) in a pill-shaped chip, at the
                // same readable size as the "+N" overflow label uses.
                readonly property bool grouped: iconSlot.count >= 2
                // The chip has to be bigger than a plain icon slot, not the
                // same size: the icon inside it still needs to render at the
                // full, un-shrunk iconSize, plus room for the count text and
                // some padding so neither is jammed against the pill's edge.
                // More padding sideways than vertically - a wide, shallow
                // pill reads calmer than a tall one.
                readonly property int chipVerticalPadding: Style.space(3)
                readonly property int chipHorizontalPadding: Style.space(8)
                // Bar.showTooltip only actually shows anything when the
                // target it's given has this exact property (it checks
                // `target.tooltipHovered === true` before doing anything) -
                // see Tray.qml/WidgetButton.qml for the same pattern. Without
                // it, showTooltip is a silent no-op: no error, no tooltip.
                readonly property bool tooltipHovered: visible && opacity > 0 && iconMouseArea.containsMouse
                // Sized directly off the icon and the count text - not off
                // Row.implicitWidth, which lays out on a deferred polish
                // pass and so wouldn't track an iconSize change in the same
                // tick, unlike every other size in this widget.
                width: iconSlot.grouped ? (root.iconSize + Style.space(3) + badgeText.implicitWidth + iconSlot.chipHorizontalPadding * 2) : root.iconSize
                height: iconSlot.grouped ? root.iconSize + iconSlot.chipVerticalPadding * 2 : root.iconSize

                // The tooltip text is a snapshot passed to bar.showTooltip,
                // not a binding, so a title change (e.g. a browser tab
                // switch) has to re-push it explicitly while still hovered.
                onWindowTitleChanged: {
                  if (root.bar && iconSlot.tooltipHovered)
                    root.bar.showTooltip(iconSlot, iconSlot.windowTitle)
                }

                Rectangle {
                  objectName: "groupBadge"
                  visible: iconSlot.grouped
                  anchors.fill: parent
                  radius: height / 2
                  color: root.bar ? root.bar.background : Color.background
                  // No border: a bordered pill is the same shape the
                  // focused workspace label uses, so drawing one here would
                  // make every group look selected regardless of which
                  // workspace is actually focused. Just a fill, dimmer off
                  // the focused workspace so it stays background info.
                  opacity: cell.focused ? 1 : 0.3
                }

                RowLayout {
                  id: chipContent
                  anchors.centerIn: parent
                  // RowLayout rather than Row so the icon and the count text
                  // are centered on top of each other despite their
                  // different heights, instead of both sitting at y: 0.
                  spacing: iconSlot.grouped ? Style.space(3) : 0

                  Item {
                    // Implicit, not plain width/height: a RowLayout sets its
                    // children's size itself, so a literal width here is the
                    // layout's to overwrite (Qt calls that undefined
                    // behaviour) rather than a size it will honour.
                    implicitWidth: root.iconSize
                    implicitHeight: root.iconSize

                    IconImage {
                      objectName: "iconImage"
                      anchors.fill: parent
                      implicitSize: root.iconSize
                      asynchronous: true
                      visible: iconSlot.icon.kind === "image"
                      source: iconSlot.icon.kind === "image" ? iconSlot.icon.source : ""
                    }

                    Text {
                      objectName: "iconText"
                      anchors.centerIn: parent
                      textFormat: Text.PlainText
                      visible: iconSlot.icon.kind === "text"
                      text: iconSlot.icon.kind === "text" ? iconSlot.icon.value : ""
                      font.family: root.bar ? root.bar.fontFamily : Style.font.family
                      font.pixelSize: root.iconSize
                      color: root.bar ? root.bar.barForeground : Color.foreground
                      renderType: Text.NativeRendering
                    }
                  }

                  Text {
                    id: badgeText
                    objectName: "groupBadgeText"
                    visible: iconSlot.grouped
                    textFormat: Text.PlainText
                    text: String(iconSlot.count)
                    font.family: root.bar ? root.bar.fontFamily : Style.font.family
                    // Style.font.caption read as too small/faint next to the
                    // icon it labels; root.iconSize was a shade too big -
                    // 4px under it lands as legible without dominating.
                    font.pixelSize: Math.max(6, root.iconSize - 4)
                    color: root.bar ? root.bar.barForeground : Color.foreground
                    renderType: Text.NativeRendering
                  }
                }

                // Sits on top of the cell-wide workspaceMouseArea below it
                // (declared first), so a click on the icon itself acts on
                // that window - or, grouped, cycles through the group's
                // windows - instead of just focusing the workspace.
                MouseArea {
                  id: iconMouseArea
                  objectName: "windowIconMouseArea"
                  anchors.fill: parent
                  hoverEnabled: true
                  acceptedButtons: Qt.LeftButton | Qt.MiddleButton
                  cursorShape: Qt.PointingHandCursor
                  onEntered: if (root.bar)
                    root.bar.showTooltip(iconSlot, iconSlot.windowTitle)
                  onExited: if (root.bar)
                    root.bar.hideTooltip(iconSlot)
                  onClicked: function (mouse) {
                    if (mouse.button === Qt.MiddleButton) {
                      root.closeWindow(iconSlot.representativeToplevel)
                    } else {
                      var next = root.nextGroupToplevel(iconSlot.groupToplevels)
                      root.activateWindow(next || iconSlot.representativeToplevel)
                    }
                  }
                }
              }
            }
          }

          Text {
            objectName: "overflowLabel"
            Layout.alignment: Qt.AlignCenter
            visible: cell.overflowCount > 0
            textFormat: Text.PlainText
            text: "+" + cell.overflowCount
            font.family: root.bar ? root.bar.fontFamily : Style.font.family
            font.pixelSize: Style.font.caption
            color: root.bar ? root.bar.barForeground : Color.foreground
            opacity: 0.7
          }
        }
      }
    }
  }
}
