extends Node

## Authority: host, dev builds only. Scenario jumps (docs/PLAYTEST.md): put the
## host's player at a moment worth judging in a second or two, through the same
## code the game runs (the run director's phases and captures, the van, Border
## Return, hiding spots, the leaf field's rake strokes, Chefty's seats), so what
## gets recorded is what players get. Only the starting position is arranged.
## remote_play.gd's ["scenario", name] step and the --scenario=<name> flag call
## run(); the playtest tools test (net/dev/playtest_tools_test.gd) checks each
## one reaches its state.
##
## Names: rake_fresh, rake_pile, raid_warn, raid_arrive, caught, hide,
## border_return, van_ride, store, drive (that one needs --town-map), toss,
## toss_full.

const _Strings = preload("res://ui/strings.gd")
const _Vehicles = preload("res://props/vehicles.gd")
const NAMES: Array[String] = ["rake_fresh", "rake_pile", "raid_warn", "raid_arrive", "caught", "hide", "border_return", "van_ride", "store", "drive", "toss", "toss_full"]
## raid_arrive: how long before the NICE BOYS show up.
const ARRIVE_LEAD_SECONDS: float = 2.0
## hide: how long the warning still has to run, time enough to get in.
const HIDE_LEAD_SECONDS: float = 3.5
## caught: how far in front of the head NICE BOY you stand.
const CAUGHT_GAP_METERS: float = 5.0
## raid_arrive: where you watch the arrival from, meters from the arrival point.
const WATCH_ARRIVAL_METERS: float = 11.0
## rake_fresh, rake_pile: an untouched strip of leaves this long, and the rake
## strokes that push it into a pile.
const STRIP_STEPS: int = 14
const STRIP_STEP_METERS: float = 0.5
const STRIP_MIN_DENSITY: int = 36
## rake_pile: stand this far short of the pile's middle, so the next stroke hits it.
const PILE_STAND_METERS: float = 2.4
## Looking a little down at the ground, in radians.
const RAKE_PITCH: float = -0.42
## toss: how far from the middle of Chefty's bed you stand, looking a touch up,
## and what the bag in your hands is worth.
const TOSS_STAND_METERS: float = 4.0
const TOSS_PITCH: float = 0.12
const TOSS_BAG_VALUE: int = 14
## Waits for a state, in seconds, before a scenario gives up.
const SETTLE_SECONDS: float = 15.0

## The --scenario=<name> one at launch has run (or there was none).
var start_done: bool = false
## Its result, for remote play's first report.
var start_result: Dictionary = {}


func _ready() -> void:
	var wanted := str(Net.dev_options().get("scenario"))
	if wanted == "":
		start_done = true
		return
	_run_at_start(wanted)


func _run_at_start(wanted: String) -> void:
	var waited := 0.0
	while (Net.current_state() != Net.State.IN_SESSION or _me() == null or _world() == null) and waited < 40.0:
		await get_tree().create_timer(0.25).timeout
		waited += 0.25
	# Let the yard, its props and the first replication settle.
	await get_tree().create_timer(1.0).timeout
	start_result = await run(wanted)
	print("[Scenario] %s at start: %s" % [wanted, start_result])
	start_done = true


## Jump to a moment. Returns {ok, scenario, note, ...} or {ok: false, error}.
func run(scenario: String) -> Dictionary:
	if scenario == "list":
		return {"ok": true, "scenarios": NAMES}
	if not OS.is_debug_build():
		return {"ok": false, "error": "scenarios are for dev builds only"}
	if not Net.is_host():
		return {"ok": false, "error": "scenarios run on the host (this is a client)"}
	if _me() == null or _world() == null:
		return {"ok": false, "error": "no world or player yet"}
	if not NAMES.has(scenario):
		return {"ok": false, "error": "unknown scenario %s (try %s)" % [scenario, ", ".join(NAMES)]}
	await reset()
	var out: Dictionary = {}
	match scenario:
		"rake_fresh":
			out = await _rake_fresh()
		"rake_pile":
			out = await _rake_pile()
		"raid_warn":
			out = await _raid_warn()
		"raid_arrive":
			out = await _raid_arrive()
		"caught":
			out = await _caught()
		"hide":
			out = await _hide()
		"border_return":
			out = await _border_return()
		"van_ride":
			out = await _van_ride()
		"store":
			out = await _store()
		"drive":
			out = await _drive()
		"toss":
			out = await _toss()
		"toss_full":
			out = await _toss(true)
	out["scenario"] = scenario
	if not out.has("ok"):
		out["ok"] = not out.has("error")
	print("[Scenario] %s: %s" % [scenario, out])
	return out


