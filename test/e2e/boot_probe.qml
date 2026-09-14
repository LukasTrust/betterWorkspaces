import QtQuick
import Quickshell
import "plugin/qml" as Plugin

// The boot service in isolation, for test/e2e/run.sh's boot check. The
// launching shell points HOME at a throwaway directory, so a run here never
// reads or writes the real user's saved setups - only the Hyprland IPC
// underneath is real. The guard file's directory can't ride on
// XDG_RUNTIME_DIR the same way: that also names where the real Wayland
// socket lives, and Quickshell needs the real one to connect at all.
// BW_E2E_BOOT_RUNTIME_DIR carries a throwaway one for the guard file alone,
// the same way probe.qml's BW_E2E_SETTINGS passes the widget its settings.
ShellRoot {
  Plugin.Service {
    property string envRuntimeDir: Quickshell.env("BW_E2E_BOOT_RUNTIME_DIR")
    // Same formula as Service.qml's own default, just with the throwaway
    // directory in place of the real XDG_RUNTIME_DIR when one was passed.
    runtimeDir: envRuntimeDir.length > 0 ? envRuntimeDir : (String(Quickshell.env("XDG_RUNTIME_DIR") || "/tmp") + "/better-workspaces")
  }
}
