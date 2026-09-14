import QtQuick

// Stand-in for Quickshell.Io's Process. Runs nothing for real: setting
// `running` to true immediately "finishes" with `testExitCode` (0 by
// default), recording the command in `testRunHistory` so a test can check
// what was actually asked to run.
QtObject {
  id: root

  property bool running: false
  property var command: []

  property int testExitCode: 0
  property var testRunHistory: []

  signal exited(int exitCode, int exitStatus)

  onRunningChanged: {
    if (!root.running)
      return
    root.testRunHistory = root.testRunHistory.concat([root.command.slice()])
    root.running = false
    root.exited(root.testExitCode, 0)
  }

  function testReset() {
    root.testExitCode = 0
    root.testRunHistory = []
  }
}
