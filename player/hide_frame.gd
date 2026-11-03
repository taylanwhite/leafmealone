extends Control

## Authority: local presentation. What frames your view while you hide in first
## person (R2 chunk 3, docs/GAME.md "Hiding"): leaves around the edges in a hedge
## (they part a little when you peek), the dark lid and rim of a bin with a
## letterbox slit between them (the lid lifts when you peek), the shed door's
## boards with light through the gaps (it opens a crack when you peek), and
## ground-level leaves in a pile that fall away as you turn. Drawn in 2D over the
## live 3D view, so nothing can ever put a wall in front of the lens.
## player/hide_view.gd shows it and feeds it the kind, the peek and the turning.

## "hedge", "bin", "shed", "pile", or "" for nothing.
var kind: String = ""
## 0 to 1: how far the peek has opened things up.
var peek: float = 0.0
## How fast the view is turning (rad/s), for the leaves' sway and the pile's shedding.
var turn_rate: float = 0.0
## 0 to 1: how far a NICE BOY has pulled it open (R2b hide): his hands parting the
## hedge, the lid flung up, the door yanked aside, the pile scooped away. A poke
## opens it a little and lets it fall back; a find opens it all the way.
var part: float = 0.0
## A knock on the shed door: the boards jolt by this much (px), fading.
var shake: float = 0.0

var _time: float = 0.0
var _leaves: Array[Dictionary] = []
var _falling: Array[Dictionary] = []
var _rng := RandomNumberGenerator.new()
var _built_for: String = ""


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_rng.seed = 2718


func _process(delta: float) -> void:
	_time += delta
	# Under a CanvasLayer in a 3D branch, anchors don't find the screen: size it by hand.
	var screen := get_viewport_rect().size
	if size != screen:
		position = Vector2.ZERO
		size = screen
	if kind != _built_for:
		_build()
	if kind == "pile" and absf(turn_rate) > 1.2:
		_shed(delta)
	for leaf: Dictionary in _falling:
		leaf["v"] = (leaf["v"] as Vector2) + Vector2(0.0, 1400.0) * delta
		leaf["p"] = (leaf["p"] as Vector2) + (leaf["v"] as Vector2) * delta
		leaf["spin"] = float(leaf["spin"]) + float(leaf["spin_rate"]) * delta
	_falling = _falling.filter(func(leaf: Dictionary) -> bool: return (leaf["p"] as Vector2).y < size.y + 200.0)
	# Leaves shed from a pile settle back in slowly while you keep still.
	if kind == "pile":
		for leaf: Dictionary in _leaves:
			leaf["gone"] = maxf(0.0, float(leaf["gone"]) - delta * 0.25)
	queue_redraw()


## Leaves knocked off the edge of the view as you turn in a pile.
func _shed(delta: float) -> void:
	for leaf: Dictionary in _leaves:
		if float(leaf["gone"]) > 0.0 or _rng.randf() > delta * absf(turn_rate) * 0.9:
			continue
		leaf["gone"] = 1.0
		var at := _leaf_pos(leaf)
		_falling.append({"p": at, "v": Vector2(signf(turn_rate) * -_rng.randf_range(60.0, 220.0), _rng.randf_range(-120.0, 40.0)), "r": float(leaf["r"]), "spin": float(leaf["a"]), "spin_rate": _rng.randf_range(-6.0, 6.0), "c": leaf["c"]})


func _build() -> void:
	_built_for = kind
	_leaves.clear()
	_falling.clear()
	if kind != "hedge" and kind != "pile":
		return
	var greens: Array[Color] = [Color(0.12, 0.27, 0.11), Color(0.17, 0.35, 0.14), Color(0.1, 0.22, 0.1), Color(0.24, 0.4, 0.16)]
	var autumn: Array[Color] = [Color(0.72, 0.36, 0.1), Color(0.8, 0.58, 0.16), Color(0.6, 0.2, 0.1), Color(0.5, 0.3, 0.12)]
	var colors := greens if kind == "hedge" else autumn
	var count := 70 if kind == "hedge" else 46
	for index: int in count:
		# Around the edge: u along it (0..1), which edge, and how far in. A pile's
		# leaves crowd the bottom edge and stay out of the middle of the view.
		var edge := _rng.randi() % 4
		if kind == "pile":
			edge = 2 if _rng.randf() < 0.6 else _rng.randi() % 4
		_leaves.append({
			"edge": edge,
			"u": _rng.randf(),
			"in": _rng.randf_range(-0.02, 0.16 if kind == "hedge" else 0.1),
			"r": _rng.randf_range(42.0, 96.0) if kind == "hedge" else _rng.randf_range(34.0, 78.0),
			"a": _rng.randf() * TAU,
			"c": colors[_rng.randi() % colors.size()].lightened(_rng.randf_range(-0.1, 0.12)),
			"phase": _rng.randf() * TAU,
			"gone": 0.0,
		})


