extends Node

## Authority: host, dev builds only. Scenario jumps (docs/PLAYTEST.md): put the
## host's player at a moment worth judging in a second or two, through the same
## code the game runs (the run director's phases and captures, the van, Annex
## B, hiding spots, the leaf field's rake strokes, Chefty's seats), so what
## gets recorded is what players get. Only the starting position is arranged.
## remote_play.gd's ["scenario", name] step and the --scenario=<name> flag call
## run(); the playtest tools test (net/dev/playtest_tools_test.gd) checks each
## one reaches its state.
##
## Names: rake_fresh, rake_pile, raid_warn, raid_arrive, caught, spotted, lunge,
## dodge, gotcha, cite_rescue, escort, hide, hide_bin, hide_shed, pile, peek,
## inspect_near, inspect_found, border_return, van_ride, van_seated, van_unbuckle,
## van_straggler, dropoff, annex, annex_break, annex_heist, annex_bigstamp,
## annex_window_d, annex_visit (needs a second player), annex_closing, store,
## drive (that one needs --town-map), toss, toss_full, toss_close.
## border_return is the old name of annex (kept for one wave).

const _Strings = preload("res://ui/strings.gd")
const _Vehicles = preload("res://props/vehicles.gd")
const _Sched = preload("res://net/annex/annex_schedule.gd")
## annex*: the raid seed and trip the visit starts with, so the room is the same every take.
const ANNEX_SEED: int = 271828
const ANNEX_TRIP: int = 1
const NAMES: Array[String] = ["rake_fresh", "rake_pile", "raid_warn", "raid_arrive", "caught", "spotted", "lunge", "dodge", "gotcha", "cite_rescue", "escort", "hide", "hide_bin", "hide_shed", "pile", "peek", "inspect_near", "inspect_found", "border_return", "van_ride", "van_seated", "van_unbuckle", "van_straggler", "dropoff", "annex", "annex_break", "annex_heist", "annex_bigstamp", "annex_window_d", "annex_visit", "annex_closing", "store", "drive", "toss", "toss_full", "toss_close"]
## van_ride: how long the seated van holds before it pulls out.
const VAN_RIDE_LEAD_SECONDS: float = 2.0
## van_unbuckle: how far from the door step you stand.
const DOOR_STAND_METERS: float = 1.2
## van_straggler: where you watch from, in the van's space: on the yard side, level
## with its back doors (the yard's pad walls keep you off the far sidewalk).
const STRAGGLER_WATCH := Vector3(6.0, 0.0, 2.5)
## raid_arrive: how long before the NICE BOYS show up.
const ARRIVE_LEAD_SECONDS: float = 2.0
## hide: how long the warning still has to run, time enough to get in.
const HIDE_LEAD_SECONDS: float = 3.5
## caught: how far from the head NICE BOY you stand once he's out (his lunge
## starts about 1.5 s in: the hop, the spot, two steps).
const CAUGHT_LUNGE_METERS: float = 4.0
## spotted: far enough to see the spot and the speed-walk.
const SPOTTED_METERS: float = 12.0
## dodge: the wind-up starts this long after the scenario.
const DODGE_LEAD_SECONDS: float = 1.0
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
## toss: how far from the middle of Chefty's bed you stand, looking a touch up,
## and what the bag in your hands is worth.
const TOSS_STAND_METERS: float = 4.0
## toss_close: right by the side wall, where a toss hops in over the rail and E
## heaves it in.
const TOSS_CLOSE_METERS: float = 2.0
const TOSS_PITCH: float = 0.12
const TOSS_BAG_VALUE: int = 14
## Waits for a state, in seconds, before a scenario gives up.
const SETTLE_SECONDS: float = 15.0

## The --scenario=<name> one at launch has run (or there was none).
var start_done: bool = false
## Its result, for remote play's first report.
var start_result: Dictionary = {}
## The window the last annex_break / annex_heist set up, for its _reached_ check.
var _annex_window: String = ""


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
		"spotted":
			out = await _spotted()
		"lunge":
			out = await _lunge()
		"dodge":
			out = await _dodge()
		"gotcha":
			out = await _gotcha()
		"cite_rescue":
			out = await _cite_rescue()
		"escort":
			out = await _escort()
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
		"border_return", "annex":
			out = await _annex()
		"annex_break":
			out = await _annex_break()
		"annex_heist":
			out = await _annex_heist()
		"annex_bigstamp":
			out = await _annex_bigstamp()
		"annex_window_d":
			out = await _annex_window_d()
		"annex_visit":
			out = await _annex_visit()
		"annex_closing":
			out = await _annex_closing()
		"van_ride":
			out = await _van_ride()
		"van_seated":
			out = await _van_seated()
		"van_unbuckle":
			out = await _van_unbuckle()
		"van_straggler":
			out = await _van_straggler()
		"dropoff":
			out = await _dropoff()
		"store":
			out = await _store()
		"drive":
			out = await _drive()
		"toss":
			out = await _toss()
		"toss_full":
			out = await _toss(true)
		"toss_close":
			out = await _toss(false, TOSS_CLOSE_METERS)
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
## toss_close: TOSS_CLOSE_METERS off, beside the side wall.
func _toss(full: bool = false, meters: float = TOSS_STAND_METERS) -> Dictionary:
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
	var at := middle + side * meters
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
	return {"note": "a bag in hand %.0f m from Chefty's bed, facing it; hold drop to wind up, let go to toss" % meters, "bed": _v(middle)}


