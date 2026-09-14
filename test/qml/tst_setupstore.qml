import QtQuick
import QtTest
import "../../qml" as Plugin

// This plugin's own setups.json store. No real filesystem here - the
// FileView and Process stand-ins record what they were asked to do, so
// these tests check the actual sequence (mkdir, then write, then chmod)
// rather than the end state alone.
TestCase {
  id: testCase
  name: "SetupStore"
  width: 200
  height: 200
  visible: true
  when: windowShown

  Component {
    id: storeComponent
    Plugin.SetupStore {}
  }

  Component {
    id: spyComponent
    SignalSpy {}
  }

  function makeStore() {
    return createTemporaryObject(storeComponent, testCase)
  }

  function fileOf(store) {
    return findChild(store, "setupsFile")
  }

  function mkdirOf(store) {
    return findChild(store, "mkdirProcess")
  }

  function chmodOf(store) {
    return findChild(store, "chmodProcess")
  }

  function committedSpy(store) {
    return createTemporaryObject(spyComponent, testCase, { target: store, signalName: "committed" })
  }

  function failedSpy(store) {
    return createTemporaryObject(spyComponent, testCase, { target: store, signalName: "saveFailed" })
  }

  function aSetup(name) {
    return {
      windows: [{
        recipe: { type: "desktop-entry", id: name + ".desktop" },
        class: name,
        floating: false,
        fullscreen: false,
        rect: { x: 0, y: 0, width: 1, height: 1 }
      }]
    }
  }

  // ---- reading ----------------------------------------------------------

  function test_readsNothingFromAMissingFile() {
    var store = makeStore()
    fileOf(store).testSetMissing()
    compare(Object.keys(store.setups).length, 0)
  }

  function test_readsBackWhatTheFileHolds() {
    var store = makeStore()
    fileOf(store).testSetContent(JSON.stringify({
      schemaVersion: 1,
      setups: { Work: aSetup("firefox") }
    }))
    compare(Object.keys(store.setups), ["Work"])
  }

  function test_dropsAFileACorruptOrUnknownSchemaVersion() {
    var store = makeStore()
    fileOf(store).testSetContent("{not json")
    compare(Object.keys(store.setups).length, 0)

    fileOf(store).testSetContent(JSON.stringify({ schemaVersion: 99, setups: { Work: aSetup("firefox") } }))
    compare(Object.keys(store.setups).length, 0)
  }

  // ---- saving -------------------------------------------------------------

  function test_saveMakesTheDirectoryThenWritesThenNarrowsThePermissions() {
    var store = makeStore()
    fileOf(store).testSetMissing()
    var committed = committedSpy(store)

    store.save("Work", aSetup("firefox"))

    compare(mkdirOf(store).testRunHistory.length, 1)
    compare(mkdirOf(store).testRunHistory[0], ["mkdir", "-p", "-m", "0700", store.configDir])

    compare(fileOf(store).testWrites.length, 1)
    var written = JSON.parse(fileOf(store).testWrites[0])
    compare(written.schemaVersion, 1)
    compare(Object.keys(written.setups), ["Work"])

    compare(chmodOf(store).testRunHistory.length, 1)
    compare(chmodOf(store).testRunHistory[0], ["chmod", "0600", store.filePath])

    compare(committed.count, 1)
  }

  function test_saveKeepsEveryOtherSetupAndOnlyReplacesTheNamedOne() {
    var store = makeStore()
    fileOf(store).testSetContent(JSON.stringify({
      schemaVersion: 1,
      setups: { Work: aSetup("firefox"), Games: aSetup("steam") }
    }))

    store.save("Work", aSetup("code"))

    var written = JSON.parse(fileOf(store).testWrites[0])
    compare(Object.keys(written.setups).sort(), ["Games", "Work"])
    compare(written.setups.Work.windows[0].class, "code")
    compare(written.setups.Games.windows[0].class, "steam")
  }

  function test_saveOverEmptyStoreGoesThroughTheSameSteps() {
    var store = makeStore()
    fileOf(store).testSetMissing()
    store.save("Solo", aSetup("firefox"))
    var written = JSON.parse(fileOf(store).testWrites[0])
    compare(Object.keys(written.setups), ["Solo"])
  }

  // ---- removing -----------------------------------------------------------

  function test_removeDropsExactlyTheNamedSetup() {
    var store = makeStore()
    fileOf(store).testSetContent(JSON.stringify({
      schemaVersion: 1,
      setups: { Work: aSetup("firefox"), Games: aSetup("steam") }
    }))

    store.remove("Games")

    var written = JSON.parse(fileOf(store).testWrites[0])
    compare(Object.keys(written.setups), ["Work"])
  }

  // ---- failure ------------------------------------------------------------

  function test_aFailedMkdirNeverWritesAndReportsFailure() {
    var store = makeStore()
    fileOf(store).testSetMissing()
    mkdirOf(store).testExitCode = 1
    var failed = failedSpy(store)

    store.save("Work", aSetup("firefox"))

    compare(fileOf(store).testWrites.length, 0)
    compare(chmodOf(store).testRunHistory.length, 0)
    tryCompare(failed, "count", 1)
  }

  function test_aFailedChmodStillWroteButReportsFailureInsteadOfCommitted() {
    var store = makeStore()
    fileOf(store).testSetMissing()
    chmodOf(store).testExitCode = 1
    var committed = committedSpy(store)
    var failed = failedSpy(store)

    store.save("Work", aSetup("firefox"))

    compare(fileOf(store).testWrites.length, 1)
    tryCompare(failed, "count", 1)
    compare(committed.count, 0)
  }
}
