// Working a dwindle split tree back out of saved rectangles, and the steps
// that rebuild it.

const test = require("node:test")
const assert = require("node:assert/strict")

const {
  inferSplitTree,
  splitTreeSteps,
  absoluteRect,
  planOpenSetup
} = require("../js/splits.js")

function sized(count, width, height) {
  return Array.from({ length: count }, () => ({ width, height }))
}

function rect(x, y, width, height, floating) {
  return { rect: { x, y, width, height }, floating: !!floating }
}

function aRecipe(id) {
  return { type: "desktop-entry", id: id }
}

function tiledWindow(recipeId, x, y, width, height) {
  return { recipe: aRecipe(recipeId), floating: false, rect: { x, y, width, height } }
}

function floatingWindow(recipeId, x, y, width, height) {
  return { recipe: aRecipe(recipeId), floating: true, rect: { x, y, width, height } }
}

test("inferSplitTree keeps a single window as one leaf", () => {
  const tree = inferSplitTree([rect(0, 0, 1, 1)])
  assert.deepEqual(tree, { tiled: { type: "leaf", index: 0 }, floatingIndices: [] })
})

test("inferSplitTree finds two windows side by side", () => {
  const tree = inferSplitTree([rect(0, 0, 0.5, 1), rect(0.5, 0, 0.5, 1)])
  assert.deepEqual(tree.tiled, {
    type: "split",
    direction: "vertical",
    first: { type: "leaf", index: 0 },
    second: { type: "leaf", index: 1 }
  })
})

test("inferSplitTree finds two windows stacked", () => {
  const tree = inferSplitTree([rect(0, 0, 1, 0.5), rect(0, 0.5, 1, 0.5)])
  assert.deepEqual(tree.tiled, {
    type: "split",
    direction: "horizontal",
    first: { type: "leaf", index: 0 },
    second: { type: "leaf", index: 1 }
  })
})

test("inferSplitTree finds one window beside two stacked ones", () => {
  const tree = inferSplitTree([
    rect(0, 0, 0.5, 1),
    rect(0.5, 0, 0.5, 0.5),
    rect(0.5, 0.5, 0.5, 0.5)
  ])
  assert.deepEqual(tree.tiled, {
    type: "split",
    direction: "vertical",
    first: { type: "leaf", index: 0 },
    second: {
      type: "split",
      direction: "horizontal",
      first: { type: "leaf", index: 1 },
      second: { type: "leaf", index: 2 }
    }
  })
})

test("inferSplitTree finds a 2x2 grid", () => {
  const tree = inferSplitTree([
    rect(0, 0, 0.5, 0.5),
    rect(0.5, 0, 0.5, 0.5),
    rect(0, 0.5, 0.5, 0.5),
    rect(0.5, 0.5, 0.5, 0.5)
  ])
  assert.deepEqual(tree.tiled, {
    type: "split",
    direction: "vertical",
    first: {
      type: "split",
      direction: "horizontal",
      first: { type: "leaf", index: 0 },
      second: { type: "leaf", index: 2 }
    },
    second: {
      type: "split",
      direction: "horizontal",
      first: { type: "leaf", index: 1 },
      second: { type: "leaf", index: 3 }
    }
  })
})

test("inferSplitTree finds a nested, unevenly-sized arrangement", () => {
  // A big window on the left (60%), and the right 40% split top/bottom
  // unevenly again.
  const tree = inferSplitTree([
    rect(0, 0, 0.6, 1),
    rect(0.6, 0, 0.4, 0.3),
    rect(0.6, 0.3, 0.4, 0.7)
  ])
  assert.deepEqual(tree.tiled, {
    type: "split",
    direction: "vertical",
    first: { type: "leaf", index: 0 },
    second: {
      type: "split",
      direction: "horizontal",
      first: { type: "leaf", index: 1 },
      second: { type: "leaf", index: 2 }
    }
  })
})

test("inferSplitTree keeps floating windows out of the tree entirely", () => {
  const tree = inferSplitTree([
    rect(0, 0, 0.5, 1),
    rect(0.2, 0.2, 0.3, 0.3, true),
    rect(0.5, 0, 0.5, 1)
  ])
  assert.deepEqual(tree.floatingIndices, [1])
  assert.deepEqual(tree.tiled, {
    type: "split",
    direction: "vertical",
    first: { type: "leaf", index: 0 },
    second: { type: "leaf", index: 2 }
  })
})

test("inferSplitTree is null when every window floats", () => {
  const tree = inferSplitTree([rect(0, 0, 0.5, 0.5, true), rect(0.5, 0.5, 0.5, 0.5, true)])
  assert.equal(tree.tiled, null)
  assert.deepEqual(tree.floatingIndices, [0, 1])
})

test("inferSplitTree falls back cleanly for a pinwheel no straight line can cut", () => {
  // Four windows in a pinwheel: every vertical or horizontal line inside the
  // group has at least one rectangle straddling it, so neither axis finds a
  // clean split at any level - a "general" partition a guillotine cut can't
  // reproduce.
  const tree = inferSplitTree([
    rect(0, 0, 0.6, 0.4),
    rect(0.6, 0, 0.4, 0.6),
    rect(0.4, 0.6, 0.6, 0.4),
    rect(0, 0.4, 0.4, 0.6)
  ])
  assert.deepEqual(tree.tiled, { type: "flat", indices: [0, 1, 2, 3] })
})

