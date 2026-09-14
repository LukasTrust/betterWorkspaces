// The overview's geometry and navigation: fitting the cards, placing a window
// inside one, walking the selection, and planning a reorder drag.

const test = require("node:test")
const assert = require("node:assert/strict")

const {
  spreadLayout,
  cardWindowRect,
  nextWorkspaceId,
  navigateGrid,
  navigateWheel,
  planReorder
} = require("../js/cards.js")

// The shape Workspaces.qml hands computeWorkspaceIds: what Hyprland knows
// about right now. Ids listed without a "+" are empty workspaces.
function workspaces(spec) {
  return spec.map(entry => ({
    id: parseInt(entry, 10),
    occupied: String(entry).endsWith("+")
  }))
}

const AREA = { width: 1600, height: 900 }

function sized(count, width, height) {
  return Array.from({ length: count }, () => ({ width, height }))
}

// Every window drawn inside the area it was given, none overlapping any
// other - the one property the overview's middle section has to hold no
// matter how many windows are open or what shape they are.
function assertLaidOut(result, area, count) {
  assert.equal(result.items.length, count)
  for (const item of result.items) {
    assert.ok(item.width > 0 && item.height > 0, "a window was laid out with no size")
    assert.ok(item.x >= -0.001 && item.y >= -0.001, "a window was laid out off the top or left")
    assert.ok(item.x + item.width <= area.width + 0.001, "a window was laid out past the right edge")
    assert.ok(item.y + item.height <= area.height + 0.001, "a window was laid out past the bottom edge")
  }
  for (let i = 0; i < result.items.length; i++) {
    for (let j = i + 1; j < result.items.length; j++) {
      const a = result.items[i]
      const b = result.items[j]
      const apart = a.x + a.width <= b.x + 0.001 || b.x + b.width <= a.x + 0.001
        || a.y + a.height <= b.y + 0.001 || b.y + b.height <= a.y + 0.001
      assert.ok(apart, `windows ${i} and ${j} overlap`)
    }
  }
}

const MONITOR = { x: 0, y: 0, width: 1920, height: 1080 }
const CARD = { width: 192, height: 108 }

// The strip as the overview shows it: an id per card, with the addresses of
// the windows currently on it.
function strip(spec) {
  return Object.entries(spec).map(([id, addresses]) => ({ id: Number(id), addresses }))
}

test("spreadLayout fits any number of windows into the area without overlap", () => {
  for (const count of [1, 2, 5, 12]) {
    const landscape = spreadLayout(sized(count, 1920, 1080), AREA, { spacing: 16, captionHeight: 40 })
    assertLaidOut(landscape, AREA, count)
    const portrait = spreadLayout(sized(count, 1080, 1920), AREA, { spacing: 16, captionHeight: 40 })
    assertLaidOut(portrait, AREA, count)
  }
})

test("spreadLayout keeps every window at its real aspect ratio", () => {
  const result = spreadLayout([
    { width: 1920, height: 1080 },
    { width: 600, height: 1200 },
    { width: 800, height: 800 }
  ], AREA, { spacing: 16, captionHeight: 40 })

  assertLaidOut(result, AREA, 3)
  assert.ok(Math.abs(result.items[0].width / result.items[0].height - 16 / 9) < 0.001)
  assert.ok(Math.abs(result.items[1].width / result.items[1].height - 0.5) < 0.001)
  assert.ok(Math.abs(result.items[2].width / result.items[2].height - 1) < 0.001)
})

test("spreadLayout scales every window by the same factor", () => {
  const result = spreadLayout([{ width: 1920, height: 1080 }, { width: 960, height: 540 }], AREA, {})
  assert.ok(Math.abs(result.items[0].width / 2 - result.items[1].width) < 0.001)
})

