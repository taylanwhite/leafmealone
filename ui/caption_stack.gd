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
## R2b: a spoken line beats everything else for a place on screen (it shows on
## the frame its sound starts instead of queueing behind a quip), then a
## teammate taken, then the radio, then quips. Added to the caller's priority.
const KIND_RANK: Dictionary = {&"subtitle": 10, &"teammate": 2, &"radio": 1, &"quip": 0}
## Kinds that belong to the yard: when the moment takes you (ui/hud_mode.gd)
## they're cleared, and while a spoken line shows a quip waits under it.
const YARD_KINDS: Array[StringName] = [&"radio", &"quip"]
const _HudMode = preload("res://ui/hud_mode.gd")
const _Overheads = preload("res://ui/overheads.gd")
const _TextFit = preload("res://ui/text_fit.gd")
## The soft plate's color (its darkness is Constants.R2B_HUD_PLATE_ALPHA).
const PLATE := Color(0.06, 0.05, 0.05)

## Whether this peer was in the cinematic HUD mode last frame.
var _cinematic: bool = false

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
	# R2c: the same words twice (two NICE BOYS with one line, a line said again
	# before the last one went) are one line on screen: it stays, or comes back if
	# it was on its way out, with its time renewed. Never a duplicate.
	for entry: Dictionary in _lines:
		if str(entry["text"]) == text and (float(entry["left"]) > 0.0 or float(entry["alpha"]) > 0.0):
			entry["left"] = maxf(float(entry["left"]), maxf(0.1, seconds))
			entry["priority"] = maxi(int(entry["priority"]), priority)
			_layout(0.0)
			return int(entry["id"])
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
	# R2b: a soft feathered plate behind the words, so a line reads over bright
	# leaves and sky (the dark caption backdrop replaces it when that's on).
	var plate := Panel.new()
	plate.name = "Plate"
	plate.mouse_filter = Control.MOUSE_FILTER_IGNORE
	plate.show_behind_parent = true
	label.add_child(plate)
	var entry := {"id": _next_id, "kind": kind, "text": text, "left": maxf(0.1, seconds), "priority": priority, "label": label, "box": box, "alpha": 0.0, "grow": 0.0, "shown": false, "at": Time.get_ticks_msec() / 1000.0}
	_next_id += 1
	_lines.append(entry)
	_style(entry)
	_layout(0.0)
	return int(entry["id"])


func drop(id: int) -> void:
	for entry: Dictionary in _lines:
		if int(entry["id"]) == id:
			entry["left"] = 0.0


## Whether a kind shows with this player's Settings: every kind follows captions
## on/off (critic.md C19: all captions honor interface.captions).
static func kind_shown(_kind: StringName) -> bool:
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
		# A piece the cinematic HUD mode has eased out isn't there to keep clear of.
		if node == null or not node.is_visible_in_tree() or node.modulate.a < 0.05:
			continue
		var rect := _rect_of(node)
		if rect.size.x > 0.0 and rect.size.y > 0.0:
			out.append(rect)
	return out


func _process(delta: float) -> void:
	_watch_mode()
	for entry: Dictionary in _lines:
		# Waiting for room holds a line's time; a line the settings hide runs out unseen.
		if bool(entry["shown"]) or not kind_shown(StringName(entry["kind"])):
			entry["left"] = float(entry["left"]) - delta
	_layout(delta)


## R2b: entering the cinematic HUD mode clears the yard's radio and quips (the
## catch is the moment now; they'd stack under his lines).
func _watch_mode() -> void:
	var now_cinematic := in_cinematic()
	if now_cinematic and not _cinematic:
		# R2c: and what the NICE BOYS said before the catch ("Slow down!") goes
		# too: it was about the chase. A line said this very moment stays.
		var now := Time.get_ticks_msec() / 1000.0
		for entry: Dictionary in _lines:
			var kind := StringName(entry["kind"])
			if YARD_KINDS.has(kind) or kind == &"subtitle" and now - float(entry.get("at", now)) > Constants.R2C_HUD_STALE_SPOKEN:
				entry["left"] = 0.0
	_cinematic = now_cinematic


