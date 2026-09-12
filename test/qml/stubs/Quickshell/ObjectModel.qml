import QtQuick

// Stand-in for Quickshell's ObjectModel: a list of objects exposed as
// `values`. Assigning a new array notifies bindings like the real model.
QtObject {
  property var values: []

  function indexOf(object) {
    return values.indexOf(object)
  }
}
