extends Control

## Authority: local presentation. The caption stack (R2 contract C5, group
## "caption_stack"): every line of text the raid puts on screen goes through this
## one column, bottom center, stacked upward from just above the job goal line
## (or the hotbar while the goal line is away), so lines never pile on top of each
## other, the goal line, the job panel or the heat meter.
##
##   var id := stack.push(&"radio", text, seconds, priority := 0)
##   stack.drop(id)
##
## Kinds: &"teammate" (a crewmate taken out of your sight: you couldn't know
## otherwise) always shows; &"radio" (dispatch chatter), &"quip" (workbook
## quips) and &"subtitle" (NICE BOY barks) are spoken lines and only show with
## Settings interface.captions on (settings:4; the crackle, the flare and the van
## are the warning itself). Every kind is sized by Settings.caption_scale() and
## gets the caption backdrop when that's on. At most CAPTION_STACK_MAX lines show;
## the rest wait their turn, highest priority first, and their time only runs
## while they show.

const _QuipPlayer = preload("res://ui/quip_player.gd")
const KINDS: Array[StringName] = [&"radio", &"quip", &"teammate", &"subtitle"]
## Presentation (docs/DECISIONS.md "Tuning vs. presentation"): font size per kind
## at the normal caption size, colors, the gap between lines and to what's below,
## the widest a line gets, and the fades.
const FONT_SIZES: Dictionary = {&"radio": 22, &"quip": 22, &"teammate": 22, &"subtitle": 20}
const COLORS: Dictionary = {
	&"radio": Color(1.0, 0.78, 0.45),
	&"quip": Color(0.949, 0.902, 0.788),
	&"teammate": Color(0.84, 0.8, 1.0),
	&"subtitle": Color(1.0, 1.0, 1.0),
}
const SHADOW := Color(0.12, 0.09, 0.07)
const LINE_GAP: float = 6.0
const CLEARANCE: float = 10.0
const MAX_WIDTH: float = 720.0
const MIN_WIDTH: float = 260.0
const FADE_IN: float = 0.22
const FADE_OUT: float = 0.3
## How long a line's slot takes to open (the lines above glide up) and to close.
const GROW_SECONDS: float = 0.18
## What the stack keeps clear of (UIRoot children): the job goal line, the job panel,
## the heat meter and the bottom-left quip caption (ui/quip_player.gd) when it's up;
## and the side columns its width keeps between.
const OBSTACLES: Array = ["JobGoal", "TaskList", "HeatMeter", "Quips/Caption"]
const COLUMNS: Array = ["TaskList", "HeatMeter"]
## How tall a band beside the stack's bottom the columns are checked over, px.
const COLUMN_BAND: float = 260.0
## How fast the whole stack glides to a new bottom (1/s).
const STACK_GLIDE_RATE: float = 12.0

var _next_id: int = 1
## Every line pushed and not yet gone: {id, kind, text, left, priority, label, alpha, shown}.
var _lines: Array[Dictionary] = []
var _bottom: float = INF
var _bottom_idle: bool = true


func _ready() -> void:
	add_to_group("caption_stack")
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	if not Settings.changed.is_connected(_on_settings_changed):
		Settings.changed.connect(_on_settings_changed)


## A line of a kind for `seconds`. Returns its id (for drop), or 0 for an empty line.
func push(kind: StringName, text: String, seconds: float, priority: int = 0) -> int:
	if text.strip_edges() == "":
		return 0
	if not KINDS.has(kind):
		kind = &"quip"
	# The slot: a clipping box the line is drawn in (it opens and closes, the line fades).
	var box := Control.new()
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.clip_contents = true
	box.visible = false
	add_child(box)
	var label := Label.new()
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.text = text
	label.modulate.a = 0.0
	box.add_child(label)
	var entry := {"id": _next_id, "kind": kind, "text": text, "left": maxf(0.1, seconds), "priority": priority, "label": label, "box": box, "alpha": 0.0, "grow": 0.0, "shown": false}
	_next_id += 1
	_lines.append(entry)
	_style(entry)
	_layout(0.0)
	return int(entry["id"])


func drop(id: int) -> void:
	for entry: Dictionary in _lines:
		if int(entry["id"]) == id:
			entry["left"] = 0.0


## Whether a kind shows with this player's Settings.
static func kind_shown(kind: StringName) -> bool:
	if kind == &"teammate":
		return true
	return _QuipPlayer.captions_on()


