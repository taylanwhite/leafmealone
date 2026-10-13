extends Node

## Local presentation. Plays draft workbook lines with a cooldown and a per-session cap.

const _Strings: Script = preload("res://ui/strings.gd")

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
	_label.visible = false
	_label.position = Vector2(80, 620)
	_label.add_theme_font_size_override("font_size", 22)
	_label.add_theme_color_override("font_color", Color(0.949, 0.902, 0.788))
	_label.add_theme_color_override("font_shadow_color", Color(0.165, 0.141, 0.110))
	_label.add_theme_constant_override("shadow_offset_x", 2)
	_label.add_theme_constant_override("shadow_offset_y", 2)
	add_child(_label)
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


func _watch_cleanup() -> void:
	if Net.player_zone(Net.local_peer_id()) != Net.Zone.LOT:
		return
	if Net.server_time() < 20.0:
		return
	var fields := get_tree().get_nodes_in_group("leaf_field")
	if fields.is_empty():
		return
	if float(fields[0].call("cleaned_fraction")) < 0.08:
		_try("low_cleanup")


func _watch_throwback() -> void:
	var crossing := get_tree().get_first_node_in_group("border_return")
	var thrown := crossing != null and str(crossing.call("status_line")) == "Thrown back"
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


func _on_phase(status: String) -> void:
	if status.find("on the way") >= 0:
		_try("run_warning")
	elif status.find("is here") >= 0:
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
		if now - float(_last_at.get(id, -1000.0)) < float(_Strings.COOLDOWN_SECONDS):
			return
		_played[id] = played + 1
		_last_at[id] = now
		_label.text = str(row["line"])
		_label.visible = true
		_hide_at = now + 4.5
		return
