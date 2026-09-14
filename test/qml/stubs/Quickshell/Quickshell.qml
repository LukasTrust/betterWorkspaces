pragma Singleton

import QtQuick

// Stand-in for the Quickshell global singleton. Members prefixed with
// "test" are test controls and don't exist on the real object.
QtObject {
  id: root

  // Themed icon name -> resolved source. Names not listed are unresolved.
  property var testThemeIcons: ({})
  property var testExecuted: []
  // Counts lookups per icon name, so tests can assert on the widget's icon
  // cache the same way they do for DesktopEntries.testStats.lookups.
  property var testIconPathCalls: ({})
  // Environment variable name -> value, for env().
  property var testEnv: ({})

  function iconPath(icon, check) {
    var name = String(icon)
    root.testIconPathCalls[name] = (root.testIconPathCalls[name] || 0) + 1
    var path = root.testThemeIcons[name]
    if (path !== undefined)
      return path
    if (typeof check === "string")
      return check.length > 0 ? root.iconPath(check, true) : ""
    return check === true ? "" : "image://icon/" + icon
  }

  function hasThemeIcon(icon) {
    return root.testThemeIcons[String(icon)] !== undefined
  }

  function execDetached(command) {
    root.testExecuted = root.testExecuted.concat([command])
  }

  function env(name) {
    var value = root.testEnv[String(name)]
    return value === undefined ? "" : value
  }

  function testReset() {
    root.testThemeIcons = {
      "application-x-executable": "image://test/application-x-executable"
    }
    root.testEnv = ({})
    root.testExecuted = []
    root.testIconPathCalls = ({})
  }

  Component.onCompleted: testReset()
}