## The lines on screen now, top to bottom, as {id, kind, text}. For tests.
func shown_lines() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for entry: Dictionary in _visible_entries():
		out.append({"id": entry["id"], "kind": entry["kind"], "text": entry["text"]})
	return out


## The Label a pushed line is drawn with (null once it's gone). For tests.
func line_label(id: int) -> Label:
	for entry: Dictionary in _lines:
		if int(entry["id"]) == id:
			return entry["label"] as Label
	return null


## Every shown line's rect on screen, for tests (stage_test checks they miss the rest).
func line_rects() -> Array[Rect2]:
	var out: Array[Rect2] = []
	for entry: Dictionary in _visible_entries():
		var box := entry["box"] as Control
		out.append(Rect2(box.position, box.size))
	return out


## What the stack keeps clear of: the job goal line, the job panel and the heat meter.
func obstacle_rects(names: Array = OBSTACLES) -> Array[Rect2]:
	var out: Array[Rect2] = []
	var ui := get_parent()
	if ui == null:
		return out
	for name_of: String in names:
		var node := ui.get_node_or_null(name_of) as Control
		if node == null or not node.is_visible_in_tree():
			continue
		var rect := _rect_of(node)
		if rect.size.x > 0.0 and rect.size.y > 0.0:
			out.append(rect)
	return out


func _process(delta: float) -> void:
	for entry: Dictionary in _lines:
		# Waiting for room holds a line's time; a line the settings hide runs out unseen.
		if bool(entry["shown"]) or not kind_shown(StringName(entry["kind"])):
			entry["left"] = float(entry["left"]) - delta
	_layout(delta)


func _visible_entries() -> Array[Dictionary]:
	var waiting: Array[Dictionary] = []
	for entry: Dictionary in _lines:
		if float(entry["left"]) > 0.0 and kind_shown(StringName(entry["kind"])):
			waiting.append(entry)
	# Highest priority first, then oldest; at most CAPTION_STACK_MAX.
	waiting.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if int(a["priority"]) != int(b["priority"]):
			return int(a["priority"]) > int(b["priority"])
		return int(a["id"]) < int(b["id"]))
	var chosen := waiting.slice(0, Constants.CAPTION_STACK_MAX)
	# On screen, oldest on top and the newest at the bottom.
	chosen.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a["id"]) < int(b["id"]))
	return chosen


func _layout(delta: float) -> void:
	var view := get_viewport_rect().size
	var shown := _visible_entries()
	var width := _line_width(view)
	# Each line opens a slot (grow 0 to 1) and fades in; leaving, it fades out and
	# then its slot closes, so the lines above glide down instead of jumping. The
	# slot clips its line, so a line never draws over its neighbour mid-move.
	var drawn: Array[Dictionary] = []
	var keep: Array[Dictionary] = []
	for entry: Dictionary in _lines:
		var on := shown.has(entry)
		entry["shown"] = on
		var alpha := float(entry["alpha"])
		var grow := float(entry["grow"])
		if delta > 0.0:
			if on:
				grow = move_toward(grow, 1.0, delta / GROW_SECONDS)
				alpha = move_toward(alpha, 1.0, delta / FADE_IN)
			else:
				alpha = move_toward(alpha, 0.0, delta / FADE_OUT)
				if alpha <= 0.0:
					grow = move_toward(grow, 0.0, delta / GROW_SECONDS)
		elif on and grow <= 0.0:
			grow = 0.0
		entry["alpha"] = alpha
		entry["grow"] = grow
		if float(entry["left"]) <= 0.0 and alpha <= 0.0 and grow <= 0.0:
			(entry["box"] as Control).queue_free()
			continue
		keep.append(entry)
		if grow > 0.0 or on:
			drawn.append(entry)
	_lines = keep
	drawn.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a["id"]) < int(b["id"]))
	var slots: Array[float] = []
	var heights: Array[float] = []
	var total := 0.0
	for entry: Dictionary in drawn:
		var label := entry["label"] as Label
		label.custom_minimum_size = Vector2(width, 0.0)
		label.size = Vector2(width, 0.0)
		var h := label.get_combined_minimum_size().y
		label.size = Vector2(width, h)
		var eased := smoothstep(0.0, 1.0, float(entry["grow"]))
		heights.append(h)
		slots.append(h * eased)
		total += (h + LINE_GAP) * eased
	total = maxf(0.0, total - LINE_GAP)
	var bottom := _baseline(view)
	var left := (view.x - width) * 0.5
	# Up and over anything it would cover.
	for _pass: int in 4:
		var stack_rect := Rect2(left, bottom - total, width, total)
		var moved := false
		for rect: Rect2 in obstacle_rects():
			if stack_rect.intersects(rect):
				bottom = rect.position.y - CLEARANCE
				moved = true
				stack_rect = Rect2(left, bottom - total, width, total)
		if not moved:
			break
	# The whole stack glides when what it keeps clear of moves (a quip appears).
	if _bottom == INF or not drawn.is_empty() and _bottom_idle:
		_bottom = bottom
	elif delta > 0.0:
		_bottom = lerpf(_bottom, bottom, 1.0 - exp(-STACK_GLIDE_RATE * delta))
		if absf(_bottom - bottom) < 0.5:
			_bottom = bottom
	_bottom_idle = drawn.is_empty()
	var y := _bottom - total
	for index: int in drawn.size():
		var entry: Dictionary = drawn[index]
		var box := entry["box"] as Control
		box.position = Vector2(left, y)
		box.size = Vector2(width, slots[index])
		box.visible = slots[index] > 0.5
		var label := entry["label"] as Label
		label.position = Vector2.ZERO
		label.modulate.a = float(entry["alpha"])
		y += slots[index] + LINE_GAP * smoothstep(0.0, 1.0, float(entry["grow"]))
	for entry: Dictionary in _lines:
		if not drawn.has(entry):
			(entry["box"] as Control).visible = false

