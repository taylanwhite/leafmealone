extends Control

## Authority: local. Chefty's dash, bottom right, while you sit in it: the speed
## in MPH, what's in the bed and what it's worth, who's driving, and the seat's
## keys (gap-specs/critic.md C7: the hotbar's row is bottom center, this sits
## clear of it). "23 MPH · Bed 14/50 ($212) · Driver: Taylan".

const _Strings = preload("res://ui/strings.gd")
const _UiStyle = preload("res://ui/ui_style.gd")
const _Seated = preload("res://player/seated.gd")
## m/s to miles per hour.
const MPH_PER_MPS: float = 2.237
const WIDTH: float = 250.0

var _panel: PanelContainer
var _speed: Label
var _bed: Label
var _driver: Label
var _keys: Label


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel = PanelContainer.new()
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel.add_theme_stylebox_override("panel", _UiStyle.box(Color(0.08, 0.07, 0.06, 0.78), 12, _UiStyle.ORANGE, 2, 10))
	add_child(_panel)
	var rows := VBoxContainer.new()
	rows.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rows.add_theme_constant_override("separation", 2)
	_panel.add_child(rows)
	_speed = _UiStyle.text("", 30, _UiStyle.PAPER)
	_bed = _UiStyle.text("", 15, _UiStyle.PAPER)
	_driver = _UiStyle.text("", 15, Color(1.0, 0.85, 0.6))
	_keys = _UiStyle.text("", 11, Color(0.8, 0.78, 0.74))
	_keys.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_keys.custom_minimum_size.x = WIDTH
	for label: Label in [_speed, _bed, _driver, _keys]:
		label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		rows.add_child(label)
	visible = false


func _process(_delta: float) -> void:
	var player := _local_player()
	var vehicle := _Seated.vehicle_of(player) if player != null else null
	visible = vehicle != null and Net.current_state() == Net.State.IN_SESSION
	if not visible:
		return
	_speed.text = _Strings.UI["drive_hud_speed"] % roundi(float(vehicle.call("speed")) * MPH_PER_MPS)
	_bed.text = _Strings.UI["drive_hud_bed"] % [int(vehicle.call("bag_count")), Constants.TRUCK_BAG_CAPACITY, int(vehicle.call("bag_value"))]
	var driver_id := int(vehicle.call("driver"))
	_driver.text = _Strings.UI["drive_hud_driver"] % Net.player_name(driver_id) if driver_id != 0 else _Strings.UI["drive_hud_no_driver"]
	var driving := driver_id == Net.local_peer_id()
	_keys.text = _Strings.keyed(_Strings.UI["drive_hud_keys_driver" if driving else "drive_hud_keys_rider"])
	var screen := get_viewport_rect().size
	_panel.reset_size()
	position = Vector2(screen.x - _panel.size.x - 16.0, screen.y - _panel.size.y - 16.0)


func _local_player() -> Node:
	for node: Node in get_tree().get_nodes_in_group("players"):
		if node.name == str(Net.local_peer_id()):
			return node
	return null
