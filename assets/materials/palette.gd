extends RefCounted

## The M6 palette. Flat colors for the store, the lot, and the border.
## assets/palette.png is the same row of swatches, left to right.

const SKY := Color(0.561, 0.706, 0.788)
const YARD := Color(0.420, 0.478, 0.271)
const FLOOR := Color(0.431, 0.396, 0.345)
const LEAF_ORANGE := Color(0.847, 0.416, 0.165)
const LEAF_YELLOW := Color(0.886, 0.706, 0.227)
const LEAF_RED := Color(0.639, 0.231, 0.141)
const WOOD := Color(0.541, 0.353, 0.227)
const CHEFTY := Color(0.769, 0.278, 0.180)
const CREW := Color(0.227, 0.239, 0.290)
const EXIT := Color(0.235, 0.561, 0.290)
const PAPER := Color(0.949, 0.902, 0.788)
const INK := Color(0.165, 0.141, 0.110)

const SWATCHES: Array[Color] = [
	SKY, YARD, FLOOR, LEAF_ORANGE, LEAF_YELLOW, LEAF_RED,
	WOOD, CHEFTY, CREW, EXIT, PAPER, INK,
]


static func nearest(color: Color) -> Color:
	var best := SWATCHES[0]
	var best_distance := INF
	for swatch: Color in SWATCHES:
		var dr := color.r - swatch.r
		var dg := color.g - swatch.g
		var db := color.b - swatch.b
		var distance := dr * dr + dg * dg + db * db
		if distance < best_distance:
			best_distance = distance
			best = swatch
	return best