## Whether the stack is laid out for the cinematic HUD mode (ui/hud_mode.gd).
func in_cinematic() -> bool:
	return is_inside_tree() and _HudMode.cinematic(get_tree(), Net.local_peer_id())


## Something on screen being read (a receipt): the visible members of the
## "caption_blockers" group. The radio and quips wait for them; a spoken line
## or a teammate taken can't wait (it would land seconds after its sound), so it
## shows, clear of them (_blocker_rects).
func _blockers() -> Array[Node]:
	var out: Array[Node] = []
	for node: Node in get_tree().get_nodes_in_group("caption_blockers"):
		if node is Node3D and (node as Node3D).is_visible_in_tree() or node is CanvasItem and (node as CanvasItem).is_visible_in_tree():
			out.append(node)
	return out


## Where the blockers are on screen: a 2D one's rect, a 3D one's meshes' boxes
## through the camera (the slip fed up into your view, or in your hand).
func _blocker_rects(view: Vector2) -> Array[Rect2]:
	var out: Array[Rect2] = []
	var camera := get_viewport().get_camera_3d()
	var screen := Rect2(Vector2.ZERO, view)
	for node: Node in _blockers():
		var rect := Rect2()
		if node is Control:
			rect = (node as Control).get_global_rect()
		elif node is Node3D and camera != null:
			var any := false
			for child: Node in node.find_children("*", "VisualInstance3D", true, false):
				var visual := child as VisualInstance3D
				if not visual.is_visible_in_tree():
					continue
				var box := visual.global_transform * visual.get_aabb()
				for corner: int in 8:
					var point := box.get_endpoint(corner)
					if not _Overheads.in_front(camera, point):
						continue
					var at := camera.unproject_position(point)
					rect = Rect2(at, Vector2.ZERO) if not any else rect.expand(at)
					any = true
		rect = rect.intersection(screen)
		if rect.size.x > 0.0 and rect.size.y > 0.0:
			out.append(rect)
	return out


func _visible_entries() -> Array[Dictionary]:
	var waiting: Array[Dictionary] = []
	var blocked := not _blockers().is_empty()
	var speaking := false
	for entry: Dictionary in _lines:
		if blocked and YARD_KINDS.has(StringName(entry["kind"])):
			continue
		if float(entry["left"]) > 0.0 and kind_shown(StringName(entry["kind"])):
			waiting.append(entry)
			speaking = speaking or StringName(entry["kind"]) == &"subtitle"
	# A quip never sits under someone speaking: it waits its turn.
	if speaking:
		waiting = waiting.filter(func(entry: Dictionary) -> bool: return StringName(entry["kind"]) != &"quip")
	# Highest priority first (a spoken line first of all), then oldest; at most
	# CAPTION_STACK_MAX, or R2B_HUD_CINEMATIC_LINES while the moment has you.
	# R2c: among spoken lines the newest wins: a line is shown on the frame its
	# sound starts, so it can't wait behind older ones (the gotcha line used to
	# wait up to 1.5 s for two chase lines to run out).
	waiting.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var rank_a := int(a["priority"]) + int(KIND_RANK.get(StringName(a["kind"]), 0))
		var rank_b := int(b["priority"]) + int(KIND_RANK.get(StringName(b["kind"]), 0))
		if rank_a != rank_b:
			return rank_a > rank_b
		if StringName(a["kind"]) == &"subtitle" and StringName(b["kind"]) == &"subtitle":
			return int(a["id"]) > int(b["id"])
		return int(a["id"]) < int(b["id"]))
	var chosen := waiting.slice(0, most_lines())
	# On screen, oldest on top and the newest at the bottom.
	chosen.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a["id"]) < int(b["id"]))
	return chosen


