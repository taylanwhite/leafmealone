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
## hide_bin, hide_shed, pile, peek, inspect_near, inspect_found, border_return,
## van_ride, store, drive (that one needs --town-map).

const _Strings = preload("res://ui/strings.gd")
const _Vehicles = preload("res://props/vehicles.gd")
const NAMES: Array[String] = ["rake_fresh", "rake_pile", "raid_warn", "raid_arrive", "caught", "hide", "hide_bin", "hide_shed", "pile", "peek", "inspect_near", "inspect_found", "border_return", "van_ride", "store", "drive"]
## raid_arrive: how long before the NICE BOYS show up.
const ARRIVE_LEAD_SECONDS: float = 2.0
## hide: how long the warning still has to run, time enough to get in.
const HIDE_LEAD_SECONDS: float = 3.5
## inspect_near, inspect_found: how long until the NICE BOY pokes the hedge.
const INSPECT_LEAD_SECONDS: float = 2.2
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
		"hide_bin":
			out = await _hide_bin()
		"hide_shed":
			out = await _hide_shed()
		"pile":
			out = await _pile()
		"peek":
			out = await _peek()
		"inspect_near":
			out = await _inspect_near()
		"inspect_found":
			out = await _inspect_found()
		"border_return":
			out = await _border_return()
		"van_ride":
			out = await _van_ride()
		"store":
			out = await _store()
		"drive":
			out = await _drive()
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


## The hedge right in front of you, the warning counting down (R2 chunk 3).
func _hide() -> Dictionary:
	return await _hide_at("hedge", "hide")


## The same with the wheelie bin.
func _hide_bin() -> Dictionary:
	return await _hide_at("bin", "hide_bin")


## The same at the shed's door.
func _hide_shed() -> Dictionary:
	return await _hide_at("shed", "hide_shed")


## Stand just outside a spot of this kind, facing it, with the warning running.
func _hide_at(kind: String, moment: String) -> Dictionary:
	var problem: String = await _to_lot()
	if problem != "":
		return {"error": problem}
	var director := _director()
	var spot := _spot_of_kind(kind)
	if spot == null:
		return {"error": "this yard has no free %s" % kind}
	var side := _open_side(spot)
	var stand: Vector3 = spot.call("entry_point", side, 0)
	_place(stand, _yaw_toward(stand, spot.global_position), -0.25)
	_warn_with(director, HIDE_LEAD_SECONDS)
	await _ticks(2)
	return {"moment": moment, "note": "facing the %s; tap interact to get in (hold secondary inside to peek), they arrive in %.1f s" % [kind, HIDE_LEAD_SECONDS], "phase": _phase(), "spot": _v(spot.global_position)}


func _reached_hide() -> bool:
	return _phase() == "WARNING" and _me().call("_nearest_free_spot") != null


func _reached_hide_bin() -> bool:
	return _reached_hide()


func _reached_hide_shed() -> bool:
	return _reached_hide()


## Standing on a raked pile, the warning counting down: interact dives in.
func _pile() -> Dictionary:
	var raked: Dictionary = await _rake_pile()
	if raked.has("error"):
		return raked
	var pile := Vector3(raked["pile"][0], 0.1, raked["pile"][2])
	var me := _me()
	var held: Node = me.call("_held_prop")
	if held != null:
		held.call("request_drop")
		await _ticks(3)
	_place(pile, -PI * 0.5, -0.3)
	_warn_with(_director(), HIDE_LEAD_SECONDS + 1.0)
	await _ticks(4)
	return {"moment": "pile", "note": "on a raked pile; tap interact to dive in, they arrive in %.1f s" % (HIDE_LEAD_SECONDS + 1.0), "phase": _phase(), "pile": _v(pile)}


func _reached_pile() -> bool:
	return bool(_me().call("_on_pile"))


## Already in the hedge, the chase on, a NICE BOY strolling past 9 m out:
## hold secondary to peek (he's facing the other way, so it's safe for now).
func _peek() -> Dictionary:
	var hidden: Dictionary = await _hidden_in_hedge(false)
	if hidden.has("error"):
		return hidden
	return {"moment": "peek", "note": "hidden in the hedge; hold secondary to peek, look around with the mouse", "phase": _phase()}


func _reached_peek() -> bool:
	return bool(_me().call("is_hidden")) and _phase() == "CHASE"


## Hidden in the hedge unseen; a NICE BOY turns, points, walks over and pokes
## it in about 2 s. Stay still: a near miss and a sticker.
func _inspect_near() -> Dictionary:
	var hidden: Dictionary = await _hidden_in_hedge(false)
	if hidden.has("error"):
		return hidden
	_inspect_soon(hidden["spot"] as Node3D, INSPECT_LEAD_SECONDS)
	return {"moment": "inspect_near", "note": "hidden unseen; he pokes the hedge in %.1f s" % INSPECT_LEAD_SECONDS, "phase": _phase()}


func _reached_inspect_near() -> bool:
	return _reached_peek()


## He watched you dive into the hedge; he walks over and pokes in about 2 s:
## found, lifted out, caught.
func _inspect_found() -> Dictionary:
	var hidden: Dictionary = await _hidden_in_hedge(true)
	if hidden.has("error"):
		return hidden
	_inspect_soon(hidden["spot"] as Node3D, INSPECT_LEAD_SECONDS)
	return {"moment": "inspect_found", "note": "he saw you go in; he pokes the hedge in %.1f s" % INSPECT_LEAD_SECONDS, "phase": _phase(), "suspicion": snappedf(float((hidden["spot"] as Node3D).call("suspicion")), 0.01)}


func _reached_inspect_found() -> bool:
	return _reached_peek()


