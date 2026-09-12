import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.Commons
import qs.Ui

import "logic.js" as Logic

// This plugin's summonable surface. One overlay serves every view; the
// payload picks which one, so the planned overview can share it and reach
// the settings from a gear button:
//
//   omarchy-shell shell toggle better-workspaces '{"view":"settings"}'
//
// Kept thin on purpose - the form itself lives in SettingsView.qml, which
// has no window and so can be tested headless.
Item {
  id: root

  property var shell: null
  property var manifest: null

  property bool opened: false
  property string view: "settings"

  readonly property string pluginId: manifest && manifest.id ? String(manifest.id) : "better-workspaces"
  readonly property var widgetSettings: Logic.widgetSettingsFrom(root.shell ? root.shell.barConfig : null, root.pluginId)

  function open(payloadJson) {
    root.view = Logic.parseOverlayPayload(payloadJson).view
    root.opened = true
    Qt.callLater(function () {
      keyCatcher.forceActiveFocus()
    })
  }

  function close() {
    root.opened = false
  }

  function dismiss() {
    root.opened = false
    if (root.shell && typeof root.shell.hide === "function")
      root.shell.hide(root.pluginId)
  }

  function toggle() {
    if (root.opened)
      root.dismiss()
    else
      root.open("{}")
  }

  PanelWindow {
    id: panel
    visible: root.opened
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

    Rectangle {
      anchors.fill: parent
      color: Color.menu.scrim
    }

    MouseArea {
      anchors.fill: parent
      onClicked: root.dismiss()
    }

    FocusScope {
      id: keyCatcher
      anchors.fill: parent
      focus: true
      Keys.onEscapePressed: root.dismiss()
    }

    BorderSurface {
      id: card
      anchors.centerIn: parent
      width: Math.min(Style.space(460), panel.width - Style.gapsOut * 2)
      radius: Style.cornerRadius
      color: Color.menu.background
      borderSpec: Border.surfaceSpec("menu", "border", Color.menu.border, Math.max(1, Style.space(2)))
      padding: Style.spacing.panelPadding
      // BorderSurface only exposes its insets; children place themselves.
      height: content.implicitHeight + card.contentTopInset + card.contentBottomInset

      // Clicks inside the card must not reach the dismiss area behind it.
      MouseArea {
        anchors.fill: parent
        onClicked: {}
      }

      Column {
        id: content

        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.topMargin: card.contentTopInset
        anchors.leftMargin: card.contentLeftInset
        anchors.rightMargin: card.contentRightInset
        spacing: Style.spacing.lg

        Text {
          objectName: "overlayTitle"
          textFormat: Text.PlainText
          text: "Better Workspaces"
          color: Color.menu.text
          font.family: Style.font.family
          font.pixelSize: Style.font.title
        }

        SettingsView {
          objectName: "settingsView"
          visible: root.view === "settings"
          width: content.width
          height: visible ? implicitHeight : 0
          shell: root.shell
          pluginId: root.pluginId
          settings: root.widgetSettings
        }

        Text {
          objectName: "overlayHint"
          textFormat: Text.PlainText
          text: "Changes apply immediately - Esc closes"
          color: Color.menu.text
          opacity: 0.7
          font.family: Style.font.family
          font.pixelSize: Style.font.caption
        }
      }
    }
  }
}
