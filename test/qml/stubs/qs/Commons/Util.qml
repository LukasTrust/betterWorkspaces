pragma Singleton

import QtQuick
import Quickshell

// Stand-in for Omarchy's qs.Commons Util. shellQuote matches the real
// implementation, since the widget's dispatch commands are built with it.
QtObject {
  function shellQuote(value) {
    return "'" + String(value || "").replace(/'/g, "'\\''") + "'"
  }

  function execDetached(command) {
    Quickshell.execDetached(["bash", "-lc", command])
  }
}
