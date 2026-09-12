pragma Singleton

import QtQuick

// Stand-in for Quickshell's DesktopEntries singleton. Entries are plain
// objects ({ id, name, icon, startupClass }). Lookups are counted so tests
// can assert on the widget's icon cache. Members prefixed with "test" don't
// exist on the real object.
QtObject {
  id: root

  property var applications: ({
      values: []
    })
  property var testEntries: ({})
  // The counter lives inside a plain object on purpose: lookups run inside
  // the widget's icon bindings, and incrementing a notifying property there
  // would make those bindings depend on the counter (a binding loop the
  // real DesktopEntries doesn't have).
  property var testStats: ({
      lookups: 0
    })

  function byId(id) {
    root.testStats.lookups++
    var entry = root.testEntries[String(id)]
    return entry === undefined ? null : entry
  }

  // Simplified stand-in for Quickshell's fuzzy scoring: matches an entry by
  // desktop id, StartupWMClass or name, case-insensitively.
  function heuristicLookup(name) {
    root.testStats.lookups++
    var wanted = String(name).toLowerCase()
    for (var key in root.testEntries) {
      var entry = root.testEntries[key]
      if (key.toLowerCase() === wanted || String(entry.startupClass || "").toLowerCase() === wanted || String(entry.name || "").toLowerCase() === wanted)
        return entry
    }
    return null
  }

  // Replaces the installed app list and emits applicationsChanged, the way
  // installing or uninstalling an app does.
  function testSetEntries(entries) {
    root.testEntries = entries
    var list = []
    for (var key in entries)
      list.push(entries[key])
    root.applications = {
      values: list
    }
  }

  function testReset() {
    root.testEntries = ({})
    root.testStats = ({
        lookups: 0
      })
    root.applications = ({
        values: []
      })
  }
}
