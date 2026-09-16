import QtQuick
import Quickshell
import Quickshell.Hyprland

import "../js/selector.js" as Selector
import "../js/splits.js" as Splits

// Opens a saved setup: walks the plan `Splits.planOpenSetup` already worked
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

  // A toplevel's `lastIpcObject` (where its window class lives) is empty
  // the instant it's inserted - Quickshell hasn't asked Hyprland for its
  // `hyprctl clients` details yet - so a step with a class to check against
  // can't decide on the spot. Candidates collect here while
  // `classCheckTimer` gives Hyprland's IPC reply a few chances to land
  // before this step commits to whichever one actually matches.
  property var _pendingClassCandidates: []
  property int _classCheckRetries: 0
  property int classCheckMs: 150
  readonly property int _maxClassCheckRetries: 6

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
    var plan = Splits.planOpenSetup(setup, targetArea)
    root._plan = plan
    root._stepIndex = 0
    root._addressByIndex = ({})
    root._timedOut = false
    root._pendingClassCandidates = []
    root._classCheckRetries = 0
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
        root.dispatch("hl.dsp.focus({ window = \"" + Selector.windowSelector(address) + "\" })")
      root.dispatch("hl.dsp.layout(\"preselect " + (op.preselect === "right" ? "r" : "d") + "\")")
    }
    stepTimer.restart()
    root.launch(op.recipe)
  }

  function _classOf(object) {
    var ipc = (object && object.lastIpcObject) || {}
    return String(ipc.class || ipc.initialClass || "")
  }

  // Commits `object` as the window this step launched: cancels whatever
  // else was pending for it and moves on, same as the old unconditional
  // "the next toplevel is it" path.
  function _acceptCandidate(op, object) {
    stepTimer.stop()
    classCheckTimer.stop()
    root._pendingClassCandidates = []
    root._classCheckRetries = 0
    root._addressByIndex[op.index] = object.address
    settleTimer.restart()
  }

  // The next toplevel to appear is normally the one this step just launched
  // - steps run strictly one at a time - but a multi-window app (a browser
  // restoring its previous session, a profile picker, anything that maps an
  // extra window on its own) can put something unrelated on the toplevel
  // list first. Taking that at face value used to misattribute the step,
  // which then cascaded into every window after it landing on the wrong
  // workspace (observed live with a saved setup that included a
  // multi-window browser). A saved window's `class` is the only signal
  // available to tell the two apart, but it isn't available yet: a
  // freshly inserted toplevel's `lastIpcObject` is still empty until
  // Hyprland answers a fresh `hyprctl clients` query. So a step with a
  // class to check against doesn't decide here - it queues the candidate
  // and `classCheckTimer` sorts it out once the reply lands. A step with
  // no recorded class keeps the old instant-accept behavior.
  Connections {
    target: Hyprland.toplevels
    function onObjectInsertedPost(object, index) {
      if (!root.running || !stepTimer.running)
        return
      var op = root._plan[root._stepIndex]
      if (!op.class) {
        root._acceptCandidate(op, object)
        return
      }
      root._pendingClassCandidates.push({
        address: String(object.address || ""),
        object: object
      })
      Hyprland.refreshToplevels()
      classCheckTimer.restart()
    }
  }

  // Checks every candidate collected since the last try against this
  // step's expected class. A match wins outright. Otherwise, as long as
  // there's still budget left, ask Hyprland again and give it another
  // round - a class that hasn't arrived yet reads the same as one that's
  // wrong, and there's no way to tell those apart except waiting. Once
  // the budget runs out, fall back to the oldest candidate rather than
  // stalling the rest of the setup over a step whose class never confirms
  // (a class Hyprland reports differently than the plugin resolved it, or
  // that genuinely never turns up).
  Timer {
    id: classCheckTimer
    objectName: "classCheckTimer"
    interval: root.classCheckMs
    onTriggered: {
      if (!root.running || !stepTimer.running)
        return
      var op = root._plan[root._stepIndex]
      var pending = root._pendingClassCandidates
      for (var i = 0; i < pending.length; i++) {
        var candidateClass = root._classOf(pending[i].object)
        if (candidateClass.length > 0 && candidateClass.toLowerCase() === op.class.toLowerCase()) {
          root._acceptCandidate(op, pending[i].object)
          return
        }
      }
      root._classCheckRetries++
      if (root._classCheckRetries >= root._maxClassCheckRetries) {
        if (pending.length > 0)
          root._acceptCandidate(op, pending[0].object)
        return
      }
      Hyprland.refreshToplevels()
      classCheckTimer.restart()
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
      classCheckTimer.stop()
      root._pendingClassCandidates = []
      root._classCheckRetries = 0
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
