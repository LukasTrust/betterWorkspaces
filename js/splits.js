// Rebuilding the window layout a setup was saved with.
//
// Hyprland doesn't expose its dwindle tree and can't be told a window's
// position directly (github.com/hyprwm/Hyprland/discussions/13035), so the
// tree is worked back out of the rectangles a setup was saved with. Splitting
// only ever divides one currently-unsplit window in two, so a valid tree is
// one where, at every level, the rectangles fall cleanly on one side or the
// other of a single straight line spanning the whole group - a "guillotine"
// partition. A pinwheel of windows (each overlapping its neighbours across
// both axes) has no such line at any level and can't be reproduced this way;
// `inferSplitTree` says so plainly instead of guessing.
//
// Pure logic, so it runs under plain Node in the tests with no
// Quickshell/Hyprland runtime. Anything needing a Quickshell singleton
// (Quickshell.iconPath, DesktopEntries, Hyprland) stays in QML and is passed
// in here as plain data or a callback.
//
// A QML JavaScript resource cannot import another one without `.import`,
// which plain Node cannot parse - so every file in js/ stands alone, and a
// QML file imports each of the ones it needs. That is also why the two
// three-line helpers `own` and `isPlainObject` appear in more than one file
// rather than being shared.

var SPLIT_EPSILON = 0.01

function boundsOf(group) {
  var minX = Infinity, minY = Infinity, maxX = -Infinity, maxY = -Infinity
  for (var i = 0; i < group.length; i++) {
    var w = group[i]
    minX = Math.min(minX, w.x)
    minY = Math.min(minY, w.y)
    maxX = Math.max(maxX, w.x + w.width)
    maxY = Math.max(maxY, w.y + w.height)
  }
  return { x: minX, y: minY, width: maxX - minX, height: maxY - minY }
}

// Whether `group` covers `bounds` fully along one axis, edge to edge - the
// check that stops a split from being accepted with a gap left over that
// belongs to neither side.
function spansFully(group, bounds, axis, size) {
  var lo = Infinity, hi = -Infinity
  for (var i = 0; i < group.length; i++) {
    lo = Math.min(lo, group[i][axis])
    hi = Math.max(hi, group[i][axis] + group[i][size])
  }
  return Math.abs(lo - bounds[axis]) <= SPLIT_EPSILON && Math.abs(hi - (bounds[axis] + bounds[size])) <= SPLIT_EPSILON
}

// One attempt at dividing `group` with a single line perpendicular to
// `direction` ("vertical" = a left/right divide, "horizontal" = top/bottom).
// Returns the two sides, or null if no such line cleanly separates every
// rectangle in the group without straddling it.
function trySplit(group, bounds, direction) {
  var axis = direction === "vertical" ? "x" : "y"
  var size = direction === "vertical" ? "width" : "height"
  var crossAxis = direction === "vertical" ? "y" : "x"
  var crossSize = direction === "vertical" ? "height" : "width"

  var candidates = {}
  for (var i = 0; i < group.length; i++) {
    candidates[group[i][axis]] = true
    candidates[group[i][axis] + group[i][size]] = true
  }
  var lines = []
  for (var line in candidates) {
    var value = Number(line)
    if (value > bounds[axis] + SPLIT_EPSILON && value < bounds[axis] + bounds[size] - SPLIT_EPSILON)
      lines.push(value)
  }
  lines.sort(function(a, b) { return a - b })

  for (var l = 0; l < lines.length; l++) {
    var first = [], second = [], straddles = false
    for (var g = 0; g < group.length; g++) {
      var w = group[g]
      var lo = w[axis], hi = w[axis] + w[size]
      if (hi <= lines[l] + SPLIT_EPSILON) first.push(w)
      else if (lo >= lines[l] - SPLIT_EPSILON) second.push(w)
      else { straddles = true; break }
    }
    if (straddles || first.length === 0 || second.length === 0) continue
    if (!spansFully(first, bounds, crossAxis, crossSize)) continue
    if (!spansFully(second, bounds, crossAxis, crossSize)) continue
    return { first: first, second: second }
  }
  return null
}

// A group of one or more windows (each `{ index, x, y, width, height }`, the
// index being its position in the saved setup) as a tree of
// `{ type: "leaf", index }` and `{ type: "split", direction, first, second }`
// nodes - "vertical" puts `first` on the left and `second` on the right,
// "horizontal" puts `first` on top and `second` below. A group that can't be
// split on either axis becomes `{ type: "flat", indices }`: every window in
// save order, with no claim about how they were actually arranged.
function decomposeGroup(group) {
  if (group.length === 1) return { type: "leaf", index: group[0].index }

  var bounds = boundsOf(group)
  var vertical = trySplit(group, bounds, "vertical")
  if (vertical) {
    return {
      type: "split",
      direction: "vertical",
      first: decomposeGroup(vertical.first),
      second: decomposeGroup(vertical.second)
    }
  }
  var horizontal = trySplit(group, bounds, "horizontal")
  if (horizontal) {
    return {
      type: "split",
      direction: "horizontal",
      first: decomposeGroup(horizontal.first),
      second: decomposeGroup(horizontal.second)
    }
  }

  var indices = []
  for (var i = 0; i < group.length; i++) indices.push(group[i].index)
  return { type: "flat", indices: indices }
}

