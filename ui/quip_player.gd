extends Node

## Local presentation. Plays draft workbook lines with a cooldown and a per-session cap.
## The line is a caption at the bottom left, styled by the player's Settings
## (interface: captions on or off, caption_size, caption_backdrop); with captions
## off the babble still plays. Anchored to the corner, not placed, so it stays on
## screen at every UI scale.

const _Strings: Script = preload("res://ui/strings.gd")
const _Director = preload("res://net/run_events/director.gd")
## The caption's look at the normal caption size (presentation, docs/DECISIONS.md
## "Tuning vs. presentation"): font size, distance from the bottom-left corner
## (x right, y up), the widest it gets before it wraps, and the backdrop box.
const FONT_SIZE: int = 22
const CORNER_OFFSET := Vector2(80.0, 100.0)
const MAX_WIDTH: float = 760.0
const BACKDROP_COLOR := Color(0.0, 0.0, 0.0, 0.55)
const BACKDROP_RADIUS: int = 10
const BACKDROP_MARGIN := Vector2(14.0, 8.0)

var _label: Label
var _hide_at: float = 0.0
var _played: Dictionary = {}
var _last_at: Dictionary = {}
var _seen_lot: bool = false
var _director: Node
var _last_roster: int = 0
var _throw_latched: bool = false


func _ready() -> void:
	_label = Label.new()
	_label.name = "Caption"
	_label.visible = false
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# Its bottom edge sits CORNER_OFFSET.y above the screen's bottom and it grows
	# upward, so a wrapped line or a big caption size never runs off the screen.
	_label.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	_label.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_label.offset_left = CORNER_OFFSET.x
	_label.offset_right = CORNER_OFFSET.x
	_label.offset_top = -CORNER_OFFSET.y
	_label.offset_bottom = -CORNER_OFFSET.y
	_label.add_theme_color_override("font_color", Color(0.949, 0.902, 0.788))
	_label.add_theme_color_override("font_shadow_color", Color(0.165, 0.141, 0.110))
	_label.add_theme_constant_override("shadow_offset_x", 2)
	_label.add_theme_constant_override("shadow_offset_y", 2)
	add_child(_label)
	_style_caption()
	Settings.changed.connect(_on_settings_changed)
	get_viewport().size_changed.connect(_fit_width)
	if not Net.player_zone_changed.is_connected(_on_zone):
		Net.player_zone_changed.connect(_on_zone)
	if not Campaign.unlocks_changed.is_connected(_on_unlocks):
		Campaign.unlocks_changed.connect(_on_unlocks)
	if not Campaign.payout_ready.is_connected(_on_payout):
		Campaign.payout_ready.connect(_on_payout)


func _process(_delta: float) -> void:
	if _label.visible and Time.get_ticks_msec() / 1000.0 > _hide_at:
		_label.visible = false
	_watch_director()
	_watch_cleanup()
	_watch_throwback()


func _on_zone(peer_id: int, zone: Net.Zone) -> void:
	if peer_id != Net.local_peer_id():
		return
	if zone == Net.Zone.LOT and not _seen_lot:
		_seen_lot = true
		_try("first_lot")
	elif zone == Net.Zone.STORE:
		if _seen_lot:
			_try("return_store")
		else:
			_try("store_arrival")


func _on_unlocks() -> void:
	_try("tool_purchase")


func _on_payout(_results: Array[Dictionary]) -> void:
	var fields := get_tree().get_nodes_in_group("leaf_field")
	if fields.is_empty():
		return
	if float(fields[0].call("cleaned_fraction")) >= 0.999:
		_try("full_clear")


## When this player last arrived on a yard; the jab about slow progress waits
## until they've had a fair go at it.
var _on_lot_since: float = -1.0


func _watch_cleanup() -> void:
	if Net.player_zone(Net.local_peer_id()) != Net.Zone.LOT:
		_on_lot_since = -1.0
		return
	if _on_lot_since < 0.0:
		_on_lot_since = Net.server_time()
	if Net.server_time() - _on_lot_since < Constants.QUIP_LOW_CLEANUP_AFTER:
		return
	var fields := get_tree().get_nodes_in_group("leaf_field")
	if fields.is_empty():
		return
	if float(fields[0].call("cleaned_fraction")) < 0.08:
		_try("low_cleanup")


