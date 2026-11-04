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
	_crew = bool(Net.dev_options().get("bot_crew"))
	_crew_number = maxi(1, number)
	_job.set("share_rake", _crew)
	_next_zone_move = _rng.randf_range(ZONE_MOVE_MIN_SECONDS, ZONE_MOVE_MAX_SECONDS)
	if not _crew:
		Input.action_press(&"move_forward")
	print("[Bot] driving the local player%s" % (" as a crew member" if _crew else ""))


func _exit_tree() -> void:
	if _job != null:
		print("[Bot] hotbar fidgets: %d in %d rake runs" % [int(_job.get("fidgets")), int(_job.get("runs"))])
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
	if _crew:
		_crew_tick(player, delta)
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
		if _crew:
			Input.action_release(&"move_forward")
		return true
	# A crew bot only walks while it means to (a soak bot always holds forward).
	Input.action_press(&"move_forward")
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
	if _crew and Net.player_zone(Net.local_peer_id()) == Net.Zone.LOT:
		# Away, but round the yard, not into its corner (tools:crew review: Bot2 sat
		# pinned in a corner for a whole chase).
		_face(player, _crew_steer(player, _crew_flee_point(player, crew.global_position)))
	else:
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
	var want := atan2(-away.x, -away.z)
	if _crew and Vector2(away.x, away.z).length() > 0.01:
		# Eased like a hand on a mouse (bot_job.gd CREW_TURN_RATE).
		var have := float(player.get("body_yaw"))
		var step := _BotJob.CREW_TURN_RATE * player.get_physics_process_delta_time()
		var error := wrapf(want - have, -PI, PI)
		_job.set("turn_left", error)
		want = have + clampf(error, -step, step)
	player.set("body_yaw", want)


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
		Input.action_press(&"move_forward")
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
		Input.action_press(&"move_forward")
		return true
	Input.action_release(&"sprint")
	if _crew:
		Input.action_release(&"move_forward")
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
## When a hidden bot climbs out after the raid (bot seconds), -1 while one's on.
var _r2_out_at: float = -1.0


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
	# The raid's over: climb out (tools:crew: this tick kept every hider in its
	# hedge for good, since it steers whenever hidden and the older "come out when
	# it ends" code below never ran). A moment's wait first, like a person checking.
	var director := get_tree().get_first_node_in_group("run_director")
	if director != null and int(director.call("phase")) == 0:
		if _r2_peek_until >= 0.0:
			_r2_peek_until = -1.0
			Input.action_release(&"secondary")
		if _r2_out_at < 0.0:
			_r2_out_at = _elapsed + _rng.randf_range(1.5, 4.0)
		elif _elapsed >= _r2_out_at:
			_r2_out_at = _elapsed + 1.0
			_press_interact()
		return true
	_r2_out_at = -1.0
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


# ---- tools:crew (tools/play.ps1 -Bots): a bot that plays a whole day as one of
# the crew. No zone moves of its own: at the store it waits by Chefty, a few
# steps apart from the others, so it rides along whenever someone sets off;
# on the yard it works the job (net/dev/bot_job.gd, sharing the rake); after
# payday Chefty takes it home with everyone. Raids, the van and the Annex are the
# R2 ticks above, as for any bot.
## Where crew bots wait for the ride, in Chefty's own space (m; +Z is behind the
## tailgate): Bot1 by the passenger side, Bot2 by the driver's, Bot3 by the cab.
## All well inside levels/boarding.gd's BOARD_RADIUS_METERS of the pad.
const CREW_WAIT_SLOTS: Array[Vector3] = [Vector3(2.4, 0.0, 0.8), Vector3(-2.4, 0.0, 0.8), Vector3(2.4, 0.0, -1.6)]
## Close enough to its waiting spot (m).
const CREW_ARRIVE_METERS: float = 0.7
## A crew bot walks only while what it's turning to is within this (rad) of
## straight ahead; past it, it stops and turns first.
const CREW_WALK_TURN: float = 0.6
## Between idle glances and shuffles (s).
const CREW_IDLE_MIN: float = 3.0
const CREW_IDLE_MAX: float = 8.0
## Wandering on the yard when there's no work: slow turns (rad/s) and no hops.
const CREW_WANDER_TURN: float = 0.6
## Wandering this close (m) to the leaf field's edge, or stuck, it walks back in to
## a spot at least CREW_INNER_METERS inside, until within CREW_WANDER_ARRIVE of it
## or CREW_WANDER_GOAL_SECONDS have gone. A runner flees to a point this far
## inside the field too, and sideways along it when cornered.
const CREW_EDGE_METERS: float = 4.0
const CREW_INNER_METERS: float = 8.0
const CREW_WANDER_ARRIVE: float = 1.5
const CREW_WANDER_GOAL_SECONDS: float = 12.0
const CREW_FLEE_METERS: float = 8.0