test("spreadLayout picks the grid shape that renders the windows largest", () => {
  const spaced = { spacing: 16, captionHeight: 40 }
  // The same two landscape windows: side by side in a wide area, stacked in
  // a tall one.
  assert.equal(spreadLayout(sized(2, 1920, 1080), { width: 1600, height: 900 }, spaced).columns, 2)
  assert.equal(spreadLayout(sized(2, 1920, 1080), { width: 600, height: 1400 }, spaced).columns, 1)
  // Three squares across a wide area, stacked in a narrow one.
  assert.equal(spreadLayout(sized(3, 1000, 1000), AREA, spaced).columns, 3)
  assert.equal(spreadLayout(sized(3, 1000, 1000), { width: 400, height: 1200 }, spaced).columns, 1)

  const twelve = spreadLayout(sized(12, 1920, 1080), AREA, spaced)
  assert.ok(twelve.columns * twelve.rows >= 12, "12 windows need at least 12 slots")
  assert.ok(twelve.columns > 1 && twelve.rows > 1, "12 windows should not end up in a single row or column")
})

test("spreadLayout centres the block, and a short last row under it", () => {
  // 5 landscape windows in a square area come out 2 wide and 3 deep, so the
  // last row holds one window on its own.
  const result = spreadLayout(sized(5, 1600, 900), { width: 1000, height: 1000 }, { spacing: 10 })
  assert.equal(result.columns, 2)
  assert.equal(result.rows, 3)

  const lonely = result.items[4]
  const middleOfRowAbove = (result.items[2].cellX + result.items[3].cellX + result.items[3].cellWidth) / 2
  assert.ok(Math.abs(middleOfRowAbove - (lonely.cellX + lonely.cellWidth / 2)) < 0.001,
    "the last row is not centred under the one above it")

  // And the block as a whole sits centred in the area, top and bottom alike.
  const top = result.items[0].cellY
  const bottom = 1000 - (lonely.cellY + lonely.cellHeight)
  assert.ok(Math.abs(top - bottom) < 0.001, "the block is not vertically centred")
})

test("spreadLayout reserves the caption room under each window, inside its cell", () => {
  const result = spreadLayout(sized(2, 1000, 1000), AREA, { captionHeight: 40 })
  for (const item of result.items) {
    assert.equal(item.cellHeight - item.height, 40)
    assert.ok(item.y + item.height + 40 <= item.cellY + item.cellHeight + 0.001)
  }
})

test("spreadLayout honours an area origin and a scale cap", () => {
  const offset = spreadLayout(sized(1, 1000, 1000), { x: 100, y: 50, width: 400, height: 400 }, {})
  assert.equal(offset.items[0].x, 100)
  assert.equal(offset.items[0].y, 50)

  const capped = spreadLayout(sized(1, 100, 100), AREA, { maxScale: 1 })
  assert.equal(capped.scale, 1)
  assert.equal(capped.items[0].width, 100)
})

test("spreadLayout treats a window with no usable size as a full-area one", () => {
  const result = spreadLayout([{ width: 0, height: 0 }], { width: 800, height: 400 }, {})
  assert.ok(Math.abs(result.items[0].width / result.items[0].height - 2) < 0.001)
})

test("spreadLayout returns nothing to draw rather than breaking", () => {
  const nothing = { columns: 0, rows: 0, scale: 0, items: [] }
  assert.deepEqual(spreadLayout([], AREA, {}), nothing)
  assert.deepEqual(spreadLayout(null, AREA, null), nothing)
  assert.deepEqual(spreadLayout(sized(1, 100, 100), { width: 0, height: 0 }, {}), nothing)
  // An area with no room left once the caption is reserved.
  assert.deepEqual(spreadLayout(sized(1, 100, 100), { width: 100, height: 40 }, { captionHeight: 40 }), nothing)
})

test("cardWindowRect shrinks a window's real rectangle onto the card", () => {
  assert.deepEqual(cardWindowRect({ x: 0, y: 0, width: 1920, height: 1080 }, MONITOR, CARD),
    { x: 0, y: 0, width: 192, height: 108 })
  assert.deepEqual(cardWindowRect({ x: 960, y: 540, width: 960, height: 540 }, MONITOR, CARD),
    { x: 96, y: 54, width: 96, height: 54 })
})

