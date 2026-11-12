.pragma library

// Where each screen's panel belongs, given the screens' geometry.
//
//   side:  "left" or "right" — the edge the panel is anchored to.
//   hover: whether the edge strip that reveals it exists at all.
//
// The panel only opens on the outside of the desktop, never on the seam between
// two screens, so moving the pointer from one monitor to the other does not
// graze an edge strip and make the panel flicker.
//
// A screen at the left of the desktop with another one to its right faces left,
// so a pair of monitors opens outwards, one panel on each side. Every other
// screen faces right, including two screens stacked on top of each other, where
// both panels stay on the right.
function layout(screens) {
  var out = {}
  var list = screens || []
  if (list.length === 0) return out

  var left = Infinity
  var right = -Infinity
  for (var i = 0; i < list.length; i++) {
    var x = Number(list[i].x) || 0
    if (x < left) left = x
    var farRight = x + (Number(list[i].width) || 0)
    if (farRight > right) right = farRight
  }

  for (var j = 0; j < list.length; j++) {
    var screen = list[j]
    var name = String(screen.name || "")
    if (name === "") continue
    var sx = Number(screen.x) || 0
    var edge = sx + (Number(screen.width) || 0)
    out[name] = {
      side: sx <= left && edge < right ? "left" : "right",
      hover: sx <= left || edge >= right
    }
  }
  return out
}