## The NICE BOYS have been called: the warning starts now. You're on the yard
## facing the curb where the flare goes up and the van pulls up (R2: no
## countdown, no arrival line; the van says it).
func _raid_warn() -> Dictionary:
	var problem: String = await _to_lot()
	if problem != "":
		return {"error": problem}
	var director := _director()
	var park: Vector3 = director.call("van_park_point")
	var lot := _lot_zone()
	var toward := Vector3(park.x - lot.global_position.x, 0.0, park.z - lot.global_position.z).normalized()
	var stand := park - toward * WATCH_ARRIVAL_METERS
	_place(Vector3(stand.x, lot.global_position.y + 0.1, stand.z), _yaw_toward(stand, park), -0.05)
	director.call("force_event")
	await _ticks(2)
	return {"moment": "raid_warn", "note": "warning now, facing the curb: the flare is up where the van parks, and it pulls up in %.0f s" % Constants.RUN_WARNING_SECONDS, "phase": _phase(), "arrives_in": snappedf(float(director.call("arrival_time")) - Net.server_time(), 0.01), "park": _v(park)}


## For the playtest tools test: the warning is on and you're facing the curb.
func _reached_raid_warn() -> bool:
	var me := _me()
	if me == null or int(_director().call("phase")) != 1:
		return false
	var park: Vector3 = _director().call("van_park_point")
	var facing := -(me as Node3D).global_basis.z
	var to_park := Vector3(park.x - me.global_position.x, 0.0, park.z - me.global_position.z).normalized()
	return facing.dot(to_park) > 0.8


## The warning is nearly over: the van has pulled up and its door opens in
## ARRIVE_LEAD_SECONDS, right in front of you, and the NICE BOYS climb out.
func _raid_arrive() -> Dictionary:
	var problem: String = await _to_lot()
	if problem != "":
		return {"error": problem}
	var director := _director()
	var door: Vector3 = director.call("crew_arrival_point")
	var lot := _lot_zone()
	var toward := Vector3(door.x - lot.global_position.x, 0.0, door.z - lot.global_position.z).normalized()
	var stand := door - toward * WATCH_ARRIVAL_METERS
	_place(Vector3(stand.x, lot.global_position.y + 0.1, stand.z), _yaw_toward(stand, door), -0.05)
	_warn_with(director, ARRIVE_LEAD_SECONDS)
	await _ticks(2)
	return {"moment": "raid_arrive", "note": "the van's door opens in %.1f s in front of you; they hop out one by one" % ARRIVE_LEAD_SECONDS, "phase": _phase(), "arrives_in": snappedf(float(director.call("arrival_time")) - Net.server_time(), 0.01), "arrival": _v(door)}


func _reached_raid_arrive() -> bool:
	return _phase() == "WARNING" and not get_tree().get_nodes_in_group("nice_crew").is_empty()


## The chase is on and the head NICE BOY has just hopped down, a few steps from
## you: his lunge starts in about 1.5 s. Stand still to be caught.
func _caught() -> Dictionary:
	var out: Dictionary = await _crew_out(0.2)
	if out.has("error"):
		return out
	var crew := _crew()
	var stand := _in_front_of(crew, CAUGHT_LUNGE_METERS)
	_place(stand, _yaw_toward(stand, crew.global_position), -0.05)
	await _ticks(2)
	return {"moment": "caught", "note": "%s is %.1f m away; stand still and he lunges in about 1.5 s" % [crew.name, CAUGHT_LUNGE_METERS], "phase": _phase(), "crew": str(crew.name)}


func _reached_caught() -> bool:
	return _phase() == "CHASE" and _crew() != null


## Out on the lawn in plain view, a dozen meters off: they spot you (the freeze,
## the whistle, the point) and come speed-walking.
func _spotted() -> Dictionary:
	var out: Dictionary = await _crew_out(0.2)
	if out.has("error"):
		return out
	var crew := _crew()
	var stand := _in_front_of(crew, SPOTTED_METERS)
	_place(stand, _yaw_toward(stand, crew.global_position), -0.05)
	await _ticks(2)
	return {"moment": "spotted", "note": "%s is %.0f m away and about to spot you" % [crew.name, SPOTTED_METERS], "phase": _phase()}


func _reached_spotted() -> bool:
	return _phase() == "CHASE" and _crew() != null