## The most lines on screen at once now, counting a line on its way out:
## CAPTION_STACK_MAX, or R2B_HUD_CINEMATIC_LINES while the moment has you.
func most_lines() -> int:
	return Constants.R2B_HUD_CINEMATIC_LINES if _cinematic else Constants.CAPTION_STACK_MAX


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
		# R2c: a spoken line never waits for a place: one newer lines have pushed
		# off is over (it would come back after them, out of time with its sound).
		if not on and StringName(entry["kind"]) == &"subtitle":
			entry["left"] = 0.0
		var alpha := float(entry["alpha"])
		var grow := float(entry["grow"])
		# A spoken line lands with its sound: its slot opens and it fades in at once.
		var spoken := StringName(entry["kind"]) == &"subtitle"
		var grow_in := Constants.R2B_HUD_SUBTITLE_ONSET if spoken else GROW_SECONDS
		var fade_in := Constants.R2B_HUD_SUBTITLE_ONSET if spoken else FADE_IN
		if delta > 0.0:
			if on:
				grow = move_toward(grow, 1.0, delta / grow_in)
				alpha = move_toward(alpha, 1.0, delta / fade_in)
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
	# R2c: never more lines on screen than the stack holds, a line on its way out
	# included: when a new one takes a slot, the oldest leaving line makes way at
	# once (a subtitle replaced, not a third line fading under two).
	var most := most_lines()
	var index_out := 0
	while drawn.size() > most and index_out < drawn.size():
		var leaving: Dictionary = drawn[index_out]
		if bool(leaving["shown"]):
			index_out += 1
			continue
		leaving["alpha"] = 0.0
		leaving["grow"] = 0.0
		(leaving["box"] as Control).visible = false
		drawn.remove_at(index_out)
	var slots: Array[float] = []
	var heights: Array[float] = []
	var total := 0.0
	var pad := plate_pad()
	for entry: Dictionary in drawn:
		var label := entry["label"] as Label
		# R2c: wrapped lines are balanced (".. at every stop sign. Every / one." was
		# a word alone on its row): the label is as narrow as keeps its row count.
		var lw := _balanced(entry, label, width)
		label.custom_minimum_size = Vector2(lw, 0.0)
		label.size = Vector2(lw, 0.0)
		var h := _text_height(label, lw)
		label.size = Vector2(lw, h)
		_fit_plate(label, lw, h, pad, width)
		h += pad.y * 2.0
		var eased := smoothstep(0.0, 1.0, float(entry["grow"]))
		heights.append(h)
		slots.append(h * eased)
		total += (h + LINE_GAP) * eased
	total = maxf(0.0, total - LINE_GAP)
	var bottom := _baseline(view)
	var left := (view.x - width) * 0.5
	# Up and over anything it would cover (a receipt being read included).
	var avoid := obstacle_rects()
	if not drawn.is_empty():
		avoid.append_array(_blocker_rects(view))
	for _pass: int in 4:
		var stack_rect := Rect2(left, bottom - total, width, total)
		var moved := false
		for rect: Rect2 in avoid:
			if stack_rect.intersects(rect):
				bottom = rect.position.y - CLEARANCE
				moved = true
				stack_rect = Rect2(left, bottom - total, width, total)
		if not moved:
			break
	# Never pushed off the top of the screen.
	bottom = maxf(bottom, total + CLEARANCE)
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
		label.position = Vector2(floorf((width - label.size.x) * 0.5), pad.y)
		label.modulate.a = float(entry["alpha"])
		y += slots[index] + LINE_GAP * smoothstep(0.0, 1.0, float(entry["grow"]))
	for entry: Dictionary in _lines:
		if not drawn.has(entry):
			(entry["box"] as Control).visible = false