func _watch_throwback() -> void:
	var crossing := get_tree().get_first_node_in_group("border_return")
	var thrown := crossing != null and bool(crossing.call("is_thrown_back"))
	if thrown and not _throw_latched:
		_try("border_fail")
	_throw_latched = thrown


func _watch_director() -> void:
	var director := get_tree().get_first_node_in_group("run_director")
	if director == null:
		return
	if _director != director:
		_director = director
		if not director.phase_changed.is_connected(_on_phase):
			director.phase_changed.connect(_on_phase)
	var roster: Array = director.call("cohort_roster")
	if roster.size() > _last_roster:
		for peer_id: Variant in roster:
			if int(peer_id) != Net.local_peer_id():
				_try("teammate_captured")
				break
	_last_roster = roster.size()


## Reads the director's phase, not its status text: the text is writing and can
## change (it once said "are here" while this looked for "is here", so Q-009 never
## played).
func _on_phase(_status: String) -> void:
	if _director == null:
		return
	var phase := int(_director.call("phase"))
	if phase == _Director.Phase.WARNING:
		_try("run_warning")
	elif phase == _Director.Phase.CHASE:
		_try("crew_arrival")


func _try(trigger: String) -> void:
	for row: Dictionary in _Strings.LINES:
		if str(row["trigger"]) != trigger:
			continue
		var id := str(row["id"])
		var played := int(_played.get(id, 0))
		if played >= int(row["max_session"]):
			return
		var now := Time.get_ticks_msec() / 1000.0
		if now - float(_last_at.get(id, -1000.0)) < Constants.QUIP_COOLDOWN_SECONDS:
			return
		_played[id] = played + 1
		_last_at[id] = now
		show_caption(str(row["line"]))
		return


## Shows line as the caption (unless the player turned captions off) and plays
## the babble that goes with it: characters never speak real words, so the
## caption carries the joke (docs/ART.md, "Audio").
func show_caption(line: String) -> void:
	_label.text = _Strings.keyed(line)
	_hide_at = Time.get_ticks_msec() / 1000.0 + Constants.QUIP_CAPTION_SECONDS
	_style_caption()
	_label.visible = captions_on()
	var sfx := get_tree().get_first_node_in_group("sfx")
	if sfx != null:
		sfx.call("play", "babble")


static func captions_on() -> bool:
	return bool(Settings.get_value("interface", "captions"))


func _on_settings_changed(section: StringName, _key: StringName, _value: Variant) -> void:
	if section == &"interface":
		_style_caption()
		if not captions_on():
			_label.visible = false


## Size and backdrop from Settings: the font at FONT_SIZE times caption_scale(),
## and a dark rounded box behind it when caption_backdrop is on.
func _style_caption() -> void:
	_label.add_theme_font_size_override("font_size", roundi(FONT_SIZE * Settings.caption_scale()))
	if bool(Settings.get_value("interface", "caption_backdrop")):
		var box := StyleBoxFlat.new()
		box.bg_color = BACKDROP_COLOR
		box.set_corner_radius_all(BACKDROP_RADIUS)
		box.content_margin_left = BACKDROP_MARGIN.x
		box.content_margin_right = BACKDROP_MARGIN.x
		box.content_margin_top = BACKDROP_MARGIN.y
		box.content_margin_bottom = BACKDROP_MARGIN.y
		_label.add_theme_stylebox_override("normal", box)
	else:
		_label.remove_theme_stylebox_override("normal")
	_fit_width()


## As wide as the line, up to MAX_WIDTH and the room the screen has at this UI
## scale; longer lines wrap and the caption grows upward from its corner.
func _fit_width() -> void:
	var font := _label.get_theme_font("font")
	var size := _label.get_theme_font_size("font_size")
	var box := _label.get_theme_stylebox("normal")
	var padding := box.get_minimum_size().x if box != null else 0.0
	var natural := font.get_string_size(_label.text, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x + padding + 2.0
	var room := _label.get_viewport_rect().size.x - CORNER_OFFSET.x * 2.0
	_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_label.offset_right = _label.offset_left + maxf(1.0, minf(natural, minf(MAX_WIDTH, room)))
	# Back to no height, so it settles at the new text's height, growing upward.
	_label.offset_top = _label.offset_bottom