## Close and in front of him once he's out: the wind-up, then the lunge.
func _lunge() -> Dictionary:
	var out: Dictionary = await _crew_out(0.2)
	if out.has("error"):
		return out
	var crew := _crew()
	var stand := _in_front_of(crew, Constants.CREW_LUNGE_RANGE + 0.4)
	_place(stand, _yaw_toward(stand, crew.global_position), -0.05)
	await _ticks(2)
	return {"moment": "lunge", "note": "%s is %.1f m away, facing you; he winds up as soon as he's on his feet" % [crew.name, Constants.CREW_LUNGE_RANGE + 0.4], "phase": _phase()}


func _reached_lunge() -> bool:
	return _phase() == "CHASE" and _crew() != null


## A NICE BOY right at your left shoulder winds up in DODGE_LEAD_SECONDS: step
## aside (strafe right) during the wind-up and he sprawls.
func _dodge() -> Dictionary:
	var out: Dictionary = await _crew_out(-1.0)
	if out.has("error"):
		return out
	var me := _me()
	var crew := _crew()
	var lot := _lot_zone()
	var stand := lot.global_position + Vector3(2.0, 0.1, 6.0)
	_place(stand, 0.0, -0.05)
	var left := -me.global_basis.x
	_put_crew(crew, stand + left * (Constants.CREW_LUNGE_RANGE - 0.5), stand)
	_safe_for(DODGE_LEAD_SECONDS)
	await _ticks(2)
	get_tree().create_timer(DODGE_LEAD_SECONDS).timeout.connect(func() -> void:
		var encounter := get_tree().get_first_node_in_group("nice_encounter")
		if encounter != null and is_instance_valid(crew):
			encounter.call("host_windup", crew, Net.local_peer_id(), false))
	return {"moment": "dodge", "note": "%s is at your left; he winds up in %.1f s: strafe right during it" % [crew.name, DODGE_LEAD_SECONDS], "phase": _phase()}


func _reached_dodge() -> bool:
	return _phase() == "CHASE" and _crew() != null


## Caught right now, no lunge: the gotcha from its first frame.
func _gotcha() -> Dictionary:
	var out: Dictionary = await _crew_out(-1.0)
	if out.has("error"):
		return out
	var crew := _crew()
	var lot := _lot_zone()
	var stand := lot.global_position + Vector3(2.0, 0.1, 6.0)
	_place(stand, 0.0, -0.05)
	_put_crew(crew, stand + Vector3(0.0, 0.0, -1.2), stand)
	await _ticks(3)
	_director().call("force_capture", Net.local_peer_id())
	await _ticks(1)
	return {"moment": "gotcha", "note": "caught by %s now: the hit-stop, the two-shot, the grin, the cite" % crew.name, "phase": _phase()}


func _reached_gotcha() -> bool:
	return _stage(Net.local_peer_id()) >= 2


## The other player is being cited a couple of meters away and you're holding a
## gnome: throw it (or punch him) and they're free. Needs a second player.
func _cite_rescue() -> Dictionary:
	var out: Dictionary = await _crew_out(-1.0)
	if out.has("error"):
		return out
	var friend := _other_player()
	if friend == null:
		return {"error": "cite_rescue needs a second player (start with -Observer, or a client)"}
	var crew := _crew()
	var lot := _lot_zone()
	var spot := lot.global_position + Vector3(0.0, 0.1, 6.0)
	friend.call("send_teleport", Transform3D(Basis.IDENTITY, spot))
	_put_crew(crew, spot + Vector3(0.0, 0.0, -1.2), spot)
	var stand := spot + Vector3(3.2, 0.0, 1.0)
	_place(stand, _yaw_toward(stand, crew.global_position), -0.1)
	_safe_for(20.0)
	await get_tree().create_timer(0.4).timeout
	_director().call("force_capture", int(str(friend.name)))
	var held: String = await _hold("gnome")
	_place(stand, _yaw_toward(stand, crew.global_position), -0.1)
	return {"moment": "cite_rescue", "note": "%s is being cited in front of you; you hold '%s': throw it at %s" % [Net.player_name(int(str(friend.name))), held, crew.name], "phase": _phase()}


func _reached_cite_rescue() -> bool:
	var friend := _other_player()
	return friend != null and _stage(int(str(friend.name))) >= 2


## Cited and on the way: arm in arm to the van.
func _escort() -> Dictionary:
	var out: Dictionary = await _gotcha()
	if out.has("error"):
		return out
	var encounter := get_tree().get_first_node_in_group("nice_encounter")
	var cite := encounter.get("_cite_end") as Dictionary
	cite[Net.local_peer_id()] = Net.server_time() + 0.4
	var walking: Variant = await _wait_for(func() -> Variant:
		return true if _stage(Net.local_peer_id()) == 4 else null)
	if walking == null:
		return {"error": "the escort never started"}
	return {"moment": "escort", "note": "arm in arm with %s to the van" % _crew().name, "phase": _phase()}