# ---------------------------------------------------------------- the moments


## A job yard, untouched leaves in front of you, the rake in your hands.
func _rake_fresh() -> Dictionary:
	var problem: String = await _to_lot()
	if problem != "":
		return {"error": problem}
	var strip := _fresh_strip()
	if strip == Vector3.INF:
		return {"error": "no untouched strip of leaves on this yard"}
	_place(strip - Vector3(1.5, 0.0, 0.0), -PI * 0.5, RAKE_PITCH)
	await _ticks(3)
	var held: String = await _hold("rake")
	_place(strip - Vector3(1.5, 0.0, 0.0), -PI * 0.5, RAKE_PITCH)
	if held != "rake":
		return {"error": "couldn't get the rake (holding '%s')" % held}
	return {"note": "facing +x along a strip of untouched leaves; hold primary to rake", "facing": "+x", "strip": _v(strip)}


## A yard half done: a pile raked up just in front of you, the rake in hand.
func _rake_pile() -> Dictionary:
	var fresh: Dictionary = await _rake_fresh()
	if fresh.has("error"):
		return fresh
	var field := _field()
	var strip := Vector3(fresh["strip"][0], 0.1, fresh["strip"][2])
	# The strokes a person would make walking down the strip (gag_test's pile, real strokes).
	for index: int in STRIP_STEPS:
		var at := strip + Vector3(float(index) * STRIP_STEP_METERS, 0.0, 0.0)
		_place(at - Vector3(1.5, 0.0, 0.0), -PI * 0.5, RAKE_PITCH)
		field.call("request_rake", at, Vector3(1.0, 0.0, 0.0), Constants.RAKE_WIDTH, Constants.RAKE_STRENGTH)
		await _ticks(1)
	await _ticks(3)
	var pile := Vector3.INF
	var most := 0
	for ahead: float in [5.5, 6.0, 6.5, 7.0, 7.5, 8.0, 8.5, 9.0, 9.5]:
		var at := strip + Vector3(ahead, 0.0, 0.0)
		var units := int(field.call("units_within_world", at, Constants.PILE_HIDE_RADIUS))
		if units > most:
			most = units
			pile = at
	if pile == Vector3.INF:
		return {"error": "the strokes made no pile"}
	_place(pile - Vector3(PILE_STAND_METERS, 0.0, 0.0), -PI * 0.5, RAKE_PITCH)
	await _ticks(3)
	return {"note": "a raked pile %.1f m ahead; hold primary to rake into it, secondary to bag it" % PILE_STAND_METERS, "pile": _v(pile), "pile_units": most, "is_pile": bool(field.call("is_pile_at", pile))}


