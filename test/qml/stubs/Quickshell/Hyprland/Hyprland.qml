pragma Singleton

import QtQuick
import Quickshell

// Stand-in for the Quickshell.Hyprland singleton. Tests drive it by
// assigning workspaces/toplevels/focus directly instead of via Hyprland's
// IPC event stream. Members prefixed with "test" don't exist on the real
// object.
QtObject {
  id: root

  property bool usingLua: true
  property string requestSocketPath: ""
  property string eventSocketPath: ""
  property var focusedMonitor: null
  property var focusedWorkspace: null
  property var activeToplevel: null
  property ObjectModel monitors: ObjectModel {}
  property ObjectModel workspaces: ObjectModel {}
  property ObjectModel toplevels: ObjectModel {}

  // dispatch() requests, in order.
  property var testDispatched: []

  function dispatch(request) {
    root.testDispatched = root.testDispatched.concat([String(request)])
  }

  function monitorFor(screen) {
    return root.focusedMonitor
  }

  function refreshMonitors() {
  }

  function refreshToplevels() {
  }

  function refreshWorkspaces() {
  }

  function testReset() {
    root.focusedMonitor = null
    root.focusedWorkspace = null
    root.activeToplevel = null
    root.monitors.values = []
    root.workspaces.values = []
    root.toplevels.values = []
    root.testDispatched = []
  }
}