func _reached_escort() -> bool:
	return _stage(Net.local_peer_id()) >= 4


## A raid with the crew out of the van and on the lawn (lead >= 0: CHASE starts
## that long from now and they're still climbing out; < 0: wait until they're all out).
func _crew_out(lead: float) -> Dictionary:
	var problem: String = await _to_lot()
	if problem != "":
		return {"error": problem}
	var director := _director()
	_warn_with(director, maxf(0.05, lead))
	var ready: Variant = await _wait_for(func() -> Variant:
		if _phase() != "CHASE" or _crew() == null:
			return null
		if lead >= 0.0:
			return true
		for crew: Node in get_tree().get_nodes_in_group("nice_crew"):
			if _in_van(crew):
				return null
		return true)
	if ready == null:
		return {"error": "the NICE BOYS never got out of the van"}
	return {}


## Where to stand: meters in front of the van's door, toward the yard; the first of a fan of headings around "toward the yard" from which he can see
## you: the Courtesy Shuttle parks on the clearest curb near the noise, which can
## put Chefty, a tree or a fence straight between the door and the yard
## (R2 integration: a caught take spent 18 s staring at Chefty's side).
func _in_front_of(crew: Node3D, meters: float) -> Vector3:
	var lot := _lot_zone()
	var door: Vector3 = _director().call("crew_arrival_point")
	var toward := Vector3(lot.global_position.x - door.x, 0.0, lot.global_position.z - door.z).normalized()
	var from := crew.global_position if _crew_on_feet(crew) else door
	var ground := lot.global_position.y + 0.1
	var first := Vector3.INF
	for degrees: float in [0.0, 25.0, -25.0, 50.0, -50.0, 75.0, -75.0]:
		var dir := toward.rotated(Vector3.UP, deg_to_rad(degrees))
		var at := from + dir * meters
		at.y = ground
		if not first.is_finite():
			first = at
		if _clear_between(Vector3(from.x, ground + 1.2, from.z), at + Vector3.UP * 1.1, crew):
			return at
	return first


## Nothing solid on the line between two points (bodies of people excepted).
func _clear_between(a: Vector3, b: Vector3, skip: Node3D) -> bool:
	var space := skip.get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.create(a, b)
	var excluded: Array[RID] = []
	for group: String in ["players", "nice_crew"]:
		for node: Node in get_tree().get_nodes_in_group(group):
			if node is CollisionObject3D:
				excluded.append((node as CollisionObject3D).get_rid())
	query.exclude = excluded
	return space.intersect_ray(query).is_empty()


func _crew_on_feet(crew: Node3D) -> bool:
	return not _in_van(crew)


## Seated, hopping out or climbing in (npcs/crew_member.gd SEATED, HOP_OUT, HOP_IN).
func _in_van(crew: Node) -> bool:
	return [15, 16, 17].has(int(crew.get("mode")))


## The host moves a NICE BOY (and settles his smoothing everywhere), facing a point.
func _put_crew(crew: Node3D, at: Vector3, facing: Vector3) -> void:
	crew.global_position = at
	var look := facing - at
	crew.rotation.y = atan2(look.x, look.z)
	crew.set("_speed_now", 0.0)
	crew.reset_physics_interpolation()


## No grabs on you for this long (so the scenario's own grab is the one that comes).
func _safe_for(seconds: float) -> void:
	var safe: Dictionary = _director().get("_safe_until")
	safe[Net.local_peer_id()] = Net.server_time() + seconds


func _stage(peer_id: int) -> int:
	var encounter := get_tree().get_first_node_in_group("nice_encounter")
	return int(encounter.call("stage_of", peer_id)) if encounter != null else 0


func _other_player() -> Node3D:
	for node: Node in get_tree().get_nodes_in_group("players"):
		if node.name != str(Net.local_peer_id()):
			return node as Node3D
	return null


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
	# Set down from the teleport (a moment in the air, and E wouldn't dive yet).
	await _wait_for(func() -> Variant: return true if me.is_on_floor() else null)
	return {"moment": "pile", "note": "on a raked pile; tap interact to dive in, they arrive in %.1f s" % (HIDE_LEAD_SECONDS + 1.0), "phase": _phase(), "pile": _v(pile), "at": _v(me.global_position), "pile_here": bool(_field().call("is_pile_at", me.global_position)), "on_floor": me.is_on_floor()}


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
	# R2: the call makes the crew, seated in the Courtesy Shuttle; this moment
	# takes them off it and places them by hand (R2 integration).
	if int(director.call("phase")) == 0:
		director.call("force_event")
	director.call("_begin_chase")
	await _ticks(4)
	var van := _van()
	if van != null:
		van.call("dev_reset")
	for each: Node in get_tree().get_nodes_in_group("crew"):
		if each.has_method("host_set_mode"):
			each.call("host_set_mode", 0)
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
				var outcome: Dictionary = spot.call("host_inspect_resolve", crew)
				print("[Scenario] inspection: %s" % outcome)
				# Found: the gotcha from the spot, as the crew brain hands it over.
				var encounter := get_tree().get_first_node_in_group("nice_encounter")
				if encounter != null and StringName(outcome.get("outcome", &"")) == &"found":
					encounter.call("host_windup", crew, int(outcome.get("peer", 0)), true)))


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


