import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Hyprland
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

  function workspaceIds() {
    var values = Hyprland.workspaces.values
    var existing = []
    for (var i = 0; i < values.length; i++)
      existing.push(values[i].id)
    return Logic.computeWorkspaceIds(existing)
  }

  function focusWorkspace(id) {
    if (!root.bar)
      return
    root.bar.run("hyprctl dispatch " + Util.shellQuote("hl.dsp.focus({ workspace = \"" + id + "\" })"))
  }

  // ---- icon resolution --------------------------------------------------
  //
  // Icon source, in order: a user override from this widget's shell.json
  // entry, then the icon of the installed app whose desktop entry best
  // matches the window's class, then a generic executable icon. Resolved
  // icons are cached by window class (not per-window), so opening a second
  // terminal or a second browser window never repeats the lookup.

  readonly property int maxIcons: Math.max(1, Number(setting("maxIcons", 5)))
  readonly property int iconSize: Math.max(8, Number(setting("iconSize", 14)))

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
  //   { "id": "better-workspaces", "icons": { "firefox": "󰍬", "discord": "omarchy-discord" } }
  function userIconOverride(key, appHint, title) {
    var overrides = root.settings ? root.settings.icons : null
    return Logic.lookupIconOverride(overrides, key, appHint, title)
  }

  function resolveDesktopEntry(key, appHint, initialTitle, domain) {
    if (!DesktopEntries)
      return null

    if (appHint) {
      var entry = DesktopEntries.byId(appHint) || DesktopEntries.heuristicLookup(appHint)
      if (entry && entry.icon)
        return entry
    }

    // Match installed desktop entries (such as web apps created by Omarchy)
    var apps = DesktopEntries.applications ? DesktopEntries.applications.values : []
    for (var i = 0; i < apps.length; i++) {
      var app = apps[i]
      if (!app)
        continue
      if (appHint && ((app.id && app.id.toLowerCase() === appHint.toLowerCase()) || (app.name && app.name.toLowerCase() === appHint.toLowerCase()))) {
        if (app.icon)
          return app
      }
      if (app.execString && Logic.execMatchesInitialTitle(app.execString, initialTitle, domain)) {
        if (app.icon)
          return app
      }
    }

    return DesktopEntries.byId(key) || DesktopEntries.heuristicLookup(key)
  }

  readonly property var fallbackIcon: ({
      kind: "image",
      source: Quickshell.iconPath("application-x-executable", true)
    })

  function iconForWindow(toplevel) {
    if (!toplevel)
      return root.fallbackIcon

    var ipc = toplevel.lastIpcObject || {}
    var key = root.windowKey(toplevel)
    if (key.length === 0)
      return root.fallbackIcon

    var title = String(ipc.title || (toplevel.wayland ? toplevel.wayland.title : "") || "")
    var initialTitle = String(ipc.initialTitle || "")

    var webAppInfo = Logic.detectWebApp(key, initialTitle, title)
    var cacheKey = Logic.computeCacheKey(key, title, initialTitle, webAppInfo.hint, webAppInfo.isWebApp)

    var cached = root._iconCache[cacheKey]
    if (cached !== undefined)
      return cached

    // 1. User override from shell.json (supports class, appHint, title:, and regex)
    var overrideValue = root.userIconOverride(key, webAppInfo.hint, title)
    var resolved = root.classifyIconValue(overrideValue)

    // 2. Desktop entry lookup (handles web apps, installed apps, and heuristic lookup)
    if (!resolved) {
      var entry = root.resolveDesktopEntry(key, webAppInfo.hint, initialTitle, webAppInfo.domain)
      if (entry && entry.icon)
        resolved = root.classifyIconValue(entry.icon)
    }

    // 3. Themed icon fallback for web apps (e.g. omarchy-discord or discord)
    if (!resolved && webAppInfo.hint) {
      resolved = root.classifyIconValue("omarchy-" + webAppInfo.hint)
      if (!resolved)
        resolved = root.classifyIconValue(webAppInfo.hint)
    }

    // 4. Default executable fallback icon
    if (!resolved)
      resolved = root.fallbackIcon

    root._iconCache[cacheKey] = resolved
    return resolved
  }

  // ---- layout -------------------------------------------------------------

  readonly property real trailingGap: root.vertical ? 0 : Style.spaceReal(1.5)

  implicitWidth: grid.implicitWidth + trailingGap
  implicitHeight: grid.implicitHeight

  GridLayout {
    id: grid
    anchors.fill: parent
    anchors.rightMargin: root.trailingGap
    columns: root.vertical ? 1 : root.workspaceIds().length
    columnSpacing: root.vertical ? 0 : Style.space(2)
    rowSpacing: root.vertical ? Style.space(2) : 0

    Repeater {
      model: root.workspaceIds()

      Item {
        id: cell
        required property int modelData

        readonly property var workspace: root.workspaceById(modelData)
        readonly property var toplevels: workspace ? workspace.toplevels.values : []
        readonly property bool occupied: toplevels.length > 0
        readonly property bool focused: Hyprland.focusedWorkspace !== null && Hyprland.focusedWorkspace.id === modelData
        readonly property var shownToplevels: toplevels.slice(0, root.maxIcons)
        readonly property int overflowCount: Math.max(0, toplevels.length - root.maxIcons)

        opacity: occupied || focused ? 1 : 0.5
        implicitWidth: root.vertical ? root.barSize : cellLayout.implicitWidth + Style.space(12)
        implicitHeight: root.vertical ? cellLayout.implicitHeight + Style.space(8) : root.barSize

        Behavior on opacity {
          NumberAnimation {
            duration: 140
            easing.type: Easing.OutCubic
          }
        }

        GridLayout {
          id: cellLayout
          anchors.centerIn: parent
          flow: root.vertical ? GridLayout.TopToBottom : GridLayout.LeftToRight
          columnSpacing: Style.space(4)
          rowSpacing: Style.space(2)

          Text {
            Layout.alignment: Qt.AlignCenter
            textFormat: Text.PlainText
            // A theme-color change rather than a swapped-in glyph: the
            // focus icon in the stock widget is a Nerd Font codepoint that
            // silently falls back to a tofu box on any bar font that
            // doesn't carry it (Style.font.family is themeable and not
            // guaranteed to be a Nerd Font). A color/weight change always
            // renders.
            text: cell.modelData === 10 ? "0" : String(cell.modelData)
            color: cell.focused ? Color.bar.active : (root.bar ? root.bar.barForeground : Color.foreground)
            font.family: root.bar ? root.bar.fontFamily : Style.font.family
            font.pixelSize: Style.font.body
            font.bold: cell.focused
            renderType: Text.NativeRendering
          }

          Row {
            Layout.alignment: Qt.AlignCenter
            spacing: Style.space(3)
            visible: cell.shownToplevels.length > 0

            Repeater {
              model: cell.shownToplevels

              Item {
                id: iconSlot
                required property var modelData
                readonly property var icon: root.iconForWindow(modelData)
                width: root.iconSize
                height: root.iconSize

                IconImage {
                  anchors.fill: parent
                  implicitSize: root.iconSize
                  asynchronous: true
                  visible: iconSlot.icon.kind === "image"
                  source: iconSlot.icon.kind === "image" ? iconSlot.icon.source : ""
                }

                Text {
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
            }
          }

          Text {
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

        MouseArea {
          anchors.fill: parent
          cursorShape: Qt.PointingHandCursor
          onClicked: root.focusWorkspace(cell.modelData)
        }
      }
    }
  }
}
