extends Node

## Authority: host for the chase; every peer for its cues. World/RunDirector/
## Pursuit (group "pursuit"), made by the run director on every peer next to the
## Encounter, so its RPC never rides on a spawned node (driving:F; docs/GAME.md
## "The pursuit", docs/DECISIONS.md "The NICE BOYS chase the crew's truck").
##
## Only in the connected town, only during a raid's CHASE. When Chefty, with
## someone aboard the crew could still catch, gets CREW_LEASH_METERS from the job
## site faster than PURSUIT_START_SPEED, the pursuit starts:
##   BOARDING   the crew drop what they're doing, jog back and climb in; the dome
##              starts pulsing hard (more than PURSUIT_BOARD_MAX and it's off)
##   CHASING    the doors slide shut and the Courtesy Shuttle gives chase: its
##              CHASE leg (net/run_events/shuttle.gd), driven here with VehicleSim
##              and a VehicleAutopilot along the town's roads, straight at Chefty
##              (led by PURSUIT_LEAD_SECONDS) once it's close with a clear line.
##              The kazoo siren wails, the head NICE BOY barks out of the window
##   PULLOVER   Chefty slower than PULLOVER_SPEED with the van within
##              PULLOVER_RADIUS for PULLOVER_SECONDS: the van pulls in behind it,
##              stops, and they climb out round the truck. A NICE BOY who gets
##              within SEAT_GRAB_RADIUS of someone's seat pulls them out (the
##              Encounter's catch, set down on the road beside the truck). Drive
##              off again and they pile back in (BOARDING); nobody left to catch
##              nearby for PULLOVER_IDLE_SECONDS and they wrap it up
##   GIVING_UP  they lost you: the siren cuts, the van brakes to a stop, then the
##              director's departure takes it away (riders and all)
## The getaway: Chefty more than PURSUIT_LOSE_DISTANCE from the van for
## PURSUIT_LOSE_SECONDS, PURSUIT_MAX_SECONDS of chasing, or Homie Depot's lot
## (STORE_AREA: no niceness on premises). It pays XP_ESCAPE once, sets the heat
## to HEAT_AFTER_ESCAPE, and whoever rode the truck in the chase gets "Lost 'em!"
## and the stinger (ui/run_cues.gd). Getting out of the truck is not a getaway:
## the van comes on, pulls in behind it and the crew climb out after whoever's on
## foot round it; with nobody left near it the chase just ends ("done", no XP,
## no heat change, no cue). Ramming the moving van faster than VAN_RAM_SPEED spins it out
## for VAN_STUN_SECONDS and adds HEAT_VAN_RAM (a ram of the parked one is the heat
## and Chefty's own crash).
##
## Nothing here is drawn: the van's pose rides the Shuttle's plan and track, the
## catches are the Encounter's, the barks the crew's, the cues run_cues'. The one
## RPC, _rpc_pursuit, says when a chase starts and how it ended.

signal changed(active: bool, reason: String)

enum State { NONE, BOARDING, CHASING, PULLOVER, GIVING_UP }
const STATE_NAMES: Array[String] = ["none", "boarding", "chasing", "pullover", "giving_up"]
## The run director's CHASE phase (director.gd Phase).
const PHASE_CHASE: int = 2

const _Crew = preload("res://npcs/crew_member.gd")
const _Vehicles = preload("res://props/vehicles.gd")

## For the probe and pursuit_test: what this peer saw (starts, pull-overs, rams,
## seat grabs, escapes and why), and the van's top speed in a chase on the host.
static var stats: Dictionary = {}

## Every peer (_rpc_pursuit): a chase on, when it started, and how the last ended
## ("lost", "done", "" for called off).
var _active: bool = false
var _started_at: float = 0.0
var _reason: String = ""
## Every peer: who this chase is about (the host's list, sent with _rpc_pursuit):
## whoever rode the crew's truck during it. Only they get the chase's mood, its
## pulse and "Lost 'em!"; a teammate shopping across town hears none of it.
var _involved := PackedInt32Array()

## Host.
var _state: int = State.NONE
var _state_at: float = 0.0
var _chase_time: float = 0.0
var _far_for: float = 0.0
var _slow_near_for: float = 0.0
var _idle_for: float = 0.0
var _auto: VehicleAutopilot
var _replan_left: float = 0.0
var _pull_point := Vector3.INF
## The pull-over's steps: "stopping" (braking), "parking" (its PARKED leg on the
## way), "out" (the crew climb out and go to the seats), and when "out" began.
var _pull_stage: String = ""
var _pull_at: float = 0.0
## The give-up: when the van stood still (its PARKED leg starts then), or -1.
var _parked_until: float = -1.0
## crew index -> the peer he's going to pull out of their seat.
var _grabs: Dictionary = {}
var _next_bark: float = 0.0
var _hooked: Node
## Rammed: the van sits spun out until then (server time).
var _stun_until: float = -1.0
## A U-turn under way: how long, and how long it has sat stuck in it (s).
var _uturn_for: float = 0.0
var _uturn_stuck: float = 0.0
## Host: riders on their way out of their seats, caught as they land:
## [{peer, crew (index), land, at (server time)}].
var _pullouts: Array[Dictionary] = []
## Host: how long each NICE BOY (index) has been within reach of his rider's seat (s).
var _near_for: Dictionary = {}
## Host: how long the crew has been getting back in with nobody being escorted (s).
var _board_wait: float = 0.0
## Host: how the chase ends once the van, giving up, has stopped ("lost", "done").
var _give_up_why: String = ""


