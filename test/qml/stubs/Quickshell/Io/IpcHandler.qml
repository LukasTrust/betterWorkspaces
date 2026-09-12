import QtQuick

// Stand-in for Quickshell.Io's IpcHandler. Nothing is registered; tests call
// the handler's functions directly.
QtObject {
  property string target: ""
  property bool enabled: true
}
