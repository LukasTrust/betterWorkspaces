// The overview's geometry and keyboard/pointer navigation: fitting the cards
// into the screen, placing a window inside a card, walking the selection,
// and the window moves a reorder drag works out to.
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

// Lays a set of rectangles out side by side, the way the overview arranges
// its workspace cards: no overlap, every one at its real aspect ratio, the
// whole block centred in the area it was given.
//
// `items` are the rectangles to fit as [{ width, height }] - for the cards,
// the monitor each workspace is on, so a card comes out the shape of the
// screen it stands for. `area` is the space to fill,
// { width, height } plus an optional { x, y } origin. `options`:
//   spacing        gap between neighbouring cells, both axes
//   captionHeight  room reserved under each window for its icon and title
//   maxScale       largest factor a window may be blown up by; Infinity by
//                  default, so a near-empty workspace still fills the area
//
// The grid shape is picked by trying every column count and keeping the one
// that renders them largest, because what "largest" means depends on both
// the area and the rectangles: two landscape cards want two columns in a
// wide area and two rows in a tall one, and nothing short of measuring gets
// that right for every mix of portrait and landscape.
//
// Returns { columns, rows, scale, items: [...] }, one entry per input in the
// same order: `x`/`y`/`width`/`height` is where the card itself is drawn,
// `cellX`/`cellY`/`cellWidth`/`cellHeight` the slot around it that the
// caption below shares.
function spreadLayout(items, area, options) {
  var list = items || []
  var bounds = area || {}
  var settings = options || {}
  var count = list.length
  var areaWidth = Number(bounds.width) || 0
  var areaHeight = Number(bounds.height) || 0
  var originX = Number(bounds.x) || 0
  var originY = Number(bounds.y) || 0
  var spacing = Math.max(0, Number(settings.spacing) || 0)
  var captionHeight = Math.max(0, Number(settings.captionHeight) || 0)
  var maxScale = Number(settings.maxScale)
  if (!(maxScale > 0)) maxScale = Infinity

  var empty = { columns: 0, rows: 0, scale: 0, items: [] }
  if (count === 0 || areaWidth <= 0 || areaHeight <= 0) return empty

  // A window Hyprland reports no usable size for is treated as filling the
  // area: better one wrongly-shaped preview than a zero-sized one that also
  // drags the whole grid's scale off, since the scale is the tightest fit
  // across every window.
  var sizes = []
  for (var i = 0; i < count; i++) {
    var item = list[i] || {}
    var width = Number(item.width)
    var height = Number(item.height)
    sizes.push({
      width: width > 0 ? width : areaWidth,
      height: height > 0 ? height : areaHeight
    })
  }

  var best = null
  for (var columns = 1; columns <= count; columns++) {
    var rows = Math.ceil(count / columns)
    var cellWidth = (areaWidth - spacing * (columns - 1)) / columns
    var cellHeight = (areaHeight - spacing * (rows - 1)) / rows
    var windowHeight = cellHeight - captionHeight
    if (cellWidth <= 0 || windowHeight <= 0) continue

    var scale = maxScale
    for (var s = 0; s < count; s++)
      scale = Math.min(scale, cellWidth / sizes[s].width, windowHeight / sizes[s].height)
    if (!(scale > 0)) continue

    // Ties happen once `maxScale` caps every candidate. Then the grid that
    // leaves no empty slot wins, and failing that the squarer one.
    var emptySlots = rows * columns - count
    if (best === null
        || scale > best.scale
        || (scale === best.scale && emptySlots < best.emptySlots)
        || (scale === best.scale && emptySlots === best.emptySlots && Math.abs(columns - rows) < Math.abs(best.columns - best.rows))) {
      best = { columns: columns, rows: rows, scale: scale, emptySlots: emptySlots }
    }
  }

  if (best === null) return empty

  // Cells are only as big as the largest window they have to hold, so the
  // block stays tight and centred instead of stretched across slack the
  // scale couldn't use.
  var slotWidth = 0
  var slotHeight = 0
  for (var m = 0; m < count; m++) {
    slotWidth = Math.max(slotWidth, sizes[m].width * best.scale)
    slotHeight = Math.max(slotHeight, sizes[m].height * best.scale)
  }
  var cellW = slotWidth
  var cellH = slotHeight + captionHeight

  var gridWidth = best.columns * cellW + spacing * (best.columns - 1)
  var gridHeight = best.rows * cellH + spacing * (best.rows - 1)
  var left = originX + (areaWidth - gridWidth) / 2
  var top = originY + (areaHeight - gridHeight) / 2

  var placed = []
  for (var index = 0; index < count; index++) {
    var row = Math.floor(index / best.columns)
    var column = index % best.columns
    // A short last row is centred under the rows above it rather than left
    // aligned, so the block reads as one shape.
    var inRow = Math.min(best.columns, count - row * best.columns)
    var rowInset = (best.columns - inRow) * (cellW + spacing) / 2

    var cellX = left + rowInset + column * (cellW + spacing)
    var cellY = top + row * (cellH + spacing)
    var width = sizes[index].width * best.scale
    var height = sizes[index].height * best.scale

    placed.push({
      x: cellX + (cellW - width) / 2,
      y: cellY + (slotHeight - height) / 2,
      width: width,
      height: height,
      cellX: cellX,
      cellY: cellY,
      cellWidth: cellW,
      cellHeight: cellH
    })
  }

  return {
    columns: best.columns,
    rows: best.rows,
    scale: best.scale,
    items: placed
  }
}

