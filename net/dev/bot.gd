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
	# R2: each chunk's tick, the first that takes control wins (chunk 2 adds the rest).
	if has_method("_r2_annex_tick") and bool(call("_r2_annex_tick", delta)):
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

# ---- R2:6
# Satellite Annex B (net/annex/annex.gd): a caught bot does its paperwork the
# way a person would. Walk to the window its next box needs and stand on the
# counter spot while he's open; when he's looking away, hold interact on his
# stamp; ring an asleep clerk's bell; take a full form to the Head NICE BOY's
# desk; drop the approved one in the tray and push through the turnstile. It
# never touches the big stamp. Returns true while it's steering.

const _AnnexSchedule = preload("res://net/annex/annex_schedule.gd")
const _AnnexForm = preload("res://net/annex/form_state.gd")
## Close enough to a spot to stop on it, in meters.
const ANNEX_STOP_METERS: float = 0.3
## How long a self-stamp hold lasts (a little over the host's ANNEX_SELF_STAMP_HOLD).
const ANNEX_HOLD_SECONDS: float = 1.35

var _annex_walking: bool = true
var _annex_hold_left: float = 0.0
var _annex_bell_wait: float = 0.0
var _annex_check_left: float = 1.0
var _annex_last_spot: Vector3 = Vector3.ZERO
var _annex_side_left: float = 0.0
var _annex_side: StringName = &"move_left"


func _r2_annex_tick(delta: float) -> bool:
	var annex := get_tree().get_first_node_in_group("annex")
	var me_id := Net.local_peer_id()
	var player := _own_player() as Node3D
	if annex == null or player == null or Net.player_zone(me_id) != Net.Zone.BORDER or not bool(annex.call("is_active")) or str(annex.call("stage_of", me_id)) != "inside":
		if not _annex_walking:
			_annex_walking = true
			Input.action_press(&"move_forward")
		if _annex_hold_left > 0.0:
			_annex_hold_left = 0.0
			_annex_interact(false)
		return false
	Input.action_release(&"sprint")
	Input.action_release(&"crouch")
	if _annex_side_left <= 0.0:
		for action: StringName in STRAFE_ACTIONS:
			Input.action_release(action)
	_annex_bell_wait -= delta
	if _annex_hold_left > 0.0:
		_annex_hold_left -= delta
		if _annex_hold_left <= 0.0:
			_annex_interact(false)
		_annex_stop()
		return true
	var form: Dictionary = annex.call("form_of", me_id)
	if form.is_empty():
		return true
	var target := Vector3.INF
	if bool(form.get("approved", false)):
		# The tray, then through the turnstile into the forecourt.
		if not bool(form.get("dropped", false)):
			_annex_go(player, _annex_point("OutgoingTray"), 0.6)
			return true
		# Line up in front of the turnstile, then straight through: it turns for us,
		# though it looks solid to the steering's ray.
		var gate := _annex_point("Turnstile")
		var out := _annex_point("Forecourt")
		if gate != Vector3.INF and out != Vector3.INF:
			var outward := Vector3(out.x - gate.x, 0.0, out.z - gate.z).normalized()
			var front := gate - outward * 0.9
			var offset := player.global_position - gate
			var side := offset.dot(outward)
			var lateral := absf(offset.dot(Vector3(-outward.z, 0.0, outward.x)))
			if side < -0.3 and lateral > 0.3:
				_annex_go(player, front, 0.0)
				return true
		_annex_go(player, out, 0.0, true)
		return true
	if _AnnexForm.is_full(form):
		_annex_go(player, _annex_point("HeadDesk/DeskSpot"), 0.0)
		return true
	var window := _AnnexForm.next_window(form)
	var state: Dictionary = annex.call("window_now", window)
	var s := int(state["state"])
	if s == _AnnexSchedule.S.ASLEEP and _annex_bell_wait <= 0.0:
		var bell := _annex_point("Windows/%s/Bell" % window)
		if _annex_go(player, bell, 0.0):
			_annex_bell_wait = 3.0
			_annex_interact(true)
			_annex_interact(false)
		return true
	if not bool(state["looking"]) and float(state["until"]) - float(annex.call("elapsed")) > ANNEX_HOLD_SECONDS + 0.4:
		# He's looking away long enough: his stamp.
		if _annex_go(player, _annex_point("Windows/%s/StampPad" % window), 0.0):
			_annex_hold_left = ANNEX_HOLD_SECONDS
			_annex_interact(true)
		return true
	_annex_go(player, _annex_point("Windows/%s/Counter" % window), 0.0)
	return true


## Walk toward a point (back meters short of it); true once standing on it.
func _annex_go(player: Node3D, point: Vector3, back: float, straight: bool = false) -> bool:
	if point == Vector3.INF:
		_annex_stop()
		return false
	var flat := Vector3(point.x - player.global_position.x, 0.0, point.z - player.global_position.z)
	if flat.length() <= ANNEX_STOP_METERS + back:
		_annex_stop()
		return true
	_face(player, point if straight else _annex_steer(player, point))
	# Pressed every tick: the job or the chase code may have let go of it.
	_annex_walking = true
	Input.action_press(&"move_forward")
	# Stuck on a bench or a booth wall: sidestep a moment, the way people do.
	_annex_check_left -= get_physics_process_delta_time()
	if _annex_check_left <= 0.0:
		_annex_check_left = 1.0
		var stuck := player.global_position.distance_to(_annex_last_spot) < 0.25
		_annex_last_spot = player.global_position
		if stuck:
			_annex_side_left = 0.9
			_annex_side = &"move_left" if _rng.randf() < 0.5 else &"move_right"
	if _annex_side_left > 0.0:
		_annex_side_left -= get_physics_process_delta_time()
		Input.action_press(_annex_side)
		if _annex_side_left <= 0.0:
			Input.action_release(_annex_side)
	return false


## Where to head for point: straight at it when the way is clear at knee height,
## else the nearest turn either side that is (round a row of chairs, a counter).
func _annex_steer(player: Node3D, point: Vector3) -> Vector3:
	var from := player.global_position + Vector3(0.0, 0.45, 0.0)
	var flat := Vector3(point.x - from.x, 0.0, point.z - from.z)
	var reach := minf(flat.length(), 2.5)
	if reach < 0.3:
		return point
	var space := player.get_world_3d().direct_space_state
	var dir := flat.normalized()
	for turn: float in [0.0, 0.5, -0.5, 1.0, -1.0, 1.5, -1.5, 2.2, -2.2]:
		var heading := dir.rotated(Vector3.UP, turn)
		var query := PhysicsRayQueryParameters3D.create(from, from + heading * reach, 1)
		query.exclude = [(player as CollisionObject3D).get_rid()]
		var hit := space.intersect_ray(query)
		if hit.is_empty():
			return player.global_position + heading * 2.0
	return point


func _annex_stop() -> void:
	if _annex_walking:
		_annex_walking = false
		Input.action_release(&"move_forward")


func _annex_interact(pressed: bool) -> void:
	var event := InputEventAction.new()
	event.action = &"interact"
	event.pressed = pressed
	Input.parse_input_event(event)


func _annex_point(path: String) -> Vector3:
	var world := get_tree().get_first_node_in_group("world")
	var node := world.get_node_or_null("BorderZone/AnnexSet/" + path) as Node3D if world != null else null
	return node.global_position if node != null else Vector3.INF