var _crew: bool = false
var _crew_wander_goal := Vector3.INF
var _crew_wander_until: float = 0.0
var _crew_got_stuck: bool = false
var _crew_number: int = 1
var _crew_next_idle: float = 0.0
var _crew_shuffle := Vector3.ZERO
var _crew_last_spot := Vector3.INF
var _crew_check_left: float = 1.0
var _crew_side_left: float = 0.0
var _crew_side: StringName = &"move_left"


func _crew_tick(player: Node3D, delta: float) -> void:
	Input.action_release(&"crouch")
	_job.set("turn_left", 0.0)
	var zone := Net.player_zone(Net.local_peer_id())
	# p1-depart: Chefty honked after the cash. Drop the work and walk over to it
	# (the honk-and-wait sits you down once you're beside the bed).
	var honking := get_tree().get_first_node_in_group("chefty")
	if zone == Net.Zone.LOT and honking != null and honking.has_method("is_boarding") and bool(honking.call("is_boarding")) and int(honking.call("boarding_destination")) == Net.Zone.STORE:
		_job.call("stop")
		Input.action_release(&"primary")
		# p2-kit: its rake goes back on the rack before it climbs in.
		if _kit_put_back(player, delta):
			return
		var spot := _crew_wait_spot()
		if spot != Vector3.INF and int(honking.call("seat_of", Net.local_peer_id())) < 0:
			_face(player, _crew_steer(player, spot))
			Input.action_press(&"sprint")
			_crew_walk(player, true, delta)
		else:
			Input.action_release(&"sprint")
			_crew_walk(player, false, delta)
		return
	if zone == Net.Zone.LOT or zone == Net.Zone.TOWN:
		if _job.call("step", player, delta):
			for action: StringName in STRAFE_ACTIONS:
				Input.action_release(action)
			_crew_walk(player, bool(_job.get("wants_walk")), delta)
			return
		# Nothing to carry and the rake's taken: amble about the yard, scooping now and
		# then. Near the yard's edge, or stuck, it heads back in to somewhere among
		# the leaves (tools:crew review: a constant turn and forward held pinned idle
		# bots against the lot's edge and corners, grinding along an invisible wall).
		if zone != Net.Zone.LOT:
			_crew_wander_goal = Vector3.INF
		elif _crew_wander_goal.is_finite():
			var left := Vector2(_crew_wander_goal.x - player.global_position.x, _crew_wander_goal.z - player.global_position.z).length()
			if left < CREW_WANDER_ARRIVE or _elapsed >= _crew_wander_until:
				_crew_wander_goal = Vector3.INF
			else:
				_face(player, _crew_steer(player, _crew_wander_goal))
				_crew_walk(player, true, delta)
				return
		if zone == Net.Zone.LOT and (_crew_got_stuck or _crew_yard_point(player.global_position, CREW_EDGE_METERS) != player.global_position):
			_crew_got_stuck = false
			_crew_wander_goal = _crew_inner_point()
			_crew_wander_until = _elapsed + CREW_WANDER_GOAL_SECONDS
			if _crew_wander_goal.is_finite():
				_crew_walk(player, false, delta)
				return
		if _elapsed >= _next_change:
			_next_change = _elapsed + _rng.randf_range(1.5, 4.0)
			_turn_rate = _rng.randf_range(-CREW_WANDER_TURN, CREW_WANDER_TURN)
		player.set("body_yaw", float(player.get("body_yaw")) + _turn_rate * delta)
		_crew_walk(player, true, delta)
		return
	_job.call("stop")
	Input.action_release(&"primary")
	if zone != Net.Zone.STORE:
		# Riding, or anywhere the R2 ticks didn't take: stand still.
		_crew_walk(player, false, delta)
		return
	if _crew_bedtime(player, delta):
		return
	# p2-kit: Day 1 shopping. A crew short of rakes: buy one with its own cash,
	# carry it to Chefty and load it, then wait for the ride like everyone.
	if _kit_shop(player, delta):
		return
	var spot := _crew_wait_spot()
	if spot == Vector3.INF:
		_crew_walk(player, false, delta)
		return
	var away := Vector2(spot.x - player.global_position.x, spot.z - player.global_position.z).length()
	if away > CREW_ARRIVE_METERS:
		_face(player, _crew_steer(player, spot))
		if away < 8.0:
			Input.action_release(&"sprint")
		else:
			Input.action_press(&"sprint")
		_crew_walk(player, true, delta)
		return
	Input.action_release(&"sprint")
	_crew_walk(player, false, delta)
	# Waiting: look at the truck, glance round now and then, shift your feet.
	if _elapsed >= _crew_next_idle:
		_crew_next_idle = _elapsed + _rng.randf_range(CREW_IDLE_MIN, CREW_IDLE_MAX)
		var truck := get_tree().get_first_node_in_group("chefty") as Node3D
		var look_at := truck.global_position if truck != null else spot
		if _rng.randf() < 0.4:
			look_at = player.global_position + Vector3(_rng.randf_range(-5.0, 5.0), 0.0, _rng.randf_range(-5.0, 5.0))
		_face(player, look_at)
		if _rng.randf() < 0.3:
			_crew_shuffle = Vector3(_rng.randf_range(-0.5, 0.5), 0.0, _rng.randf_range(-0.5, 0.5))


