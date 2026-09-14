import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Wayland
import qs.Commons
import qs.Ui

import "../js/logic.js" as Logic

// This plugin's summonable surface. One overlay serves every view; the
// payload picks which one:
//
//   omarchy-shell shell toggle better-workspaces '{}'
//   omarchy-shell shell toggle better-workspaces '{"view":"settings"}'
//   omarchy-shell shell toggle better-workspaces '{"view":"save"}'
//
// The save view saves the focused workspace on its own, no overview needed.
// Kept thin on purpose - every view (SettingsView.qml, Overview.qml,
// SaveSetupView.qml) has no window of its own and so can be tested headless.
Item {
  id: root

  property var shell: null
  property var manifest: null

  property bool opened: false
  // The view that owns the surface, and whether a card sits on top of it:
  // the settings (reached through the overview's gear, or summoned
  // directly) or the save dialog (reached through a workspace's own save
  // button, or summoned directly for whichever workspace is focused). Both
  // keep the overview underneath, suspended - either one changes what it's
  // showing, unless it was summoned on its own.
  property string view: "overview"
  property bool settingsOpen: false
  property bool saveOpen: false
  // Which workspace the save dialog is for - a workspace's own button
  // passes its real id, since the one clicked isn't necessarily the one
  // you're on; summoned directly it stays 0, and SaveSetupView falls back
  // to whatever is focused.
  property int saveWorkspaceId: 0

  readonly property bool cardOpen: root.settingsOpen || root.saveOpen

  readonly property string pluginId: manifest && manifest.id ? String(manifest.id) : "better-workspaces"
  readonly property var widgetSettings: Logic.widgetSettingsFrom(root.shell ? root.shell.barConfig : null, root.pluginId)

  function open(payloadJson) {
    var state = Logic.overlayState(payloadJson)
    root.view = state.base
    root.settingsOpen = state.settingsOpen
    root.saveOpen = state.saveOpen
    root.saveWorkspaceId = 0
    root.opened = true
    Qt.callLater(function () {
      if (root.cardOpen)
        keyCatcher.forceActiveFocus()
    })
  }

  // Escape, and a click past the card. From a card reached through the
  // overview it is a step back; anywhere else it is the way out.
  function stepBack() {
    if (Logic.overlayEscape(root.view, root.cardOpen) === "back") {
      root.settingsOpen = false
      root.saveOpen = false
      root.saveWorkspaceId = 0
      return
    }
    root.dismiss()
  }

  function openSettings() {
    root.saveOpen = false
    root.saveWorkspaceId = 0
    root.settingsOpen = true
    Qt.callLater(function () {
      keyCatcher.forceActiveFocus()
    })
  }

  function openSave(workspaceId) {
    root.settingsOpen = false
    root.saveOpen = true
    root.saveWorkspaceId = workspaceId
    Qt.callLater(function () {
      keyCatcher.forceActiveFocus()
    })
  }

  function close() {
    root.opened = false
    root.settingsOpen = false
    root.saveOpen = false
    root.saveWorkspaceId = 0
  }

  function dismiss() {
    root.opened = false
    root.settingsOpen = false
    root.saveOpen = false
    root.saveWorkspaceId = 0
    if (root.shell && typeof root.shell.hide === "function")
      root.shell.hide(root.pluginId)
  }

  function toggle() {
    if (root.opened)
      root.dismiss()
    else
      root.open("{}")
  }

  // Which workspace the save dialog is actually showing - `saveWorkspaceId`
  // itself stays 0 when summoned directly, with SaveSetupView resolving the
  // focused workspace on its own; the title needs that same number.
  readonly property int resolvedSaveWorkspaceId: root.saveWorkspaceId > 0 ? root.saveWorkspaceId : (Hyprland.focusedWorkspace ? Hyprland.focusedWorkspace.id : 0)

  // The screen Hyprland says has focus, so the overview opens where you are
  // rather than on whichever monitor Quickshell happens to list first.
  readonly property var focusedScreen: {
    var monitor = Hyprland.focusedMonitor
    if (!monitor)
      return null
    var screens = Quickshell.screens
    for (var i = 0; i < screens.length; i++)
      if (screens[i].name === monitor.name)
        return screens[i]
    return null
  }

  // The one store instance, shared by the save dialog and (later) the
  // overview's own list of saved setups - both have to agree on what's
  // there.
  SetupStore {
    id: setupStore
    objectName: "setupStore"
  }

  SetupOpener {
    id: setupOpener
    objectName: "setupOpener"
  }

  Connections {
    target: setupStore
    // Only when the save dialog is actually what's open: `committed` also
    // fires for a future delete from the overview's setups list, which
    // shouldn't close whatever else happens to be on top at the time.
    function onCommitted() {
      if (root.saveOpen)
        root.stepBack()
    }
  }

  PanelWindow {
    id: panel
    visible: root.opened
    screen: root.focusedScreen
    color: "transparent"
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.namespace: "better-workspaces"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive

    anchors {
      top: true
      bottom: true
      left: true
      right: true
    }

    // The overview fills the surface and brings its own keyboard handling
    // and closing animation, so it is asked to close rather than dismissed
    // outright - the cards shrink away before the surface goes. With the
    // settings on top it stays on screen, previews and all, but suspended.
    Overview {
      objectName: "overviewView"
      anchors.fill: parent
      visible: root.view === "overview"
      shell: root.shell
      settings: root.widgetSettings
      store: setupStore
      opener: setupOpener
      active: root.opened && root.view === "overview"
      suspended: root.cardOpen
      onCloseRequested: root.dismiss()
      onSettingsRequested: root.openSettings()
      onSaveRequested: function (workspaceId) {
        root.openSave(workspaceId)
      }
    }

    // Dims whatever the card sits on - the overview's cards, or nothing at
    // all when it was summoned straight. Above the overview, so it dims
    // that too; the overview brings its own backdrop for when it is on its
    // own.
    Rectangle {
      anchors.fill: parent
      visible: root.cardOpen
      color: Color.menu.scrim
    }

    // A click past the card. Only while it's showing: the overview has its
    // own backdrop, so that clicking past its cards still plays the closing
    // animation rather than cutting the surface away.
    MouseArea {
      anchors.fill: parent
      visible: root.cardOpen
      enabled: visible
      onClicked: root.stepBack()
    }

    FocusScope {
      id: keyCatcher
      anchors.fill: parent
      focus: root.cardOpen
      visible: root.cardOpen
      Keys.onEscapePressed: root.stepBack()
    }

    BorderSurface {
      id: card
      visible: root.cardOpen
      anchors.centerIn: parent
      width: Math.min(Style.space(460), panel.width - Style.gapsOut * 2)
      radius: Style.cornerRadius
      color: Color.menu.background
      borderSpec: Border.surfaceSpec("menu", "border", Color.menu.border, Math.max(1, Style.space(2)))
      padding: Style.spacing.panelPadding
      // BorderSurface only exposes its insets; children place themselves.
      //
      // The card is as tall as its content right up to the point where that
      // would run off the screen, and no taller - the settings grow by a row
      // per saved setup (the boot assignments), so there is no content height
      // that can be assumed to fit. Past that the content scrolls instead,
      // which is the difference between a long list being awkward and its
      // last rows being unreachable.
      height: Math.min(content.implicitHeight + card.contentTopInset + card.contentBottomInset, panel.height - Style.gapsOut * 2)

      // Clicks inside the card must not reach the dismiss area behind it.
      MouseArea {
        anchors.fill: parent
        onClicked: {}
      }

      Flickable {
        id: cardScroll

        anchors.fill: parent
        anchors.topMargin: card.contentTopInset
        anchors.bottomMargin: card.contentBottomInset
        anchors.leftMargin: card.contentLeftInset
        anchors.rightMargin: card.contentRightInset
        contentWidth: width
        contentHeight: content.implicitHeight
        clip: true
        // Nothing to drag while it all fits: leaving it interactive would
        // let a stray drag on a settings row rubber-band the whole form.
        interactive: contentHeight > height
        boundsBehavior: Flickable.StopAtBounds

        Column {
          id: content

          width: cardScroll.width
          spacing: Style.spacing.lg

          Text {
            objectName: "overlayTitle"
            textFormat: Text.PlainText
            text: root.saveOpen ? "Save workspace " + (root.resolvedSaveWorkspaceId === 10 ? "0" : root.resolvedSaveWorkspaceId) : "Better Workspaces"
            color: Color.menu.text
            font.family: Style.font.family
            font.pixelSize: Style.font.title
          }

          SettingsView {
            objectName: "settingsView"
            visible: root.settingsOpen
            width: content.width
            height: visible ? implicitHeight : 0
            shell: root.shell
            pluginId: root.pluginId
            settings: root.widgetSettings
            store: setupStore
          }

          SaveSetupView {
            objectName: "saveSetupView"
            visible: root.saveOpen
            width: content.width
            height: visible ? implicitHeight : 0
            settings: root.widgetSettings
            store: setupStore
            workspaceId: root.saveWorkspaceId
          }

          Text {
            objectName: "overlayHint"
            textFormat: Text.PlainText
            text: root.saveOpen ? "Enter saves - Esc " + (root.view === "overview" ? "goes back to the overview" : "closes") : (root.view === "overview" ? "Changes apply immediately - Esc goes back to the overview" : "Changes apply immediately - Esc closes")
            color: Color.menu.text
            opacity: 0.7
            font.family: Style.font.family
            font.pixelSize: Style.font.caption
          }
        }
      }
    }
  }
}
