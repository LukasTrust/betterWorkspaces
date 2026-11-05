import QtQuick
import Quickshell
import Quickshell.Io

import "../js/settings.js" as Settings

// Which block of ten Hyprland workspaces each monitor owns (Omarchy 4.5 gives
// every monitor its own: 1-10, 11-20, ...), read from the file Hyprland keeps
// them in and kept up to date while it changes. The bar, the overview and the
// boot service all need the same answer, so they share this rather than each
// reading the file their own way.
//
// `block` is the block of `monitorName`; the boot service, which asks about
// several monitors, reads `blocks` and calls Settings.monitorBlock itself.
Item {
  id: root
  visible: false

  // The monitor to answer for, and the workspace it is showing: until
  // Hyprland has written the file, that workspace is what says which block
  // the monitor is in.
  property string monitorName: ""
  property int activeWorkspaceId: 0

  // Connector -> block, as parseMonitorBlocks reads it. Empty until the file
  // has loaded, and again if it goes missing.
  property var blocks: ({})
  readonly property int block: Settings.monitorBlock(root.blocks, root.monitorName, root.activeWorkspaceId)

  // Not `readonly`: a test points it at a throwaway path.
  property string path: (Quickshell.env("XDG_STATE_HOME") || Quickshell.env("HOME") + "/.local/state") + "/omarchy/monitor-workspaces"

  FileView {
    objectName: "monitorBlocksFile"
    path: root.path
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: root.blocks = Settings.parseMonitorBlocks(text())
    onLoadFailed: root.blocks = ({})
  }
}