func _draw() -> void:
	match kind:
		"hedge", "pile":
			# The shade inside the leaves, deepest at the edges.
			var shade := Color(0.04, 0.1, 0.04) if kind == "hedge" else Color(0.12, 0.06, 0.02)
			for ring: int in 7:
				var band := 16.0
				var inset := float(ring) * band - peek * 30.0 - part * 140.0
				var tint := Color(shade.r, shade.g, shade.b, 0.11 - 0.014 * float(ring))
				draw_rect(Rect2(0.0, 0.0, size.x, maxf(0.0, inset + band)), tint)
				draw_rect(Rect2(0.0, size.y - maxf(0.0, inset + band), size.x, maxf(0.0, inset + band)), tint)
				draw_rect(Rect2(0.0, 0.0, maxf(0.0, inset + band), size.y), tint)
				draw_rect(Rect2(size.x - maxf(0.0, inset + band), 0.0, maxf(0.0, inset + band), size.y), tint)
			for leaf: Dictionary in _leaves:
				if float(leaf["gone"]) >= 0.99:
					continue
				var scale_now := 1.0 - float(leaf["gone"])
				_draw_leaf(_leaf_pos(leaf), float(leaf["r"]) * scale_now, float(leaf["a"]) + sin(_time * 1.7 + float(leaf["phase"])) * 0.12 + turn_rate * 0.05, leaf["c"])
			for leaf: Dictionary in _falling:
				_draw_leaf(leaf["p"], float(leaf["r"]), float(leaf["spin"]), leaf["c"])
		"bin":
			_draw_bin()
		"shed":
			_draw_shed()


## Where an edge leaf sits now: pushed out past the edge as the peek opens up,
## and swept off the screen when a NICE BOY pulls it apart.
func _leaf_pos(leaf: Dictionary) -> Vector2:
	var u := float(leaf["u"])
	var inward := float(leaf["in"]) - peek * 0.12 - part * (0.32 + 0.2 * float(leaf["phase"]) / TAU)
	var sway := sin(_time * 2.1 + float(leaf["phase"])) * 6.0 + turn_rate * 8.0
	match int(leaf["edge"]):
		0:
			return Vector2(u * size.x + sway, inward * size.y)
		1:
			return Vector2(size.x - inward * size.x, u * size.y + sway * 0.5)
		2:
			return Vector2(u * size.x + sway, size.y - inward * size.y)
		_:
			return Vector2(inward * size.x, u * size.y + sway * 0.5)


func _draw_leaf(at: Vector2, radius: float, angle: float, leaf_color: Color) -> void:
	var points := PackedVector2Array()
	for step: int in 10:
		var t := float(step) / 10.0 * TAU
		# A pointed oval: wider in the middle, a tip at one end.
		var r := radius * (0.55 + 0.45 * absf(cos(t * 0.5))) * (1.0 if t < PI else 0.85)
		points.append(at + Vector2(cos(t) * r, sin(t) * r * 0.48).rotated(angle))
	draw_colored_polygon(points, leaf_color)
	draw_line(at - Vector2(radius * 0.9, 0.0).rotated(angle), at + Vector2(radius * 0.9, 0.0).rotated(angle), leaf_color.darkened(0.35), 2.0)


