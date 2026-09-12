import QtQuick

// Test double for the scoped shell facade a plugin is handed
// ($OMARCHY_PATH/shell/services/PluginShellApi.qml). Writes are recorded
// instead of touching shell.json. Members prefixed with "test" don't exist
// on the real facade.
QtObject {
  id: api

  property string pluginId: "better-workspaces"
  property var bar: null
  property var barConfig: ({})
  property var idleConfig: ({})
  property var appLibrary: null

  // { id, settings } of every updateEntryInline call, in order.
  property var testWrites: []
  property var testHidden: []

  function updateEntryInline(id, settings) {
    api.testWrites = api.testWrites.concat([
      {
        id: String(id || ""),
        settings: JSON.parse(JSON.stringify(settings))
      }
    ])
    return true
  }

  function hide(id) {
    api.testHidden = api.testHidden.concat([String(id || "")])
    return true
  }

  function summon(id, payloadJson) {
    return true
  }

  function toggle(id, payloadJson) {
    return true
  }

  function isPluginOpen(id) {
    return false
  }

  function serviceFor(id) {
    return null
  }

  function firstPartyServiceFor(id) {
    return null
  }

  function pluginShellForBarEntry(ownerId, moduleName) {
    return null
  }

  function mutateShellConfig(mutator) {
    return false
  }

  function testReset() {
    api.testWrites = []
    api.testHidden = []
    api.barConfig = ({})
  }
}