## The chase on, the crew held where this scenario puts them (no crew brain
## before R2 chunk 2 merges), and you inside the hedge: seen going in or not.
func _hidden_in_hedge(seen: bool) -> Dictionary:
	var problem: String = await _to_lot()
	if problem != "":
		return {"error": problem}
	var spot := _spot_of_kind("hedge")
	if spot == null:
		return {"error": "this yard has no free hedge"}
	var director := _director()
	var me_id := Net.local_peer_id()
	var safe: Dictionary = director.get("_safe_until")
	safe[me_id] = Net.server_time() + 3.0
	director.call("_begin_chase")
	await _ticks(4)
	var crew := _crew()
	if crew == null:
		return {"error": "no NICE BOY spawned"}
	for each: Node in get_tree().get_nodes_in_group("crew"):
		each.set_physics_process(false)
	var side := _open_side(spot)
	var out: Vector3 = spot.call("side_direction", side)
	var along := Vector3(-out.z, 0.0, out.x)
	# Off to the side, 9 m out: facing the hedge if he's to see you go in, else strolling across.
	var watch_at := spot.global_position + out * 7.0 + along * 4.0
	crew.global_position = Vector3(watch_at.x, crew.global_position.y, watch_at.z)
	var look := (spot.global_position - watch_at) if seen else along
	crew.rotation.y = atan2(look.x, look.z)
	for index: int in range(1, get_tree().get_nodes_in_group("crew").size()):
		var other := get_tree().get_nodes_in_group("crew")[index] as Node3D
		other.global_position = spot.global_position - out * 25.0 + along * float(index) * 3.0
	var stand: Vector3 = spot.call("entry_point", side, 0)
	_place(stand, _yaw_toward(stand, spot.global_position), -0.2)
	await _ticks(3)
	_dive_into(spot)
	var inside: Variant = await _wait_for(func() -> Variant: return true if bool(spot.call("is_inside", me_id)) else null)
	if inside == null:
		return {"error": "couldn't get into the hedge"}
	await get_tree().create_timer(Constants.HIDE_ENTER_SECONDS + 0.4).timeout
	return {"spot": spot, "crew": crew}


## The local player dives in the way interact does.
func _dive_into(spot: Node3D) -> void:
	var me := _me()
	me.call("_hide_view").call("predict_enter", spot)
	spot.call("request_enter")


## A NICE BOY's inspection, the way the crew brain (R2 chunk 2) runs one: a
## look and a point, a walk to the spot's inspect point, the poke, the verdict.
## Without the R2 Encounter a found hider goes straight to the director.
func _inspect_soon(spot: Node3D, lead: float) -> void:
	var crew := _crew()
	if crew == null:
		return
	var body := crew.get_node_or_null("Visual/CartoonBody")
	get_tree().create_timer(maxf(0.1, lead - 1.6)).timeout.connect(func() -> void:
		if not is_instance_valid(crew):
			return
		var to := spot.global_position - crew.global_position
		crew.rotation.y = atan2(to.x, to.z)
		if body != null:
			body.call("gesture", "point")
		# The R2 crew (chunk 2) barks its own line; before it, the point says it.
		if crew.has_method("bark"):
			crew.call("bark", "inspect"))
	get_tree().create_timer(lead - 1.0).timeout.connect(func() -> void:
		if is_instance_valid(crew):
			_walk(crew, spot.call("inspect_point"), 0.9))
	get_tree().create_timer(lead).timeout.connect(func() -> void:
		if not is_instance_valid(crew):
			return
		var face := spot.global_position - crew.global_position
		crew.rotation.y = atan2(face.x, face.z)
		spot.call("host_inspect_begin", crew)
		get_tree().create_timer(Constants.HIDE_INSPECT_SECONDS).timeout.connect(func() -> void:
			if is_instance_valid(crew) and is_instance_valid(spot):
				print("[Scenario] inspection: %s" % spot.call("host_inspect_resolve", crew))))


## Walk a held-still NICE BOY to a point over seconds (the host's body replicates).
func _walk(crew: Node3D, to: Vector3, seconds: float) -> void:
	var from := crew.global_position
	var target := Vector3(to.x, from.y, to.z)
	var flat := target - from
	crew.rotation.y = atan2(flat.x, flat.z)
	var tween := crew.create_tween()
	tween.set_process_mode(Tween.TWEEN_PROCESS_PHYSICS)
	tween.tween_property(crew, "global_position", target, seconds).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)


func _spot_of_kind(kind: String) -> Node3D:
	for node: Node in get_tree().get_nodes_in_group("hide_spots"):
		if str(node.get("spot_kind")) == kind and bool(node.call("has_room")):
			return node as Node3D
	return null


## The side of a spot with a clear view out to 8 m (not facing the house or a fence).
func _open_side(spot: Node3D) -> int:
	if str(spot.get("spot_kind")) == "shed":
		return 0
	var space := spot.get_world_3d().direct_space_state
	for side: int in [0, 2, 1, 3]:
		var out: Vector3 = spot.call("side_direction", side)
		var query := PhysicsRayQueryParameters3D.create(spot.call("top_point"), spot.global_position + out * 8.0 + Vector3(0.0, 1.4, 0.0), 1)
		query.exclude = spot.call("_own_rids")
		if space.intersect_ray(query).is_empty() and bool(spot.call("_exit_clear", side, 0)):
			return side
	return 0


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
		# Let a climb-out finish, or it carries on after the next placement.
		var view := me.get_node_or_null("HideView")
		if view != null:
			await _wait_for(func() -> Variant: return true if not bool(view.call("is_moving")) else null)
		me.set("peeking", false)
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