## Under the lid: its dark underside over the top, the rim along the bottom,
## and a bright slit of yard between. Peeking lifts the lid.
func _draw_bin() -> void:
	# Peeking lifts the lid a little; a NICE BOY lifting it from outside flings it
	# up and off the top of the view (and the rim drops a touch as you're hauled).
	var lid_bottom := size.y * lerpf(lerpf(0.36, 0.2, peek), -0.05, part)
	var rim_top := size.y * lerpf(0.7, 0.86, part)
	var lid := Color(0.06, 0.08, 0.08)
	draw_rect(Rect2(0.0, 0.0, size.x, lid_bottom), lid)
	# The lid's front lip catches a little light.
	draw_rect(Rect2(0.0, lid_bottom - 10.0, size.x, 10.0), Color(0.16, 0.2, 0.2))
	draw_rect(Rect2(0.0, rim_top, size.x, size.y - rim_top), Color(0.05, 0.07, 0.07))
	draw_rect(Rect2(0.0, rim_top, size.x, 8.0), Color(0.2, 0.25, 0.25))
	# Darker corners, the inside of the bin round the slit.
	draw_rect(Rect2(0.0, lid_bottom, size.x * 0.05, rim_top - lid_bottom), Color(0.03, 0.04, 0.04, 0.85))
	draw_rect(Rect2(size.x * 0.95, lid_bottom, size.x * 0.05, rim_top - lid_bottom), Color(0.03, 0.04, 0.04, 0.85))


## Inside the shed door: dark boards with light between them, and three knot
## holes in the middle board at eye height; the door opens a crack to the right
## when you peek.
func _draw_shed() -> void:
	# A knock jolts the boards; yanked open, the whole door swings off to the left.
	var jolt := Vector2(sin(_time * 70.0), cos(_time * 53.0)) * shake
	draw_set_transform(Vector2(-size.x * 1.05 * part * part, 0.0) + jolt, 0.0, Vector2.ONE)
	var board := Color(0.13, 0.09, 0.06)
	var hole_center := size * Vector2(0.5, 0.5)
	var hole := Vector2(size.x * 0.34, size.y * 0.26) * (1.0 + peek * 0.25)
	var gap_x := size.x * lerpf(1.0, 0.82, peek)
	# The boards: everything left of the door's edge except the ragged hole,
	# one quarter at a time (each a corner of the screen and its quarter of the rim).
	var corners: Array[Vector2] = [Vector2(gap_x, 0.0), Vector2(0.0, 0.0), Vector2(0.0, size.y), Vector2(gap_x, size.y)]
	for quarter: int in 4:
		var piece := PackedVector2Array()
		piece.append(corners[quarter])
		for step: int in 9:
			var t := (float(quarter) + float(step) / 8.0) * PI * 0.5
			# Screen y points down, so the angle runs from the right, up, left, down.
			piece.append(hole_center + Vector2(cos(t) * hole.x, -sin(t) * hole.y) * _rim(t))
		var next_corner := corners[(quarter + 1) % 4]
		piece.append(next_corner)
		draw_colored_polygon(piece, board)
	# Seams between the boards, with a sliver of daylight, broken by the hole.
	var boards := 5
	for index: int in range(1, boards):
		var x := gap_x * float(index) / float(boards)
		var across := (x - hole_center.x) / (hole.x * 1.1)
		var spans: Array[Vector2] = [Vector2(0.0, size.y)]
		if absf(across) < 1.0:
			var reach := hole.y * 1.1 * sqrt(1.0 - across * across)
			spans = [Vector2(0.0, hole_center.y - reach), Vector2(hole_center.y + reach, size.y)]
		for span: Vector2 in spans:
			draw_rect(Rect2(x - 2.0, span.x, 4.0, span.y - span.x), Color(0.9, 0.85, 0.7, 0.18))
			draw_rect(Rect2(x - 6.0, span.x, 4.0, span.y - span.x), board.darkened(0.4))
	# The hole's ragged edge: wood grain round it.
	var ring := PackedVector2Array()
	for step: int in 33:
		var t := float(step) / 32.0 * TAU
		ring.append(hole_center + Vector2(cos(t) * hole.x, -sin(t) * hole.y) * _rim(t))
	draw_polyline(ring, board.lightened(0.18), 10.0, true)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


## The knot hole's ragged rim: a little bigger here, a little smaller there.
func _rim(t: float) -> float:
	return 1.0 + 0.06 * sin(t * 5.0 + 1.3) + 0.04 * sin(t * 9.0)