## A full leaf bag in your hands, TOSS_STAND_METERS from the middle of Chefty's
## bed on the yard's side, facing it (bags:throw; hold drop to wind up a toss).
## toss_full: Chefty's bed is already full, so the toss bounces off the pile.
func _toss(full: bool = false) -> Dictionary:
	var problem: String = await _to_lot()
	if problem != "":
		return {"error": problem}
	var truck := get_tree().get_first_node_in_group("chefty") as Node3D
	if truck == null or not truck.has_method("bed_transform"):
		return {"error": "no Chefty here"}
	if full:
		truck.call("accept_bags", Constants.TRUCK_BAG_CAPACITY - int(truck.call("bag_count")), 0)
	var bed: Transform3D = truck.call("bed_transform")
	var middle := bed * Vector3(0.0, 0.0, 0.72)
	var lot := get_tree().get_first_node_in_group("job_lot") as Node3D
	var side := Vector3(bed.basis.x.x, 0.0, bed.basis.x.z).normalized()
	if (middle + side).distance_to(lot.global_position) > (middle - side).distance_to(lot.global_position):
		side = -side
	var at := middle + side * TOSS_STAND_METERS
	at.y = bed.origin.y + 0.1
	var yaw := _yaw_toward(at, middle)
	_place(at, yaw, TOSS_PITCH)
	await _ticks(3)
	_world().call("_spawn_bag", _me().global_position + Vector3(-sin(yaw), 0.0, -cos(yaw)) * 0.8, 0)
	await _ticks(3)
	var bag: Node3D = null
	for node: Node in get_tree().get_nodes_in_group("props"):
		if str(node.get("kind")) == "leaf_bag" and bool(node.call("is_loose")) and not node.is_queued_for_deletion() and (node as Node3D).global_position.distance_to(_me().global_position) < 2.0:
			bag = node as Node3D
	if bag == null:
		return {"error": "no bag to hand you"}
	bag.set("value", TOSS_BAG_VALUE)
	var held: String = await _hold("leaf_bag")
	_place(at, yaw, TOSS_PITCH)
	if held != "leaf_bag":
		return {"error": "couldn't get the bag (holding '%s')" % held}
	return {"note": "a bag in hand %.0f m from Chefty's bed, facing it; hold drop to wind up, let go to toss" % TOSS_STAND_METERS, "bed": _v(middle)}


## The NICE BOYS have been called: the warning starts now.
func _raid_warn() -> Dictionary:
	var problem: String = await _to_lot()
	if problem != "":
		return {"error": problem}
	var director := _director()
	director.call("force_event")
	await _ticks(2)
	return {"note": "warning now; they arrive in %.0f s" % Constants.RUN_WARNING_SECONDS, "phase": _phase(), "arrives_in": snappedf(float(director.call("arrival_time")) - Net.server_time(), 0.01)}


## The warning is nearly over: they arrive in ARRIVE_LEAD_SECONDS, and you're
## standing where you can watch the arrival point.
func _raid_arrive() -> Dictionary:
	var problem: String = await _to_lot()
	if problem != "":
		return {"error": problem}
	var director := _director()
	var arrival: Vector3 = director.call("crew_arrival_point")
	var lot := _lot_zone()
	var toward := Vector3(arrival.x - lot.global_position.x, 0.0, arrival.z - lot.global_position.z).normalized()
	var stand := arrival - toward * WATCH_ARRIVAL_METERS
	_place(Vector3(stand.x, lot.global_position.y + 0.1, stand.z), _yaw_toward(stand, arrival), -0.05)
	_warn_with(director, ARRIVE_LEAD_SECONDS)
	await _ticks(2)
	return {"note": "they arrive in %.1f s at the point you're facing (the game has no van pulling up: they appear there)" % ARRIVE_LEAD_SECONDS, "phase": _phase(), "arrives_in": snappedf(float(director.call("arrival_time")) - Net.server_time(), 0.01), "arrival": _v(arrival)}


## The chase is on and the head NICE BOY is a few steps away, coming for you.
func _caught() -> Dictionary:
	var problem: String = await _to_lot()
	if problem != "":
		return {"error": problem}
	var director := _director()
	director.call("_begin_chase")
	await _ticks(3)
	var crew := _crew()
	if crew == null:
		return {"error": "no NICE BOY spawned"}
	var lot := _lot_zone()
	var toward_lot := Vector3(lot.global_position.x - crew.global_position.x, 0.0, lot.global_position.z - crew.global_position.z).normalized()
	var stand := crew.global_position + toward_lot * CAUGHT_GAP_METERS
	_place(Vector3(stand.x, crew.global_position.y + 0.1, stand.z), _yaw_toward(stand, crew.global_position), -0.05)
	await _ticks(2)
	return {"note": "%s is %.0f m away and coming; stand still to be caught, sprint to get away" % [crew.name, CAUGHT_GAP_METERS], "phase": _phase(), "crew": str(crew.name)}