## Buckled into the NICE BOYS' van at the yard's curb, and it pulls out in
## VAN_RIDE_LEAD_SECONDS: the door, the blinker, the drive, the iris.
func _van_ride() -> Dictionary:
	var seated: Dictionary = await _van_seated()
	if seated.has("error"):
		return seated
	var van := _van()
	van.call("host_depart", Net.server_time() + VAN_RIDE_LEAD_SECONDS)
	await _ticks(2)
	return {"note": "in the van; it pulls out in %.0f s" % VAN_RIDE_LEAD_SECONDS, "zone": _zone(), "trip": int(seated["trip"])}


func _reached_van_ride() -> bool:
	var van := _van()
	return van != null and not (van.call("seat_info", Net.local_peer_id()) as Dictionary).is_empty() and str(van.call("leg_name", int(van.call("raid_trip_id")))) in ["parked", "depart", "hidden", "annex_arrive", "annex_parked"]


## Buckled into the parked van, the door open: the seat camera, the window, the
## knock (primary), the driver's mirror checks. It holds until something else
## says go.
func _van_seated() -> Dictionary:
	var problem: String = await _to_lot()
	if problem != "":
		return {"error": problem}
	var van := _van()
	if van == null:
		return {"error": "no Courtesy Shuttle (net/run_events/shuttle.gd)"}
	var trip := int(van.call("dev_park_now", true))
	await _ticks(3)
	van.call("dev_seat", trip, Net.local_peer_id())
	var sat: Variant = await _wait_for(func() -> Variant:
		return true if bool((van.call("seat_info", Net.local_peer_id()) as Dictionary).get("settled", false)) else null)
	if sat == null:
		return {"error": "never sat down in the van"}
	return {"note": "seated in the parked van, the door open; primary knocks", "zone": _zone(), "trip": trip}


func _reached_van_seated() -> bool:
	var van := _van()
	return van != null and bool((van.call("seat_info", Net.local_peer_id()) as Dictionary).get("settled", false))


## A friend buckled into the parked van and you at its door: hold interact to
## unbuckle them, between the driver's mirror checks. Needs a second player (the
## -Observer window).
func _van_unbuckle() -> Dictionary:
	var friend := 0
	for peer_id: int in Net.peer_ids():
		if peer_id != Net.local_peer_id():
			friend = peer_id
	if friend == 0:
		return {"error": "van_unbuckle needs a friend in the van: start with -Observer"}
	var problem: String = await _to_lot()
	if problem != "":
		return {"error": problem}
	if Net.player_zone(friend) != Net.Zone.LOT:
		Net.move_player_to_zone(friend, Net.Zone.LOT)
		await get_tree().create_timer(0.5).timeout
	var van := _van()
	var trip := int(van.call("dev_park_now", true))
	await _ticks(3)
	van.call("dev_seat", trip, friend)
	var step: Vector3 = van.call("door_step_point")
	var pose: Transform3D = van.call("trip_pose", trip, Net.server_time())
	var stand := step + pose.basis.x.normalized() * DOOR_STAND_METERS
	_place(stand, _yaw_toward(stand, step + Vector3(0.0, 0.0, 0.0) - pose.basis.x * 2.0), -0.15)
	await _ticks(3)
	return {"note": "at the van's door with %s buckled in; hold interact %.1f s while the driver isn't checking his mirror" % [Net.player_name(friend), Constants.VAN_UNBUCKLE_HOLD], "friend": friend, "trip": trip}


func _reached_van_unbuckle() -> bool:
	var van := _van()
	if van == null:
		return false
	for peer_id: int in Net.peer_ids():
		if peer_id != Net.local_peer_id() and bool((van.call("seat_info", peer_id) as Dictionary).get("settled", false)):
			return true
	return false


## The van leaving with one NICE BOY still out on the lawn: it creeps on with its
## back doors open and he jogs after it and hops onto the bumper. You watch
## from behind it.
func _van_straggler() -> Dictionary:
	var problem: String = await _to_lot()
	if problem != "":
		return {"error": problem}
	var van := _van()
	var trip := int(van.call("dev_park_now", true))
	await _ticks(3)
	van.call("dev_crew", 2, [2])
	await get_tree().create_timer(3.0).timeout
	var pose: Transform3D = van.call("trip_pose", trip, Net.server_time())
	var stand := pose * STRAGGLER_WATCH
	_place(Vector3(stand.x, pose.origin.y + 0.1, stand.z), _yaw_toward(stand, pose * Vector3(0.0, 0.0, 3.0)), -0.1)
	van.call("dev_straggle", 2)
	van.call("host_depart", Net.server_time() + 1.0)
	await _ticks(2)
	return {"note": "the van pulls out in 1 s with Crew2 still out; it creeps, he hops on the bumper", "trip": trip}


