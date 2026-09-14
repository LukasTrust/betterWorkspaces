pragma Singleton

import QtQuick
import Quickshell

// Stand-in for Omarchy's qs.Commons Util. shellQuote and fileUrl match the
// real implementations, since the widget's dispatch commands and the
// overview's wallpaper source are built with them.
QtObject {
  function fileUrl(path) {
    if (!path)
      return ""
    return "file://" + String(path).split("/").map(encodeURIComponent).join("/")
  }

  function shellQuote(value) {
    return "'" + String(value || "").replace(/'/g, "'\\''") + "'"
  }

  function execDetached(command) {
    Quickshell.execDetached(["bash", "-lc", command])
  }
}
