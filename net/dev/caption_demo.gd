extends Node

## Authority: local, dev only. --open-settings=captions: for windowed screenshots
## of the captions and key names at a UI scale (settings:4). A homeowner of its
## own stands in front of the local player and talks, so her caption and the
## floating "[E]  Talk to the homeowner" prompt are in view; the quip caption
## shows at the bottom left; the store clerk says a line. Everything repeats every
## REPEAT_SECONDS so a --screenshot run catches it. UI scale, caption size and
## backdrop, and rebound keys come from the run's settings file
## (user://settings_test_<port>.cfg), written before launch.

const _Homeowner = preload("res://npcs/homeowner.gd")
const _Strings = preload("res://ui/strings.gd")
const REPEAT_SECONDS: float = 2.0
## How far in front of the player the homeowner stands, in meters (inside her talk reach).
const STAND_DISTANCE: float = 2.4

var _homeowner: Node3D
var _wait: float = 0.0


func _process(delta: float) -> void:
	_wait -= delta
	if _wait > 0.0:
		return
	_wait = REPEAT_SECONDS
	var me := _me()
	if me == null:
		return
	if _homeowner == null:
		_homeowner = _Homeowner.new()
		_homeowner.name = "CaptionDemoHomeowner"
		add_child(_homeowner)
	var ahead := me.global_position - me.global_basis.z * STAND_DISTANCE
	_homeowner.global_position = ahead
	_homeowner.look_at(Vector3(me.global_position.x, ahead.y, me.global_position.z), Vector3.UP, true)
	_homeowner.call("show_caption", _line(_Strings.HOMEOWNER_LINES["thrilled"]))
	var quips := get_tree().root.find_child("Quips", true, false)
	if quips != null:
		quips.call("show_caption", _line(_Strings.LINES.map(func(row: Dictionary) -> String: return str(row["line"]))))
	var clerk := get_tree().get_first_node_in_group("store_clerk")
	if clerk != null:
		clerk.call("say_line", "greet")


func _line(lines: Array) -> String:
	return str(lines[randi() % lines.size()]) if not lines.is_empty() else ""


func _me() -> Node3D:
	for node: Node in get_tree().get_nodes_in_group("players"):
		if node.name == str(Net.local_peer_id()):
			return node as Node3D
	return null
