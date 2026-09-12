import QtQuick

// Stand-in for Omarchy's qs.Ui NumberField. It draws nothing; tests call
// testType() to act like a user entering a value. Members prefixed with
// "test" don't exist on the real control.
Item {
  id: root

  property string label: ""
  property int value: 0
  property int from: 0
  property int to: 100
  property int stepSize: 1
  property color foreground: "#ffffff"
  property color accent: "#88aaff"
  property string fontFamily: "monospace"
  property real fontSize: 12
  property real fieldWidth: 60
  property bool hasCursor: false

  signal modified(int value)
  signal hovered(bool on)

  function testType(newValue) {
    root.modified(newValue)
  }
}
