import QtQuick

// Stand-in for Quickshell.Io's FileView. There is no real filesystem here:
// a test seeds what a path holds with `testSetContent(content, path)` /
// `testSetMissing(path)` (defaulting to the current `path`, for a FileView
// that only ever points at one file) and reads back what got written via
// `testWrites`.
//
// Like the real one it loads when it is created and whenever `path` changes,
// answering with `loaded` or `loadFailed`; and with `watchChanges` on, a
// seeded change to its file emits `fileChanged`, which a handler answers with
// `reload()`.
QtObject {
  id: root

  property string path: ""
  property bool atomicWrites: false
  property bool blockLoading: false
  property bool blockAllReads: false
  property bool printErrors: true
  property bool watchChanges: false

  // path -> content, so one stubbed FileView can stand in for reads at more
  // than one path (e.g. a shared /proc/<pid>/cmdline reader).
  property var testFiles: ({})
  property var testWrites: []

  signal saved
  signal saveFailed(int error)
  signal loaded
  signal loadFailed(int error)
  signal fileChanged

  // Loading is not synchronous on the real one, but it has finished by the
  // time anything a test does next can see it, and nothing here reads the
  // difference.
  function reload() {
    if (root.testFiles[root.path] === undefined)
      root.loadFailed(2)
    else
      root.loaded()
  }

  Component.onCompleted: root.reload()
  onPathChanged: root.reload()

  function text() {
    var content = root.testFiles[root.path]
    return content === undefined ? "" : content
  }

  function setText(value) {
    // A fresh object, not an in-place mutation of the existing one: `var`
    // properties only notify on reassignment, and a mutated-in-place
    // `testFiles` would leave anything bound through `text()` (like
    // SetupStore's `setups`) stuck on a stale value forever.
    var content = String(value)
    var next = {}
    for (var key in root.testFiles)
      next[key] = root.testFiles[key]
    next[root.path] = content
    root.testFiles = next
    root.testWrites = root.testWrites.concat([content])
    root.saved()
  }

  function testSetContent(content, path) {
    var target = path === undefined ? root.path : path
    var next = {}
    for (var key in root.testFiles)
      next[key] = root.testFiles[key]
    next[target] = String(content)
    root.testFiles = next
    if (root.watchChanges && target === root.path)
      root.fileChanged()
  }

  function testSetMissing(path) {
    var target = path === undefined ? root.path : path
    var next = {}
    for (var key in root.testFiles)
      if (key !== target)
        next[key] = root.testFiles[key]
    root.testFiles = next
    if (root.watchChanges && target === root.path)
      root.fileChanged()
  }

  function testReset() {
    root.testFiles = ({})
    root.testWrites = []
  }
}