func _ready() -> void:
	add_to_group("pursuit")
	reset_stats()


static func reset_stats() -> void:
	stats = {"starts": 0, "chases": 0, "pullovers": 0, "rams": 0, "spins": 0, "seat_grabs": 0, "escapes": 0, "ends": 0,
		"last_reason": "", "reasons": [], "van_top_speed": 0.0, "seen_active": 0, "seen_lost": 0, "states": []}


# ---------------------------------------------------------------- reading it (every peer)


## A chase is on (every peer).
func is_active() -> bool:
	return _active


func started_at() -> float:
	return _started_at


## How the last chase ended: "lost" (they got away), "done", "" (called off).
func last_reason() -> String:
	return _reason


## Every peer: this chase is this player's (they rode the truck in it, or ride it
## now). The last chase's riders still count after it ends, for its "Lost 'em!".
func involves(peer_id: int) -> bool:
	if _involved.has(peer_id):
		return true
	if not _active:
		return false
	var chefty := _chefty()
	return chefty != null and int(chefty.call("seat_of", peer_id)) >= 0


## Host: the pursuit is busy with the raid (the director leaves its own timing be).
func host_busy() -> bool:
	return _state != State.NONE


## Host: the van has pulled the truck over and the crew is out round it.
func pulling_over() -> bool:
	return _state == State.PULLOVER


## Host: where the van pulled the crew's truck over (the chase's middle then), or INF.
func pull_point() -> Vector3:
	return _pull_point if _state == State.PULLOVER else Vector3.INF


func state_name() -> String:
	return STATE_NAMES[_state]


## For the probe and the test.
func dev_report() -> Dictionary:
	var out := stats.duplicate(true)
	out["active"] = _active
	out["state"] = state_name()
	return out


## The chase for a late joiner (the director's state carries it).
func snapshot() -> Dictionary:
	return {"active": _active, "started_at": _started_at, "reason": _reason, "involved": _involved}


func apply_snapshot(data: Dictionary) -> void:
	if Net.is_host():
		return
	_active = bool(data.get("active", false))
	_started_at = float(data.get("started_at", 0.0))
	_reason = str(data.get("reason", ""))
	_involved = PackedInt32Array(data.get("involved", PackedInt32Array()))


## Dev (the director's reset): no chase.
func dev_reset() -> void:
	if not Net.is_host():
		return
	_grabs.clear()
	_pullouts.clear()
	_auto = null
	_pull_point = Vector3.INF
	_state = State.NONE
	if _active:
		_rpc_pursuit.rpc(false, Net.server_time(), "", PackedInt32Array())


# ---------------------------------------------------------------- the host


func _physics_process(delta: float) -> void:
	if not Net.is_host() or multiplayer.multiplayer_peer == null or Net.current_state() != Net.State.IN_SESSION:
		return
	var director := get_parent()
	if director == null or not director.has_method("phase"):
		return
	_hook_crashes()
	if _state == State.NONE:
		if _should_start(director):
			_begin(director)
		return
	if int(director.call("phase")) != PHASE_CHASE:
		# The raid moved on without us (a reset, a departure): over.
		_end("", false)
		return
	var shuttle := _shuttle()
	var chefty := _chefty()
	if shuttle == null or chefty == null:
		_end("", false)
		return
	for peer_id: int in _catchable_riders(director):
		if not _involved.has(peer_id):
			_involved.append(peer_id)
	match _state:
		State.BOARDING:
			_step_boarding(director, shuttle)
		State.CHASING:
			_step_chasing(director, shuttle, chefty, delta)
		State.PULLOVER:
			_step_pullover(director, shuttle, chefty, delta)
		State.GIVING_UP:
			_step_giving_up(director, shuttle, delta)
	_step_pullouts(director)
	if _state == State.BOARDING or _state == State.CHASING or _state == State.PULLOVER:
		_check_escape(director, shuttle, chefty, delta)


