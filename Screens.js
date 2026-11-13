.pragma library

// Where each screen's panel belongs, given the screens' geometry.
//
//   side:  "left" or "right" — the edge the panel is anchored to.
//   hover: whether the edge strip that reveals it exists at all.
//
// The panel only opens on an outside edge, never on the seam between two
// screens, so moving the pointer from one monitor to the other does not graze
// an edge strip and make the panel flicker.
//
// Each screen is judged by its own neighbours: another screen counts as one when
// it touches this screen's left or right edge and shares some of its height. A
// screen with a neighbour only on its right faces left, so a pair of monitors
// opens outwards, one panel on each side. Every other screen faces right,
// including screens stacked on top of each other, whatever their widths. A
// screen whose chosen edge is a seam (neighbours on both sides) gets no strip.

// Fractional scaling can leave a pixel of gap or overlap between screens that
// are meant to touch.
var TOUCH_TOLERANCE = 2

function num(value) {
  return Number(value) || 0
}

function layout(screens) {
  var out = {}
  var list = screens || []

  for (var j = 0; j < list.length; j++) {
    var screen = list[j]
    var name = String(screen.name || "")
    if (name === "") continue
    var sx = num(screen.x)
    var sy = num(screen.y)
    var sw = num(screen.width)
    var sh = num(screen.height)

    var hasLeft = false
    var hasRight = false
    for (var k = 0; k < list.length; k++) {
      if (k === j) continue
      var other = list[k]
      var ox = num(other.x)
      var oy = num(other.y)
      var ow = num(other.width)
      var oh = num(other.height)
      // Only a screen beside this one, not above or below it, makes a seam.
      if (!(oy < sy + sh && sy < oy + oh)) continue
      if (Math.abs(ox + ow - sx) <= TOUCH_TOLERANCE) hasLeft = true
      if (Math.abs(ox - (sx + sw)) <= TOUCH_TOLERANCE) hasRight = true
    }

    var side = hasRight && !hasLeft ? "left" : "right"
    out[name] = {
      side: side,
      hover: side === "left" ? !hasLeft : !hasRight
    }
  }
  return out
}
