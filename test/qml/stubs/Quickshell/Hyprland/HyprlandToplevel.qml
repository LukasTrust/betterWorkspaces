import QtQuick

// Stand-in for Quickshell.Hyprland's HyprlandToplevel. `wayland` holds a
// Quickshell.Wayland Toplevel stand-in, `lastIpcObject` the window's
// `hyprctl clients` entry (class, initialClass, at, size, ...).
QtObject {
  property string address: ""
  property var handle: null
  property var wayland: null
  property string title: ""
  property bool activated: false
  property bool urgent: false
  property var lastIpcObject: ({})
  property var workspace: null
  property var monitor: null
}
