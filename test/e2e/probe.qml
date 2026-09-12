import QtQuick
import Quickshell
import "plugin" as Plugin

// Shell config for the throwaway Quickshell instance run.sh starts: its own
// IPC socket, no window. run.sh places it next to symlinks to Omarchy's
// qs.Commons/qs.Ui and to this repo as "plugin", so the current checkout of
// the widget runs against the real Quickshell, Hyprland and Omarchy modules
// without touching the user's bar. BW_E2E_SETTINGS passes widget settings
// as JSON.
ShellRoot {
  QtObject {
    id: probeBar

    property color foreground: "#ffffff"
    property color barForeground: "#ffffff"
    property color urgent: "#ff0000"
    property string fontFamily: "monospace"
    property bool vertical: false
    property int barSize: 26

    function run(command) {
      console.log("run:", command)
    }

    function showTooltip(target, text) {
    }

    function hideTooltip(target) {
    }
  }

  Plugin.Workspaces {
    bar: probeBar
    settings: JSON.parse(Quickshell.env("BW_E2E_SETTINGS") || "{}")
  }
}
