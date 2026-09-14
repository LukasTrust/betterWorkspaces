import QtQuick
import QtTest
import "helpers"
import "../.." as Plugin

// The plugin's own settings form. The overlay window around it isn't
// covered here: a layer-shell window can't be driven headless, which is why
// the form is a separate, windowless component.
TestCase {
  id: testCase
  name: "SettingsView"
  width: 500
  height: 300
  visible: true
  when: windowShown

  FakeShell {
    id: fakeShell
  }

  Component {
    id: viewComponent
    Plugin.SettingsView {}
  }

  Component {
    id: storeComponent
    Plugin.SetupStore {}
  }

  SignalSpy {
    id: changedSpy
    signalName: "settingChanged"
  }

  // Mirrors how Overlay.qml stacks the form and the hint below it.
  Component {
    id: cardComponent

    Column {
      property alias view: cardView
      property alias hint: cardHint

      width: 400
      spacing: 6

      Plugin.SettingsView {
        id: cardView
        width: parent.width
        height: implicitHeight
      }

      Text {
        id: cardHint
        text: "Changes apply immediately"
      }
    }
  }

  function init() {
    fakeShell.testReset()
    changedSpy.clear()
  }

  function createView(settings, store) {
    var props = { shell: fakeShell, settings: settings || {} }
    if (store !== undefined) props.store = store
    var view = createTemporaryObject(viewComponent, testCase, props)
    verify(view !== null, "settings view should be created")
    return view
  }

  function makeStore(setups) {
    var store = createTemporaryObject(storeComponent, testCase)
    findChild(store, "setupsFile").testSetContent(JSON.stringify({
      schemaVersion: 1,
      setups: setups || {}
    }))
    return store
  }

  function aSetup(bootWorkspace) {
    return {
      windows: [{ recipe: { type: "desktop-entry", id: "x" }, class: "x", floating: false, fullscreen: false, rect: { x: 0, y: 0, width: 1, height: 1 } }],
      bootWorkspace: bootWorkspace === undefined ? null : bootWorkspace
    }
  }

  function fieldInput(view, key) {
    return findChild(findChild(view, "field-" + key), "fieldInput")
  }

  function test_showsOneFieldPerSetting() {
    var view = createView()
    var keys = ["maxIcons", "iconSize", "minWorkspaces", "hideEmpty", "groupApps", "gameIcons", "overviewEnabled", "setupTargetMode", "focusAfterSetupDrop"]
    compare(findChild(view, "fieldRepeater").count, keys.length)

    for (var i = 0; i < keys.length; i++) {
      var field = findChild(view, "field-" + keys[i])
      verify(field !== null, keys[i] + " has no field")
      verify(findChild(field, "fieldLabel").text.length > 0, keys[i] + ": no label")
      verify(findChild(field, "fieldDescription").text.length > 0, keys[i] + ": no description")
      verify(fieldInput(view, keys[i]) !== null, keys[i] + ": no control")
    }
    compare(findChild(findChild(view, "field-maxIcons"), "fieldLabel").text, "Icons per workspace")
    compare(findChild(findChild(view, "field-iconSize"), "fieldLabel").text, "Icon size")
  }

  function test_fieldsOfferExactlyTheAllowedRange() {
    var view = createView()
    compare(fieldInput(view, "maxIcons").from, 1)
    compare(fieldInput(view, "maxIcons").to, 10)
    compare(fieldInput(view, "iconSize").from, 8)
    compare(fieldInput(view, "iconSize").to, 32)
    compare(fieldInput(view, "minWorkspaces").from, 0)
    compare(fieldInput(view, "minWorkspaces").to, 10)
  }

  // A boolean setting gets a switch rather than a number field.
  function test_showsBooleanSettingsAsASwitch() {
    var view = createView({
      hideEmpty: true
    })
    var input = fieldInput(view, "hideEmpty")
    compare(input.checked, true)
    verify(input.from === undefined, "hideEmpty should not be a number field")
    compare(fieldInput(view, "maxIcons").checked, undefined)
  }

  function test_flippingASwitchWritesTheEntryBack() {
    var view = createView({
      maxIcons: 3
    })
    compare(fieldInput(view, "hideEmpty").checked, false)

    fieldInput(view, "hideEmpty").testToggle()
    compare(fakeShell.testWrites.length, 1)
    compare(fakeShell.testWrites[0].settings, {
      maxIcons: 3,
      hideEmpty: true
    })
    compare(fieldInput(view, "hideEmpty").checked, true)

    fieldInput(view, "hideEmpty").testToggle()
    compare(fakeShell.testWrites[1].settings.hideEmpty, false)
    compare(fieldInput(view, "hideEmpty").checked, false)
  }

  function test_showsAnUnusableBooleanAsTheValueTheWidgetUses() {
    var view = createView({
      hideEmpty: "nonsense"
    })
    compare(fieldInput(view, "hideEmpty").checked, false)
  }

  // ---- the enum control (setupTargetMode) ------------------------------------

  function optionButton(view, key, option) {
    return findChild(findChild(view, "field-" + key), "option-" + option)
  }

  function test_showsOneOptionButtonPerEnumValue() {
    var view = createView()
    var row = fieldInput(view, "setupTargetMode")
    compare(findChild(row, "optionRepeater").count, 2)
    verify(optionButton(view, "setupTargetMode", "add") !== null)
    verify(optionButton(view, "setupTargetMode", "replace") !== null)
  }

  function test_theCurrentEnumValueIsMarkedSelected() {
    var view = createView({ setupTargetMode: "replace" })
    verify(optionButton(view, "setupTargetMode", "replace").selected)
    verify(!optionButton(view, "setupTargetMode", "add").selected)
  }

  function test_anUnusableEnumValueShowsTheDefaultAsSelected() {
    var view = createView({ setupTargetMode: "overwrite-everything" })
    verify(optionButton(view, "setupTargetMode", "add").selected)
    verify(!optionButton(view, "setupTargetMode", "replace").selected)
  }

  function test_clickingAnOptionWritesTheEntryBack() {
    var view = createView({ maxIcons: 3 })
    mouseClick(optionButton(view, "setupTargetMode", "replace"))

    compare(fakeShell.testWrites.length, 1)
    compare(fakeShell.testWrites[0].settings, {
      maxIcons: 3,
      setupTargetMode: "replace"
    })
    verify(optionButton(view, "setupTargetMode", "replace").selected)
    verify(!optionButton(view, "setupTargetMode", "add").selected)
  }

  function test_clickingAnOptionReportsTheChange() {
    var view = createView()
    changedSpy.target = view
    mouseClick(optionButton(view, "setupTargetMode", "replace"))

    compare(changedSpy.count, 1)
    compare(changedSpy.signalArguments[0][0], "setupTargetMode")
    compare(changedSpy.signalArguments[0][1], "replace")
  }

  function test_flippingASwitchReportsTheChange() {
    var view = createView()
    changedSpy.target = view
    fieldInput(view, "hideEmpty").testToggle()

    compare(changedSpy.count, 1)
    compare(changedSpy.signalArguments[0][0], "hideEmpty")
    compare(changedSpy.signalArguments[0][1], true)
  }

  // How Overlay.qml places the form: in a column that takes its height from
  // the content. A form that reports no height of its own would let whatever
  // sits below it render on top of the rows.
  function test_fitsInAColumnThatSizesItselfFromContent() {
    var card = createTemporaryObject(cardComponent, testCase, {})
    verify(card !== null, "card should be created")
    var view = card.view

    var first = findChild(view, "field-maxIcons")
    var second = findChild(view, "field-hideEmpty")
    verify(view.height > 0, "form reports no height")
    verify(first.height > 0, "row has no height")
    verify(second.y >= first.y + first.height, "rows overlap each other")
    verify(view.height >= second.y + second.height, "form is shorter than its rows")
    verify(card.hint.y >= view.y + view.height, "content below the form overlaps it")
  }

  function test_showsCurrentValuesAndDefaultsForTheRest() {
    var view = createView({
      maxIcons: 3
    })
    compare(fieldInput(view, "maxIcons").value, 3)
    compare(fieldInput(view, "iconSize").value, 14)
  }

  function test_showsAnOutOfRangeSettingAsTheValueTheWidgetUses() {
    var view = createView({
      maxIcons: 99
    })
    compare(fieldInput(view, "maxIcons").value, 10)
  }

  function test_editingWritesTheWholeEntryBack() {
    var view = createView({
      maxIcons: 3,
      icons: {
        firefox: "🦊"
      }
    })
    fieldInput(view, "maxIcons").testType(7)

    compare(fakeShell.testWrites.length, 1)
    compare(fakeShell.testWrites[0].id, "better-workspaces")
    compare(fakeShell.testWrites[0].settings, {
      maxIcons: 7,
      icons: {
        firefox: "🦊"
      }
    })
  }

  function test_editingClampsBeforeSaving() {
    var view = createView()
    fieldInput(view, "iconSize").testType(999)

    compare(fakeShell.testWrites[0].settings.iconSize, 32)
    compare(fieldInput(view, "iconSize").value, 32)
  }

  function test_editingReportsTheChange() {
    var view = createView()
    changedSpy.target = view
    fieldInput(view, "maxIcons").testType(2)

    compare(changedSpy.count, 1)
    compare(changedSpy.signalArguments[0][0], "maxIcons")
    compare(changedSpy.signalArguments[0][1], 2)
  }

  // ---- boot workspace per setup ---------------------------------------------

  function test_hidesTheBootSectionWithoutAStore() {
    var view = createView()
    verify(!findChild(view, "bootSection").visible)
  }

  function test_hidesTheBootSectionWithNoSetupsSaved() {
    var view = createView({}, makeStore({}))
    verify(!findChild(view, "bootSection").visible)
  }

  function test_showsOneRowPerSetupSortedByName() {
    var store = makeStore({ Zeta: aSetup(3), Alpha: aSetup(null) })
    var view = createView({}, store)
    verify(findChild(view, "bootSection").visible)
    compare(findChild(view, "bootRepeater").count, 2)
    compare(view.setupNames, ["Alpha", "Zeta"])
  }

  function test_showsTheCurrentBootWorkspaceOrZeroForOff() {
    var store = makeStore({ Work: aSetup(5), Games: aSetup(null) })
    var view = createView({}, store)
    compare(findChild(findChild(view, "boot-Work"), "bootField").value, 5)
    compare(findChild(findChild(view, "boot-Games"), "bootField").value, 0)
  }

  function test_editingABootFieldWritesTheAssignmentBack() {
    var store = makeStore({ Work: aSetup(null) })
    var view = createView({}, store)

    findChild(findChild(view, "boot-Work"), "bootField").testType(4)

    compare(findChild(store, "setupsFile").testWrites.length, 1)
    compare(store.setups.Work.bootWorkspace, 4)
  }

  // Assigning a workspace another setup already had takes it away from
  // that one, rather than leaving two setups claiming the same slot.
  function test_editingABootFieldClearsWhoeverElseHadThatWorkspace() {
    var store = makeStore({ Work: aSetup(4), Games: aSetup(null) })
    var view = createView({}, store)

    findChild(findChild(view, "boot-Games"), "bootField").testType(4)

    compare(store.setups.Games.bootWorkspace, 4)
    compare(store.setups.Work.bootWorkspace, null)
  }

  function test_worksWithoutAShellToWriteTo() {
    var view = createTemporaryObject(viewComponent, testCase, {
      settings: {
        maxIcons: 4
      }
    })
    fieldInput(view, "maxIcons").testType(6)
    compare(fieldInput(view, "maxIcons").value, 6)
  }
}