test("cardWindowRect places a window relative to its own monitor", () => {
  const second = { x: 1920, y: 0, width: 1920, height: 1080 }
  assert.deepEqual(cardWindowRect({ x: 2880, y: 0, width: 960, height: 1080 }, second, CARD),
    { x: 96, y: 0, width: 96, height: 108 })
})

test("cardWindowRect clips a window that hangs off the monitor", () => {
  assert.deepEqual(cardWindowRect({ x: -100, y: -50, width: 2120, height: 1180 }, MONITOR, CARD),
    { x: 0, y: 0, width: 192, height: 108 })
  assert.deepEqual(cardWindowRect({ x: 1820, y: 0, width: 1920, height: 1080 }, MONITOR, CARD),
    { x: 182, y: 0, width: 10, height: 108 })
})

test("cardWindowRect keeps a tiny window visible", () => {
  const sliver = cardWindowRect({ x: 0, y: 0, width: 4, height: 4 }, MONITOR, CARD)
  assert.ok(sliver.width >= 1 && sliver.height >= 1)
})

test("cardWindowRect reports nothing to draw rather than an unusable rectangle", () => {
  assert.equal(cardWindowRect({ x: 0, y: 0, width: 100, height: 100 }, MONITOR, { width: 0, height: 0 }), null)
  assert.equal(cardWindowRect({ x: 0, y: 0, width: 100, height: 100 }, { width: 0, height: 0 }, CARD), null)
  // Entirely off the monitor - another screen's window on this card.
  assert.equal(cardWindowRect({ x: 4000, y: 0, width: 800, height: 600 }, MONITOR, CARD), null)
  assert.equal(cardWindowRect({ x: 0, y: 0, width: 0, height: 0 }, MONITOR, CARD), null)
  assert.equal(cardWindowRect(null, null, null), null)
})

test("nextWorkspaceId offers the one after the highest shown", () => {
  assert.equal(nextWorkspaceId([1, 2, 3, 4, 5]), 6)
  assert.equal(nextWorkspaceId([1, 2, 8]), 9)
  assert.equal(nextWorkspaceId([7]), 8)
})

// Not "the first gap": emptying workspace 3 shouldn't make "+" reopen the
// one you just cleared instead of carrying on past the end.
test("nextWorkspaceId skips past gaps rather than filling them", () => {
  assert.equal(nextWorkspaceId([1, 5]), 6)
  assert.equal(nextWorkspaceId([2, 3]), 4)
})

test("nextWorkspaceId reports nothing left once 10 is taken", () => {
  assert.equal(nextWorkspaceId([10]), 0)
  assert.equal(nextWorkspaceId([1, 2, 3, 4, 5, 6, 7, 8, 9, 10]), 0)
})

test("nextWorkspaceId starts at 1 when nothing is shown", () => {
  assert.equal(nextWorkspaceId([]), 1)
  assert.equal(nextWorkspaceId(null), 1)
})

test("navigateGrid walks the grid and stops at its edges", () => {
  // 0 1 2
  // 3 4 5
  assert.equal(navigateGrid(0, 6, 3, "right"), 1)
  assert.equal(navigateGrid(2, 6, 3, "right"), 2)
  assert.equal(navigateGrid(1, 6, 3, "left"), 0)
  assert.equal(navigateGrid(0, 6, 3, "left"), 0)
  assert.equal(navigateGrid(1, 6, 3, "down"), 4)
  assert.equal(navigateGrid(4, 6, 3, "down"), 4)
  assert.equal(navigateGrid(4, 6, 3, "up"), 1)
  assert.equal(navigateGrid(1, 6, 3, "up"), 1)
})

test("navigateWheel steps one card per notch, in card order", () => {
  // 0 1 2
  // 3 4 5   - a notch moves by one, not by a whole row.
  assert.equal(navigateWheel(0, 6, -120), 1)
  assert.equal(navigateWheel(1, 6, -120), 2)
  assert.equal(navigateWheel(2, 6, -120), 3)
  assert.equal(navigateWheel(3, 6, 120), 2)
})