# ---- p2-kit: crew bots buy their own rake and load it (docs/GAME.md "The crew's kit").
## The way in to Homie Depot's lobby from the lot, then back out (StoreZone
## space): outside the doors, then just inside them, then the rake bin.
const KIT_DOOR_PATH: Array[Vector3] = [Vector3(-8.2, 0.0, -2.0), Vector3(-11.4, 0.0, -1.0)]
## Close enough to a waypoint (m), and to the bin's front to buy.
const KIT_WAYPOINT_METERS: float = 0.8
const KIT_BUY_METERS: float = 0.9
## Where a bot stands to load the bed (truck space): beside it, its own side.
const KIT_LOAD_SIDE := Vector3(1.9, 0.0, -0.3)
## How long a bot gives a buy (s) before it tries again.
const KIT_BUY_WAIT: float = 3.0
var _kit_leg: int = 0
var _kit_bought_at: float = -100.0


## True while shopping or loading (the bot is steering). Buys only when the crew
## has fewer rakes than players, this bot carries none, has the cash, and the
## store's open.
func _kit_shop(player: Node3D, delta: float) -> bool:
	var me := Net.local_peer_id()
	var held: Node = player.call("_held_prop")
	var mine := _carried_rake(me)
	var truck := get_tree().get_first_node_in_group("chefty")
	var bed: Node = truck.call("tool_bed") if truck != null and truck.has_method("tool_bed") else null
	if mine != null:
		# Got one: to Chefty, and onto the rack.
		if bed == null or bool(truck.call("is_riding")) or not bool(bed.call("has_room_for", "rake")):
			return false
		if held != mine:
			# In a pocket: out into the hands first.
			_kit_draw(mine)
			_crew_walk(player, false, delta)
			return true
		if _kit_leg > 0:
			if _kit_walk_path(player, delta, true):
				return true
		var side := (truck.call("bed_transform") as Transform3D) * KIT_LOAD_SIDE
		# Up onto the rack as soon as it's in reach (hotbar:E: walking on to the
		# load side, a bot stood inside the other one waiting there,
		# play-observer\rec_fetch_3p frame 57).
		if bool(bed.call("can_load_from", player)):
			_crew_walk(player, false, delta)
			_face(player, truck.call("body_position"))
			if _elapsed >= _next_interact:
				_next_interact = _elapsed + 1.0
				mine.call("request_load_truck")
			return true
		_face(player, _crew_steer(player, side))
		_crew_walk(player, true, delta)
		return true
	# hotbar:E: the crew's own rake lying by the front door (left at a yard, walked
	# over by a neighbor overnight): fetch it before buying another.
	if held == null and _kit_fetch(player, delta, bed):
		return true
	var kit := get_tree().get_first_node_in_group("kit")
	var shops := get_tree().get_first_node_in_group("shops")
	if kit == null or shops == null or held != null or not bool(shops.call("is_open", "homie_depot")):
		_kit_leg = 0
		return false
	var crew := 0
	for peer_id: int in Net.peer_ids():
		if not Net.is_watcher(peer_id) and Net.player_name(peer_id) != "Observer":
			crew += 1
	if int(kit.call("count_of", "rake")) >= crew or Campaign.credits(me) < Catalog.price("rake"):
		_kit_leg = 0
		return false
	var bin := get_tree().get_first_node_in_group("rake_bin")
	var store := _store_zone()
	if bin == null or store == null:
		return false
	# Through the doors, to the bin.
	if _kit_leg < KIT_DOOR_PATH.size():
		var point := store.to_global(KIT_DOOR_PATH[_kit_leg])
		if Vector2(point.x - player.global_position.x, point.z - player.global_position.z).length() < KIT_WAYPOINT_METERS:
			_kit_leg += 1
		else:
			_face(player, _crew_steer(player, point))
			_crew_walk(player, true, delta)
			return true
	var front: Vector3 = bin.call("slot_front", 0)
	if Vector2(front.x - player.global_position.x, front.z - player.global_position.z).length() > KIT_BUY_METERS:
		_face(player, _crew_steer(player, front))
		_crew_walk(player, true, delta)
		return true
	_crew_walk(player, false, delta)
	_face(player, bin.global_position)
	if _elapsed - _kit_bought_at > KIT_BUY_WAIT:
		_kit_bought_at = _elapsed
		shops.call("request_buy", "homie_depot", "rake", 1)
	return true