func _should_start(director: Node) -> bool:
	if not TownMap.enabled(get_tree()) or int(director.call("phase")) != PHASE_CHASE:
		return false
	var chefty := _chefty()
	var shuttle := _shuttle()
	if chefty == null or shuttle == null or not chefty.has_method("ground_speed") or not shuttle.has_method("host_chase_start"):
		return false
	if str(shuttle.call("raid_leg")) != "parked":
		return false
	if float(chefty.call("ground_speed")) < Constants.PURSUIT_START_SPEED:
		return false
	if _flat(chefty.call("body_position"), _site()) < Constants.CREW_LEASH_METERS:
		return false
	return not _catchable_riders(director).is_empty()


func _begin(director: Node) -> void:
	_set_state(State.BOARDING)
	_chase_time = 0.0
	_far_for = 0.0
	_slow_near_for = 0.0
	_idle_for = 0.0
	_pull_point = Vector3.INF
	_grabs.clear()
	_auto = null
	_involved = PackedInt32Array(_catchable_riders(director))
	stats["starts"] = int(stats["starts"]) + 1
	_log("pursuit_start", {"riders": _catchable_riders(director)})
	_rpc_pursuit.rpc(true, Net.server_time(), "", _involved)
	_shuttle().call("host_chase_cues", false, true)
	_recall_crew()


## Host: every NICE BOY not busy with a catch heads back to the van at a jog; the
## head NICE BOY yells for it.
func _recall_crew() -> void:
	var first := true
	for crew: Node in _crew_list():
		var mode := int(crew.get("mode"))
		if bool(crew.call("in_brain_mode")) or mode == _Crew.Mode.WHIFF or mode == _Crew.Mode.DOOR:
			crew.call("host_walk", Vector3.INF, 0.0)
			crew.call("host_set_mode", _Crew.Mode.RECALL)
			if first:
				crew.call("bark", "pursuit", true)
				first = false


## Host: they pile back in; once everyone's sat (and nobody's still being walked
## to the door) the van goes.
func _step_boarding(director: Node, shuttle: Node) -> void:
	var door: Vector3 = shuttle.call("door_step_point")
	var escorting := bool(director.call("_escorting")) or not _pullouts.is_empty()
	var aboard := not escorting
	# The clock on getting back in runs only while nobody's still being caught or
	# walked to the door.
	if not escorting:
		_board_wait += get_physics_process_delta_time()
	for crew: Node in _crew_list():
		var mode := int(crew.get("mode"))
		if mode == _Crew.Mode.SEATED or bool(shuttle.call("crew_aboard", int(crew.call("crew_index")))):
			continue
		aboard = false
		if bool(crew.call("in_brain_mode")) or mode == _Crew.Mode.DOOR:
			crew.call("host_set_mode", _Crew.Mode.RECALL)
			mode = _Crew.Mode.RECALL
		if mode != _Crew.Mode.RECALL:
			continue
		var at := (crew as Node3D).global_position
		if Vector2(at.x - door.x, at.z - door.z).length() <= Constants.CREW_BOARD_REACH:
			crew.call("host_walk", Vector3.INF, 0.0)
			shuttle.call("host_crew_board", crew)
		else:
			crew.call("host_walk", door_way(at, door), Constants.CREW_SPEED_RECALL)
	if aboard:
		var start := float(shuttle.call("host_chase_start"))
		if start < 0.0:
			_end("", false)
			return
		_set_state(State.CHASING)
		_pull_point = Vector3.INF
		_auto = VehicleAutopilot.new()
		_auto.cruise = Constants.NICE_VAN_TOP_SPEED
		_replan_left = 0.0
		_slow_near_for = 0.0
		_next_bark = start + Constants.PURSUIT_FIRST_BARK_DELAY
		stats["chases"] = int(stats["chases"]) + 1
		shuttle.call("host_chase_cues", true, true)
	elif _board_wait > Constants.PURSUIT_BOARD_MAX:
		# They couldn't get it together: the chase is off, back to the yard.
		for crew: Node in _crew_list():
			if int(crew.get("mode")) == _Crew.Mode.RECALL:
				crew.call("host_walk", Vector3.INF, 0.0)
				crew.call("host_set_mode", _Crew.Mode.PATROL)
		_end("", false)


## Host: after the truck, along the roads or straight at it.
func _step_chasing(_director: Node, shuttle: Node, chefty: Node, delta: float) -> void:
	var van: Dictionary = shuttle.call("host_chase_pose")
	if van.is_empty():
		_end("", false)
		return
	if not bool(van["driving"]):
		# The doors are still sliding shut.
		return
	_chase_time += delta
	stats["van_top_speed"] = maxf(float(stats["van_top_speed"]), float(van["speed"]))
	var now := Net.server_time()
	if now < _stun_until:
		# Spun out (the Shuttle spins it), then sat there a moment, dazed.
		shuttle.call("host_chase_step", {"brake": true}, delta)
		_replan_left = 0.0
		_slow_near_for = 0.0
		return
	var input := _chase_input(shuttle, chefty, van, delta)
	shuttle.call("host_chase_step", input, delta)
	var gap := _flat(van["pos"], chefty.call("body_position"))
	if float(chefty.call("ground_speed")) < Constants.PULLOVER_SPEED and gap <= Constants.PULLOVER_RADIUS:
		_slow_near_for += delta
	else:
		_slow_near_for = 0.0
	if _slow_near_for >= Constants.PULLOVER_SECONDS:
		_set_state(State.PULLOVER)
		_pull_stage = "stopping"
		_pull_point = chefty.call("body_position")
		_grabs.clear()
		return
	if now >= _next_bark:
		_next_bark = now + Constants.PURSUIT_BARK_SECONDS
		var head := _head_crew()
		if head != null:
			head.call("bark", "pursuit")