func _reached_van_straggler() -> bool:
	var van := _van()
	return van != null and str(van.call("leg_name", int(van.call("raid_trip_id")))) in ["parked", "creep"]


## Riding home: the shuttle pulling up at the yard's curb, you aboard; it parks,
## the door slides, you unbuckle and step down onto the curb.
func _dropoff() -> Dictionary:
	var problem: String = await _to_lot()
	if problem != "":
		return {"error": problem}
	var van := _van()
	var trip := int(van.call("dev_dropoff", [Net.local_peer_id()]))
	var sat: Variant = await _wait_for(func() -> Variant:
		return true if not (van.call("seat_info", Net.local_peer_id()) as Dictionary).is_empty() else null)
	if sat == null:
		return {"error": "not aboard the return shuttle"}
	return {"note": "aboard the return shuttle pulling up at the yard; it drops you at the curb", "trip": trip}


func _reached_dropoff() -> bool:
	var van := _van()
	return van != null and not (van.call("seat_info", Net.local_peer_id()) as Dictionary).is_empty()


## Satellite Annex B (R2 chunk 6): you're through the door with Form 27-B in your
## hands, a step back from the counter of the window your first box needs. The
## visit starts the way the shuttle starts it (Annex.begin), with a fixed raid
## seed so a recording shows the same room every time.
func _annex() -> Dictionary:
	var started: Dictionary = await _annex_start([Net.local_peer_id()])
	if started.has("error"):
		return started
	var annex := _annex_node()
	var form: Dictionary = annex.call("form_of", Net.local_peer_id())
	var window := str(preload("res://net/annex/form_state.gd").next_window(form))
	_stand_by(_annex_point("Windows/%s/Counter" % window), _annex_point("Windows/%s/ClerkSeat" % window), 1.4)
	await _ticks(3)
	return {"moment": "annex", "note": "Form 27-B in hand, window %s ahead (%d boxes)" % [window, (form["boxes"] as PackedStringArray).size()], "window": window, "zone": _zone(), "annex": annex.call("status")}


func _reached_annex() -> bool:
	var annex := _annex_node()
	return annex != null and bool(annex.call("is_active")) and str(annex.call("stage_of", Net.local_peer_id())) == "inside" and _zone() == "BORDER"


## A clerk about to stand up and stretch for his break: the window your next box
## needs, its telegraph 2 s away.
func _annex_break() -> Dictionary:
	var started: Dictionary = await _annex()
	if started.has("error"):
		return started
	var annex := _annex_node()
	var window := str(started["window"])
	var at := _find_state(annex, window, [_Sched.S.TELEGRAPH], [_Sched.S.BREAK, _Sched.S.JAM, _Sched.S.ASLEEP])
	if at < 0.0:
		return {"error": "no break coming at window %s" % window}
	annex.call("dev_retime", at - 2.0)
	_annex_window = window
	await _ticks(3)
	return {"moment": "annex_break", "note": "window %s's clerk telegraphs his break in 2 s" % window, "window": window}


## His stretch is on now or within 3 s, and a break (or jam, or nap) follows it.
func _reached_annex_break() -> bool:
	if not _reached_annex() or _annex_window == "":
		return false
	var annex := _annex_node()
	var seed_value := int(annex.call("seed_value"))
	var now: Dictionary = annex.call("window_now", _annex_window)
	var telegraph := now
	if int(now["state"]) != _Sched.S.TELEGRAPH:
		var wait := float(now["until"]) - float(annex.call("elapsed"))
		if wait <= 0.0 or wait > 3.0:
			return false
		telegraph = _Sched.window_state(seed_value, _annex_window, float(now["until"]) + 0.01)
		if int(telegraph["state"]) != _Sched.S.TELEGRAPH:
			return false
	var after := int(_Sched.window_state(seed_value, _annex_window, float(telegraph["until"]) + 0.01)["state"])
	return [_Sched.S.BREAK, _Sched.S.JAM, _Sched.S.ASLEEP].has(after)


## A heist: your next box's clerk is on the phone or away, and you're at his stamp.
func _annex_heist() -> Dictionary:
	var started: Dictionary = await _annex()
	if started.has("error"):
		return started
	var annex := _annex_node()
	var window := str(started["window"])
	var at := _find_state(annex, window, [_Sched.S.PHONE, _Sched.S.BREAK], [])
	if at < 0.0:
		return {"error": "window %s never looks away" % window}
	annex.call("dev_retime", at + 0.3)
	_annex_window = window
	_stand_by(_annex_point("Windows/%s/StampPad" % window), _annex_point("Windows/%s/ClerkSeat" % window), 0.25)
	await _ticks(3)
	return {"moment": "annex_heist", "note": "window %s's clerk is looking away; hold interact on his stamp" % window, "window": window}