## A loose rake this close (m) to a bot waiting at the store is the crew's to fetch.
const KIT_FETCH_METERS: float = 40.0
## Close enough to pick it up (m).
const KIT_FETCH_GRAB_METERS: float = 1.5


## hotbar:E: while Chefty's rack has fewer rakes than the crew has players, walk to
## a loose rake at the store (the ones a neighbor brought back sit by the front
## door) and pick it up; _kit_shop then carries it to the rack like a bought one.
## A bot nearer the same rake leaves it to that bot. True while it's doing that.
func _kit_fetch(player: Node3D, delta: float, bed: Node) -> bool:
	var truck := get_tree().get_first_node_in_group("chefty")
	if bed == null or truck == null or bool(truck.call("is_riding")) or not bool(bed.call("has_room_for", "rake")):
		return false
	var crew := 0
	for peer_id: int in Net.peer_ids():
		if not Net.is_watcher(peer_id) and Net.player_name(peer_id) != "Observer":
			crew += 1
	if int(bed.call("count_of", "rake")) >= crew:
		return false
	var target: Node3D = null
	var best := KIT_FETCH_METERS
	for node: Node in get_tree().get_nodes_in_group("props"):
		var prop := node as Node3D
		if prop == null or str(prop.get("kind")) != "rake" or not bool(prop.call("is_loose")) or bool(prop.call("is_flying")):
			continue
		var away := Vector2(prop.global_position.x - player.global_position.x, prop.global_position.z - player.global_position.z).length()
		if away < best and not _other_bot_nearer(player, prop.global_position, away):
			best = away
			target = prop
	if target == null:
		return false
	if best > KIT_FETCH_GRAB_METERS:
		_face(player, _crew_steer(player, target.global_position))
		_crew_walk(player, true, delta)
		return true
	_crew_walk(player, false, delta)
	_face(player, target.global_position)
	if _elapsed >= _next_interact:
		_next_interact = _elapsed + 1.0
		target.call("request_grab")
	return true


