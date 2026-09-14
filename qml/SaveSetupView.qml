import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import qs.Commons
import qs.Ui

import "../js/logic.js" as Logic

// The save dialog, shown by Overlay.qml over a workspace's own save button.
// Windowless, like Overview.qml and SettingsView.qml, so it can be driven
// headless - the overlay supplies the layer-shell surface.
//
// The windows are only read, never touched: saving writes a snapshot to the
// setup store and nothing closes, moves or restarts anything.
Item {
  id: root

  property var settings: ({})
  // The shared setups.json store (Overlay.qml owns the one instance).
  property var store: null
  // Which workspace to save. 0 - the default - means "whatever is focused
  // right now"; a workspace's own save button always passes its real id,
  // since the one clicked isn't necessarily the one you're on.
  property int workspaceId: 0

  readonly property bool gameIcons: Logic.clampSetting("gameIcons", Logic.settingValue(root.settings, "gameIcons"))

  implicitWidth: layout.implicitWidth
  implicitHeight: layout.implicitHeight

  // ---- what's on the workspace right now -----------------------------------

  function workspaceById(id) {
    var values = Hyprland.workspaces.values
    for (var i = 0; i < values.length; i++)
      if (values[i].id === id) return values[i]
    return null
  }

  readonly property int resolvedWorkspaceId: root.workspaceId > 0 ? root.workspaceId : (Hyprland.focusedWorkspace ? Hyprland.focusedWorkspace.id : 0)
  readonly property var workspace: root.workspaceById(root.resolvedWorkspaceId)
  readonly property var toplevels: root.workspace && root.workspace.toplevels ? root.workspace.toplevels.values : []
  readonly property var monitor: (root.workspace && root.workspace.monitor) || Hyprland.focusedMonitor
  readonly property var monitorArea: {
    var m = root.monitor
    return m ? { x: m.x, y: m.y, width: m.width, height: m.height } : { x: 0, y: 0, width: 0, height: 0 }
  }

  function windowRectOf(toplevel) {
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

  readonly property string wallpaperUrl: {
    var home = String(Quickshell.env("HOME") || "")
    return home.length > 0 ? Util.fileUrl(home + "/.local/state/omarchy/current/background") : ""
  }

  IconResolver {
    id: previewIconResolver
    objectName: "previewIconResolver"
    settings: root.settings
    gameIcons: root.gameIcons
  }

  // ---- capturing a start recipe for each window ----------------------------
  //
  // A desktop entry beats a raw command line whenever one matches: it
  // survives the app itself changing how it's launched, where a frozen argv
  // wouldn't. Only a window with no entry match falls back to
  // /proc/<pid>/cmdline - one shared FileView, read synchronously
  // (`blockLoading`/`blockAllReads`) once per window, right before the
  // recipe it feeds is used - there is nothing to poll here, this only runs
  // when the dialog is opened.

  FileView {
    id: cmdlineReader
    objectName: "cmdlineReader"
    blockLoading: true
    blockAllReads: true
    printErrors: false
  }

  function argvFor(pid) {
    var numeric = Number(pid)
    if (!(numeric > 0)) return null
    cmdlineReader.path = "/proc/" + numeric + "/cmdline"
    var argv = Logic.parseProcCmdline(cmdlineReader.text())
    return argv.length > 0 ? argv : null
  }

  function desktopEntryIdFor(key) {
    if (!key) return ""
    var entry = DesktopEntries.byId(key) || DesktopEntries.heuristicLookup(key)
    return entry ? String(entry.id || "") : ""
  }

  function captureItems() {
    var items = []
    var list = root.toplevels
    for (var i = 0; i < list.length; i++) {
      var toplevel = list[i]
      var ipc = toplevel.lastIpcObject || {}
      var key = Logic.computeWindowKey(ipc.class, ipc.initialClass, toplevel.wayland ? toplevel.wayland.appId : "")
      var desktopEntryId = root.desktopEntryIdFor(key)
      items.push({
        class: key,
        floating: !!ipc.floating,
        fullscreen: !!ipc.fullscreen,
        rect: root.windowRectOf(toplevel),
        area: root.monitorArea,
        desktopEntryId: desktopEntryId,
        argv: desktopEntryId ? null : root.argvFor(ipc.pid)
      })
    }
    return items
  }

  // A snapshot taken when the dialog opens, not a live binding: nothing
  // here should keep re-reading /proc while you're just looking at the
  // preview and typing a name.
  property var capturedWindows: []

  function refreshCapture() {
    root.capturedWindows = Logic.captureSetupWindows(root.captureItems())
  }

  readonly property bool empty: root.capturedWindows.length === 0

  // ---- naming and saving ---------------------------------------------------

  readonly property var existingNames: {
    var list = []
    if (root.store)
      for (var key in root.store.setups) list.push(key)
    return list
  }

  property bool triedEmptySubmit: false
  property bool confirmingOverwrite: false
  property bool saveErrored: false

  function reset() {
    nameField.text = ""
    root.triedEmptySubmit = false
    root.confirmingOverwrite = false
    root.saveErrored = false
  }

  // Called when the dialog appears - a fresh name field and a fresh
  // snapshot of whatever is open right now.
  //
  // A window's geometry (`lastIpcObject`) only updates in Quickshell when
  // Hyprland actually pushes an event for it - focus, move, resize. A
  // window that has sat untouched since the shell started (easy to hit via
  // the direct `'{"view":"save"}'` trigger, which - unlike the overview -
  // never asked Hyprland for anything before this dialog opened) can still
  // be showing empty geometry, so it's invisible in the preview (a null
  // `cardWindowRect`) and has no rect worth saving. `refreshToplevels()`
  // asks for everyone's current geometry; the reply is async, so the
  // capture is redone once more after a short settle rather than trusting
  // whatever was already there the instant this ran.
  function open() {
    root.reset()
    Hyprland.refreshToplevels()
    root.refreshCapture()
    refreshSettleTimer.restart()
  }

  Timer {
    id: refreshSettleTimer
    objectName: "refreshSettleTimer"
    interval: root.refreshSettleMs
    onTriggered: if (root.visible) root.refreshCapture()
  }

  property int refreshSettleMs: 150

  Component.onCompleted: root.open()
  onVisibleChanged: if (root.visible) root.open()
  // Deferred rather than immediate: right after `workspaceId` changes,
  // `resolvedWorkspaceId` (and everything chained off it) hasn't
  // necessarily re-evaluated yet - QML doesn't guarantee a dependent
  // binding is already current by the time a sibling change handler for
  // the same signal runs. `Qt.callLater` waits for everything to settle
  // first.
  onWorkspaceIdChanged: Qt.callLater(function () {
    if (root.visible) root.refreshCapture()
  })

  function attemptSave() {
    if (root.empty) return
    var trimmed = String(nameField.text || "").trim()
    var status = Logic.setupNameStatus(trimmed, root.existingNames)
    if (status === "empty") {
      root.triedEmptySubmit = true
      return
    }
    root.triedEmptySubmit = false
    if (status === "duplicate" && !root.confirmingOverwrite) {
      root.confirmingOverwrite = true
      return
    }
    root.saveErrored = false
    if (root.store)
      root.store.save(trimmed, { windows: root.capturedWindows })
  }

  Connections {
    target: root.store
    function onSaveFailed() {
      root.saveErrored = true
    }
  }

  // ---- the form -------------------------------------------------------------

  ColumnLayout {
    id: layout
    objectName: "saveSetupLayout"
    width: root.width
    spacing: Style.spacing.lg

    Text {
      objectName: "emptyWorkspaceHint"
      visible: root.empty
      Layout.fillWidth: true
      textFormat: Text.PlainText
      text: "Nothing to save - this workspace has no windows."
      color: Color.menu.text
      opacity: 0.7
      font.family: Style.font.family
      font.pixelSize: Style.font.body
      wrapMode: Text.WordWrap
    }

    ColumnLayout {
      objectName: "saveForm"
      visible: !root.empty
      Layout.fillWidth: true
      spacing: Style.spacing.lg

      Item {
        id: previewBox
        objectName: "previewBox"
        Layout.alignment: Qt.AlignHCenter
        readonly property real aspect: root.monitorArea.width > 0 && root.monitorArea.height > 0 ? root.monitorArea.height / root.monitorArea.width : 0.5625
        width: Style.space(220)
        height: width * aspect

        CardSurface {
          id: previewCard
          objectName: "previewCard"
          anchors.fill: parent
          wallpaper: root.wallpaperUrl
          captionHeight: 0

          Repeater {
            objectName: "previewWindowRepeater"
            model: root.toplevels

            Item {
              id: previewSlot
              objectName: "previewWindow"
              required property var modelData

              readonly property var rect: Logic.cardWindowRect(root.windowRectOf(previewSlot.modelData), root.monitorArea, {
                width: previewCard.width,
                height: previewCard.height
              })

              visible: previewSlot.rect !== null
              x: previewSlot.rect ? previewSlot.rect.x : 0
              y: previewSlot.rect ? previewSlot.rect.y : 0
              width: previewSlot.rect ? previewSlot.rect.width : 0
              height: previewSlot.rect ? previewSlot.rect.height : 0

              WindowThumb {
                objectName: "previewThumb"
                anchors.fill: parent
                radius: Math.max(2, Style.cornerRadius / 2)
                toplevel: previewSlot.modelData
                icon: previewIconResolver.iconFor(previewSlot.modelData)
                capturing: false
                live: false
              }
            }
          }
        }
      }

      TextField {
        id: nameField
        objectName: "nameField"
        Layout.fillWidth: true
        placeholderText: "Setup name"
        foreground: Color.menu.text
        onTextChanged: {
          root.triedEmptySubmit = false
          root.confirmingOverwrite = false
          root.saveErrored = false
        }
        onAccepted: root.attemptSave()
      }

      Text {
        objectName: "emptyNameHint"
        visible: root.triedEmptySubmit
        Layout.fillWidth: true
        textFormat: Text.PlainText
        text: "Name is required."
        color: Color.urgent
        font.family: Style.font.family
        font.pixelSize: Style.font.caption
      }

      Text {
        objectName: "overwriteHint"
        visible: root.confirmingOverwrite
        Layout.fillWidth: true
        textFormat: Text.PlainText
        text: "“" + nameField.text.trim() + "” already exists - press Enter again to overwrite it."
        color: Color.menu.text
        opacity: 0.8
        font.family: Style.font.family
        font.pixelSize: Style.font.caption
        wrapMode: Text.WordWrap
      }

      Text {
        objectName: "saveErrorHint"
        visible: root.saveErrored
        Layout.fillWidth: true
        textFormat: Text.PlainText
        text: "Couldn't save - try again."
        color: Color.urgent
        font.family: Style.font.family
        font.pixelSize: Style.font.caption
      }
    }
  }
}