## Host: this tick's controls for the van. Its target: Chefty a moment ahead along
## its way, or (Chefty crawling or stopped) a spot PULLOVER_BEHIND behind it. The
## route: straight there inside PURSUIT_DIRECT_METERS with a clear line, else the
## town's roads, planned again every PURSUIT_REPLAN_SECONDS.
func _chase_input(shuttle: Node, chefty: Node, van: Dictionary, delta: float) -> Dictionary:
	var at: Vector3 = chefty.call("body_position")
	var vel: Vector3 = chefty.call("ground_velocity")
	var body: Transform3D = chefty.call("body_transform")
	var target := at + vel * Constants.PURSUIT_LEAD_SECONDS
	if float(chefty.call("ground_speed")) < Constants.PULLOVER_SPEED:
		var back := body.basis.z
		back.y = 0.0
		target = at + back.normalized() * Constants.PULLOVER_BEHIND
	var van_at: Vector3 = van["pos"]
	_replan_left -= delta
	if _auto == null:
		_auto = VehicleAutopilot.new()
		_auto.cruise = Constants.NICE_VAN_TOP_SPEED
	if _replan_left <= 0.0:
		_replan_left = Constants.PURSUIT_REPLAN_SECONDS
		var route: PackedVector3Array
		if _flat(van_at, target) <= Constants.PURSUIT_DIRECT_METERS and _clear_line(shuttle, chefty, van_at, target):
			route = PackedVector3Array([Vector3(van_at.x, 0.0, van_at.z), Vector3(target.x, 0.0, target.z)])
		else:
			route = VehicleAutopilot.plan(van_at, target)
		_auto.start(route, target)
	var state := {"yaw": float(van["yaw"]), "vel": van["vel"]}
	var input := _auto.next_input(state, van_at, delta)
	# Facing the wrong way at a crawl (it pulled up nose the other way): a tight
	# U-turn across the street on full lock, not the autopilot's polite three-point
	# turn. Stuck at it (a wall, a parked car), the autopilot's reverse takes over.
	var forward := VehicleSim.forward_of(float(van["yaw"]))
	var aim := Vector3(target.x - van_at.x, 0.0, target.z - van_at.z)
	var angle := atan2(forward.cross(aim.normalized()).y, forward.dot(aim.normalized())) if aim.length() > 0.5 else 0.0
	if absf(angle) > Constants.PURSUIT_UTURN_ANGLE and float(van["speed"]) < Constants.PURSUIT_UTURN_SPEED and _uturn_stuck < Constants.PURSUIT_UTURN_STUCK:
		_uturn_stuck = _uturn_stuck + delta if float(van["speed"]) < Constants.CHEFTY_PARK_SPEED and _uturn_for > Constants.PURSUIT_UTURN_SETTLE else 0.0
		_uturn_for += delta
		return {"throttle": Constants.PURSUIT_UTURN_THROTTLE, "steer": -signf(angle) if angle != 0.0 else 1.0}
	if absf(angle) < Constants.PURSUIT_UTURN_ANGLE * Constants.PURSUIT_UTURN_DONE_SHARE:
		_uturn_stuck = 0.0
		_uturn_for = 0.0
	return input


