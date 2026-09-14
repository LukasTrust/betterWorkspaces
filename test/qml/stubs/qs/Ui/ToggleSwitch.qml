import QtQuick

// Stand-in for Omarchy's qs.Ui ToggleSwitch. It draws nothing; tests call
// testToggle() to act like a user flipping it. Members prefixed with "test"
// don't exist on the real control.
Item {
  id: root

  property bool checked: false
  property bool interactive: true
  property bool busy: false
  property color foreground: "#ffffff"
  property color accent: "#88aaff"

  signal toggled
  signal hovered(bool isHovered)

  implicitWidth: 40
  implicitHeight: 22

  function testToggle() {
    root.toggled()
  }
}
