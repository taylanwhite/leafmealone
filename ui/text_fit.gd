extends RefCounted

## Authority: local presentation (R2c hud). How words are fitted on screen,
## shared by the caption stack (ui/caption_stack.gd), the corner quip
## (ui/quip_player.gd) and the floating words (ui/overheads.gd).


## The narrowest wrap width (px) at which text takes no more rows than at
## `width`: wrapped lines come out even instead of a long row and a lone word
## ("... at every stop sign. Every / one.").
static func balanced_width(font: Font, text: String, font_size: int, width: float) -> float:
	var want := rows(font, text, font_size, width)
	if want <= 1:
		return width
	# The widest word sets a floor: no row can be narrower than it.
	var floor_w := 1.0
	for word: String in text.split(" ", false):
		floor_w = maxf(floor_w, font.get_string_size(word, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x)
	var lo := maxf(floor_w, width / float(want) * 0.8)
	var hi := width
	if rows(font, text, font_size, lo) <= want:
		return minf(width, ceilf(lo) + 2.0)
	for _step: int in 12:
		var mid := (lo + hi) * 0.5
		if rows(font, text, font_size, mid) <= want:
			hi = mid
		else:
			lo = mid
	return minf(width, ceilf(hi) + 2.0)


## How many rows text wraps to at a width (px).
static func rows(font: Font, text: String, font_size: int, width: float) -> int:
	var row := font.get_height(font_size)
	var size := font.get_multiline_string_size(text, HORIZONTAL_ALIGNMENT_CENTER, width, font_size)
	return maxi(1, roundi(size.y / maxf(1.0, row)))


## The scale (applied to a Label3D's pixel size) that keeps one line of it
## between lo and hi shares of the view's height for this camera, from the
## line's natural share now. 1.0 when it already fits.
static func clamp_scale(line_share: float, lo: float, hi: float) -> float:
	if line_share <= 0.0:
		return 1.0
	if line_share > hi:
		return hi / line_share
	if line_share < lo:
		return lo / line_share
	return 1.0