## Host: pulled over. It stops, stands, the crew climb out and go for the seats.
func _step_pullover(director: Node, shuttle: Node, chefty: Node, delta: float) -> void:
	var now := Net.server_time()
	var speed := float(chefty.call("ground_speed"))
	match _pull_stage:
		"stopping":
			shuttle.call("host_chase_step", {"brake": true}, delta)
			var van: Dictionary = shuttle.call("host_chase_pose")
			if speed > Constants.PURSUIT_START_SPEED:
				# Off again before it even stopped.
				_set_state(State.CHASING)
				_pull_point = Vector3.INF
				_slow_near_for = 0.0
				return
			if not van.is_empty() and float(van["speed"]) < Constants.CHEFTY_PARK_SPEED and bool(shuttle.call("host_chase_park")):
				_pull_stage = "parking"
				_pull_at = now + Constants.VAN_PLAN_LEAD
				shuttle.call("host_chase_cues", false, true)
		"parking":
			if now >= _pull_at:
				shuttle.call("host_unload_crew", now + 0.05)
				_pull_stage = "out"
				_pull_at = now
				_idle_for = 0.0
				stats["pullovers"] = int(stats["pullovers"]) + 1
				_log("pursuit_pullover", {"at": _pull_point})
		"out":
			_step_grabs(director, chefty)
			var gap := _flat(shuttle.call("raid_pose").origin, chefty.call("body_position"))
			var riders := _catchable_riders(director)
			if speed > Constants.PURSUIT_START_SPEED and gap > Constants.PULLOVER_DRIVE_OFF_METERS and not riders.is_empty():
				# Off they go: back in, and after them.
				_release_grabs()
				_set_state(State.BOARDING)
				_recall_crew()
				return
			var busy := bool(director.call("_escorting")) or not _pullouts.is_empty()
			if riders.is_empty() and not busy and not _anyone_catchable_near(director):
				_idle_for += delta
			else:
				_idle_for = 0.0
			if _idle_for >= Constants.PULLOVER_IDLE_SECONDS or (now - _pull_at >= Constants.RUN_CHASE_SECONDS and not busy):
				_release_grabs()
				_end("done", true)


## Host, pulled over: each NICE BOY on his feet takes a rider still sat in the
## truck, walks to their side of it, and pulls them out from within SEAT_GRAB_RADIUS.
func _step_grabs(director: Node, chefty: Node) -> void:
	var riders := _catchable_riders(director)
	for index: Variant in _grabs.keys():
		var crew := _crew_by_index(int(index))
		if not riders.has(int(_grabs[index])) or crew == null or not bool(crew.call("in_brain_mode")):
			if crew != null and bool(crew.call("in_brain_mode")):
				crew.call("host_walk", Vector3.INF, 0.0)
			_grabs.erase(index)
	if riders.is_empty():
		return
	var body: Transform3D = chefty.call("body_transform")
	# Chefty's own frame, upright (its nose along -Z), whatever its lean.
	var nose := Vector3(-body.basis.z.x, 0.0, -body.basis.z.z)
	var flat := Transform3D(Basis.looking_at(nose.normalized() if nose.length() > 0.01 else Vector3.FORWARD, Vector3.UP), body.origin)
	var inverse := flat.affine_inverse()
	for crew: Node in _crew_list():
		if not bool(crew.call("in_brain_mode")) or bool(crew.call("is_stunned")):
			continue
		var index := int(crew.call("crew_index"))
		if _pulling_out(index):
			continue
		var peer := int(_grabs.get(index, 0))
		var crew_at := (crew as Node3D).global_position
		if peer == 0:
			var best := INF
			for rider: int in riders:
				if _grabs.values().has(rider):
					continue
				var seat: Transform3D = chefty.call("seat_transform", int(chefty.call("seat_of", rider)))
				var distance := _flat(crew_at, seat.origin)
				if distance < best:
					best = distance
					peer = rider
			if peer == 0:
				continue
			_grabs[index] = peer
		var seat := int(chefty.call("seat_of", peer))
		var seat_at: Vector3 = (chefty.call("seat_transform", seat) as Transform3D).origin
		var local_seat := inverse * seat_at
		# On the side they'll get out on (the cab's door, the bed row's rail), a step
		# back from where they'll land, so they hop down in front of him.
		var side := float(chefty.call("_exit_side", seat)) if chefty.has_method("_exit_side") else 1.0
		var stand := flat * Vector3(side * Constants.PULLOVER_STAND_SIDE, 0.0, local_seat.z + Constants.PULLOVER_STAND_BACK)
		stand.y = crew_at.y
		crew.call("host_walk", stand, Constants.CREW_SPEED_CHASE)
		# Within reach of the seat: at his spot, or as close as he's getting to it (it's
		# blocked: the van, a post) after PULLOVER_REACH_WAIT.
		# Nobody's pulled out of a truck that's rolling faster than anyone could step
		# down from it: he keeps pace beside it until it stops (or it gets away).
		var close := _flat(crew_at, seat_at) <= Constants.SEAT_GRAB_RADIUS and float(chefty.call("ground_speed")) <= Constants.CHEFTY_EXIT_MAX_SPEED
		_near_for[index] = float(_near_for.get(index, 0.0)) + get_physics_process_delta_time() if close else 0.0
		if close and (_flat(crew_at, stand) <= Constants.PULLOVER_STAND_REACH or float(_near_for[index]) >= Constants.PULLOVER_REACH_WAIT):
			_near_for.erase(index)
			_grab(director, crew, peer, chefty)


