import QtQuick
import Quickshell

// Stand-in for Quickshell.Hyprland's HyprlandWorkspace. Members prefixed
// with "test" don't exist on the real type.
QtObject {
  property int id: 0
  property string name: ""
  property bool active: false
  property bool focused: false
  property bool urgent: false
  property bool hasFullscreen: false
  property var lastIpcObject: ({})
  property var monitor: null
  property ObjectModel toplevels: ObjectModel {}

  property int testActivateCalls: 0

  function activate() {
    testActivateCalls++
  }
}