// A window's place on a workspace card: its real rectangle on the monitor,
// shrunk to the card. `window` and `monitor` are in Hyprland's global
// coordinates (what `lastIpcObject.at`/`size` and a monitor's x/y/width/
// height report), `card` is just { width, height }.
//
// The result is clipped to the card, so a window hanging off the edge of the
// monitor - or one on another monitor entirely - can't draw outside it, and
// never collapses to nothing: a card is small enough that an honest 0.4px
// tall window would simply disappear.
function cardWindowRect(window, monitor, card) {
  var rect = window || {}
  var screen = monitor || {}
  var size = card || {}
  var cardWidth = Number(size.width) || 0
  var cardHeight = Number(size.height) || 0
  var screenWidth = Number(screen.width) || 0
  var screenHeight = Number(screen.height) || 0
  if (cardWidth <= 0 || cardHeight <= 0 || screenWidth <= 0 || screenHeight <= 0) return null

  var scaleX = cardWidth / screenWidth
  var scaleY = cardHeight / screenHeight
  var left = ((Number(rect.x) || 0) - (Number(screen.x) || 0)) * scaleX
  var top = ((Number(rect.y) || 0) - (Number(screen.y) || 0)) * scaleY
  var right = left + Math.max(0, Number(rect.width) || 0) * scaleX
  var bottom = top + Math.max(0, Number(rect.height) || 0) * scaleY

  left = Math.min(Math.max(0, left), cardWidth)
  top = Math.min(Math.max(0, top), cardHeight)
  right = Math.min(Math.max(0, right), cardWidth)
  bottom = Math.min(Math.max(0, bottom), cardHeight)
  if (right <= left || bottom <= top) return null

  return {
    x: left,
    y: top,
    width: Math.max(1, right - left),
    height: Math.max(1, bottom - top)
  }
}

// The workspace the "+" card opens: the one after the highest the overview
// shows. A strip of 1-5 grows to 6, and one that already reaches 8 grows to
// 9 - "the next one along", not "the first gap", which would reopen a
// workspace you had just emptied. 0 once 10 is taken, because Hyprland's
// numbered strip stops there.
function nextWorkspaceId(ids) {
  var list = ids || []
  var highest = 0
  for (var i = 0; i < list.length; i++) {
    var id = Number(list[i])
    if (id > highest) highest = id
  }
  var next = highest + 1
  return next <= 10 ? next : 0
}

