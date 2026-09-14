import QtQuick
import Quickshell
import Quickshell.Io

import "../js/logic.js" as Logic

// Reads and writes this plugin's saved setups:
// `~/.config/omarchy/better-workspaces/setups.json`. One shared store, so
// the save dialog, the overview's setups list and the boot service all agree
// on what's there.
//
// The file is hand-editable, so a load never throws - `setups` just comes
// back as `{}` for a missing, corrupt or outdated file, same as
// `Logic.validateSetupFile` on its own. A write is atomic (`atomicWrites` on
// the FileView: a temp file, then a rename, so a crash mid-write can't leave
// a half-written file behind) and narrowed to the owner only - both the file
// and the directory holding it, on every write rather than only at creation
// (see `dirModeProcess`) - because a saved setup can carry a command line,
// and a command line can carry tokens or other arguments a user wouldn't
// want group- or world-readable.
Item {
  id: root
  visible: false

  readonly property string configDir: String(Quickshell.env("HOME") || "") + "/.config/omarchy/better-workspaces"
  readonly property string filePath: root.configDir + "/setups.json"

  readonly property var setups: Logic.validateSetupFile(file.text())

  // Fires once a save or delete's write has actually landed (after the
  // permissions are set), so a caller like the save dialog knows it is safe
  // to close.
  signal committed
  signal saveFailed

  property var _pendingWrite: null

  FileView {
    id: file
    objectName: "setupsFile"
    path: root.filePath
    atomicWrites: true
    printErrors: false
    onSaved: chmodProcess.running = true
    onSaveFailed: root.saveFailed()
  }

  // `mkdir -p` is a no-op once the directory exists, so this runs before
  // every write rather than only the first one - simpler than tracking
  // whether it has already happened, and cheap enough that it doesn't
  // matter: this only runs on an explicit save or delete, never on a timer.
  Process {
    id: mkdirProcess
    objectName: "mkdirProcess"
    command: ["mkdir", "-p", "-m", "0700", root.configDir]
    onExited: function (exitCode) {
      if (exitCode !== 0) {
        root._pendingWrite = null
        root.saveFailed()
        return
      }
      dirModeProcess.running = true
    }
  }

  // `mkdir -m` only sets the mode on a directory it actually creates, so a
  // directory that already existed keeps whatever mode it had - an older
  // version of this plugin, or a hand-created one, can leave it group- and
  // world-readable for good. That matters here and not just cosmetically:
  // `atomicWrites` lands the temp file at the umask default (usually 0644)
  // and only then is it narrowed to 0600, so the directory's own mode is
  // what keeps anyone else out in between. Setting it unconditionally is
  // the only way to make that true for a directory this didn't create.
  Process {
    id: dirModeProcess
    objectName: "dirModeProcess"
    command: ["chmod", "0700", root.configDir]
    onExited: function (exitCode) {
      if (exitCode !== 0 || root._pendingWrite === null) {
        root._pendingWrite = null
        if (exitCode !== 0)
          root.saveFailed()
        return
      }
      file.setText(root._pendingWrite)
      root._pendingWrite = null
    }
  }

  Process {
    id: chmodProcess
    objectName: "chmodProcess"
    command: ["chmod", "0600", root.filePath]
    onExited: function (exitCode) {
      if (exitCode === 0)
        root.committed()
      else
        root.saveFailed()
    }
  }

  function _write(nextSetups) {
    root._pendingWrite = JSON.stringify({
      schemaVersion: Logic.SETUP_SCHEMA_VERSION,
      setups: nextSetups
    })
    mkdirProcess.running = true
  }

  // Replaces (or adds) one setup by name and writes the whole file back -
  // `setups.json` holds every setup in one document, so saving one means
  // rewriting all of them.
  function save(name, entry) {
    var next = {}
    for (var key in root.setups)
      next[key] = root.setups[key]
    next[String(name)] = entry
    root._write(next)
  }

  function remove(name) {
    var next = {}
    for (var key in root.setups)
      if (key !== String(name))
        next[key] = root.setups[key]
    root._write(next)
  }

  // For a change that touches more than one setup at once (reassigning a
  // boot workspace can clear it off whichever other setup had it) - one
  // write instead of two `save()` calls racing each other's mkdir/chmod.
  function replaceAll(nextSetups) {
    root._write(nextSetups || {})
  }
}
