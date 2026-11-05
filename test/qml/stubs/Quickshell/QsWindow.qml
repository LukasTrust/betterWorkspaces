pragma Singleton

import QtQuick

// Stand-in for Quickshell's QsWindow attached type, which a widget reads as
// `root.QsWindow.window` for the window it sits in. The real one is attached
// to each item; this is a singleton, which that same expression resolves
// against too, so a test sets `window` to say which screen the bar is on
// (`{ screen: { name: "DP-1" } }`) and leaves it null for a widget with no
// window yet.
QtObject {
  id: root

  property var window: null

  function testReset() {
    root.window = null
  }
}
