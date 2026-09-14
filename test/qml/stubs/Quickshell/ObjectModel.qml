import QtQuick

// Stand-in for Quickshell's ObjectModel: a list of objects exposed as
// `values`. Assigning a new array notifies bindings like the real model.
// `objectInsertedPost`/`objectRemovedPost` only fire from `testInsert`/
// `testRemove` - a plain `values = [...]` assignment (what most fixtures
// use to seed initial state) does not, matching how the real model only
// fires them for an actual incremental insert/remove.
QtObject {
  id: root

  property var values: []

  signal objectInsertedPost(var object, int index)
  signal objectRemovedPost(var object, int index)

  function indexOf(object) {
    return root.values.indexOf(object)
  }

  function testInsert(object, index) {
    var at = index === undefined ? root.values.length : index
    var next = root.values.slice()
    next.splice(at, 0, object)
    root.values = next
    root.objectInsertedPost(object, at)
  }

  function testRemove(object) {
    var at = root.values.indexOf(object)
    if (at === -1) return
    var next = root.values.slice()
    next.splice(at, 1)
    root.values = next
    root.objectRemovedPost(object, at)
  }
}
