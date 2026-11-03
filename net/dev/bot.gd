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
	# R2: each chunk's raid behavior, the first that takes control wins (crew,
	# hiding, the van, the Annex); then the older counterplay below.
	for tick: StringName in [&"_r2_crew_tick", &"_r2_hide_tick", &"_r2_van_tick", &"_r2_annex_tick"]:
		if has_method(tick) and bool(call(tick, delta)):
			_job.call("stop")
			return
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
		elif here == Net.Zone.LOT or here == Net.Zone.TOWN:
			# Out in the connected town counts as away from the store too.
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
			# A shed is only got into from before its door: head for the doorstep.
			var goal := spot.global_position
			if str(spot.get("spot_kind")) == "shed":
				goal = spot.call("entry_point", 0, 0)
			_face(player, goal)
			if goal.distance_to(player.global_position) <= Constants.HIDE_REACH * 0.9 and _elapsed >= _next_interact:
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


# ---- R2:2 the catch (net/run_events/encounter.gd): a caught bot mashes jump
# through the cite; a free bot with something in hand goes for a NICE BOY who has
# hold of a friend half the time (decided once per catch) and throws it at him.
var _r2_rescue_roll: Dictionary = {}
var _r2_next_wriggle: float = 0.0


func _r2_crew_tick(_delta: float) -> bool:
	var encounter := get_tree().get_first_node_in_group("nice_encounter")
	var player := _own_player() as Node3D
	if encounter == null or player == null:
		return false
	var me := Net.local_peer_id()
	var stage := int(encounter.call("stage_of", me))
	if stage == 2 or stage == 3:
		if _elapsed >= _r2_next_wriggle:
			_r2_next_wriggle = _elapsed + _rng.randf_range(0.15, 0.4)
			Input.action_press(&"jump")
			_jump_held = true
		return true
	if stage >= 2 and stage <= 6:
		return true
	for crew: Node in get_tree().get_nodes_in_group("nice_crew"):
		var holder := crew as Node3D
		var held_peer := int(crew.get("mode_peer"))
		var mode := int(crew.get("mode"))
		if holder == null or held_peer == me or (mode != 11 and mode != 12):
			continue
		var key := "%s:%d" % [crew.name, held_peer]
		if not _r2_rescue_roll.has(key):
			_r2_rescue_roll[key] = _rng.randf() < 0.5
		if not bool(_r2_rescue_roll[key]):
			continue
		var held: Node = null
		for node: Node in get_tree().get_nodes_in_group("props"):
			if int(node.get("held_by")) == me:
				held = node
		if held == null:
			continue
		_face(player, holder.global_position)
		var distance := player.global_position.distance_to(holder.global_position)
		if distance > 6.0:
			Input.action_press(&"sprint")
			return true
		var toward := holder.global_position + Vector3.UP * 0.9 - player.global_position
		held.call("request_throw", toward.normalized(), 1.2)
		_r2_rescue_roll[key] = false
		return true
	return false


# ---- R2:4
## The van's holds this bot has decided about: trip id -> whether it goes for the door.
var _van_plan: Dictionary = {}
var _van_try_at: float = -10.0


## The Courtesy Shuttle (net/run_events/shuttle.gd), from the R2 dispatcher: a
## seated bot knocks on the glass now and then; a free one goes for the van's door
## on a quarter of the holds and holds interact on it to unbuckle a friend. True
## while it is steering.
func _r2_van_tick(delta: float) -> bool:
	var shuttle := get_tree().get_first_node_in_group("nice_shuttle")
	var player := _own_player() as Node3D
	if shuttle == null or player == null:
		return false
	if not (shuttle.call("seat_info", Net.local_peer_id()) as Dictionary).is_empty():
		if _rng.randf() < delta * 0.25:
			shuttle.call("request_knock")
		return true
	var trip := int(shuttle.call("raid_trip_id"))
	if trip == 0 or str(shuttle.call("leg_name", trip)) != "parked" or (shuttle.call("seated_riders") as Array).is_empty():
		return false
	if not _van_plan.has(trip):
		_van_plan[trip] = _rng.randf() < 0.25
	if not bool(_van_plan[trip]):
		return false
	var step: Vector3 = shuttle.call("door_step_point")
	var away := Vector2(step.x - player.global_position.x, step.z - player.global_position.z).length()
	_face(player, step)
	if away > Constants.VAN_DOOR_REACH * 0.7:
		Input.action_press(&"sprint")
		return true
	Input.action_release(&"sprint")
	if _elapsed - _van_try_at >= Constants.VAN_UNBUCKLE_HOLD + 1.0:
		_van_try_at = _elapsed
		var riders: Array = shuttle.call("seated_riders")
		shuttle.call("start_unbuckle", trip, int(riders[0]), true)
	return true


# ---- R2:3 hiding: hiders peek now and then, and bolt on a telegraph half the time.
## When the next peek starts and the one running ends (bot seconds), and whether
## this bot already decided about the poke going on now.
var _r2_next_peek: float = -1.0
var _r2_peek_until: float = -1.0
var _r2_poke_seen: bool = false


## Called by the R2 dispatcher (chunk 2) each tick: true while it is steering.
func _r2_hide_tick(_delta: float) -> bool:
	var player := _own_player()
	if player == null or not bool(player.call("is_hidden")):
		_r2_next_peek = -1.0
		_r2_poke_seen = false
		if _r2_peek_until >= 0.0:
			_r2_peek_until = -1.0
			Input.action_release(&"secondary")
		return false
	if _r2_next_peek < 0.0:
		_r2_next_peek = _elapsed + _rng.randf_range(4.0, 9.0)
	if _r2_peek_until >= 0.0 and _elapsed >= _r2_peek_until:
		_r2_peek_until = -1.0
		Input.action_release(&"secondary")
		_r2_next_peek = _elapsed + _rng.randf_range(5.0, 11.0)
	elif _r2_peek_until < 0.0 and _elapsed >= _r2_next_peek:
		_r2_peek_until = _elapsed + _rng.randf_range(0.8, 2.0)
		Input.action_press(&"secondary")
	# A NICE BOY poking our spot (every peer sees the poke): bolt, or hold still.
	var spot: Node = player.call("hidden_spot")
	var poked := spot != null and float(spot.get("_poking")) > 0.0
	if poked and not _r2_poke_seen:
		_r2_poke_seen = true
		if _rng.randf() < 0.5:
			Input.action_release(&"secondary")
			_r2_peek_until = -1.0
			_press_interact()
	elif not poked:
		_r2_poke_seen = false
	return true
