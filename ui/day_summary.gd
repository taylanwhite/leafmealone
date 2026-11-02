extends PanelContainer

## Authority: local. The card at the end of a day (net/day/day_clock.gd): jobs,
## cash, stars, the XP banked by sleeping, every rank-up (with its blurb) and what
## it unlocked, and what the town did overnight, under a quip about how the day
## went (Strings.summary_quip). Styled like the payout receipt.

## The card was put away (audio/cue_hooks.gd plays the morning stinger on it).
signal closed

const _Strings = preload("res://ui/strings.gd")
const PAPER := Color(0.97, 0.93, 0.84)
const INK := Color(0.17, 0.14, 0.11)
const ORANGE := Color(0.93, 0.47, 0.13)
const GREEN := Color(0.2, 0.55, 0.25)
const NIGHT := Color(0.16, 0.2, 0.34)

var _title: Label
var _rows: VBoxContainer


func _ready() -> void:
	add_to_group("day_summary")
	visible = false
	mouse_filter = Control.MOUSE_FILTER_STOP
	custom_minimum_size = Vector2(460, 0)
	add_theme_stylebox_override("panel", _box(PAPER, 18, NIGHT, 6))
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 10)
	add_child(column)
	_title = _text("", 32, NIGHT)
	column.add_child(_title)
	_rows = VBoxContainer.new()
	_rows.add_theme_constant_override("separation", 6)
	column.add_child(_rows)
	var close := Button.new()
	close.text = _Strings.UI["summary_close"]
	close.add_theme_font_size_override("font_size", 18)
	close.add_theme_stylebox_override("normal", _box(ORANGE, 10, ORANGE.darkened(0.25), 0))
	close.add_theme_stylebox_override("hover", _box(ORANGE.lightened(0.12), 10, ORANGE.darkened(0.25), 0))
	close.add_theme_stylebox_override("pressed", _box(ORANGE.darkened(0.12), 10, ORANGE.darkened(0.25), 0))
	close.add_theme_color_override("font_color", Color.WHITE)
	close.size_flags_horizontal = Control.SIZE_SHRINK_END
	close.pressed.connect(close_window)
	column.add_child(close)
	_hook_clock.call_deferred()


func _hook_clock() -> void:
	# The world (and its clock) comes and goes with the session: hook the one
	# there now, and every one added later.
	var current := get_tree().get_first_node_in_group("day_clock")
	if current != null:
		_watch(current)
	get_tree().node_added.connect(func(node: Node) -> void:
		if node.name == "DayClock":
			_watch(node)
	)


func _watch(clock: Node) -> void:
	if clock.has_signal("day_ended") and not clock.is_connected("day_ended", show_summary):
		clock.connect("day_ended", show_summary)


func show_summary(summary: Dictionary) -> void:
	for child: Node in _rows.get_children():
		child.queue_free()
	_title.text = _Strings.UI["summary_title"] % int(summary.get("day", 1))
	# How the day went, in one line. Every peer picks the same one from the summary.
	_line(_Strings.summary_quip(summary), INK.lightened(0.25), 17)
	_line(_Strings.UI["summary_jobs"] % int(summary.get("jobs", 0)), INK)
	_line(_Strings.UI["summary_cash"] % int(summary.get("cash", 0)), INK)
	_line(_Strings.UI["summary_stars"] % int(summary.get("stars", 0)), INK)
	_line(_Strings.UI["summary_xp"] % int(summary.get("xp_banked", 0)), ORANGE.darkened(0.1), 20)
	var wages: Dictionary = summary.get("wages", {})
	if int(wages.get("wages", 0)) > 0:
		_line(_Strings.UI["summary_wages"] % int(wages["wages"]), INK)
	for name_quit: Variant in (wages.get("quit", []) as Array):
		_line(_Strings.UI["summary_quit"] % str(name_quit), Color(0.75, 0.2, 0.15))
	_rows.add_child(HSeparator.new())
	for rank_up: Variant in (summary.get("rank_ups", []) as Array):
		var entry := rank_up as Dictionary
		_line(_Strings.UI["summary_rank_up"] % str(entry.get("title", "")), GREEN, 22)
		_line(_Strings.rank_blurb(int(entry.get("tier", 0))), INK.lightened(0.15), 15)
		var unlock := str(entry.get("unlock", ""))
		if unlock != "":
			_line(_Strings.UI["summary_unlock"] % _Strings.unlock_name(unlock), INK)
		for extra: Variant in (entry.get("extras", []) as Array):
			_line(_Strings.UI["summary_unlock"] % _Strings.unlock_name(str(extra)), INK)
	_line(_Strings.UI["summary_rank"] % str(summary.get("title", "")), NIGHT, 18)
	if summary.has("season"):
		_rows.add_child(HSeparator.new())
		_line(str(summary["season"]), Color(0.2, 0.45, 0.7), 20)
	var town: Dictionary = summary.get("town", {})
	if not town.is_empty():
		_rows.add_child(HSeparator.new())
		for hood: Variant in (town.get("opened", []) as Array):
			_line(_Strings.UI["summary_opened"] % str(hood), GREEN, 20)
		for poached: Variant in (town.get("poached", []) as Array):
			_line(_Strings.UI["summary_poached"] % str(poached), Color(0.1, 0.5, 0.25))
		if int(town.get("missed", 0)) > 0:
			_line(_Strings.UI["summary_missed"] % int(town["missed"]), INK.lightened(0.3))
		_line(_Strings.UI["summary_requests"] % int(town.get("requests", 0)), INK)
	visible = true
	set_anchors_and_offsets_preset(Control.PRESET_CENTER, Control.PRESET_MODE_MINSIZE)
	grow_horizontal = Control.GROW_DIRECTION_BOTH
	grow_vertical = Control.GROW_DIRECTION_BOTH
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func close_window() -> void:
	var was_open := visible
	visible = false
	var ui := get_tree().get_first_node_in_group("game_ui")
	if ui != null:
		ui.call("recapture_mouse")
	if was_open:
		closed.emit()


func _line(value: String, color: Color, size: int = 18) -> void:
	var label := _text(value, size, color)
	# A wrapping label needs a width, or it wraps every word onto its own line.
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.custom_minimum_size.x = 420.0
	_rows.add_child(label)


func _text(value: String, size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = value
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", color)
	return label


func _box(color: Color, radius: int, border: Color, border_width: int) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = color
	box.set_corner_radius_all(radius)
	box.border_color = border
	box.set_border_width_all(border_width)
	box.content_margin_left = 18
	box.content_margin_right = 18
	box.content_margin_top = 14
	box.content_margin_bottom = 14
	return box