// `windows` is a setup's windows in save order, each with a `rect`
// (`{ x, y, width, height }`, relative to the workspace) and `floating`.
// Floating windows take no part in the split tree - they get placed at their
// exact saved rectangle once the tiled ones are open - so they come back
// separately as `floatingIndices`. `tiled` is null when every window floats.
function inferSplitTree(windows) {
  var list = windows || []
  var tiled = []
  var floatingIndices = []
  for (var i = 0; i < list.length; i++) {
    var w = list[i] || {}
    if (w.floating) {
      floatingIndices.push(i)
      continue
    }
    var rect = w.rect || {}
    tiled.push({
      index: i,
      x: Number(rect.x) || 0,
      y: Number(rect.y) || 0,
      width: Number(rect.width) || 0,
      height: Number(rect.height) || 0
    })
  }

  return {
    tiled: tiled.length > 0 ? decomposeGroup(tiled) : null,
    floatingIndices: floatingIndices
  }
}

// The leaf that must exist, as a single unsplit window, before any of a
// node's own splits can happen - the one every split in the tree eventually
// traces back to `first`, down to a leaf.
function seedIndex(node) {
  if (node.type === "leaf") return node.index
  if (node.type === "flat") return node.indices[0]
  return seedIndex(node.first)
}

// A tree's construction order flattened into the moves that actually build
// it: focus an already-open window, preselect a direction, open the next
// one. Splitting only ever divides a single, not-yet-split window, so a
// node's own split must run *before* either side is subdivided further -
// `first` cannot be sliced up as if it already had its final, smaller share
// of the space, because until the split happens it still has the whole
// thing.
//
// Returns the moves after the very first window - the one that starts with
// nothing open yet and so takes no focus or preselect - which the caller
// prepends itself via `seedIndex`.
function splitSteps(node) {
  if (node.type === "leaf") return []
  if (node.type === "flat") {
    var steps = []
    for (var i = 1; i < node.indices.length; i++)
      steps.push({ focusIndex: node.indices[i - 1], preselect: "right", index: node.indices[i] })
    return steps
  }

  var firstSeed = seedIndex(node.first)
  var secondSeed = seedIndex(node.second)
  var cut = {
    focusIndex: firstSeed,
    preselect: node.direction === "vertical" ? "right" : "down",
    index: secondSeed
  }
  return [cut].concat(splitSteps(node.first), splitSteps(node.second))
}

// The full open order for a tiled split tree: `{ index, preselect,
// focusIndex }` per window, in the order to run them in. The very first
// entry has `preselect`/`focusIndex` both null - there is nothing yet to
// focus or split. `null` in (no tiled windows at all) comes back as `[]`.
function splitTreeSteps(tree) {
  if (!tree) return []
  var steps = [{ index: seedIndex(tree), preselect: null, focusIndex: null }]
  var rest = splitSteps(tree)
  for (var i = 0; i < rest.length; i++)
    steps.push({ index: rest[i].index, preselect: rest[i].preselect, focusIndex: rest[i].focusIndex })
  return steps
}

// The inverse of `relativeRect`: a saved 0..1 rectangle scaled back into
// real pixels for wherever it's being opened - not necessarily the same
// size as the workspace it was saved from, which is exactly why the saved
// rect is relative in the first place.
function absoluteRect(rect, area) {
  var r = rect || {}
  var a = area || {}
  var areaWidth = Number(a.width) || 0
  var areaHeight = Number(a.height) || 0
  return {
    x: (Number(a.x) || 0) + (Number(r.x) || 0) * areaWidth,
    y: (Number(a.y) || 0) + (Number(r.y) || 0) * areaHeight,
    width: (Number(r.width) || 0) * areaWidth,
    height: (Number(r.height) || 0) * areaHeight
  }
}

// Turns a saved setup into the ordered list of operations that open it. The
// caller (QML - only it can talk to Hyprland and launch a process) walks
// this list one at a time: launch the window's recipe, wait for it to
// appear, then act on what the entry says, before moving to the next.
//
// A tiled entry carries `focusIndex`/`preselect` straight from
// `splitTreeSteps`: focus the already-open window at that *setup* index (by
// whatever address it ended up with - this only ever deals in indices, the
// address is something only the caller, watching windows actually open,
// can know) and preselect that direction before launching. `preselect: null`
// means just open it - either the very first window, or a step from an
// indecomposable ("flat") group with no direction worth preselecting.
//
// A floating entry carries the exact rect to place the window at once it's
// open, already scaled into `targetArea` - which need not be the area it
// was saved from.
//
// Tiled windows come first, in build order, so every floating window is
// free to be positioned last without disturbing the tiled layout underneath
// it.
function planOpenSetup(setup, targetArea) {
  var windows = (setup && setup.windows) || []
  var captured = []
  for (var i = 0; i < windows.length; i++) {
    var w = windows[i] || {}
    captured.push({ index: i, floating: !!w.floating, rect: w.rect })
  }

  var tree = inferSplitTree(captured)
  var steps = splitTreeSteps(tree.tiled)

  var operations = []
  for (var s = 0; s < steps.length; s++) {
    var step = steps[s]
    operations.push({
      index: step.index,
      recipe: windows[step.index].recipe,
      floating: false,
      preselect: step.preselect,
      focusIndex: step.focusIndex,
      rect: null
    })
  }
  for (var f = 0; f < tree.floatingIndices.length; f++) {
    var index = tree.floatingIndices[f]
    operations.push({
      index: index,
      recipe: windows[index].recipe,
      floating: true,
      preselect: null,
      focusIndex: null,
      rect: absoluteRect(windows[index].rect, targetArea)
    })
  }
  return operations
}

// Node's CommonJS module loader defines `module`; QML's JS engine never
// does, so this is a no-op when the file is imported as a QML library.

// Node, for the unit tests. In QML this branch is never taken - the file is
// imported as a plain JavaScript resource, and `module` doesn't exist there.
if (typeof module !== "undefined") {
  module.exports = {
    inferSplitTree: inferSplitTree,
    splitTreeSteps: splitTreeSteps,
    absoluteRect: absoluteRect,
    planOpenSetup: planOpenSetup
  }
}
