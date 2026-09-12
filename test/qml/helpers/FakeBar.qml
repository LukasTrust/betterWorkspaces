import QtQuick

// Test double for the bar facade third-party widgets receive as `bar`
// ($OMARCHY_PATH/shell/Ui/PluginBarApi.qml). Every call is recorded so tests
// can assert on the commands and tooltips a widget produced. Members
// prefixed with "test" don't exist on the real facade.
QtObject {
  id: api

  property color foreground: "#cacccc"
  property color barForeground: "#dddddd"
  property color background: "#101010"
  property color urgent: "#a55555"
  property string fontFamily: "monospace"
  property string position: "top"
  property bool vertical: false
  property int barSize: 26
  property bool transparent: false
  property bool foregroundAnimationEnabled: true

  // run() commands, in order.
  property var testCommands: []
  // { action: "show" | "hide", target, text } entries, in order.
  property var testTooltipLog: []

  function run(command) {
    api.testCommands = api.testCommands.concat([String(command || "")])
  }

  // Matches Bar.qml's own gate: showTooltip is a silent no-op unless the
  // target carries a `tooltipHovered` property that is exactly `true`. A
  // widget that forgets this property gets no tooltip on the real bar even
  // though calling showTooltip looks like it worked - this stub has to
  // reject the same way or that bug passes tests. "test" prefix since this
  // isn't a real PluginBarApi member, just this stub's own gate.
  function testTargetTooltipHovered(target) {
    return !!target && target.visible !== false && target.opacity !== 0 && target.tooltipHovered === true
  }

  function showTooltip(target, text) {
    if (!api.testTargetTooltipHovered(target) || !text)
      return
    api.testTooltipLog = api.testTooltipLog.concat([
      {
        action: "show",
        target: target,
        text: String(text || "")
      }
    ])
  }

  function hideTooltip(target) {
    api.testTooltipLog = api.testTooltipLog.concat([
      {
        action: "hide",
        target: target,
        text: ""
      }
    ])
  }

  function registerClickTarget(target) {
  }

  function unregisterClickTarget(target) {
  }

  function requestPopout(owner) {
  }

  function releasePopout(owner) {
  }

  function switchPanelFrom(owner, direction) {
    return false
  }

  function targetBelongsToWindow(target, window) {
    return false
  }

  function moduleWidgets(id) {
    return []
  }

  function setCenterHoverRevealSuppressed(value) {
  }

  function testReset() {
    api.vertical = false
    api.position = "top"
    api.barSize = 26
    api.foregroundAnimationEnabled = true
    api.testCommands = []
    api.testTooltipLog = []
  }
}