## A hiding spot right in front of you, the warning counting down.
func _hide() -> Dictionary:
	var problem: String = await _to_lot()
	if problem != "":
		return {"error": problem}
	var director := _director()
	var arrival: Vector3 = director.call("crew_arrival_point")
	var spot: Node3D = null
	for node: Node in get_tree().get_nodes_in_group("hide_spots"):
		var candidate := node as Node3D
		if int(candidate.get("occupant")) != 0:
			continue
		if spot == null or candidate.global_position.distance_to(arrival) > spot.global_position.distance_to(arrival):
			spot = candidate
	if spot == null:
		return {"error": "this yard has no free hiding spot"}
	var stand: Vector3 = spot.call("exit_position")
	_place(stand, _yaw_toward(stand, spot.global_position), -0.2)
	_warn_with(director, HIDE_LEAD_SECONDS)
	await _ticks(2)
	return {"note": "facing %s; tap interact to get in, they arrive in %.1f s" % [str(spot.get("label")), HIDE_LEAD_SECONDS], "phase": _phase(), "spot": _v(spot.global_position)}


## Caught: the cohort closes, the van takes you (you're in it now).
func _van_ride() -> Dictionary:
	var problem: String = await _to_lot()
	if problem != "":
		return {"error": problem}
	var director := _director()
	director.call("force_capture", Net.local_peer_id())
	var van: Node = await _wait_for(func() -> Variant:
		var ride := _van()
		return ride if ride != null and bool(ride.call("is_riding")) and int(ride.call("seat_of", Net.local_peer_id())) >= 0 else null)
	if van == null:
		return {"error": "the van didn't leave with you in it"}
	return {"note": "in the van, %.0f s from the border" % float(van.get("_duration")), "zone": _zone()}


## Border Return starts now: caught, and the van ride skipped to its end.
func _border_return() -> Dictionary:
	var ride: Dictionary = await _van_ride()
	if ride.has("error"):
		return ride
	var van := _van()
	# The ride's place on its path is a function of the shared clock: move its
	# start back so it arrives on the next tick, through its own arrival code.
	# Only the host's start moves: other peers (an observer) see the van drive on
	# normally until the arrival message parks it at the route's end, a cut, so
	# a 3P recording of this moment is the real thing only from the border on.
	van.set("_start_time", Net.server_time() - float(van.get("_duration")))
	var there: Variant = await _wait_for(func() -> Variant:
		return true if Net.player_zone(Net.local_peer_id()) == Net.Zone.BORDER else null)
	if there == null:
		return {"error": "never got to the border"}
	await _ticks(3)
	var crossing := get_tree().get_first_node_in_group("border_return")
	return {"note": "Border Return staging; the lanes start in %.0f s" % Constants.BORDER_STAGING_SECONDS, "zone": _zone(), "status": str(crossing.call("status_line")) if crossing != null else ""}


## Back at the store (Homie Depot), the way the debug zone gates send you.
func _store() -> Dictionary:
	Net.move_player_to_zone(Net.local_peer_id(), Net.Zone.STORE)
	var there: Variant = await _wait_for(func() -> Variant:
		return true if Net.player_zone(Net.local_peer_id()) == Net.Zone.STORE else null)
	await _ticks(3)
	return {"zone": _zone()} if there != null else {"error": "never got to the store"}


