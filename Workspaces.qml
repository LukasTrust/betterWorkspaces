import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import Quickshell.Widgets
import qs.Commons
import qs.Ui

import "logic.js" as Logic

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

  // What Hyprland currently has, in the shape logic.js works on. Reading
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

  readonly property var candidateWorkspaceIds: Logic.computeWorkspaceIds(root.workspaceModel(), {
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
    if (!Logic.sameIds(root.candidateWorkspaceIds, root.workspaceIds))
      root.workspaceIds = root.candidateWorkspaceIds
  }

  function focusWorkspace(id) {
    if (!root.bar)
      return
    root.bar.run("hyprctl dispatch " + Util.shellQuote("hl.dsp.focus({ workspace = \"" + id + "\" })"))
  }

  // ---- per-window interaction -------------------------------------------

  function windowTitle(toplevel) {
    if (!toplevel)
      return ""
    return String(toplevel.title || (toplevel.wayland ? toplevel.wayland.title : "") || "")
  }

  // The foreign-toplevel activate request is what every other widget uses
  // (ActiveWindow, Tray) and works even across monitors. It can be missing
  // for a toplevel Hyprland hasn't matched to a wlr handle yet, so fall back
  // to Hyprland's own dispatcher by address - this is the classic
  // `hyprctl dispatch focuswindow` selector, not the Lua `hl.dsp` table,
  // since there is no confirmed Lua equivalent for focusing by address.
  function activateWindow(toplevel) {
    if (!toplevel)
      return
    if (toplevel.wayland && typeof toplevel.wayland.activate === "function") {
      toplevel.wayland.activate()
      return
    }
    if (!root.bar || !toplevel.address)
      return
    root.bar.run("hyprctl dispatch focuswindow " + Util.shellQuote("address:" + toplevel.address))
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

  // ---- icon resolution --------------------------------------------------
  //
  // Icon source, in order: a user override from this widget's shell.json
  // entry, then the icon of the installed app whose desktop entry best
  // matches the window's class, then a generic executable icon. Resolved
  // icons are cached by window class (not per-window), so opening a second
  // terminal or a second browser window never repeats the lookup.

  // Ranges and fallbacks live in logic.js (SETTING_FIELDS), so the edit view
  // and this clamping can't drift apart.
  readonly property int maxIcons: Logic.clampSetting("maxIcons", setting("maxIcons", null))
  readonly property int iconSize: Logic.clampSetting("iconSize", setting("iconSize", null))
  readonly property int minWorkspaces: Logic.clampSetting("minWorkspaces", setting("minWorkspaces", null))
  readonly property bool hideEmpty: Logic.clampSetting("hideEmpty", setting("hideEmpty", null))
  readonly property bool groupApps: Logic.clampSetting("groupApps", setting("groupApps", null))

  property var _iconCache: ({})

  function clearIconCache() {
    root._iconCache = ({})
  }

  // The user's app list can change (installs/uninstalls); drop the cache so
  // affected windows re-resolve instead of keeping a stale fallback icon.
  Connections {
    target: DesktopEntries
    function onApplicationsChanged() {
      root.clearIconCache()
    }
  }

  // shell.json edits (e.g. to the "icons" overrides) hot-reload into
  // `settings` - drop the cache so they take effect immediately.
  onSettingsChanged: root.clearIconCache()

  // Hyprland's own "class" (from hyprctl) is preferred over the wlr-toplevel
  // appId: some XWayland apps report an empty wayland appId while hyprctl
  // still reports a class, and this is what icon overrides are keyed by.
  function windowKey(toplevel) {
    if (!toplevel)
      return ""
    var ipc = toplevel.lastIpcObject || {}
    return Logic.computeWindowKey(ipc.class, ipc.initialClass, toplevel.wayland ? toplevel.wayland.appId : "")
  }

  // Turns a raw icon value (a user override or a DesktopEntry.icon) into
  // either a themed/file image source, or - if it doesn't resolve to an
  // icon-theme entry - plain text. This lets a user override with either an
  // icon-theme name or a literal glyph/emoji in shell.json.
  function classifyIconValue(value) {
    return Logic.classifyIconValue(value, function (name) {
      return Quickshell.iconPath(name, true)
    })
  }

  // Reads this widget's "icons" map from its shell.json layout entry, e.g.:
  //   { "id": "better-workspaces", "icons": { "firefox": "󰍬" } }
  function userIconOverride(key) {
    var overrides = root.settings ? root.settings.icons : null
    return Logic.lookupIconOverride(overrides, key)
  }

  readonly property var fallbackIcon: ({
      kind: "image",
      source: Quickshell.iconPath("application-x-executable", true)
    })

  function iconForWindow(toplevel) {
    var key = root.windowKey(toplevel)
    if (key.length === 0)
      return root.fallbackIcon

    var cacheKey = key.toLowerCase()
    var cached = root._iconCache[cacheKey]
    if (cached !== undefined)
      return cached

    var resolved = root.classifyIconValue(root.userIconOverride(key))
    if (!resolved) {
      // An exact desktop-id match (e.g. window class "zen" -> zen.desktop)
      // beats the fuzzy heuristic: heuristicLookup scores by name/exec
      // similarity and can under-match a short, generic-looking class like
      // "zen" even though the id match is exact and free.
      var entry = DesktopEntries.byId(key) || DesktopEntries.heuristicLookup(key)
      if (entry && entry.icon)
        resolved = root.classifyIconValue(entry.icon)
    }
    if (!resolved)
      resolved = root.fallbackIcon

    root._iconCache[cacheKey] = resolved
    return resolved
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
        groupApps: root.groupApps
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
    columnSpacing: root.vertical ? 0 : Style.space(2)
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
        readonly property var iconGroups: root.groupApps ? Logic.groupToplevels(toplevels, root.windowKey) : toplevels.map(function (toplevel) {
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
          onClicked: root.focusWorkspace(cell.modelData)
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
                    width: root.iconSize
                    height: root.iconSize

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
                  onEntered: if (root.bar) root.bar.showTooltip(iconSlot, iconSlot.windowTitle)
                  onExited: if (root.bar) root.bar.hideTooltip(iconSlot)
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
