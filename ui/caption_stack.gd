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
const FADE_IN: float = 0.18
const FADE_OUT: float = 0.3
## How fast a line glides to its new spot when the stack shifts (1/s).
const GLIDE_RATE: float = 14.0

var _next_id: int = 1
## Every line pushed and not yet gone: {id, kind, text, left, priority, label, alpha, shown}.
var _lines: Array[Dictionary] = []


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
	var label := Label.new()
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.text = text
	label.modulate.a = 0.0
	label.visible = false
	add_child(label)
	var entry := {"id": _next_id, "kind": kind, "text": text, "left": maxf(0.1, seconds), "priority": priority, "label": label, "alpha": 0.0, "shown": false, "placed": false}
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
		var label := entry["label"] as Label
		out.append(Rect2(label.position, label.size))
	return out


## What the stack keeps clear of: the job goal line, the job panel and the heat meter.
func obstacle_rects() -> Array[Rect2]:
	var out: Array[Rect2] = []
	var ui := get_parent()
	if ui == null:
		return out
	for name_of: String in ["JobGoal", "TaskList", "HeatMeter"]:
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
	# Size each line, then stack them upward from the baseline.
	var heights: Array[float] = []
	for entry: Dictionary in shown:
		var label := entry["label"] as Label
		label.size = Vector2(width, 0.0)
		label.custom_minimum_size = Vector2(width, 0.0)
		heights.append(label.get_combined_minimum_size().y)
	var total := 0.0
	for h: float in heights:
		total += h
	total += LINE_GAP * maxf(0.0, float(heights.size() - 1))
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
	var y := bottom - total
	for index: int in shown.size():
		var entry: Dictionary = shown[index]
		var label := entry["label"] as Label
		var target := Vector2(left, y)
		if not bool(entry["placed"]):
			# A new line rises into place from a little below.
			label.position = target + Vector2(0.0, 8.0)
			entry["placed"] = true
		elif delta > 0.0:
			label.position = label.position.lerp(target, 1.0 - exp(-GLIDE_RATE * delta))
			if label.position.distance_to(target) < 0.5:
				label.position = target
		# Never parked over the goal line, panel or meter, even mid-glide.
		label.position.x = target.x
		entry["shown"] = true
		y += heights[index] + LINE_GAP
	# Fades: in while shown, out once gone or waiting.
	var keep: Array[Dictionary] = []
	for entry: Dictionary in _lines:
		var label := entry["label"] as Label
		var on := shown.has(entry)
		if not on:
			entry["shown"] = false
		var alpha := float(entry["alpha"])
		if delta > 0.0:
			alpha = move_toward(alpha, 1.0 if on else 0.0, delta / (FADE_IN if on else FADE_OUT))
		entry["alpha"] = alpha
		label.modulate.a = alpha
		label.visible = on or alpha > 0.0
		if float(entry["left"]) <= 0.0 and alpha <= 0.0:
			label.queue_free()
		else:
			keep.append(entry)
	_lines = keep


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
	var left_edge := 0.0
	for rect: Rect2 in obstacle_rects():
		if rect.position.x < view.x * 0.5:
			left_edge = maxf(left_edge, rect.end.x)
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
