import QtQuick

// Stand-in for Quickshell.Hyprland's HyprlandMonitor.
QtObject {
  property int id: 0
  property string name: ""
  property string description: ""
  property int x: 0
  property int y: 0
  property int width: 1920
  property int height: 1080
  property real scale: 1
  property var lastIpcObject: ({})
  property var activeWorkspace: null
  property bool focused: false
}