## Where the stack's bottom sits: above the goal line when it's up, else above
## the hotbar's band.
func _baseline(view: Vector2) -> float:
	var bottom := view.y - Constants.HOTBAR_GOAL_LINE_Y - CLEARANCE
	var ui := get_parent()
	var goal := ui.get_node_or_null("JobGoal") as Control if ui != null else null
	if goal != null and goal.is_visible_in_tree() and goal.size.y > 0.0:
		bottom = minf(bottom, goal.get_global_rect().position.y - CLEARANCE)
	return bottom


## As wide as fits between the left-hand HUD columns (the job panel, the heat
## meter), mirrored, up to MAX_WIDTH.
func _line_width(view: Vector2) -> float:
	# Only the side columns: the goal line is centered, under the stack, not beside it.
	var left_edge := 0.0
	var band_top := _baseline(view) - COLUMN_BAND
	for rect: Rect2 in obstacle_rects(COLUMNS):
		# Only what sits beside the stack's band (the job panel is high above it).
		if rect.end.y < band_top:
			continue
		if rect.end.x <= view.x * 0.5:
			left_edge = maxf(left_edge, rect.end.x)
		elif rect.position.x >= view.x * 0.5:
			left_edge = maxf(left_edge, view.x - rect.position.x)
	var room := view.x - 2.0 * (left_edge + CLEARANCE)
	return clampf(room, MIN_WIDTH, MAX_WIDTH)


## A control and everything visible inside it, as one screen rect.
func _rect_of(node: Control) -> Rect2:
	var rect := node.get_global_rect()
	var any := rect.size.x > 0.0 and rect.size.y > 0.0
	for child: Node in node.find_children("*", "Control", true, false):
		var control := child as Control
		if not control.is_visible_in_tree() or control.size.x <= 0.0 or control.size.y <= 0.0:
			continue
		var r := control.get_global_rect()
		rect = r if not any else rect.merge(r)
		any = true
	return rect if any else Rect2()


func _style(entry: Dictionary) -> void:
	var label := entry["label"] as Label
	var kind := StringName(entry["kind"])
	label.add_theme_font_size_override("font_size", roundi(float(FONT_SIZES.get(kind, 22)) * Settings.caption_scale()))
	label.add_theme_color_override("font_color", COLORS.get(kind, Color.WHITE))
	label.add_theme_color_override("font_shadow_color", SHADOW)
	label.add_theme_constant_override("shadow_offset_x", 2)
	label.add_theme_constant_override("shadow_offset_y", 2)
	_QuipPlayer.apply_backdrop(label)


func _on_settings_changed(section: StringName, _key: StringName, _value: Variant) -> void:
	if section != &"interface":
		return
	for entry: Dictionary in _lines:
		_style(entry)
