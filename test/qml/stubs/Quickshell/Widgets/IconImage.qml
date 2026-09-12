import QtQuick

// Stand-in for Quickshell.Widgets' IconImage. Draws nothing; it only holds
// the properties the widget sets so tests can read them back.
Item {
  property string source: ""
  property real implicitSize: 0
  property bool asynchronous: false
  property bool mipmap: false

  implicitWidth: implicitSize
  implicitHeight: implicitSize
}