// Where the keyboard selection lands when an arrow (or its hjkl twin) is
// pressed in a `columns`-wide grid of `count` items. Movement stops at the
// edges rather than wrapping, and a step off the end of a short last row
// lands on its last item instead of nowhere.
function navigateGrid(index, count, columns, direction) {
  var total = Math.max(0, Number(count) || 0)
  if (total === 0) return -1
  var width = Math.max(1, Number(columns) || 1)
  var current = Number(index)
  if (!(current >= 0 && current < total)) return 0

  var row = Math.floor(current / width)
  var column = current % width

  if (direction === "left") return column === 0 ? current : current - 1
  if (direction === "right") return current + 1 < total && column + 1 < width ? current + 1 : current
  if (direction === "up") return row === 0 ? current : current - width
  if (direction === "down") {
    if (current + width < total) return current + width
    // Nothing directly below: from the row above a short last row, step to
    // that row's last item rather than refusing to move.
    return row === Math.floor((total - 1) / width) ? current : total - 1
  }
  return current
}

// Where the wheel moves the overview's selection: one card per notch, in the
// order the cards are laid out rather than by grid direction. A wheel has one
// axis and the cards read left to right, top to bottom, so "the next one" is
// the honest reading of a notch - stepping a whole row per notch, the way a
// down arrow does, would skip past cards the pointer is sitting next to.
//
// Stops at the ends rather than wrapping, same as `navigateGrid`.
//
// `angleDelta` is Qt's own: positive when the wheel is rolled away from the
// user, which is "up" and so the previous card.
function navigateWheel(index, count, angleDelta) {
  var total = Math.max(0, Number(count) || 0)
  if (total === 0) return -1
  var current = Number(index)
  if (!(current >= 0 && current < total)) return 0

  var delta = Number(angleDelta) || 0
  if (delta === 0) return current

  var next = current + (delta > 0 ? -1 : 1)
  return Math.min(total - 1, Math.max(0, next))
}

// The window moves that drag a workspace from one place in the strip to
// another. Hyprland can't renumber a workspace, so the numbers stay put and
// the windows move between them: dropping 5 onto 2 leaves 5's windows on 2,
// 2's on 3, 3's on 4 and 4's on 5 - the same end state as swapping 5 with
// its neighbour over and over, done in one pass.
//
// `cards` is the strip as shown, [{ id, addresses }] in display order, with
// every window's Hyprland address. Because every window is addressed
// individually and the whole plan is worked out before anything moves, no
// scratch workspace is needed and it doesn't matter that two workspaces'
// windows share a number in between.
//
// Returns [{ address, workspace }], or nothing at all when the drag changes
// no window's workspace.
function planReorder(cards, fromIndex, toIndex) {
  var list = cards || []
  var from = Number(fromIndex)
  var to = Number(toIndex)
  if (!(from >= 0 && from < list.length)) return []
  if (!(to >= 0 && to < list.length)) return []
  if (from === to) return []

  var reordered = list.slice()
  reordered.splice(to, 0, reordered.splice(from, 1)[0])

  var moves = []
  for (var slot = 0; slot < list.length; slot++) {
    var target = list[slot] || {}
    var card = reordered[slot] || {}
    if (card.id === target.id) continue
    var addresses = card.addresses || []
    for (var i = 0; i < addresses.length; i++) {
      var address = String(addresses[i] || "")
      if (address.length > 0) moves.push({ address: address, workspace: target.id })
    }
  }
  return moves
}

// Node, for the unit tests. In QML this branch is never taken - the file is
// imported as a plain JavaScript resource, and `module` doesn't exist there.
if (typeof module !== "undefined") {
  module.exports = {
    spreadLayout: spreadLayout,
    cardWindowRect: cardWindowRect,
    nextWorkspaceId: nextWorkspaceId,
    navigateGrid: navigateGrid,
    navigateWheel: navigateWheel,
    planReorder: planReorder
  }
}
