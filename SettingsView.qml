import QtQuick
import QtQuick.Layouts
import qs.Commons
import qs.Ui

import "logic.js" as Logic

// The plugin's own settings form, shown by Overlay.qml. Every change is
// written straight back to this widget's shell.json entry, so the bar
// updates while you edit - there is no save button and nothing to apply.
Item {
  id: root

  // The scoped shell facade a plugin is handed; used only to write this
  // plugin's own entry back.
  property var shell: null
  property string pluginId: "better-workspaces"
  // The widget's current shell.json entry, without its id.
  property var settings: ({})

  signal settingChanged(string key, var value)

  implicitWidth: layout.implicitWidth
  implicitHeight: layout.implicitHeight

  function valueOf(key) {
    return Logic.settingValue(root.settings, key)
  }

  function change(key, value) {
    var next = Logic.applySetting(root.settings, key, value)
    root.settings = next
    if (root.shell && typeof root.shell.updateEntryInline === "function")
      root.shell.updateEntryInline(root.pluginId, next)
    root.settingChanged(key, next[key])
  }

  // Width comes from the caller, height from the content: anchoring the
  // layout to the parent instead would make the two depend on each other.
  ColumnLayout {
    id: layout
    objectName: "settingsLayout"
    width: root.width
    spacing: Style.spacing.lg

    Repeater {
      objectName: "fieldRepeater"
      model: Logic.SETTING_FIELDS

      RowLayout {
        id: row
        required property var modelData

        objectName: "field-" + modelData.key
        Layout.fillWidth: true
        spacing: Style.spacing.lg

        ColumnLayout {
          Layout.fillWidth: true
          spacing: Style.spacing.xxs

          Text {
            objectName: "fieldLabel"
            textFormat: Text.PlainText
            text: row.modelData.label
            color: Color.menu.text
            font.family: Style.font.family
            font.pixelSize: Style.font.body
          }

          Text {
            objectName: "fieldDescription"
            textFormat: Text.PlainText
            text: row.modelData.description
            color: Color.menu.text
            opacity: 0.7
            font.family: Style.font.family
            font.pixelSize: Style.font.caption
            wrapMode: Text.WordWrap
            Layout.fillWidth: true
          }
        }

        // One control per setting type, picked by the field. Both are
        // declared here so they can read the row's own `modelData`.
        Component {
          id: numberControl

          NumberField {
            objectName: "fieldInput"
            value: root.valueOf(row.modelData.key)
            from: row.modelData.min
            to: row.modelData.max
            stepSize: 1
            foreground: Color.menu.text
            onModified: function (value) {
              root.change(row.modelData.key, value)
            }
          }
        }

        Component {
          id: switchControl

          ToggleSwitch {
            objectName: "fieldInput"
            checked: root.valueOf(row.modelData.key)
            foreground: Color.menu.text
            onToggled: root.change(row.modelData.key, !checked)
          }
        }

        Loader {
          readonly property bool isSwitch: row.modelData.type === "boolean"

          Layout.alignment: Qt.AlignVCenter
          Layout.preferredWidth: isSwitch ? implicitWidth : Style.spacing.numberFieldWidth
          sourceComponent: isSwitch ? switchControl : numberControl
        }
      }
    }
  }
}
