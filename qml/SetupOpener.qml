import QtQuick
import Quickshell
import Quickshell.Hyprland

import "../js/logic.js" as Logic

// Opens a saved setup: walks the plan `Logic.planOpenSetup` already worked
// out, one window at a time. Splitting only ever divides whichever single
// window is currently focused, so a step has to actually be open before the
// next one's preselect means anything - there is no way to fire all the
// launches at once and sort the layout out afterwards.
//
// Windowless, like every other view here, so the sequencing itself is
// testable without a real compositor; only the live dispatch/launch calls
// need one.
Item {
  id: root
  visible: false

  // Every Hyprland request this makes, in order - so a test (or a future
  // "what is it doing" indicator) can see the actual sequence.
  signal dispatched(string request)
  // Fires once the whole plan has been worked through - `true` if every
  // window appeared in time, `false` if at least one step timed out and was
  // skipped.
  signal finished(bool completed)

  property int timeoutMs: 30000
  // A window that was *just* inserted isn't reliably focusable by address
  // yet - Quickshell reports the new toplevel a beat before Hyprland's own
  // `hl.dsp.focus` can resolve it, so an immediate focus request fails with
  // "window not found" (observed live: every multi-window restore). The
  // preselect that follows still goes through regardless, landing on
  // whatever was focused before instead of the window this step just
  // opened - silently wrecking the rest of the layout. Giving Hyprland's
  // own bookkeeping a moment to catch up before touching the new window
  // fixes it; there is no dispatch result to poll instead, `dispatch()` is
  // fire-and-forget.
  property int settleMs: 150
  property bool running: false

  property var _plan: []
  property int _stepIndex: 0
  property var _addressByIndex: ({})
  property bool _timedOut: false

  function dispatch(request) {
    Hyprland.dispatch(request)
    root.dispatched(request)
  }

  // A desktop entry beats a raw command line whenever a setup has one -
  // same reasoning as capturing it in the first place: `execute()` goes
  // through the installed app's own launch recipe (icon, startup
  // notification, working directory) rather than replaying a frozen argv.
  // Either way, nothing runs through a shell: `execute()` is Quickshell's
  // own launcher, and a bare argv goes straight to `execDetached`.
  function launch(recipe) {
    if (!recipe)
      return
    if (recipe.type === "desktop-entry") {
      var entry = DesktopEntries.byId(recipe.id)
      if (entry && typeof entry.execute === "function") {
        entry.execute()
        return
      }
    }
    if (recipe.type === "argv" && Array.isArray(recipe.argv) && recipe.argv.length > 0)
      Quickshell.execDetached(recipe.argv)
  }

  // Starts opening `setup` on `targetArea` (the workspace's monitor
  // rectangle, for placing floating windows). Does nothing if a plan is
  // already running - one restore at a time, since steps share the single
  // "currently focused window" preselect splits off of.
  function open(setup, targetArea) {
    if (root.running)
      return
    var plan = Logic.planOpenSetup(setup, targetArea)
    root._plan = plan
    root._stepIndex = 0
    root._addressByIndex = ({})
    root._timedOut = false
    if (plan.length === 0) {
      root.finished(true)
      return
    }
    root.running = true
    root._runStep()
  }

  function _runStep() {
    if (root._stepIndex >= root._plan.length) {
      root.running = false
      root.finished(!root._timedOut)
      return
    }
    var op = root._plan[root._stepIndex]
    if (op.preselect !== null && op.focusIndex !== null) {
      var address = root._addressByIndex[op.focusIndex]
      if (address)
        root.dispatch("hl.dsp.focus({ window = \"" + Logic.windowSelector(address) + "\" })")
      root.dispatch("hl.dsp.layout(\"preselect " + (op.preselect === "right" ? "r" : "d") + "\")")
    }
    stepTimer.restart()
    root.launch(op.recipe)
  }

  // The very next toplevel to appear is the one this step just launched -
  // steps run strictly one at a time, so there is nothing else it could be
  // (short of something unrelated opening a window in the same moment,
  // which would misattribute one step and is the same "best effort on a
  // busy workspace" tradeoff the rest of restoring already makes).
  Connections {
    target: Hyprland.toplevels
    function onObjectInsertedPost(object, index) {
      if (!root.running || !stepTimer.running)
        return
      stepTimer.stop()
      var op = root._plan[root._stepIndex]
      root._addressByIndex[op.index] = object.address
      settleTimer.restart()
    }
  }

  // A launch that never produces a window (a broken recipe, a crashed app)
  // can't be allowed to stall every window after it - skip on and let the
  // rest of the setup still open.
  Timer {
    id: stepTimer
    objectName: "stepTimer"
    interval: root.timeoutMs
    onTriggered: {
      root._timedOut = true
      root._stepIndex++
      root._runStep()
    }
  }

  // See `settleMs` - the pause between a window appearing and this opener
  // acting on its address.
  Timer {
    id: settleTimer
    objectName: "settleTimer"
    interval: root.settleMs
    onTriggered: {
      root._stepIndex++
      root._runStep()
    }
  }
}