## His clerk is looking away right now.
func _reached_annex_heist() -> bool:
	if not _reached_annex() or _annex_window == "":
		return false
	return not bool((_annex_node().call("window_now", _annex_window) as Dictionary)["looking"])


## The Head NICE BOY just went to the copier: a full form, and his big stamp on its pad in front of you.
func _annex_bigstamp() -> Dictionary:
	var started: Dictionary = await _annex()
	if started.has("error"):
		return started
	var annex := _annex_node()
	var at := _find_state(annex, "head", [_Sched.S.AWAY], [])
	if at < 0.0:
		return {"error": "the Head NICE BOY never leaves his desk"}
	annex.call("dev_retime", at + 1.5)
	var form: Dictionary = annex.call("form_of", Net.local_peer_id())
	form["stamped"] = (form["boxes"] as PackedStringArray).size() - 1
	annex.call("dev_set_form", Net.local_peer_id(), form)
	_stand_by(_annex_point("HeadDesk/Pad"), _annex_point("HeadDesk"), 0.9)
	await _ticks(3)
	return {"moment": "annex_bigstamp", "note": "he's away; interact lifts his big stamp, primary stamps"}


## He's away from his desk, and his big stamp is still on its pad.
func _reached_annex_bigstamp() -> bool:
	if not _reached_annex():
		return false
	var annex := _annex_node()
	return int((annex.call("window_now", "head") as Dictionary)["state"]) == _Sched.S.AWAY and int(annex.call("big_stamp_holder")) == 0


## Window D's blinds go up in 2 s; you're halfway across the room.
func _annex_window_d() -> Dictionary:
	var started: Dictionary = await _annex()
	if started.has("error"):
		return started
	var annex := _annex_node()
	var d_at := float(preload("res://net/annex/annex_schedule.gd").d_open_at(int(annex.call("seed_value"))))
	annex.call("dev_retime", d_at - 2.0)
	_stand_by(_annex_point("Windows/D/Counter"), _annex_point("Windows/D/ClerkSeat"), 4.0)
	await _ticks(3)
	return {"moment": "annex_window_d", "note": "Window D opens in 2 s"}


## Window D's blinds go up within 3 s.
func _reached_annex_window_d() -> bool:
	if not _reached_annex():
		return false
	var annex := _annex_node()
	var wait := _Sched.d_open_at(int(annex.call("seed_value"))) - float(annex.call("elapsed"))
	return wait > 0.0 and wait <= 3.0


## A friend at the Annex (the second player is the rider), and you at the visitor
## door: the Field Office's in the town, the Courtesy Desk by Homie Depot otherwise.
func _annex_visit() -> Dictionary:
	var friend := 0
	for peer_id: int in Net.peer_ids():
		if peer_id != Net.local_peer_id():
			friend = peer_id
			break
	if friend == 0:
		return {"error": "annex_visit needs a second player to be the one at the Annex (tools\\play.ps1 -Observer)"}
	if not bool(_world().call("is_town_map")):
		Net.move_player_to_zone(Net.local_peer_id(), Net.Zone.STORE)
		await _wait_for(func() -> Variant: return true if Net.player_zone(Net.local_peer_id()) == Net.Zone.STORE else null)
	var started: Dictionary = await _annex_start([friend])
	if started.has("error"):
		return started
	await _ticks(3)
	var door: Node3D = null
	for node: Node in get_tree().get_nodes_in_group("annex_doors"):
		door = node as Node3D
	if door == null:
		return {"error": "no visitor door"}
	var out: Transform3D = door.call("out_transform")
	_place(out.origin, out.basis.get_euler().y + PI, -0.05)
	await _ticks(3)
	return {"moment": "annex_visit", "note": "%s is at Annex B; the door in front of you lets you in" % Net.player_name(friend)}


func _reached_annex_visit() -> bool:
	var annex := _annex_node()
	return annex != null and bool(annex.call("is_active")) and not get_tree().get_nodes_in_group("annex_doors").is_empty()


## Closing time in 10 s: the clock races, the lights flicker.
func _annex_closing() -> Dictionary:
	var started: Dictionary = await _annex()
	if started.has("error"):
		return started
	var annex := _annex_node()
	var status: Dictionary = annex.call("status")
	annex.call("dev_retime", Constants.ANNEX_CAP_SECONDS - 10.0)
	await _ticks(3)
	return {"moment": "annex_closing", "note": "closing time in 10 s", "was": status}


func _reached_annex_closing() -> bool:
	var annex := _annex_node()
	return _reached_annex() and bool(annex.call("urgent"))


