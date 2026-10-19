extends Node

## Authority: the local peer, for its own character only. Drives the local
## player with the same input actions a person presses, so the player script
## runs its normal code path. Turns by changing body_yaw, which mouse look also
## changes. Never stands still, which NetSmoother's hitch count relies on.
## Every so often it asks the host for a zone move between the store and the lot.

const TURN_RATE_MAX: float = 1.5
const ZONE_MOVE_MIN_SECONDS: float = 20.0
const ZONE_MOVE_MAX_SECONDS: float = 35.0
const STRAFE_ACTIONS: Array[StringName] = [&"move_left", &"move_right"]

var _rng := RandomNumberGenerator.new()
var _elapsed: float = 0.0
var _next_change: float = 0.0
var _next_zone_move: float = 0.0
var _turn_rate: float = 0.0
var _jump_held: bool = false


func _ready() -> void:
	_rng.seed = hash(OS.get_process_id())
	_next_zone_move = _rng.randf_range(ZONE_MOVE_MIN_SECONDS, ZONE_MOVE_MAX_SECONDS)
	Input.action_press(&"move_forward")
	print("[Bot] driving the local player")


func _exit_tree() -> void:
	for action: StringName in [&"move_forward", &"move_left", &"move_right", &"sprint", &"crouch", &"jump"]:
		Input.action_release(action)


func _physics_process(delta: float) -> void:
	_elapsed += delta
	var player := _own_player()
	if player == null:
		return
	if _jump_held:
		Input.action_release(&"jump")
		_jump_held = false
	if _elapsed >= _next_change:
		_choose_next()
	player.set("body_yaw", float(player.get("body_yaw")) + _turn_rate * delta)
	if _elapsed >= _next_zone_move:
		_next_zone_move = _elapsed + _rng.randf_range(ZONE_MOVE_MIN_SECONDS, ZONE_MOVE_MAX_SECONDS)
		var here := Net.player_zone(Net.local_peer_id())
		if here == Net.Zone.STORE:
			Net.request_zone_move(Net.Zone.LOT)
		elif here == Net.Zone.LOT:
			Net.request_zone_move(Net.Zone.STORE)


func _choose_next() -> void:
	_next_change = _elapsed + _rng.randf_range(0.5, 2.5)
	# Always turning, so a wall never pins the bot in place for long.
	_turn_rate = _rng.randf_range(0.3, TURN_RATE_MAX) * (1.0 if _rng.randf() < 0.5 else -1.0)
	for action: StringName in STRAFE_ACTIONS:
		Input.action_release(action)
	if _rng.randf() < 0.3:
		Input.action_press(STRAFE_ACTIONS[_rng.randi_range(0, 1)])
	_set_held(&"sprint", _rng.randf() < 0.4)
	_set_held(&"crouch", _rng.randf() < 0.1)
	if _rng.randf() < 0.35:
		Input.action_press(&"jump")
		_jump_held = true


func _set_held(action: StringName, held: bool) -> void:
	if held:
		Input.action_press(action)
	else:
		Input.action_release(action)


func _own_player() -> Node:
	var own_name := str(Net.local_peer_id())
	for node: Node in get_tree().get_nodes_in_group("players"):
		if node.name == own_name:
			return node
	return null