## Whether another bot on this zone stands nearer the point than distance.
func _other_bot_nearer(player: Node3D, point: Vector3, distance: float) -> bool:
	for node: Node in get_tree().get_nodes_in_group("players"):
		var other := node as Node3D
		var peer_id := int(str(node.name))
		if other == null or other == player or not Net.player_name(peer_id).begins_with("Bot"):
			continue
		if Net.player_zone(peer_id) != Net.player_zone(Net.local_peer_id()):
			continue
		if Vector2(point.x - other.global_position.x, point.z - other.global_position.z).length() < distance:
			return true
	return false


## Back out through the doors with the rake (true while still on the way).
func _kit_walk_path(player: Node3D, delta: float, outward: bool) -> bool:
	var store := _store_zone()
	if store == null or not outward:
		_kit_leg = 0
		return false
	var index := _kit_leg - 1
	if index < 0:
		return false
	var point := store.to_global(KIT_DOOR_PATH[index])
	if Vector2(point.x - player.global_position.x, point.z - player.global_position.z).length() < KIT_WAYPOINT_METERS:
		_kit_leg -= 1
		return _kit_leg > 0
	_face(player, _crew_steer(player, point))
	_crew_walk(player, true, delta)
	return true


## A rake lying this close (m) when Chefty honks home is picked up on the way.
const KIT_HONK_PICKUP_METERS: float = 10.0


## On the yard, Chefty honking to go home: a rake in hand or pocket goes back
## on the rack first (true while it's doing that), and a rake it set down nearby
## is picked up on the way. The honk-and-wait is short (CHEFTY_BOARD_WAIT_SECONDS)
## and climbing in starts at CHEFTY_BOARD_WALKUP_METERS from the tailgate, farther
## out than the rack's KIT_LOAD_REACH, so (hotbar:E, P2's crew session: no bot was
## ever seen putting its rake back) the rake comes out of the pocket while it
## walks, not standing still, and it goes up onto the rack from wherever the
## bot is once it's in reach, even from its seat in the bed, which it had
## reached first every time.
func _kit_put_back(player: Node3D, delta: float) -> bool:
	var mine := _carried_rake(Net.local_peer_id())
	var truck := get_tree().get_first_node_in_group("chefty")
	var bed: Node = truck.call("tool_bed") if truck != null and truck.has_method("tool_bed") else null
	if bed == null or not bool(bed.call("has_room_for", "rake")):
		return false
	var seated := int(truck.call("seat_of", Net.local_peer_id())) >= 0
	var held: Node = player.call("_held_prop")
	if mine == null:
		return not seated and held == null and _kit_honk_pickup(player, delta)
	if held != mine:
		if held != null:
			return false
		_kit_draw(mine)
	var can_load := bool(bed.call("can_load_from", player))
	if held == mine and can_load and _elapsed >= _next_interact:
		_next_interact = _elapsed + 1.0
		mine.call("request_load_truck")
	if seated:
		return true
	if can_load:
		_crew_walk(player, false, delta)
		_face(player, truck.call("body_position"))
		return true
	var side := (truck.call("bed_transform") as Transform3D) * KIT_LOAD_SIDE
	_face(player, _crew_steer(player, side))
	Input.action_press(&"sprint")
	_crew_walk(player, true, delta)
	return true


## The honk home with no rake on it: one lying within KIT_HONK_PICKUP_METERS that
## no other bot is nearer gets picked up (then _kit_put_back loads it).
func _kit_honk_pickup(player: Node3D, delta: float) -> bool:
	var target: Node3D = null
	var best := KIT_HONK_PICKUP_METERS
	for node: Node in get_tree().get_nodes_in_group("props"):
		var prop := node as Node3D
		if prop == null or str(prop.get("kind")) != "rake" or not bool(prop.call("is_loose")) or bool(prop.call("is_flying")):
			continue
		var away := Vector2(prop.global_position.x - player.global_position.x, prop.global_position.z - player.global_position.z).length()
		if away < best and not _other_bot_nearer(player, prop.global_position, away):
			best = away
			target = prop
	if target == null:
		return false
	if best > KIT_FETCH_GRAB_METERS:
		_face(player, _crew_steer(player, target.global_position))
		Input.action_press(&"sprint")
		_crew_walk(player, true, delta)
		return true
	_crew_walk(player, false, delta)
	_face(player, target.global_position)
	if _elapsed >= _next_interact:
		_next_interact = _elapsed + 1.0
		target.call("request_grab")
	return true