## Host: "Out of the vehicle, please." He has them hop down out of their seat the
## way anyone gets out (Chefty's own step down: out of the cab door, or over the
## bed's rail, no pop on any screen), and the catch lands as they touch the road
## (_step_pullouts).
func _grab(_director: Node, crew: Node, peer: int, chefty: Node) -> void:
	crew.call("host_walk", (crew as Node3D).global_position, 0.0)
	var index := int(crew.call("crew_index"))
	_grabs.erase(index)
	if not chefty.has_method("_handle_exit"):
		return
	chefty.call("_handle_exit", peer)
	var exit: Dictionary = chefty.call("dev_last_exit", peer)
	# A bail (it was rolling after all) flings them off the seat: the catch takes
	# them wherever they come down, never back up at the seat.
	var land: Vector3 = Vector3.INF if bool(exit.get("bail", false)) else exit.get("at", (crew as Node3D).global_position)
	_pullouts.append({"peer": peer, "crew": index, "land": land, "at": Net.server_time() + Constants.STEP_DOWN_SECONDS + Constants.PULLOUT_CATCH_SLACK})
	stats["seat_grabs"] = int(stats["seat_grabs"]) + 1
	_log("pursuit_seat_grab", {"peer_id": peer})


## Host: each one pulled out is caught as they land (the gotcha, there on the road).
func _step_pullouts(director: Node) -> void:
	if _pullouts.is_empty():
		return
	var now := Net.server_time()
	var encounter: Node = director.call("encounter")
	for entry: Dictionary in _pullouts.duplicate():
		var crew := _crew_by_index(int(entry["crew"]))
		if crew != null and bool(crew.call("in_brain_mode")):
			# He stands and waits for them to land (his own eyes switched off: he'd
			# spot them mid-hop and lunge).
			crew.call("host_walk", (crew as Node3D).global_position, 0.0)
		if now < float(entry["at"]):
			continue
		_pullouts.erase(entry)
		var peer := int(entry["peer"])
		if encounter == null or not bool(director.call("pursuable", peer)):
			continue
		if crew != null:
			crew.call("host_walk", Vector3.INF, 0.0)
		encounter.call("host_begin_catch", peer, crew if crew != null and bool(crew.call("in_brain_mode")) else null, 0, entry["land"])


## Host: where a NICE BOY heading back to the van's door walks next (in the
## connected town; the yard's navmesh finds its own way): out in the
## open beside the door first (off the van's flank, where he'd scrape along its
## side and stick on a mirror), then in to the step.
func door_way(at: Vector3, door: Vector3) -> Vector3:
	var shuttle := _shuttle()
	if shuttle == null or not TownMap.enabled(get_tree()):
		return door
	var van: Transform3D = shuttle.call("raid_pose")
	var out := van.basis.x
	out.y = 0.0
	out = out.normalized()
	var offset := at - door
	offset.y = 0.0
	if offset.dot(out) >= Constants.CREW_DOOR_APPROACH_OUT * Constants.CREW_DOOR_APPROACH_SHARE or offset.length() <= Constants.CREW_DOOR_APPROACH_OUT:
		return door
	return door + out * Constants.CREW_DOOR_APPROACH_OUT


func _pulling_out(crew_index: int) -> bool:
	for entry: Dictionary in _pullouts:
		if int(entry["crew"]) == crew_index:
			return true
	return false


func _release_grabs() -> void:
	for index: Variant in _grabs.keys():
		var crew := _crew_by_index(int(index))
		if crew != null and bool(crew.call("in_brain_mode")):
			crew.call("host_walk", Vector3.INF, 0.0)
	_grabs.clear()


## Host: the getaways.
func _check_escape(director: Node, shuttle: Node, chefty: Node, delta: float) -> void:
	var at: Vector3 = chefty.call("body_position")
	if Constants.STORE_AREA.has_point(Vector2(at.x, at.z)):
		_escape(director, shuttle, "store")
		return
	var riders := _catchable_riders(director)
	if _state == State.CHASING and riders.is_empty() and not _anyone_catchable_near(director):
		# Nobody left in the truck. Getting out isn't getting away: with anyone they
		# could catch still on foot round it, the van keeps coming, pulls in behind
		# the truck (_chase_input aims there once it's stopped) and the crew climb out
		# after them (the pull-over's leash is round the truck). Nobody near it (they
		# ran off, or were caught): no getaway, no XP, the van just wraps it up.
		_far_for = 0.0
		if not _anyone_near_truck(director, chefty) or _chase_time >= Constants.PURSUIT_MAX_SECONDS:
			_give_up("done")
		return
	var van: Transform3D = shuttle.call("raid_pose")
	if _flat(van.origin, at) > Constants.PURSUIT_LOSE_DISTANCE:
		_far_for += delta
	else:
		_far_for = 0.0
	if _far_for >= Constants.PURSUIT_LOSE_SECONDS:
		_escape(director, shuttle, "far")
		return
	if _chase_time >= Constants.PURSUIT_MAX_SECONDS:
		_escape(director, shuttle, "time")


