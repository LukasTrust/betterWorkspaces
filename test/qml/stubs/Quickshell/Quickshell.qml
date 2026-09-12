pragma Singleton

import QtQuick

// Stand-in for the Quickshell global singleton. Members prefixed with
// "test" are test controls and don't exist on the real object.
QtObject {
  id: root

  // Themed icon name -> resolved source. Names not listed are unresolved.
  property var testThemeIcons: ({})
  property var testExecuted: []

  function iconPath(icon, check) {
    var path = root.testThemeIcons[String(icon)]
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
    return ""
  }

  function testReset() {
    root.testThemeIcons = {
      "application-x-executable": "image://test/application-x-executable"
    }
    root.testExecuted = []
  }

  Component.onCompleted: testReset()
}