## Out of its pocket into the hands: that slot, asked for outright (a number key
## pressed on the selected slot would put the hands away instead), once a second.
func _kit_draw(item: Node) -> void:
	var slot := int(item.get("pocket_slot"))
	var hotbar := get_tree().get_first_node_in_group("hotbar")
	if slot < 0 or hotbar == null or _elapsed < _next_interact:
		return
	_next_interact = _elapsed + 1.0
	hotbar.call("request_select", slot)
	var pockets := _own_player().get_node_or_null("Pockets") if _own_player() != null else null
	if pockets != null and "selected" in pockets:
		pockets.set("selected", slot)


func _carried_rake(peer_id: int) -> Node:
	for node: Node in get_tree().get_nodes_in_group("props"):
		if str(node.get("kind")) == "rake" and (int(node.get("held_by")) == peer_id or int(node.get("pocketed_by")) == peer_id) and not node.is_queued_for_deletion():
			return node
	return null


func _store_zone() -> Node3D:
	var world := get_tree().get_first_node_in_group("world")
	return world.get_node_or_null("StoreZone") as Node3D if world != null else null


## Where this bot waits for the ride: beside Chefty's bed, a slot per bot number
## (CREW_WAIT_SLOTS, in the truck's own space), never behind the tailgate where
## people walk up to board (tools:crew: waiting round the pad, Bot1 stood on the
## spot the host walked to and the host's eye ended up in its head). Round the
## truck pad while Chefty's away.
func _crew_wait_spot() -> Vector3:
	var truck := get_tree().get_first_node_in_group("chefty") as Node3D
	var slot: Vector3 = CREW_WAIT_SLOTS[(_crew_number - 1) % CREW_WAIT_SLOTS.size()]
	if truck != null and truck.has_method("bed_transform") and not bool(truck.call("is_riding")):
		var bed: Transform3D = truck.call("bed_transform")
		var at := bed * slot
		return Vector3(at.x, bed.origin.y, at.z) + _crew_shuffle
	var world := get_tree().get_first_node_in_group("world")
	var pad := world.get_node_or_null("StoreZone/TruckPad") as Node3D if world != null else null
	if pad == null:
		return Vector3.INF
	return pad.global_transform * slot + _crew_shuffle


## Holds or lets go of move_forward, and sidesteps when walking gets nowhere (a
## doorframe, a shelf end, a teammate in the way), the way people do.
func _crew_walk(player: Node3D, walking: bool, delta: float) -> void:
	# Turn first, then go: walking while still turning hard circled a spot it
	# could never reach (tools:crew: Bot2 orbited its waiting spot for a minute,
	# at 5 rad/s and a walk its turn circle was wider than the spot).
	var turning := absf(float(_job.get("turn_left"))) > CREW_WALK_TURN
	if not walking or turning:
		Input.action_release(&"move_forward")
		for action: StringName in STRAFE_ACTIONS:
			Input.action_release(action)
		_crew_last_spot = Vector3.INF
		return
	Input.action_press(&"move_forward")
	_crew_check_left -= delta
	if _crew_check_left <= 0.0:
		_crew_check_left = 1.0
		var stuck := _crew_last_spot.is_finite() and player.global_position.distance_to(_crew_last_spot) < 0.25
		_crew_last_spot = player.global_position
		if stuck:
			_crew_side_left = 0.9
			_crew_side = STRAFE_ACTIONS[_rng.randi_range(0, 1)]
			_crew_got_stuck = true
	if _crew_side_left > 0.0:
		_crew_side_left -= delta
		Input.action_press(_crew_side)
		if _crew_side_left <= 0.0:
			Input.action_release(_crew_side)