## Where the stack's bottom sits: above the goal line when it's up, else above
## the hotbar's band.
func _baseline(view: Vector2) -> float:
	# R2b: with the yard HUD eased out, the lines sit low, film-subtitle style,
	# under the faces of a two-shot.
	if _cinematic:
		return view.y - Constants.R2B_HUD_CINEMATIC_BOTTOM
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
	_style_plate(label)


## A line's height wrapped at width, from the font itself: on the frame a line is
## pushed the Label hasn't laid its words out at the new width yet, and its own
## minimum size (one word a row) would throw the whole stack up the screen for
## a frame.
func _text_height(label: Label, width: float) -> float:
	var box := label.get_theme_stylebox("normal")
	var margins := box.get_minimum_size() if box != null else Vector2.ZERO
	var font := label.get_theme_font("font")
	var font_size := label.get_theme_font_size("font_size")
	var text := font.get_multiline_string_size(label.text, HORIZONTAL_ALIGNMENT_CENTER, maxf(1.0, width - margins.x), font_size)
	var lines := maxi(1, roundi(text.y / font.get_height(font_size)))
	var spacing := float(label.get_theme_constant("line_spacing")) * float(lines - 1)
	return ceilf(text.y + spacing + margins.y)


## R2c: how wide a line's label is drawn: the stack's width for one row, else
## the narrowest width that keeps the same number of rows, so the rows come out
## even instead of a long row and a lone word. Cached per text, size and width.
func _balanced(entry: Dictionary, label: Label, width: float) -> float:
	var font := label.get_theme_font("font")
	var font_size := label.get_theme_font_size("font_size")
	var key := "%s|%d|%d" % [label.text, font_size, roundi(width)]
	if str(entry.get("bw_key", "")) == key:
		return float(entry["bw"])
	var box := label.get_theme_stylebox("normal")
	var margins := box.get_minimum_size().x if box != null else 0.0
	var result := _TextFit.balanced_width(font, label.text, font_size, maxf(1.0, width - margins)) + margins
	result = minf(width, result)
	entry["bw_key"] = key
	entry["bw"] = result
	return result


## The room the soft plate takes round a line (zero while the dark caption
## backdrop is on: that box has its own margins).
static func plate_pad() -> Vector2:
	if bool(Settings.get_value("interface", "caption_backdrop")):
		return Vector2.ZERO
	return Constants.R2B_HUD_PLATE_PAD


## The plate hugs the words (centered, as wide as the widest wrapped line),
## not the stack's whole width.
func _fit_plate(label: Label, width: float, height: float, pad: Vector2, room: float = -1.0) -> void:
	var plate := label.get_node_or_null("Plate") as Panel
	if plate == null:
		return
	plate.visible = pad != Vector2.ZERO
	if not plate.visible:
		return
	var font := label.get_theme_font("font")
	var font_size := label.get_theme_font_size("font_size")
	var natural := font.get_string_size(label.text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	var words := minf(natural, width)
	# A balanced label is narrower than the stack: its plate still pads the words,
	# within the stack's width (room).
	var plate_width := minf(words + pad.x * 2.0, maxf(width, room))
	plate.position = Vector2((width - plate_width) * 0.5, -pad.y)
	plate.size = Vector2(plate_width, height + pad.y * 2.0)


func _style_plate(label: Label) -> void:
	var plate := label.get_node_or_null("Plate") as Panel
	if plate == null:
		return
	var box := StyleBoxFlat.new()
	box.bg_color = Color(PLATE, Constants.R2B_HUD_PLATE_ALPHA)
	box.set_corner_radius_all(Constants.R2B_HUD_PLATE_FEATHER)
	box.anti_aliasing_size = minf(float(Constants.R2B_HUD_PLATE_FEATHER) * 0.5, 6.0)
	plate.add_theme_stylebox_override("panel", box)


func _on_settings_changed(section: StringName, _key: StringName, _value: Variant) -> void:
	if section != &"interface":
		return
	for entry: Dictionary in _lines:
		_style(entry)