## In Chefty's driver's seat, parked at Homie Depot (the connected town only).
func _drive() -> Dictionary:
	var world := _world()
	if not bool(world.call("is_town_map")):
		return {"error": "drive needs the connected town: start with --town-map (tools\\play.ps1 -Start -Scenario drive adds it)"}
	var chefty := get_tree().get_first_node_in_group("chefty")
	if chefty == null or not chefty.has_method("request_enter"):
		return {"error": "no drivable Chefty"}
	chefty.call("dev_place", Constants.CHEFTY_PARK_SPOT, Constants.CHEFTY_PARK_YAW)
	await get_tree().create_timer(0.3).timeout
	var me := _me()
	for attempt: int in 4:
		if int(chefty.call("driver")) == Net.local_peer_id():
			break
		var at: Transform3D = chefty.call("body_transform")
		var door: Vector3 = at * _Vehicles.CHEFTY_DRIVER_DOOR
		me.call("apply_network_teleport", Transform3D(Basis.IDENTITY, door + Vector3(0.0, 0.1, 0.0)))
		await _ticks(3)
		chefty.call("request_enter", 0)
		await get_tree().create_timer(0.5).timeout
	if int(chefty.call("driver")) != Net.local_peer_id():
		return {"error": "couldn't get in the driver's seat"}
	return {"note": "driving: move_forward/back throttle, move_left/right steer, interact gets out", "zone": _zone()}


# ---------------------------------------------------------------- reset


## Undo whatever an earlier moment left behind (a raid, a capture, a ride, a
## crossing, a hiding spot, a seat), so each scenario starts clean.
func reset() -> void:
	var me_id := Net.local_peer_id()
	var me := _me()
	var director := _director()
	var crossing := get_tree().get_first_node_in_group("border_return")
	if me != null:
		var spot := preload("res://net/components/hide_spot.gd").spot_of(get_tree(), me_id)
		if spot != null:
			spot.call("request_exit")
		if bool(me.get("in_pile")):
			me.call("set_pile", false)
	for vehicle: Node in get_tree().get_nodes_in_group("vehicles"):
		if vehicle.has_method("seat_of") and int(vehicle.call("seat_of", me_id)) >= 0 and vehicle.has_method("request_exit"):
			vehicle.call("request_exit")
	if director != null:
		director.set("_batching", false)
		if bool(director.call("is_captured", me_id)) or _van() != null:
			# Off the van and out of the cohort, on every peer (the director's own message).
			director.rpc("_rpc_drop_rider", me_id)
		if int(director.call("phase")) != 0:
			director.call("_dismiss_crew")
		var safe: Dictionary = director.get("_safe_until")
		safe.erase(me_id)
	if crossing != null and (crossing.get("_roster") as Array).has(me_id):
		crossing.call("_send_home", me_id)
	# A van still on its way (empty now) finishes its trip, or it can't leave again
	# (the host's start time only, as in _border_return: other peers see it jump
	# to the route's end when it arrives; start an observer recording after this).
	var van := _van()
	if van != null and bool(van.call("is_riding")):
		van.set("_start_time", Net.server_time() - float(van.get("_duration")))
		await _wait_for(func() -> Variant: return true if not bool(van.call("is_riding")) else null)
	await _ticks(3)


# ---------------------------------------------------------------- helpers


## On a job yard: load one if none is waiting, and send the player there the
## way the game does (a host-ordered teleport). Returns "" or why not.
func _to_lot() -> String:
	var world := _world()
	if get_tree().get_first_node_in_group("job_lot") == null:
		world.call("_load_job_lot")
		await _ticks(5)
	if get_tree().get_first_node_in_group("job_lot") == null or _field() == null:
		return "no job yard (start with --start-zone=lot --job-seed=777, which tools\\play.ps1 -Scenario adds)"
	if Net.player_zone(Net.local_peer_id()) != Net.Zone.LOT:
		Net.move_player_to_zone(Net.local_peer_id(), Net.Zone.LOT)
		var there: Variant = await _wait_for(func() -> Variant:
			return true if Net.player_zone(Net.local_peer_id()) == Net.Zone.LOT else null)
		if there == null:
			return "couldn't get to the yard"
		await get_tree().create_timer(0.5).timeout
	return ""


## The first strip of untouched leaves, gag_test's way: STRIP_STEPS samples along +x.
func _fresh_strip() -> Vector3:
	var field := _field()
	var lot := get_tree().get_first_node_in_group("job_lot") as Node3D
	for z: float in [-6.0, -10.0, 2.0, 6.0, -14.0, 10.0, -2.0, 14.0]:
		for x: float in [-15.0, -9.0, 3.0, 9.0, -3.0]:
			var fine := true
			for step: int in STRIP_STEPS:
				if int(field.call("sample_world", lot.global_position + Vector3(x + float(step) * STRIP_STEP_METERS, 0.2, z))) < STRIP_MIN_DENSITY:
					fine = false
					break
			if fine:
				return lot.global_position + Vector3(x, 0.1, z)
	return Vector3.INF


