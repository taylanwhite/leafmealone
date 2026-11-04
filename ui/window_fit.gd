extends RefCounted

## Authority: local presentation (p1-ui, docs/GAME.md "Windows sit in the middle
## of the screen"). Keeps a catalog-look window (the shop, the job board, the
## payout card) exactly the size of what's in it, centered on the screen and
## never past its edges: a window bigger than the screen less
## Constants.UI_WINDOW_MARGIN_PX all round is drawn smaller (scaled about its
## middle) instead of hanging off it. The job board used to grow and slide right
## until its title and Close were off screen (crew-07), and the second payout card
## kept the first one's height and ran off the top and bottom (NB-06).
##
##   WindowFit.fit(window)     size to content, center, scale to fit (now)
##   WindowFit.watch(window)   and again whenever its content or the screen
##                             changes size while it's up


static func fit(window: Control, force := false) -> void:
	if window == null or not window.is_inside_tree():
		return
	var view := window.get_viewport_rect().size
	if view.x <= 0.0 or view.y <= 0.0:
		return
	# Anchored on the middle of the screen, so a later change grows both ways.
	window.anchor_left = 0.5
	window.anchor_right = 0.5
	window.anchor_top = 0.5
	window.anchor_bottom = 0.5
	window.grow_horizontal = Control.GROW_DIRECTION_BOTH
	window.grow_vertical = Control.GROW_DIRECTION_BOTH
	var want := window.get_combined_minimum_size()
	var room := view - Vector2.ONE * Constants.UI_WINDOW_MARGIN_PX * 2.0
	var shrink := minf(1.0, minf(room.x / maxf(1.0, want.x), room.y / maxf(1.0, want.y)))
	var settled := window.size.is_equal_approx(want) and is_equal_approx(window.scale.x, shrink)
	if settled and not force:
		return
	window.size = want
	window.pivot_offset = want * 0.5
	window.scale = Vector2.ONE * shrink
	window.position = ((view - want) * 0.5).round()


## Fits it again (deferred, once per frame) whenever what's in it or the screen
## changes size while it's showing.
static func watch(window: Control) -> void:
	if window == null or window.has_meta(&"window_fit"):
		return
	window.set_meta(&"window_fit", true)
	var refit := func() -> void:
		if is_instance_valid(window) and window.visible and not window.has_meta(&"window_fit_queued"):
			window.set_meta(&"window_fit_queued", true)
			(func() -> void:
				if is_instance_valid(window):
					window.remove_meta(&"window_fit_queued")
					if window.visible:
						fit(window)
			).call_deferred()
	window.minimum_size_changed.connect(refit)
	window.get_viewport().size_changed.connect(func() -> void:
		if is_instance_valid(window) and window.visible:
			fit(window, true)
	)
	window.visibility_changed.connect(refit)


## Whether the window's drawn rect lies inside the screen (tests).
static func inside(window: Control, margin := 0.0) -> bool:
	var view := window.get_viewport_rect().size
	var drawn := Rect2(window.position + window.pivot_offset * (Vector2.ONE - window.scale), window.size * window.scale)
	return Rect2(Vector2.ONE * margin, view - Vector2.ONE * margin * 2.0).encloses(drawn.grow(-0.5))
