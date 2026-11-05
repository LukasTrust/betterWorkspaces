import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland

import "../js/settings.js" as Settings
import "../js/setups.js" as Setups

// Runs once when the shell starts: opens whichever saved setups are
// assigned a boot workspace (the "Beim Start öffnen" section of
// SettingsView.qml). Windowless like every other view in this plugin -
// nothing here is visual, it only launches apps and talks to Hyprland.
Item {
  id: root
  visible: false

  // Injected by omarchy-shell's service loader.
  property var shell: null
  property var manifest: null

  // Not `readonly`: a test overrides both to point at a throwaway location
  // and a fixed signature instead of this machine's real runtime dir and
  // whatever Hyprland session happens to be running the test.
  property string runtimeDir: String(Quickshell.env("XDG_RUNTIME_DIR") || "/tmp") + "/better-workspaces"
  readonly property string guardPath: root.runtimeDir + "/boot-guard"
  // Ties the guard to this particular Hyprland run, not just "has this
  // plugin ever booted" - a fresh login gets a fresh signature and so a
  // fresh boot, while `omarchy restart shell` inside the same session
  // reuses the one already on disk and does nothing.
  property string signature: String(Quickshell.env("HYPRLAND_INSTANCE_SIGNATURE") || "")

  property var _queue: []
  property int _queueIndex: 0

  // Every Hyprland request this makes, in order - so a test can see the
  // actual sequence, same reasoning as `SetupOpener.dispatched`.
  signal dispatched(string request)

  function dispatch(request) {
    Hyprland.dispatch(request)
    root.dispatched(request)
  }

  // The one store instance - same setups.json the save dialog and the
  // overview's setups strip read, so boot always matches what's configured.
  SetupStore {
    id: setupStore
    objectName: "setupStore"
  }

  SetupOpener {
    id: setupOpener
    objectName: "setupOpener"
    onFinished: root._openNext()
  }

  // One synchronous read at startup, same pattern as SaveSetupView's
  // `/proc/<pid>/cmdline` reader: `blockLoading`/`blockAllReads` are both
  // required for a first access to actually return what's on disk instead
  // of an empty string. A missing file (first boot ever) reads as "" too,
  // which `Setups.shouldRunBoot` already treats as "not this session yet".
  FileView {
    id: guardFile
    objectName: "guardFile"
    path: root.guardPath
    blockLoading: true
    blockAllReads: true
    printErrors: false
  }

  // `mkdir -p` is a no-op once the directory exists, so this runs on every
  // boot check rather than only the first - simpler than tracking whether
  // it already happened, and this only ever runs once per Hyprland session
  // regardless.
  Process {
    id: mkdirProcess
    objectName: "mkdirProcess"
    command: ["mkdir", "-p", root.runtimeDir]
    onExited: function (exitCode) {
      if (exitCode === 0)
        guardFile.setText(root.signature)
    }
  }

  // Which block of ten workspaces each monitor owns, from the file Hyprland
  // keeps them in - a setup is assigned slot 1-10 of a monitor's block, and
  // only this says which Hyprland workspace that is.
  MonitorBlocks {
    id: monitorBlocks
    objectName: "monitorBlocks"
  }

  // The monitor a boot entry is for. A setup with none assigned, or whose
  // monitor is not plugged in now, goes to the focused monitor (whichever
  // Hyprland put the cursor on at startup): boot is the one time there is
  // no "workspace you were already on" to fall back to either, so it is the
  // least arbitrary guess, same fallback `Overview.qml` uses for its own "+"
  // card.
  //
  // `entry.monitor` is a connector or, so that a dock or a port change does
  // not lose it, the monitor's identity from the monitor-workspaces file.
  function monitorFor(entry) {
    if (entry.monitor.length > 0) {
      var values = Hyprland.monitors.values
      var names = []
      for (var i = 0; i < values.length; i++)
        names.push(values[i].name)
      var connector = Setups.bootMonitorConnector(entry.monitor, names, monitorBlocks.identities)
      for (var j = 0; j < values.length; j++)
        if (connector.length > 0 && values[j].name === connector)
          return values[j]
    }
    return Hyprland.focusedMonitor
  }

  // The Hyprland workspace a boot entry's slot is on that monitor. With no
  // monitor known at all, block 0 - the one a single monitor has.
  function workspaceIdFor(entry, monitor) {
    if (!monitor)
      return entry.slot
    var active = monitor.activeWorkspace ? monitor.activeWorkspace.id : 0
    return Settings.workspaceIdFor(Settings.monitorBlock(monitorBlocks.blocks, monitor.name, active), entry.slot)
  }

  // The same request the bar and the overview send, so a workspace that
  // does not exist yet is made on the right monitor rather than on
  // whichever one has focus.
  function focusRequestFor(entry, monitor) {
    var id = root.workspaceIdFor(entry, monitor)
    if (!monitor)
      return Settings.focusWorkspaceRequest(id, 0, "", false)
    return Settings.focusWorkspaceRequest(id, Settings.blockOf(id), monitor.name, monitorBlocks.perMonitor)
  }

  function monitorArea(monitor) {
    if (!monitor)
      return {
        x: 0,
        y: 0,
        width: 0,
        height: 0
      }
    // Monitor width/height are physical pixels, but the window rectangles
    // saved setups are replayed against are in logical/layout pixels, i.e.
    // physical / scale. Convert so both share the same coordinate space.
    var scale = monitor.scale > 0 ? monitor.scale : 1
    return {
      x: monitor.x,
      y: monitor.y,
      width: monitor.width / scale,
      height: monitor.height / scale
    }
  }

  function _openNext() {
    if (root._queueIndex >= root._queue.length)
      return
    var entry = root._queue[root._queueIndex]
    root._queueIndex++
    var setup = setupStore.setups[entry.name]
    if (!setup) {
      root._openNext()
      return
    }
    // A launched process lands on whichever workspace is focused when it
    // maps, not wherever it was launched "for" - `Overview.openSetup` does
    // the same focus-first dance for the interactive path, and boot has no
    // "workspace you're already on" to lean on instead.
    var monitor = root.monitorFor(entry)
    root.dispatch(root.focusRequestFor(entry, monitor))
    setupOpener.open(setup, root.monitorArea(monitor))
  }

  function runBoot() {
    if (!Setups.shouldRunBoot(guardFile.text(), root.signature))
      return
    mkdirProcess.running = true
    root._queue = Setups.bootEntries(setupStore.setups)
    root._queueIndex = 0
    if (root._queue.length > 0)
      root._openNext()
  }

  // Hyprland can still be discovering monitors in the moment the shell
  // starts, which would put a multi-monitor boot's windows on the wrong
  // screen. Wait for a quiet period with no monitor added or removed before
  // opening anything - a settle timer restarted only off real Hyprland
  // events, not a poll (same pattern as `SetupOpener.settleMs`).
  property int settleMs: 1000

  Timer {
    id: settleTimer
    objectName: "settleTimer"
    interval: root.settleMs
    onTriggered: root.runBoot()
  }

  Connections {
    target: Hyprland.monitors
    function onObjectInsertedPost() {
      settleTimer.restart()
    }
    function onObjectRemovedPost() {
      settleTimer.restart()
    }
  }

  Component.onCompleted: settleTimer.restart()
}
