import QtQuick

// Stand-in for Quickshell.Wayland's ScreencopyView. It paints nothing;
// tests read back what the overview asked it to capture. Members prefixed
// with "test" don't exist on the real type.
Item {
  id: root

  property var captureSource: null
  property bool paintCursor: false
  property bool live: false
  property bool hasContent: false
  property size sourceSize
  property size constraintSize

  signal stopped

  function captureFrame() {
  }
}