## Get one of these into the player's hands, the way E does. Returns what's held.
func _hold(kind: String) -> String:
	var me := _me()
	var pockets := me.get_node_or_null("Pockets")
	if _held(me) == kind:
		return kind
	if pockets != null and int(pockets.call("slot_of_kind", kind)) >= 0:
		pockets.call("select", int(pockets.call("slot_of_kind", kind)))
		await _ticks(4)
		if _held(me) == kind:
			return kind
	var item: Node3D = null
	for node: Node in get_tree().get_nodes_in_group("props"):
		if str(node.get("kind")) == kind and not node.is_queued_for_deletion() and bool(node.call("is_loose")):
			item = node as Node3D
			break
	if item == null:
		return _held(me)
	item.global_position = me.global_position + Vector3(0.0, 0.4, 0.0) + (-me.global_basis.z) * 0.8
	item.set("linear_velocity", Vector3.ZERO)
	await _ticks(2)
	item.call("request_grab")
	await _ticks(4)
	if _held(me) != kind and pockets != null and int(pockets.call("slot_of_kind", kind)) >= 0:
		pockets.call("select", int(pockets.call("slot_of_kind", kind)))
		await _ticks(4)
	return _held(me)


func _held(me: Node) -> String:
	var held: Node = me.call("_held_prop")
	return str(held.get("kind")) if held != null else ""


## Stand here, facing yaw (radians; 0 faces -z), looking pitch radians up.
func _place(at: Vector3, yaw: float, pitch: float) -> void:
	var me := _me()
	me.call("apply_network_teleport", Transform3D(Basis(Vector3.UP, yaw), at))
	me.set("body_yaw", yaw)
	me.set("head_pitch", pitch)


func _yaw_toward(from: Vector3, to: Vector3) -> float:
	var flat := Vector3(to.x - from.x, 0.0, to.z - from.z)
	return atan2(-flat.x, -flat.z)


## The warning, through the director's own phase message to every peer, started
## as if the call came in a while ago: the crew arrives in lead seconds.
func _warn_with(director: Node, lead: float) -> void:
	director.rpc("_rpc_phase", 1, Net.server_time() - (Constants.RUN_WARNING_SECONDS - lead), _Strings.UI["status_crew_coming"])


func _wait_for(check: Callable) -> Variant:
	var waited := 0.0
	while waited < SETTLE_SECONDS:
		var value: Variant = check.call()
		if value != null:
			return value
		await get_tree().create_timer(0.1).timeout
		waited += 0.1
	return null


func _ticks(count: int) -> void:
	for _tick: int in count:
		await get_tree().physics_frame


func _me() -> Node3D:
	for node: Node in get_tree().get_nodes_in_group("players"):
		if node.name == str(Net.local_peer_id()):
			return node as Node3D
	return null


func _world() -> Node:
	return get_tree().get_first_node_in_group("world")


func _director() -> Node:
	return get_tree().get_first_node_in_group("run_director")


func _field() -> Node:
	return get_tree().get_first_node_in_group("leaf_field")


func _lot_zone() -> Node3D:
	return _world().get_node_or_null("LotZone") as Node3D


func _van() -> Node:
	return _world().get_node_or_null("Rides/Van")


func _crew() -> Node3D:
	var crew := get_tree().get_nodes_in_group("crew")
	return crew[0] as Node3D if not crew.is_empty() else null


func _phase() -> String:
	return ["QUIET", "WARNING", "CHASE"][clampi(int(_director().call("phase")), 0, 2)]


func _zone() -> String:
	return Net.Zone.keys()[Net.player_zone(Net.local_peer_id())]


func _v(at: Vector3) -> Array:
	return [snappedf(at.x, 0.01), snappedf(at.y, 0.01), snappedf(at.z, 0.01)]
