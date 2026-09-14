pragma Singleton

import QtQuick

// Stand-in for Omarchy's qs.Commons Style with fixed, unscaled tokens.
QtObject {
  function spaceReal(px) {
    return Number(px)
  }

  function space(px) {
    return Math.round(Number(px))
  }

  readonly property int cornerRadius: 0
  readonly property int gapsOut: 5

  readonly property QtObject font: QtObject {
    readonly property string family: "monospace"
    readonly property int caption: 10
    readonly property int body: 12
    readonly property int title: 14
  }

  readonly property QtObject spacing: QtObject {
    readonly property int xxs: 2
    readonly property int xs: 3
    readonly property int md: 6
    readonly property int lg: 8
    readonly property int controlPaddingX: 10
    readonly property int controlPaddingY: 6
    readonly property int panelPadding: 18
    readonly property int controlHeight: 28
    readonly property int numberFieldWidth: 120
  }

  readonly property QtObject bar: QtObject {
    readonly property int sizeHorizontal: 26
    readonly property int sizeVertical: 28
  }
}