test("navigateWheel stops at both ends rather than wrapping", () => {
  assert.equal(navigateWheel(5, 6, -120), 5)
  assert.equal(navigateWheel(0, 6, 120), 0)
})

test("navigateWheel ignores a notch that carries no movement", () => {
  assert.equal(navigateWheel(2, 6, 0), 2)
  assert.equal(navigateWheel(2, 6, null), 2)
  assert.equal(navigateWheel(2, 6, "nonsense"), 2)
})

test("navigateWheel copes with an empty or out-of-range selection", () => {
  assert.equal(navigateWheel(0, 0, -120), -1)
  assert.equal(navigateWheel(-1, 6, -120), 0)
  assert.equal(navigateWheel(99, 6, -120), 0)
})

test("navigateGrid lands on the last item when the row below is short", () => {
  // 0 1 2
  // 3 4
  assert.equal(navigateGrid(2, 5, 3, "down"), 4)
  assert.equal(navigateGrid(1, 5, 3, "down"), 4)
  assert.equal(navigateGrid(4, 5, 3, "right"), 4)
})

test("navigateGrid copes with an empty grid and a selection off the end", () => {
  assert.equal(navigateGrid(0, 0, 3, "down"), -1)
  assert.equal(navigateGrid(9, 5, 3, "down"), 0)
  assert.equal(navigateGrid(-1, 5, 3, "up"), 0)
  assert.equal(navigateGrid(1, 5, 0, "right"), 1)
  assert.equal(navigateGrid(1, 5, 3, "sideways"), 1)
})

test("planReorder swaps two neighbouring workspaces' windows", () => {
  const cards = strip({ 1: ["a"], 2: ["b", "c"], 3: [] })
  assert.deepEqual(planReorder(cards, 0, 1), [
    { address: "b", workspace: 1 },
    { address: "c", workspace: 1 },
    { address: "a", workspace: 2 }
  ])
})

test("planReorder rotates everything in between when a card moves further", () => {
  const cards = strip({ 1: ["a"], 2: ["b"], 3: ["c"], 4: ["d"], 5: ["e"] })
  // Dropping 5 onto 2: 5's windows land on 2, and 2, 3 and 4 each shift one
  // number up, exactly as swapping 5 leftwards one place at a time would.
  assert.deepEqual(planReorder(cards, 4, 1), [
    { address: "e", workspace: 2 },
    { address: "b", workspace: 3 },
    { address: "c", workspace: 4 },
    { address: "d", workspace: 5 }
  ])
  // The same drag the other way round.
  assert.deepEqual(planReorder(cards, 1, 4), [
    { address: "c", workspace: 2 },
    { address: "d", workspace: 3 },
    { address: "e", workspace: 4 },
    { address: "b", workspace: 5 }
  ])
})

test("planReorder moves nothing for an empty workspace, but still shifts the rest", () => {
  const cards = strip({ 1: ["a"], 2: [], 3: ["c"] })
  assert.deepEqual(planReorder(cards, 2, 0), [
    { address: "c", workspace: 1 },
    { address: "a", workspace: 2 }
  ])
  assert.deepEqual(planReorder(strip({ 1: [], 2: [] }), 0, 1), [])
})

test("planReorder works on the ids actually shown, not on 1..n", () => {
  const cards = strip({ 2: ["a"], 5: ["b"], 9: ["c"] })
  assert.deepEqual(planReorder(cards, 2, 0), [
    { address: "c", workspace: 2 },
    { address: "a", workspace: 5 },
    { address: "b", workspace: 9 }
  ])
})

test("planReorder plans nothing for a drag that changes no order", () => {
  const cards = strip({ 1: ["a"], 2: ["b"] })
  assert.deepEqual(planReorder(cards, 1, 1), [])
  assert.deepEqual(planReorder(cards, -1, 0), [])
  assert.deepEqual(planReorder(cards, 0, 7), [])
  assert.deepEqual(planReorder(null, 0, 1), [])
  assert.deepEqual(planReorder([{ id: 1, addresses: ["a", ""] }, { id: 2 }], 1, 0), [
    { address: "a", workspace: 2 }
  ])
})