## Begin a visit for these riders the way the shuttle does, and wait for the walk-in.
func _annex_start(riders: Array) -> Dictionary:
	var annex := _annex_node()
	var director := _director()
	if annex == null or director == null:
		return {"error": "no Annex (net/annex/annex.gd) in this world"}
	if bool(annex.call("is_active")):
		annex.rpc("_rpc_end")
		await _ticks(2)
	director.set("_hazard_seed", ANNEX_SEED)
	annex.call("begin", ANNEX_TRIP, riders, Net.server_time())
	var first := int(riders[0])
	var inside: Variant = await _wait_for(func() -> Variant:
		return true if str(annex.call("stage_of", first)) == "inside" else null)
	if inside == null:
		return {"error": "the walk-in never finished (stage %s)" % annex.call("stage_of", first)}
	return {}


## The schedule's first moment from now on where the window enters one of states
## (followed by one of then, when given). -1 when there's none in the day.
func _find_state(annex: Node, window: String, states: Array, then: Array) -> float:
	var seed_value := int(annex.call("seed_value"))
	var t := float(annex.call("elapsed")) + 1.0
	while t < Constants.ANNEX_CAP_SECONDS - 12.0:
		var state := _Sched.window_state(seed_value, window, t)
		if states.has(int(state["state"])):
			if then.is_empty() or then.has(int(_Sched.window_state(seed_value, window, float(state["until"]) + 0.01)["state"])):
				return float(state["since"])
			t = float(state["until"]) + 0.01
			continue
		t = float(state["until"]) + 0.01
	return -1.0


## Stand back from a spot, facing what it faces (toward look_at), on the floor.
func _stand_by(spot: Vector3, look_at: Vector3, back: float) -> void:
	if spot == Vector3.INF:
		return
	var away := Vector3(spot.x - look_at.x, 0.0, spot.z - look_at.z).normalized() if look_at != Vector3.INF else Vector3.BACK
	var at := spot + away * back
	_place(Vector3(at.x, spot.y + 0.1, at.z), _yaw_toward(at, spot - away * 2.0), -0.12)


func _annex_node() -> Node:
	return get_tree().get_first_node_in_group("annex")


func _annex_point(path: String) -> Vector3:
	var set_root := _world().get_node_or_null("BorderZone/AnnexSet")
	var node := set_root.get_node_or_null(path) as Node3D if set_root != null else null
	return node.global_position if node != null else Vector3.INF


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
## visit to Annex B, a hiding spot, a seat), so each scenario starts clean.
func reset() -> void:
	var me_id := Net.local_peer_id()
	var me := _me()
	var director := _director()
	var annex := _annex_node()
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
		if bool(director.call("is_captured", me_id)) or _van() != null:
			# Off the van and out of the cohort, on every peer (the director's own message).
			director.rpc("_rpc_drop_rider", me_id)
		# No raid, no catches, no crew (R2 chunk 2: the director's own reset).
		director.call("dev_reset")
		await _ticks(2)
	if annex != null and bool(annex.call("is_active")):
		# Closed up, and everyone it held back where the game would send them.
		var held: Array = annex.call("roster")
		held.append_array(annex.call("visitors"))
		annex.rpc("_rpc_end")
		for peer_id: Variant in held:
			if Net.player_zone(int(peer_id)) == Net.Zone.BORDER:
				Net.move_player_to_zone(int(peer_id), Net.Zone.STORE)
	# Every Courtesy Shuttle trip gone at once, riders let go where they sit.
	var van := _van()
	if van != null:
		van.call("dev_reset")
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
	# Backdated first, then the call makes the crew (seated in the van): the
	# Courtesy Shuttle plans its van's arrival from the director's arrival time, so
	# it pulls up in lead seconds too (made the other way round, it arrived a whole
	# warning later and the crew got out long after the chase began).
	var fresh := int(director.call("phase")) == 0
	director.rpc("_rpc_phase", 1, Net.server_time() - (Constants.RUN_WARNING_SECONDS - lead), _Strings.UI["status_crew_coming"])
	if fresh:
		# What _begin_warning resets, without its own (un-backdated) phase message.
		director.set("_raid_caught", 0)
		director.set("_first_seat_at", -1.0)
		(director.get("_spotted") as Dictionary).clear()
		(director.get("_hops") as Array).clear()
		director.call("_spawn_crew")


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


## The Courtesy Shuttle (net/run_events/shuttle.gd).
func _van() -> Node:
	return get_tree().get_first_node_in_group("nice_shuttle")


func _crew() -> Node3D:
	var crew := get_tree().get_nodes_in_group("crew")
	return crew[0] as Node3D if not crew.is_empty() else null


func _phase() -> String:
	return ["QUIET", "WARNING", "CHASE", "DEPARTING"][clampi(int(_director().call("phase")), 0, 3)]


func _zone() -> String:
	return Net.Zone.keys()[Net.player_zone(Net.local_peer_id())]


func _v(at: Vector3) -> Array:
	return [snappedf(at.x, 0.01), snappedf(at.y, 0.01), snappedf(at.z, 0.01)]