## Host: lost them. XP once, the heat, the cue on every peer; the van stops and goes.
func _escape(director: Node, shuttle: Node, why: String) -> void:
	stats["escapes"] = int(stats["escapes"]) + 1
	(stats["reasons"] as Array).append(why)
	_log("pursuit_escape", {"why": why})
	_release_grabs()
	var someone_free := false
	for peer_id: int in Net.peer_ids():
		if bool(director.call("pursuable", peer_id)):
			someone_free = true
	if someone_free:
		Campaign.award_escape(0)
	var heat := get_tree().get_first_node_in_group("heat")
	if heat != null:
		heat.call("add", Constants.HEAT_AFTER_ESCAPE - float(heat.get("heat")), "pursuit_escape")
	director.call("note_pursuit_escape")
	_rpc_pursuit.rpc(false, Net.server_time(), "lost", _involved)
	_give_up("lost")


## Host: the siren cuts and the van brakes to a stop (_step_giving_up), then the
## chase ends with why ("lost": the getaway already paid; "done": nothing to pay).
func _give_up(why: String) -> void:
	_release_grabs()
	var shuttle := _shuttle()
	if shuttle != null:
		shuttle.call("host_chase_cues", false, false)
	_give_up_why = why
	if _active and why != "lost":
		_rpc_pursuit.rpc(false, Net.server_time(), why, _involved)
	_set_state(State.GIVING_UP)
	_pull_point = Vector3.INF
	_parked_until = -1.0


## Host: they brake to a stop wherever they are, then the director sends the van off.
func _step_giving_up(_director: Node, shuttle: Node, delta: float) -> void:
	var now := Net.server_time()
	if _parked_until < 0.0:
		var van: Dictionary = shuttle.call("host_chase_pose")
		if van.is_empty() or not bool(van["driving"]):
			# Standing already (pulled over, or still at the curb).
			_parked_until = now
		else:
			shuttle.call("host_chase_step", {"brake": true}, delta)
			if float(van["speed"]) < Constants.CHEFTY_PARK_SPEED and bool(shuttle.call("host_chase_park")):
				_parked_until = now + Constants.VAN_PLAN_LEAD
		return
	if now >= _parked_until:
		_end(_give_up_why, true)


## Host: the chase is over. depart: the director wraps up the raid now (the van
## leaves with whoever it has).
func _end(why: String, depart: bool) -> void:
	var was := _state
	_set_state(State.NONE)
	_auto = null
	_pull_point = Vector3.INF
	_grabs.clear()
	_pullouts.clear()
	stats["ends"] = int(stats["ends"]) + 1
	stats["last_reason"] = why
	var shuttle := _shuttle()
	if shuttle != null:
		shuttle.call("host_chase_cues", false, false)
	if _active:
		_rpc_pursuit.rpc(false, Net.server_time(), why, _involved)
	if was != State.NONE:
		_log("pursuit_end", {"why": why})
	if depart:
		var director := get_parent()
		if director != null and director.has_method("host_begin_departure"):
			director.call("host_begin_departure")


func _set_state(state: int) -> void:
	_state = state
	_board_wait = 0.0
	_state_at = Net.server_time()
	var seen: Array = stats["states"]
	seen.append(STATE_NAMES[state])
	if seen.size() > 32:
		seen.pop_front()


## Host: a crash of the crew's truck right into the van is a ram.
func _hook_crashes() -> void:
	var chefty := _chefty()
	if chefty == null or chefty == _hooked or not chefty.has_signal("crashed"):
		return
	_hooked = chefty
	chefty.connect("crashed", _on_crashed)


func _on_crashed(strength: float, at: Vector3) -> void:
	if not Net.is_host() or _state == State.NONE or _state == State.GIVING_UP:
		return
	var shuttle := _shuttle()
	var chefty := _chefty()
	if shuttle == null or chefty == null or strength < Constants.VAN_RAM_SPEED:
		return
	var van: Transform3D = shuttle.call("raid_pose")
	var local := van.affine_inverse() * at
	var half := Constants.NICE_VAN_CHASSIS_SIZE * 0.5
	if absf(local.x) > half.x + Constants.VAN_RAM_SLACK or absf(local.z) > half.z + Constants.VAN_RAM_SLACK:
		return
	stats["rams"] = int(stats["rams"]) + 1
	_log("pursuit_ram", {"strength": strength})
	var heat := get_tree().get_first_node_in_group("heat")
	if heat != null:
		heat.call("add", Constants.HEAT_VAN_RAM, "van_ram")
	var pose: Dictionary = shuttle.call("host_chase_pose")
	if _state != State.CHASING or pose.is_empty() or not bool(pose["driving"]):
		# Parked: it rocks, Chefty crumples, the heat goes up; it doesn't go anywhere.
		return
	var push: Vector3 = chefty.call("ground_velocity")
	if push.length() < 0.5:
		push = (van.origin - (chefty.call("body_position") as Vector3))
	push.y = 0.0
	var shove := push.normalized() * strength * Constants.VAN_RAM_PUSH_SHARE
	var dir := signf(van.basis.z.cross(push).y)
	shuttle.call("host_chase_spin", shove, dir if dir != 0.0 else 1.0)
	stats["spins"] = int(stats["spins"]) + 1
	# Spun out: back on it after VAN_STUN_SECONDS (_step_chasing).
	_stun_until = Net.server_time() + Constants.VAN_STUN_SECONDS


