extends Node

## Authority: the local peer, for its own character only. Drives the local
## player with the same input actions a person presses, so the player script
## runs its normal code path. Turns by changing body_yaw, which mouse look also
## changes. Never stands still, which NetSmoother's hitch count relies on.
## Every so often it asks the host for a zone move between the store and the lot.
## On the lot it works the job (net/dev/bot_job.gd) unless --walk-straight.

const TURN_RATE_MAX: float = 1.5
const ZONE_MOVE_MIN_SECONDS: float = 20.0
const ZONE_MOVE_MAX_SECONDS: float = 35.0
const STRAFE_ACTIONS: Array[StringName] = [&"move_left", &"move_right"]
const _BotJob = preload("res://net/dev/bot_job.gd")

var _rng := RandomNumberGenerator.new()
var _elapsed: float = 0.0
var _next_change: float = 0.0
var _next_zone_move: float = 0.0
var _turn_rate: float = 0.0
var _jump_held: bool = false
## Hiders head for a hide spot when the crew arrives. Runners sprint away.
var _hider: bool = false
var _next_interact: float = 0.0
var _job: RefCounted


func _ready() -> void:
	_rng.seed = hash(OS.get_process_id())
	# Odd-numbered bots hide and the rest run, so every soak with a run event tests both.
	var number := str(Net.dev_options().get("player_name")).trim_prefix("Bot").to_int()
	_hider = number % 2 == 1
	_job = _BotJob.new(_rng)
	_next_zone_move = _rng.randf_range(ZONE_MOVE_MIN_SECONDS, ZONE_MOVE_MAX_SECONDS)
	Input.action_press(&"move_forward")
	print("[Bot] driving the local player")


func _exit_tree() -> void:
	for action: StringName in [&"move_forward", &"move_left", &"move_right", &"sprint", &"crouch", &"jump", &"primary"]:
		Input.action_release(action)


func _physics_process(delta: float) -> void:
	_elapsed += delta
	var player := _own_player() as Node3D
	if player == null:
		return
	if _jump_held:
		Input.action_release(&"jump")
		_jump_held = false
	if _during_run_event(player):
		_job.call("stop")
		return
	# For measuring smoothness: steady walking, no turns, no jumps.
	if bool(Net.dev_options().get("walk_straight")):
		Input.action_release(&"sprint")
		Input.action_release(&"crouch")
		return
	_maybe_change_zone()
	if _job.call("step", player, delta):
		for action: StringName in STRAFE_ACTIONS:
			Input.action_release(action)
		return
	if _elapsed >= _next_change:
		_choose_next()
	player.set("body_yaw", float(player.get("body_yaw")) + _turn_rate * delta)


func _maybe_change_zone() -> void:
	if _elapsed >= _next_zone_move and not bool(Net.dev_options().get("bot_stay")):
		_next_zone_move = _elapsed + _rng.randf_range(ZONE_MOVE_MIN_SECONDS, ZONE_MOVE_MAX_SECONDS)
		var here := Net.player_zone(Net.local_peer_id())
		if here == Net.Zone.STORE:
			Net.request_zone_move(Net.Zone.LOT)
		elif here == Net.Zone.LOT:
			Net.request_zone_move(Net.Zone.STORE)


## Counterplay during a chase: hiders go for the nearest free hide spot and get
## in, runners sprint away from the nearest crew member. Hiders come out when the
## run event ends. Returns true while it is steering, so wandering pauses.
func _during_run_event(player: Node3D) -> bool:
	var director := get_tree().get_first_node_in_group("run_director")
	var chasing := director != null and int(director.call("phase")) == 2
	var hidden := bool(player.call("is_hidden"))
	if not chasing:
		if hidden and _elapsed >= _next_interact:
			_next_interact = _elapsed + 1.0
			_press_interact()
		return false
	if hidden:
		return true
	if _hider:
		var spot := _nearest_free_spot(player)
		if spot != null:
			Input.action_press(&"sprint")
			_face(player, spot.global_position)
			if spot.global_position.distance_to(player.global_position) <= Constants.HIDE_REACH * 0.9 and _elapsed >= _next_interact:
				_next_interact = _elapsed + 1.0
				_press_interact()
			return true
	var crew := get_tree().get_first_node_in_group("crew") as Node3D
	if crew == null:
		return false
	Input.action_press(&"sprint")
	_face(player, player.global_position * 2.0 - crew.global_position)
	return true


func _nearest_free_spot(player: Node3D) -> Node3D:
	var closest: Node3D = null
	var closest_distance := INF
	for node: Node in get_tree().get_nodes_in_group("hide_spots"):
		var spot := node as Node3D
		if spot == null or int(spot.get("occupant")) != 0:
			continue
		var distance := spot.global_position.distance_to(player.global_position)
		if distance < closest_distance:
			closest = spot
			closest_distance = distance
	return closest


## Turn so move_forward heads toward the point. Forward is -Z, rotated by body_yaw.
func _face(player: Node3D, point: Vector3) -> void:
	var away := point - player.global_position
	player.set("body_yaw", atan2(-away.x, -away.z))


func _press_interact() -> void:
	for pressed: bool in [true, false]:
		var event := InputEventAction.new()
		event.action = &"interact"
		event.pressed = pressed
		Input.parse_input_event(event)


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
