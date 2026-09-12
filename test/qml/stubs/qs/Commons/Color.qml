pragma Singleton

import QtQuick

// Stand-in for Omarchy's qs.Commons Color. The values are arbitrary but
// distinct, so tests can tell which theme color was applied.
QtObject {
  property color foreground: "#cacccc"
  property color background: "#101010"
  property color accent: "#88aaff"
  property color urgent: "#a55555"

  readonly property QtObject bar: QtObject {
    property color active: "#ffcc00"
  }

  // The settings overlay borrows the menu surface tokens.
  readonly property QtObject menu: QtObject {
    property color background: "#141414"
    property color text: "#e0e0e0"
    property color border: "#3a3a3a"
    property color scrim: "#80000000"
    property color selectedBackground: "#252525"
    property color selectedText: "#88aaff"
  }
}