# ---------------------------------------------------------------- helpers (host)


func _catchable_riders(director: Node) -> Array[int]:
	var out: Array[int] = []
	var chefty := _chefty()
	if chefty == null or not chefty.has_method("riders"):
		return out
	for peer_id: int in chefty.call("riders"):
		if peer_id != 0 and bool(director.call("pursuable", peer_id)):
			out.append(peer_id)
	return out


## Anyone the crew could still catch near the chase on foot.
func _anyone_catchable_near(director: Node) -> bool:
	for peer_id: int in Net.peer_ids():
		if bool(director.call("can_capture", peer_id)):
			return true
	return false


## Anyone the crew could still be after on foot within CREW_LEASH_METERS of the
## crew's truck (they just got out of it).
func _anyone_near_truck(director: Node, chefty: Node) -> bool:
	var at: Vector3 = chefty.call("body_position")
	for peer_id: int in Net.peer_ids():
		if not bool(director.call("pursuable", peer_id)) or int(chefty.call("seat_of", peer_id)) >= 0:
			continue
		if Net.player_zone(peer_id) != Net.Zone.TOWN:
			continue
		var player: Node3D = director.call("_player", peer_id)
		if player != null and _flat(player.global_position, at) <= Constants.CREW_LEASH_METERS:
			return true
	return false


## The job site: the yard's middle.
func _site() -> Vector3:
	var world := get_tree().get_first_node_in_group("world")
	var lot := world.get_node_or_null("LotZone") as Node3D if world != null else null
	return lot.global_position if lot != null else Vector3.ZERO


## A clear line between two points at the height of a windshield (the town's
## solids; the two trucks themselves don't block it).
func _clear_line(shuttle: Node, chefty: Node, from: Vector3, to: Vector3) -> bool:
	var world := get_viewport().world_3d if get_viewport() != null else null
	if world == null:
		return true
	var exclude: Array[RID] = []
	var solid: Variant = chefty.call("solid_body") if chefty.has_method("solid_body") else null
	if solid is CollisionObject3D:
		exclude.append((solid as CollisionObject3D).get_rid())
	var look: Variant = shuttle.call("van_look")
	if look is Node3D:
		var van_solid := (look as Node3D).get_node_or_null("Solid") as CollisionObject3D
		if van_solid != null:
			exclude.append(van_solid.get_rid())
	var query := PhysicsRayQueryParameters3D.create(from + Vector3.UP * Constants.PURSUIT_SIGHT_HEIGHT, to + Vector3.UP * Constants.PURSUIT_SIGHT_HEIGHT, 1)
	query.exclude = exclude
	return world.direct_space_state.intersect_ray(query).is_empty()


func _crew_list() -> Array[Node]:
	var out: Array[Node] = []
	for crew: Node in get_tree().get_nodes_in_group("nice_crew"):
		if not crew.is_queued_for_deletion():
			out.append(crew)
	return out


func _crew_by_index(index: int) -> Node:
	for crew: Node in _crew_list():
		if int(crew.call("crew_index")) == index:
			return crew
	return null


## The head NICE BOY, or whoever is first.
func _head_crew() -> Node:
	var list := _crew_list()
	for crew: Node in list:
		if int(crew.call("crew_index")) == 1:
			return crew
	return list[0] if not list.is_empty() else null


func _chefty() -> Node:
	var chefty := get_tree().get_first_node_in_group("chefty")
	return chefty if chefty != null and chefty.has_method("ground_speed") else null


func _shuttle() -> Node:
	var shuttle := get_tree().get_first_node_in_group("nice_shuttle")
	return shuttle if shuttle != null and shuttle.has_method("host_chase_start") else null


static func _flat(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()


func _log(event_name: String, data: Dictionary) -> void:
	var telemetry := get_tree().get_first_node_in_group("telemetry")
	if telemetry != null:
		telemetry.call("event", event_name, data)


# ---------------------------------------------------------------- every peer


## A chase on (active, from server time at) or over (reason: "lost" when they got
## away, "done" when the crew wrapped it up, "" called off).
@rpc("authority", "call_local", "reliable")
func _rpc_pursuit(active: bool, at: float, reason: String, involved: PackedInt32Array) -> void:
	_active = active
	_involved = involved
	if active:
		_started_at = at
		stats["seen_active"] = int(stats["seen_active"]) + 1
	else:
		_reason = reason
		if reason == "lost":
			stats["seen_lost"] = int(stats["seen_lost"]) + 1
	changed.emit(active, reason)
