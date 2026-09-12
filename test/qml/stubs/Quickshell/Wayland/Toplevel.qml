import QtQuick

// Stand-in for Quickshell.Wayland's Toplevel (the foreign-toplevel handle a
// HyprlandToplevel exposes as `wayland`). Calls are counted so tests can
// assert on them. Members prefixed with "test" don't exist on the real type.
QtObject {
  property string appId: ""
  property string title: ""
  property var parent: null
  property bool activated: false
  property var screens: []
  property bool maximized: false
  property bool minimized: false
  property bool fullscreen: false

  property int testActivateCalls: 0
  property int testCloseCalls: 0

  function activate() {
    testActivateCalls++
  }

  function close() {
    testCloseCalls++
  }

  function fullscreenOn(screen) {
  }

  function setRectangle(window, rect) {
  }

  function unsetRectangle() {
  }
}
