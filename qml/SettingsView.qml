import QtQuick
import QtQuick.Layouts
import qs.Commons
import qs.Ui

import "../js/logic.js" as Logic

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
  // The shared setup store (Overlay.qml owns the one instance) - lets this
  // form double as where each setup's boot workspace is assigned, since
  // that's per-setup, not a plugin-wide setting `SETTING_FIELDS` could hold.
  property var store: null

  signal settingChanged(string key, var value)

  readonly property var setupNames: {
    var names = []
    if (root.store)
      for (var key in root.store.setups)
        names.push(key)
    return names.sort()
  }

  implicitWidth: layout.implicitWidth
  implicitHeight: layout.implicitHeight

  function valueOf(key) {
    return Logic.settingValue(root.settings, key)
  }

  // ---- renaming a setup -----------------------------------------------------
  //
  // Which row's rename was refused, and what to tell it. Kept here rather
  // than in the row itself so it survives the repeater rebuilding the row,
  // and so only one message can be up at a time.
  property string renameError: ""
  property string renameErrorFor: ""

  function clearRenameError() {
    root.renameError = ""
    root.renameErrorFor = ""
  }

  // `Logic.renameSetup` refuses rather than resolves a collision - taking a
  // name another setup holds would otherwise drop that setup silently. It
  // says no by returning null; which no it was comes from `setupNameStatus`,
  // the same check the save dialog reports with.
  function renameSetup(from, to) {
    if (!root.store)
      return
    var trimmed = String(to || "").trim()
    // Pressing Enter without having changed anything isn't an error.
    if (trimmed === from) {
      root.clearRenameError()
      return
    }

    var next = Logic.renameSetup(root.store.setups, from, trimmed)
    if (next === null) {
      root.renameErrorFor = from
      root.renameError = Logic.setupNameStatus(trimmed, root.setupNames) === "empty" ? "A setup needs a name." : "“" + trimmed + "” is already taken."
      return
    }

    root.clearRenameError()
    root.store.replaceAll(next)
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

        // A row of small buttons, one per option - the only field type with
        // more than two possible values, so a switch doesn't fit it.
        Component {
          id: enumControl

          RowLayout {
            objectName: "fieldInput"
            spacing: Style.spacing.xs

            Repeater {
              objectName: "optionRepeater"
              model: row.modelData.options

              Rectangle {
                id: option
                objectName: "option-" + modelData
                required property string modelData
                readonly property bool selected: root.valueOf(row.modelData.key) === modelData

                implicitWidth: optionLabel.implicitWidth + Style.spacing.controlPaddingX * 2
                implicitHeight: optionLabel.implicitHeight + Style.spacing.controlPaddingY * 2
                radius: Style.cornerRadius
                color: option.selected ? Color.accent : "transparent"
                border.width: Math.max(1, Style.space(1))
                border.color: option.selected ? Color.accent : Color.menu.border

                Text {
                  id: optionLabel
                  anchors.centerIn: parent
                  textFormat: Text.PlainText
                  text: option.modelData
                  color: option.selected ? Color.menu.background : Color.menu.text
                  font.family: Style.font.family
                  font.pixelSize: Style.font.caption
                }

                MouseArea {
                  anchors.fill: parent
                  cursorShape: Qt.PointingHandCursor
                  onClicked: root.change(row.modelData.key, option.modelData)
                }
              }
            }
          }
        }

        Loader {
          readonly property string kind: row.modelData.type

          Layout.alignment: Qt.AlignVCenter
          Layout.preferredWidth: kind === "integer" ? Style.spacing.numberFieldWidth : implicitWidth
          sourceComponent: kind === "boolean" ? switchControl : (kind === "enum" ? enumControl : numberControl)
        }
      }
    }

    // Nothing to show without a store to read, or without a single setup
    // saved yet - an empty section header with nothing under it would just
    // be noise.
    ColumnLayout {
      objectName: "bootSection"
      visible: root.setupNames.length > 0
      Layout.fillWidth: true
      spacing: Style.spacing.xxs

      Text {
        objectName: "bootSectionTitle"
        textFormat: Text.PlainText
        text: "Saved setups"
        color: Color.menu.text
        font.family: Style.font.family
        font.pixelSize: Style.font.body
      }

      Text {
        objectName: "bootSectionHint"
        textFormat: Text.PlainText
        text: "Rename one by typing over its name and pressing Enter. The number is the workspace it opens on at boot - 0 turns that off, and at most one setup per workspace, so assigning one here takes it away from whichever setup already had it."
        color: Color.menu.text
        opacity: 0.7
        font.family: Style.font.family
        font.pixelSize: Style.font.caption
        wrapMode: Text.WordWrap
        Layout.fillWidth: true
      }

      Repeater {
        objectName: "bootRepeater"
        model: root.setupNames

        ColumnLayout {
          id: setupRow
          required property string modelData

          objectName: "boot-" + setupRow.modelData
          Layout.fillWidth: true
          spacing: Style.spacing.xxs

          RowLayout {
            Layout.fillWidth: true
            spacing: Style.spacing.lg

            // Enter commits, rather than losing focus: renaming rebuilds
            // this very row (the repeater is keyed by name), so a commit on
            // focus loss would fire while the field is being torn down.
            TextField {
              objectName: "nameField"
              Layout.fillWidth: true
              text: setupRow.modelData
              foreground: Color.menu.text
              onAccepted: root.renameSetup(setupRow.modelData, text)
            }

            NumberField {
              objectName: "bootField"
              value: (root.store.setups[setupRow.modelData] && root.store.setups[setupRow.modelData].bootWorkspace) || 0
              from: 0
              to: 10
              stepSize: 1
              foreground: Color.menu.text
              Layout.preferredWidth: Style.spacing.numberFieldWidth
              onModified: function (value) {
                root.store.replaceAll(Logic.assignBootWorkspace(root.store.setups, setupRow.modelData, value))
              }
            }
          }

          Text {
            objectName: "renameError"
            visible: root.renameErrorFor === setupRow.modelData && root.renameError.length > 0
            Layout.fillWidth: true
            textFormat: Text.PlainText
            text: root.renameError
            color: Color.urgent
            font.family: Style.font.family
            font.pixelSize: Style.font.caption
            wrapMode: Text.WordWrap
          }
        }
      }
    }
  }
}