test("splitTreeSteps opens a single leaf with no preselect at all", () => {
  const tree = inferSplitTree([rect(0, 0, 1, 1)]).tiled
  assert.deepEqual(splitTreeSteps(tree), [{ index: 0, preselect: null, focusIndex: null }])
})

test("splitTreeSteps focuses the first window and preselects the second, side by side", () => {
  const tree = inferSplitTree([rect(0, 0, 0.5, 1), rect(0.5, 0, 0.5, 1)]).tiled
  assert.deepEqual(splitTreeSteps(tree), [
    { index: 0, preselect: null, focusIndex: null },
    { index: 1, preselect: "right", focusIndex: 0 }
  ])
})

test("splitTreeSteps stacks the second window below the first", () => {
  const tree = inferSplitTree([rect(0, 0, 1, 0.5), rect(0, 0.5, 1, 0.5)]).tiled
  assert.deepEqual(splitTreeSteps(tree), [
    { index: 0, preselect: null, focusIndex: null },
    { index: 1, preselect: "down", focusIndex: 0 }
  ])
})

test("splitTreeSteps splits the outer pair before subdividing either side", () => {
  const tree = inferSplitTree([
    rect(0, 0, 0.5, 1),
    rect(0.5, 0, 0.5, 0.5),
    rect(0.5, 0.5, 0.5, 0.5)
  ]).tiled
  assert.deepEqual(splitTreeSteps(tree), [
    { index: 0, preselect: null, focusIndex: null },
    // The outer left/right cut, made while window 0 still fills the screen.
    { index: 1, preselect: "right", focusIndex: 0 },
    // Only now does the right side get divided top/bottom.
    { index: 2, preselect: "down", focusIndex: 1 }
  ])
})

test("splitTreeSteps chains a flat fallback with an arbitrary but usable order", () => {
  const tree = { type: "flat", indices: [2, 0, 1] }
  assert.deepEqual(splitTreeSteps(tree), [
    { index: 2, preselect: null, focusIndex: null },
    { index: 0, preselect: "right", focusIndex: 2 },
    { index: 1, preselect: "right", focusIndex: 0 }
  ])
})

test("splitTreeSteps is empty with no tiled tree at all", () => {
  assert.deepEqual(splitTreeSteps(null), [])
})

test("absoluteRect scales a saved 0..1 rect back into real pixels", () => {
  assert.deepEqual(absoluteRect({ x: 0.5, y: 0, width: 0.5, height: 1 }, { x: 0, y: 0, width: 1920, height: 1080 }), {
    x: 960,
    y: 0,
    width: 960,
    height: 1080
  })
})

test("absoluteRect places it relative to the target area's own origin", () => {
  assert.deepEqual(absoluteRect({ x: 0, y: 0, width: 0.25, height: 0.25 }, { x: 1920, y: 0, width: 1920, height: 1080 }), {
    x: 1920,
    y: 0,
    width: 480,
    height: 270
  })
})

test("absoluteRect copes with nothing usable", () => {
  assert.deepEqual(absoluteRect(null, null), { x: 0, y: 0, width: 0, height: 0 })
})

test("planOpenSetup opens a single tiled window with no preselect", () => {
  const setup = { windows: [tiledWindow("a", 0, 0, 1, 1)] }
  assert.deepEqual(planOpenSetup(setup, { width: 1920, height: 1080 }), [
    { index: 0, recipe: aRecipe("a"), floating: false, preselect: null, focusIndex: null, rect: null }
  ])
})

test("planOpenSetup carries the split direction and focus target for a second tiled window", () => {
  const setup = { windows: [tiledWindow("a", 0, 0, 0.5, 1), tiledWindow("b", 0.5, 0, 0.5, 1)] }
  assert.deepEqual(planOpenSetup(setup, { width: 1920, height: 1080 }), [
    { index: 0, recipe: aRecipe("a"), floating: false, preselect: null, focusIndex: null, rect: null },
    { index: 1, recipe: aRecipe("b"), floating: false, preselect: "right", focusIndex: 0, rect: null }
  ])
})

test("planOpenSetup puts every floating window after the tiled ones, positioned on the target area", () => {
  const setup = {
    windows: [
      tiledWindow("a", 0, 0, 1, 1),
      floatingWindow("b", 0.25, 0.25, 0.5, 0.5)
    ]
  }
  const plan = planOpenSetup(setup, { x: 0, y: 0, width: 1000, height: 1000 })
  assert.equal(plan.length, 2)
  assert.equal(plan[0].index, 0)
  assert.equal(plan[0].floating, false)
  assert.deepEqual(plan[1], {
    index: 1,
    recipe: aRecipe("b"),
    floating: true,
    preselect: null,
    focusIndex: null,
    rect: { x: 250, y: 250, width: 500, height: 500 }
  })
})

test("planOpenSetup handles a workspace that is only floating windows", () => {
  const setup = { windows: [floatingWindow("a", 0, 0, 0.5, 0.5)] }
  const plan = planOpenSetup(setup, { x: 0, y: 0, width: 1000, height: 1000 })
  assert.deepEqual(plan, [
    { index: 0, recipe: aRecipe("a"), floating: true, preselect: null, focusIndex: null, rect: { x: 0, y: 0, width: 500, height: 500 } }
  ])
})

test("planOpenSetup copes with an empty setup", () => {
  assert.deepEqual(planOpenSetup({ windows: [] }, { width: 1920, height: 1080 }), [])
  assert.deepEqual(planOpenSetup(null, { width: 1920, height: 1080 }), [])
})