## The point moved inside the leaf field, at least margin (m) from its edges (the
## middle where the field is narrower than that); the point itself when it's there
## already or there's no field.
func _crew_yard_point(point: Vector3, margin: float) -> Vector3:
	var field := get_tree().get_first_node_in_group("leaf_field") as Node3D
	if field == null:
		return point
	var origin: Vector3 = field.get("grid_origin")
	var cell := float(field.get("cell_size"))
	var size := Vector2(float(int(field.get("grid_width"))), float(int(field.get("grid_depth")))) * cell
	var local := field.global_transform.affine_inverse() * point
	var x := local.x - origin.x
	var z := local.z - origin.z
	var in_x := clampf(x, minf(margin, size.x * 0.5), maxf(size.x - margin, size.x * 0.5))
	var in_z := clampf(z, minf(margin, size.y * 0.5), maxf(size.y - margin, size.y * 0.5))
	if is_equal_approx(in_x, x) and is_equal_approx(in_z, z):
		return point
	var inside := field.global_transform * Vector3(origin.x + in_x, local.y, origin.z + in_z)
	return Vector3(inside.x, point.y, inside.z)


## A random spot well inside the leaf field (Vector3.INF without one).
func _crew_inner_point() -> Vector3:
	var field := get_tree().get_first_node_in_group("leaf_field") as Node3D
	if field == null:
		return Vector3.INF
	var origin: Vector3 = field.get("grid_origin")
	var cell := float(field.get("cell_size"))
	var size := Vector2(float(int(field.get("grid_width"))), float(int(field.get("grid_depth")))) * cell
	var margin := Vector2(minf(CREW_INNER_METERS, size.x * 0.5), minf(CREW_INNER_METERS, size.y * 0.5))
	var local := origin + Vector3(_rng.randf_range(margin.x, size.x - margin.x), 0.0, _rng.randf_range(margin.y, size.y - margin.y))
	return field.global_transform * local


## Where a crew runner flees to: away from the NICE BOY, but kept inside the yard;
## cornered (that leaves it nowhere to go), sideways along the edge, whichever
## way leads back toward the middle.
func _crew_flee_point(player: Node3D, from: Vector3) -> Vector3:
	var here := player.global_position
	var away := Vector3(here.x - from.x, 0.0, here.z - from.z)
	if away.length() < 0.01:
		away = Vector3.FORWARD
	away = away.normalized()
	var goal := _crew_yard_point(here + away * CREW_FLEE_METERS, CREW_EDGE_METERS)
	if Vector2(goal.x - here.x, goal.z - here.z).length() > CREW_FLEE_METERS * 0.5:
		return goal
	var middle := _crew_yard_point(here, INF)
	var side := Vector3(-away.z, 0.0, away.x)
	if middle.is_finite() and side.dot(middle - here) < 0.0:
		side = -side
	return _crew_yard_point(here + side * CREW_FLEE_METERS, CREW_EDGE_METERS)


## Straight at the point when the way is clear at knee height, else the nearest
## clear heading either side (the store's shelves, the truck's bed).
func _crew_steer(player: Node3D, point: Vector3) -> Vector3:
	return _annex_steer(player, point)

## Bedtime: once a teammate lies down on a cot in the evening, a crew bot walks
## to the nearest free one and lies down too (the day only ends with everyone in
## bed). True while it's handling that.
func _crew_bedtime(player: Node3D, delta: float) -> bool:
	var clock := get_tree().get_first_node_in_group("day_clock")
	if clock == null or not bool(clock.call("can_sleep_now")):
		return false
	var me := Net.local_peer_id()
	if bool(clock.call("is_sleeping", me)):
		_crew_walk(player, false, delta)
		return true
	var sleepers: Array = clock.get("sleepers")
	if sleepers.is_empty():
		return false
	var world := get_tree().get_first_node_in_group("world")
	var store := world.get_node_or_null("StoreZone") as Node3D if world != null else null
	if store == null:
		return false
	var taken: Array = (clock.get("cots") as Dictionary).values()
	var cot := -1
	var closest := INF
	for index: int in Constants.COT_SPOTS.size():
		var at := store.to_global(Constants.COT_SPOTS[index])
		var away := Vector2(at.x - player.global_position.x, at.z - player.global_position.z).length()
		if not taken.has(index) and away < closest:
			cot = index
			closest = away
	if cot < 0:
		return false
	var spot := store.to_global(Constants.COT_SPOTS[cot])
	if closest > 1.2:
		_face(player, _crew_steer(player, spot))
		_crew_walk(player, true, delta)
		return true
	_crew_walk(player, false, delta)
	if _elapsed >= _crew_next_idle:
		_crew_next_idle = _elapsed + 1.5
		clock.call("request_sleep", true, cot)
	return true