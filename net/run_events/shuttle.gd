extends Node3D

## Authority: host for trips (where the van goes, when, and who sits where);
## every peer draws them. World/RunDirector/Shuttle, group "nice_shuttle"
## (nice_boys:4, docs/GAME.md "The Courtesy Shuttle, door to door"; contract C12 in
## gap-specs/nice_boys.json). It absorbs net/run_events/van_arrival.gd.
##
## One van per trip, from pull-up to drive-off. A trip is a list of legs, each
## {k: Leg, t: server time it starts, ...}: a moving leg carries its route (ground
## points the host checked) and a speed profile from v0 through constant-acceleration
## segments; a standing leg carries its pose. The van's pose is a pure function of
## (legs, Net.server_time()) on every peer, so it never needs a position stream, and
## every leg is sent VAN_PLAN_LEAD ahead (_rpc_plan), so a 150 ms client never sees a
## leg start late and jump back. A peer that first sees a trip mid-leg snaps once.
##
## The legs: ARRIVE (from out of sight down the real street, braking to the clear
## curb), PARKED (door, crew out, the hold), DEPART (door shut, blinker, a lawful
## pull-out to a route end out of everyone's sight), CREEP (back doors open for a
## straggler), HIDDEN (stopped at the route end), ANNEX_ARRIVE / ANNEX_PARKED (Annex
## B's curb), RETURN_DEPART, DROP_ARRIVE / DROP_PARKED (the curb back home), LEAVE.
##
## Who rides is the host's: host_board(peer) seats a caught player (_rpc_seat), every
## peer places the body from the van's seat anchor (player.set_staged, nice_boys:1;
## without it the "rides" group seats it), the owner's camera sits in the seat
## (stage_push &'van_seat') and their primary knocks on the glass. A free friend at
## the door holding interact unbuckles a rider, unless the driver is checking his
## mirror or a NICE BOY who can see them is close. Riders' zone moves happen behind
## their iris (group 'iris'), the van out of sight of the yard. The crew ride the same
## way (crew.set_staged, nice_boys:2; a fallback here until then) and the driver is
## the van's own: a local NICE BOY who never leaves the wheel.
##
## Never faded: each peer stops drawing its van only when its own camera can't see
## it, and a van that has to jump (a leg in another zone) waits for that too.
## Cross-chunk calls go through groups and has_method (the director, 'nice_encounter',
## 'annex', 'iris', 'caption_stack'), so any merge order compiles and runs.

signal riders_at_annex(trip_id: int, riders: Array)
signal dropped_off(peer_id: int)

const _NiceVan = preload("res://props/nice_van.gd")
const _VanGestures = preload("res://props/van_gestures.gd")
const _CrewMember = preload("res://npcs/crew_member.gd")
const _CartoonBody = preload("res://player/cartoon_body.gd")
const _Sfx = preload("res://audio/sfx.gd")
const _Trees = preload("res://props/trees.gd")
const _Strings = preload("res://ui/strings.gd")
const CREW_SCENE: PackedScene = preload("res://npcs/crew_member.tscn")

enum Leg { ARRIVE, PARKED, DEPART, CREEP, HIDDEN, ANNEX_ARRIVE, ANNEX_PARKED, RETURN_DEPART, DROP_ARRIVE, DROP_PARKED, LEAVE }
const LEG_NAMES: Array[String] = ["arrive", "parked", "depart", "creep", "hidden", "annex_arrive", "annex_parked", "return_depart", "drop_arrive", "drop_parked", "leave"]
const MOVING: Array[int] = [Leg.ARRIVE, Leg.DEPART, Leg.CREEP, Leg.ANNEX_ARRIVE, Leg.RETURN_DEPART, Leg.DROP_ARRIVE, Leg.LEAVE]
## The run director's phases (net/run_events/director.gd; DEPARTING comes with nice_boys:2).
const PHASE_QUIET: int = 0
const PHASE_WARNING: int = 1
const PHASE_CHASE: int = 2
## Encounter stages (C7, net/run_events/encounter.gd, nice_boys:2).
const STAGE_BOARDING: int = 5
const STAGE_SEATED: int = 6
const STAGE_RIDING: int = 7
const STAGE_RETURNING: int = 9
const STAGE_FREE: int = 10
## A rider's seat entry: how they get there.
const BOARD_STEP: int = 0
const BOARD_WALK: int = 1
const BOARD_NOW: int = 2
## A crew entry: seated, climbing in from where they stand, climbing out, on the bumper.
const CREW_SEATED: int = 0
const CREW_HOP_IN: int = 1
const CREW_HOP_OUT: int = 2
const CREW_REAR: int = 3
## Stage-cam shot priorities (C2).
const SHOT_SEAT: StringName = &"van_seat"
const SHOT_FRESHENER: StringName = &"freshener"
## The ground a route is checked against: a ray this far above the road down this far.
const GROUND_PROBE := Vector2(1.0, 3.0)

## For tests and the probe: trips started, the fastest and longest step the van
## made where this peer could see it, how far parking slid, and more.
static var stats: Dictionary = {}

var _trips: Dictionary = {}
var _next_trip_id: int = 1
## The trip the raid uses (the van at the yard), or 0.
var _raid_trip: int = 0
var _last_phase: int = -1
var _phase_seen_at: float = -1.0
## Host: the park point and the raid it was worked out for.
var _park_cache: Dictionary = {}
## Host: peers already put in a van this raid by the fallback (no Encounter).
var _handled: Dictionary = {}
## Host: unbuckle holds, rescuer -> {target, trip, at}.
var _holds: Dictionary = {}
## Local: our own unbuckle hold {trip, target, at}, and when we last knocked.
var _my_hold: Dictionary = {}
var _knocked_at: float = -10.0
## Local: the radio loop for the ride montage.
var _radio: AudioStreamPlayer
static var _has_staging: int = -1


class Trip extends RefCounted:
	var id: int = 0
	var legs: Array = []
	var info: Dictionary = {}
	## peer -> {seat, at, mode, from (VanLook space), state}
	var seats: Dictionary = {}
	## peer -> {at, exit (world)}
	var unseats: Dictionary = {}
	## crew index -> {seat, at, mode, from (VanLook space), land}
	var crew: Dictionary = {}
	var doors: Dictionary = {"side": [false, -1000.0], "back": [false, -1000.0]}
	var knocks: Dictionary = {}
	var holder: Node3D
	var look: Node3D
	var driver: Node3D
	var anchors: Dictionary = {}
	var placed: bool = false
	var hidden_local: bool = false
	var drawn := Transform3D()
	var last_drawn := Vector3.INF
	var played: Dictionary = {}
	var staged_pose: Dictionary = {}
	var crew_staged: Dictionary = {}
	var my_beats: Dictionary = {}
	var ended: bool = false
	var ended_at: float = 0.0
	# Host bookkeeping.
	var annex_called: bool = false
	var moved_zone: bool = false
	var dropping: Dictionary = {}
	var depart_planned: bool = false
	var last_seat_done: float = -1.0
	var creep_started: float = -1.0


func _enter_tree() -> void:
	# The pre-R2 director makes this as "VanArrival" (the shim); every peer renames
	# it the same way, so the RPC paths agree.
	name = "Shuttle"


func _ready() -> void:
	add_to_group("nice_shuttle")
	# Kept for anything still looking for the old arrival (cast_test, playtests).
	add_to_group("van_arrival")
	top_level = true
	# After the default priority (the director, the crew) and before the players
	# (100) and their staged bodies (110), so a seat anchor is where the van is now.
	process_physics_priority = 50
	process_priority = 50
	_VanGestures.register()
	if not _player_has_staging():
		add_to_group("rides")
	stats = {"trips": 0, "max_speed_on_screen": 0.0, "max_step_m": 0.0, "park_slides": 0.0, "seats": 0, "knocks": 0,
		"unbuckles": 0, "unbuckle_refused": 0, "stragglers": 0, "zone_moves": [], "drops": 0, "freed_trips": 0, "route_ground_misses": 0,
		"legs_seen": [], "snaps": 0}
	if not Net.player_left.is_connected(_on_player_left):
		Net.player_left.connect(_on_player_left)
	# Without the director's late-join state (nice_boys:2) a client asks for ours.
	if not Net.is_host() and multiplayer.multiplayer_peer != null:
		var director := get_parent()
		if director == null or not director.has_method("_rpc_request_state"):
			_rpc_request_snapshot.rpc_id(1)


# ---------------------------------------------------------------- the contract (C12)


## Where the raid van parks: the curb nearest the noisiest player, slid along the
## curb until a VAN_PARK_CLEARANCE box is clear. Host-computed and cached per raid;
## every other peer gets it in the plan.
func park_point() -> Vector3:
	var trip := _trip(_raid_trip)
	if trip != null and trip.info.has("park"):
		return (trip.info["park"] as Transform3D).origin
	if not Net.is_host():
		return _default_curb().origin
	return _host_park().origin


## The ground outside the raid van's door, where escorts bring people (C12).
## While it creeps for a straggler, the bumper.
func door_step_point() -> Vector3:
	var trip := _trip(_raid_trip)
	if trip == null:
		return park_point()
	var leg := _current_leg(trip, Net.server_time())
	var pose := _pose(trip, Net.server_time())
	if not leg.is_empty() and int(leg["k"]) == Leg.CREEP:
		return pose * _local_marker(trip, "RearStep").origin
	return pose * _local_marker(trip, "DoorStep").origin


## Host: spawns the raid's crew already seated in the van (which is out of
## everyone's sight at the start of its arrival). Returns them.
func host_spawn_crew(count: int) -> Array[Node]:
	var out: Array[Node] = []
	if not Net.is_host():
		return out
	var trip := _ensure_raid_trip()
	var world := _world()
	var npcs := world.get_node_or_null("Npcs") if world != null else null
	if trip == null or npcs == null:
		return out
	var pose := _pose(trip, Net.server_time())
	for index: int in clampi(count, 1, Constants.HEAT_MAX_CREW):
		var crew_name := "Crew%d" % (index + 1)
		var crew := npcs.get_node_or_null(crew_name)
		if crew == null:
			crew = CREW_SCENE.instantiate()
			crew.name = crew_name
			var seat := _local_marker(trip, "CrewSeats/Seat%d" % mini(index, 2))
			(crew as Node3D).position = (pose * seat * _crew_turn()).origin
			npcs.add_child(crew, true)
		out.append(crew)
		_rpc_crew_seat.rpc(trip.id, index + 1, mini(index, 2), Net.server_time(), CREW_SEATED, Vector3.ZERO)
	return out


## Host: a recalled NICE BOY at the door (or the bumper of a creeping van) climbs
## back in (C8).
func host_crew_board(crew: Node) -> void:
	var trip := _trip(_raid_trip)
	if not Net.is_host() or trip == null or crew == null or not crew.has_method("crew_index"):
		return
	var index := int(crew.call("crew_index"))
	var entry: Dictionary = trip.crew.get(index, {})
	if not entry.is_empty() and int(entry["mode"]) != CREW_HOP_OUT:
		return
	var now := Net.server_time() + Constants.VAN_PLAN_LEAD * 0.5
	var leg := _current_leg(trip, now)
	var local := _pose(trip, now).affine_inverse() * (crew as Node3D).global_position
	if not leg.is_empty() and int(leg["k"]) == Leg.CREEP:
		_rpc_crew_seat.rpc(trip.id, index, -1, now, CREW_REAR, local)
		stats["stragglers"] = int(stats["stragglers"]) + 1
	else:
		_rpc_crew_seat.rpc(trip.id, index, _free_crew_seat(trip, index), now, CREW_HOP_IN, local)


## Host: seats a caught player in the raid van (C12). They step up from where
## they stand. Returns the seat, or -1 (no van, or it's full).
func host_board(peer_id: int) -> int:
	return _host_board(_raid_trip, peer_id, BOARD_STEP)


## Who sits in any van now, fully seated (every peer).
func seated_riders() -> Array:
	var out: Array = []
	var now := Net.server_time()
	for trip: Trip in _trips.values():
		for peer_id: Variant in trip.seats.keys():
			if not trip.unseats.has(peer_id) and _seat_settled(trip, int(peer_id), now):
				out.append(int(peer_id))
	return out


## Everyone a van has taken, still in it or getting in (every peer).
func boarded_riders() -> Array:
	var out: Array = []
	for trip: Trip in _trips.values():
		for peer_id: Variant in trip.seats.keys():
			if not trip.unseats.has(peer_id):
				out.append(int(peer_id))
	return out


## Host: the raid van leaves at server time at (C12): the door slides shut, the
## blinker ticks, and it pulls out; a NICE BOY still out makes it creep with its
## back doors open first. Still pulling up, it drives on past instead.
func host_depart(at: float) -> void:
	var trip := _trip(_raid_trip)
	if not Net.is_host() or trip == null or trip.depart_planned:
		return
	trip.depart_planned = true
	var start := maxf(at, Net.server_time() + Constants.VAN_PLAN_LEAD)
	var leg := _current_leg(trip, start)
	if not leg.is_empty() and int(leg["k"]) == Leg.ARRIVE:
		_plan_drive_on(trip, start)
		return
	_plan_departure(trip, start, Leg.DEPART)


## True once the raid's van is out of sight at the end of its route, or there is
## none (C12): the director frees what's left of the crew then.
func is_gone() -> bool:
	var trip := _trip(_raid_trip)
	if trip == null:
		return true
	var leg := _current_leg(trip, Net.server_time())
	return not leg.is_empty() and int(leg["k"]) in [Leg.HIDDEN, Leg.ANNEX_ARRIVE, Leg.ANNEX_PARKED, Leg.LEAVE] and _leg_done(trip, Net.server_time())


## Host, from the Annex (C13): these peers ride home. A return van waits at the
## Annex forecourt; they climb in, it waits RETURN_WAIT after the last one sits,
## and drops them at to = {zone, marker} (LOT or TOWN: the yard's curb; STORE: the
## Homie Depot stop).
func host_start_return(peers: Array, to: Dictionary) -> void:
	if not Net.is_host() or peers.is_empty():
		return
	var trip := _return_trip(true)
	if trip == null:
		return
	trip.info["drop"] = to.duplicate()
	_rpc_info.rpc(trip.id, trip.info)
	for peer_id: Variant in peers:
		_host_board(trip.id, int(peer_id), BOARD_STEP)
		_stage(int(peer_id), STAGE_RETURNING)


## The trips' state for a late joiner (C6: the director's _rpc_state carries it).
func snapshot() -> Dictionary:
	var trips: Array = []
	for trip: Trip in _trips.values():
		if trip.ended:
			continue
		trips.append({"id": trip.id, "legs": trip.legs, "info": trip.info, "seats": trip.seats, "unseats": trip.unseats,
			"crew": trip.crew, "doors": trip.doors})
	return {"trips": trips, "next": _next_trip_id, "raid": _raid_trip}


func apply_snapshot(data: Dictionary) -> void:
	if Net.is_host():
		return
	_raid_trip = int(data.get("raid", 0))
	_next_trip_id = maxi(_next_trip_id, int(data.get("next", 1)))
	for entry: Variant in data.get("trips", []):
		var d := entry as Dictionary
		var trip := _make_trip(int(d["id"]))
		trip.legs = (d.get("legs", []) as Array).duplicate(true)
		trip.info = (d.get("info", {}) as Dictionary).duplicate(true)
		trip.seats = _int_keys(d.get("seats", {}))
		trip.unseats = _int_keys(d.get("unseats", {}))
		trip.crew = _int_keys(d.get("crew", {}))
		trip.doors = (d.get("doors", trip.doors) as Dictionary).duplicate(true)
		trip.placed = false


# ---------------------------------------------------------------- reading it


## The raid van as drawn now (VanLook), or null. For tests and the recorder.
func van_look() -> Node3D:
	var trip := _trip(_raid_trip)
	return trip.look if trip != null and trip.placed and not trip.hidden_local else null


## The trip ids in play now.
func trip_ids() -> Array:
	return _trips.keys()


func raid_trip_id() -> int:
	return _raid_trip


## The current leg's name for a trip ("" before it starts or for no trip), and the
## old arrival's words for the raid van ("arriving", "parked", "leaving", "").
func leg_name(trip_id: int) -> String:
	var trip := _trip(trip_id)
	if trip == null:
		return ""
	var leg := _current_leg(trip, Net.server_time())
	return LEG_NAMES[int(leg["k"])] if not leg.is_empty() else ""


func state_name() -> String:
	match leg_name(_raid_trip):
		"arrive":
			return "arriving"
		"parked":
			return "parked"
		"":
			return ""
	return "leaving"


## The van's world pose for a trip at server time t: the same on every peer.
func trip_pose(trip_id: int, t: float) -> Transform3D:
	var trip := _trip(trip_id)
	return _pose(trip, t) if trip != null else Transform3D()


## The route points of every moving leg of a trip (tests check the ground under them).
func trip_routes(trip_id: int) -> Array:
	var out: Array = []
	var trip := _trip(trip_id)
	if trip == null:
		return out
	for leg: Dictionary in trip.legs:
		if leg.has("p"):
			out.append(leg["p"])
	return out


func trip_info(trip_id: int) -> Dictionary:
	var trip := _trip(trip_id)
	return trip.info.duplicate() if trip != null else {}


## Which trip and seat a peer is in, {} when none.
func seat_info(peer_id: int) -> Dictionary:
	for trip: Trip in _trips.values():
		if trip.seats.has(peer_id):
			var entry: Dictionary = trip.seats[peer_id]
			return {"trip": trip.id, "seat": int(entry["seat"]), "settled": _seat_settled(trip, peer_id, Net.server_time()), "leaving": trip.unseats.has(peer_id)}
	return {}


## The world transform of a rider's or crew member's anchor now ("p<peer>" or
## "c<index>"), or an empty transform.
func anchor_transform(trip_id: int, key: String) -> Transform3D:
	var trip := _trip(trip_id)
	if trip == null or not trip.anchors.has(key):
		return Transform3D()
	return (trip.anchors[key] as Node3D).global_transform


## True while the driver is looking at his mirror (a pure function of the trip and
## the clock, the same on every peer). glint: the VAN_GLINT_LEAD before counts too.
func mirror_checking(trip_id: int, t: float, glint: bool = false) -> bool:
	var trip := _trip(trip_id)
	if trip == null:
		return false
	var hold := _hold_leg(trip, t)
	if hold.is_empty():
		return false
	var window := mirror_window(trip.id, t - float(hold["t"]))
	var lead := Constants.VAN_GLINT_LEAD if glint else 0.0
	var rel := t - float(hold["t"])
	return rel >= window.x - lead and rel < window.y


## The mirror check that is on now or comes next, [start, end) in seconds after
## the hold began, seeded by the trip: every VAN_MIRROR_EVERY for VAN_MIRROR_SECONDS.
static func mirror_window(trip_id: int, rel: float) -> Vector2:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash("mirror%d" % trip_id)
	var start := rng.randf_range(Constants.VAN_MIRROR_EVERY.x, Constants.VAN_MIRROR_EVERY.y)
	while start + Constants.VAN_MIRROR_SECONDS <= rel:
		start += Constants.VAN_MIRROR_SECONDS + rng.randf_range(Constants.VAN_MIRROR_EVERY.x, Constants.VAN_MIRROR_EVERY.y)
	return Vector2(start, start + Constants.VAN_MIRROR_SECONDS)


# ---------------------------------------------------------------- dev and tests (host)


## A raid van parked at the yard's curb right now, door open, holding until told
## to go (host_depart). Returns its trip id. Scenarios and tests only: it isn't
## seen arriving.
func dev_park_now(door_open: bool = true) -> int:
	if not Net.is_host():
		return 0
	var now := Net.server_time()
	_park_cache.clear()
	var trip := _new_trip("raid")
	var park := _host_park()
	trip.info["park"] = park
	trip.info["zone"] = Net.Zone.LOT
	trip.info["dev_hold"] = true
	trip.legs = [{"k": Leg.PARKED, "t": now, "x": park}]
	_raid_trip = trip.id
	_send_plan(trip)
	_rpc_raid.rpc(trip.id)
	if door_open:
		_host_door(trip, "side", true, now - Constants.VAN_DOOR_SLIDE)
	return trip.id


## Seats a peer in a trip at once (no walk, no step).
func dev_seat(trip_id: int, peer_id: int) -> int:
	return _host_board(trip_id, peer_id, BOARD_NOW)


## Puts NICE BOYS in the raid van's seats; climb_out lists the ones (1-based) that
## hop straight out.
func dev_crew(count: int, climb_out: Array = []) -> Array[Node]:
	var crew := host_spawn_crew(count)
	var trip := _trip(_raid_trip)
	var order := 0
	for index: Variant in climb_out:
		_rpc_crew_seat.rpc(trip.id, int(index), int((trip.crew.get(int(index), {"seat": 0}) as Dictionary)["seat"]), Net.server_time() + 0.3 + float(order) * Constants.CREW_UNLOAD_STAGGER, CREW_HOP_OUT, Vector3(float(order), 0.0, 0.0))
		order += 1
	return crew


## A NICE BOY jogs back to the raid van's bumper (the straggler, for scenarios and
## tests: the R2 crew brain does this itself on a recall).
func dev_straggle(crew_index: int) -> void:
	_dev_stragglers[crew_index] = true


## A return trip pulling up at the yard's curb right now with these peers aboard.
func dev_dropoff(peers: Array) -> int:
	if not Net.is_host():
		return 0
	var trip := _new_trip("return")
	trip.info["drop"] = {"zone": Net.Zone.LOT, "marker": ""}
	trip.info["zone"] = Net.Zone.LOT
	trip.moved_zone = true
	trip.depart_planned = true
	var curb := _drop_curb(Net.Zone.LOT)
	trip.legs = _arrival_legs(curb, Net.server_time() + Constants.VAN_PLAN_LEAD, -1.0, Leg.DROP_ARRIVE, Leg.DROP_PARKED, peers)
	_send_plan(trip)
	for peer_id: Variant in peers:
		_host_board(trip.id, int(peer_id), BOARD_NOW)
	return trip.id


## Skips a departing trip's drive: its riders move on now, as if out of sight.
func dev_skip_ride(trip_id: int) -> void:
	var trip := _trip(trip_id)
	if not Net.is_host() or trip == null:
		return
	trip.info["dev_skip"] = true
	var now := Net.server_time()
	_cut_legs(trip, now)
	trip.legs.append({"k": Leg.HIDDEN, "t": now, "x": _pose(trip, now)})
	_send_plan(trip)


## Every trip gone at once, riders and crew let go (scenario reset).
func dev_reset() -> void:
	if Net.is_host():
		_dev_stragglers.clear()
		_rpc_dev_reset.rpc()


@rpc("authority", "call_local", "reliable")
func _rpc_dev_reset() -> void:
	for trip: Trip in _trips.values():
		for peer_id: Variant in trip.seats.keys():
			_unstage_rider(trip, int(peer_id), false)
		for index: Variant in trip.crew.keys():
			_unstage_crew(trip, int(index))
		if trip.holder != null:
			trip.holder.queue_free()
	_trips.clear()
	_raid_trip = 0
	_handled.clear()
	_radio_on(false)


var _dev_stragglers: Dictionary = {}


func _dev_straggle_tick(delta: float) -> void:
	var trip := _trip(_raid_trip)
	if trip == null:
		return
	for index: Variant in _dev_stragglers.keys():
		var crew := _crew_node(int(index))
		var entry: Dictionary = trip.crew.get(int(index), {})
		if crew == null or entry.is_empty() or int(entry["mode"]) != CREW_HOP_OUT or str(trip.crew_staged.get(int(index), "")) != "done":
			continue
		var leg := _current_leg(trip, Net.server_time())
		if leg.is_empty() or int(leg["k"]) != Leg.CREEP:
			continue
		crew.set_physics_process(false)
		var goal := door_step_point()
		var flat := Vector3(goal.x - crew.global_position.x, 0.0, goal.z - crew.global_position.z)
		if flat.length() > 0.2:
			crew.global_position += flat.normalized() * minf(flat.length(), 4.5 * delta)
			crew.rotation.y = atan2(flat.x, flat.z)


# ---------------------------------------------------------------- the rides fallback


## Without staged bodies (player.set_staged, nice_boys:1) a rider is put on its
## seat the way rides do it (player.gd _current_seat): these three.
func seat_of(peer_id: int) -> int:
	if _player_has_staging():
		return -1
	var slot := 0
	for trip: Trip in _trips.values():
		if trip.seats.has(peer_id) and trip.anchors.has("p%d" % peer_id):
			return slot * 8 + int((trip.seats[peer_id] as Dictionary)["seat"])
		slot += 1
	return -1


func seat_transform(index: int) -> Transform3D:
	var slot := 0
	for trip: Trip in _trips.values():
		if slot == index / 8:
			for peer_id: Variant in trip.seats.keys():
				if int((trip.seats[peer_id] as Dictionary)["seat"]) == index % 8 and trip.anchors.has("p%d" % int(peer_id)):
					return (trip.anchors["p%d" % int(peer_id)] as Node3D).global_transform
		slot += 1
	return global_transform


func is_riding() -> bool:
	for trip: Trip in _trips.values():
		var leg := _current_leg(trip, Net.server_time())
		if not leg.is_empty() and int(leg["k"]) in MOVING and not trip.seats.is_empty():
			return true
	return false


# ---------------------------------------------------------------- every tick


func _physics_process(delta: float) -> void:
	if Net.current_state() != Net.State.IN_SESSION or multiplayer.multiplayer_peer == null:
		return
	var now := Net.server_time()
	if Net.is_host():
		_host_tick(now)
		_dev_straggle_tick(delta)
	for trip: Trip in _trips.values().duplicate():
		_draw_trip(trip, now, delta)
	_local_rider_beats(now)


func _process(_delta: float) -> void:
	if Net.current_state() != Net.State.IN_SESSION:
		return
	# The crew fallback draws their bodies here, from the interpolated anchors.
	for trip: Trip in _trips.values():
		_draw_crew_fallback(trip)
	_step_my_hold()


# ---------------------------------------------------------------- the host


func _host_tick(now: float) -> void:
	var director := get_parent()
	if director == null or not director.has_method("phase"):
		return
	var phase := int(director.call("phase"))
	var started := float(director.call("phase_started_at")) if director.has_method("phase_started_at") else now
	if phase != _last_phase or not is_equal_approx(started, _phase_seen_at):
		_on_phase(phase, started)
		_last_phase = phase
		_phase_seen_at = started
	var raid := _trip(_raid_trip)
	# The pre-R2 director caught someone with no raid on (a dev or test capture):
	# a van comes for them.
	if raid == null and not _director_has_r2() and not _encounter_present() and director.has_method("cohort_roster"):
		for peer_id: Variant in director.call("cohort_roster"):
			if not _handled.has(int(peer_id)) and seat_info(int(peer_id)).is_empty():
				raid = _ensure_raid_trip()
				break
	if raid != null:
		_host_raid(raid, director, phase, now)
	for trip: Trip in _trips.values().duplicate():
		_host_trip(trip, now)
	_host_holds(now)


func _on_phase(phase: int, started: float) -> void:
	match phase:
		PHASE_WARNING:
			_park_cache.clear()
			_handled.clear()
			var trip := _ensure_raid_trip()
			# The pre-R2 director spawns its crew at the chase, out of nowhere; the
			# shuttle brings them seated instead (nice_boys:2's director calls
			# host_spawn_crew itself).
			if trip != null and not _director_has_r2():
				var heat := get_tree().get_first_node_in_group("heat")
				host_spawn_crew(int(heat.call("crew_count")) if heat != null else 1)
		PHASE_CHASE:
			var trip := _ensure_raid_trip()
			if trip != null:
				var door_at := maxf(started, _arrive_end(trip))
				door_at = maxf(door_at, Net.server_time() + Constants.VAN_PLAN_LEAD)
				_host_door(trip, "side", true, door_at)
				# The crew climb out one by one once the door's half open.
				var order := 0
				var indices := trip.crew.keys()
				indices.sort()
				for index: Variant in indices:
					var entry: Dictionary = trip.crew[index]
					if int(entry["mode"]) == CREW_SEATED:
						var hop_at := door_at + Constants.VAN_DOOR_SLIDE * 0.6 + float(order) * Constants.CREW_UNLOAD_STAGGER
						_rpc_crew_seat.rpc(trip.id, int(index), int(entry["seat"]), hop_at, CREW_HOP_OUT, Vector3(float(order), 0.0, 0.0))
						order += 1


## The raid van's own decisions while the pre-R2 director runs (it has no hold,
## no recall and no departure call): seat whoever it caught, wait a moment, go.
func _host_raid(trip: Trip, director: Node, phase: int, now: float) -> void:
	if _director_has_r2() or trip.depart_planned or bool(trip.info.get("dev_hold", false)):
		return
	if not _encounter_present():
		for peer_id: Variant in director.call("cohort_roster"):
			var peer := int(peer_id)
			if _handled.has(peer) or _seat_info_any(peer) != null:
				continue
			_handled[peer] = true
			if _host_board(trip.id, peer, BOARD_WALK) >= 0:
				_stage(peer, STAGE_BOARDING)
	if phase != PHASE_QUIET:
		return
	# Called off or given up with nobody aboard: on its way at once. With riders:
	# once the last one has sat down for a moment.
	var waiting := false
	for peer_id: Variant in trip.seats.keys():
		if not _seat_settled(trip, int(peer_id), now - Constants.VAN_FALLBACK_HOLD):
			waiting = true
	if not waiting:
		host_depart(now)


## Every trip's timeline on the host: zone moves behind the iris, the Annex, the
## drop-off, the end.
func _host_trip(trip: Trip, now: float) -> void:
	if trip.ended:
		if now - trip.ended_at > 2.0:
			_trips.erase(trip.id)
		return
	var leg := _current_leg(trip, now)
	if leg.is_empty():
		return
	var kind := int(leg["k"])
	var riders := _riding_peers(trip)
	match kind:
		Leg.CREEP:
			_host_creep(trip, leg, now)
		Leg.HIDDEN:
			if not riders.is_empty() and not trip.moved_zone and _riders_iris_closed(trip, now):
				var sighted := _seen_by_yard(trip, now, riders) and not bool(trip.info.get("dev_skip", false))
				if not sighted or now - float(leg["t"]) >= Constants.VAN_HIDDEN_CAP:
					_host_move_riders(trip, now)
			elif riders.is_empty() and not trip.moved_zone and now - float(leg["t"]) >= 1.0:
				_host_end_trip(trip)
		Leg.ANNEX_PARKED:
			if not trip.annex_called and now >= float(leg["t"]):
				trip.annex_called = true
				_host_at_annex(trip, now)
		Leg.DROP_PARKED:
			_host_drop(trip, leg, now)
		Leg.LEAVE:
			if _leg_done(trip, now):
				_host_end_trip(trip)
	# The return van waits RETURN_WAIT after its last rider sits, then goes.
	if str(trip.info.get("purpose", "")) == "return" and kind == Leg.ANNEX_PARKED and not trip.depart_planned and not trip.seats.is_empty():
		var all_in := true
		for peer_id: Variant in trip.seats.keys():
			if not _seat_settled(trip, int(peer_id), now):
				all_in = false
		if all_in and trip.last_seat_done > 0.0 and now >= trip.last_seat_done + Constants.RETURN_WAIT:
			trip.depart_planned = true
			_plan_departure(trip, now + Constants.VAN_PLAN_LEAD, Leg.RETURN_DEPART)


func _host_creep(trip: Trip, leg: Dictionary, now: float) -> void:
	var pose := _pose(trip, now)
	var step := pose * _local_marker(trip, "RearStep").origin
	var out := 0
	for index: Variant in trip.crew.keys():
		var entry: Dictionary = trip.crew[index]
		if int(entry["mode"]) != CREW_HOP_OUT or now < float(entry["at"]) + _crew_hop_out_seconds(entry):
			continue
		var crew := _crew_node(int(index))
		if crew == null:
			continue
		out += 1
		var flat := Vector2(crew.global_position.x - step.x, crew.global_position.z - step.z).length()
		if flat <= Constants.VAN_DOOR_REACH + 0.4:
			host_crew_board(crew)
	var hopping := false
	for index: Variant in trip.crew.keys():
		var entry: Dictionary = trip.crew[index]
		if int(entry["mode"]) == CREW_REAR and now < float(entry["at"]) + Constants.VAN_HOP_SECONDS:
			hopping = true
	if trip.creep_started < 0.0:
		trip.creep_started = float(leg["t"])
	if not hopping and (out == 0 or now - trip.creep_started >= Constants.VAN_CREEP_MAX):
		# Everyone's on (or the straggler's on his own): doors shut, off it goes.
		var at := now + Constants.VAN_PLAN_LEAD
		_host_door(trip, "back", false, at)
		_plan_route_from(trip, at, Leg.DEPART, Constants.VAN_CREEP_SPEED)


## Behind every rider's closed iris, the van out of the yard's sight: the riders
## change zone and the van turns up at its next stop.
func _host_move_riders(trip: Trip, now: float) -> void:
	trip.moved_zone = true
	var returning := str(trip.info.get("purpose", "")) == "return"
	var drop: Dictionary = trip.info.get("drop", {})
	var zone: int = int(drop.get("zone", Net.Zone.LOT)) if returning else Net.Zone.BORDER
	for peer_id: int in _riding_peers(trip):
		Net.move_player_to_zone(peer_id, zone as Net.Zone, &"", false)
		(stats["zone_moves"] as Array).append({"peer": peer_id, "zone": zone, "at": snappedf(now, 0.01), "trip": trip.id})
	var at := now + Constants.VAN_PLAN_LEAD
	if returning:
		var curb := _drop_curb(zone)
		var arrive := _arrival_legs(curb, at, -1.0, Leg.DROP_ARRIVE, Leg.DROP_PARKED, _avoid_points(trip))
		trip.legs.append_array(arrive)
	else:
		var curb := _annex_curb("AnnexCurb")
		trip.legs.append_array(_roll_in_legs(curb, at))
	trip.info["zone"] = zone
	_send_plan(trip)


## At Annex B's curb: the door opens and the Annex takes the riders (C13); without
## it, the legacy Border Return does (world.on_ride_arrived).
func _host_at_annex(trip: Trip, now: float) -> void:
	var riders := _riding_peers(trip)
	var door_at := now + Constants.VAN_PLAN_LEAD
	_host_door(trip, "side", true, door_at)
	if str(trip.info.get("purpose", "")) == "return":
		return
	riders_at_annex.emit(trip.id, riders)
	var annex := get_tree().get_first_node_in_group("annex")
	if annex != null and annex.has_method("begin"):
		annex.call("begin", trip.id, riders, door_at + Constants.VAN_DOOR_SLIDE)
		# The Annex walks them off (its own staging); this van's seats are done.
		_rpc_release_riders.rpc(trip.id, door_at + Constants.VAN_DOOR_SLIDE)
		var forecourt := _annex_curb("ForecourtCurb")
		var curb := _annex_curb("AnnexCurb")
		if forecourt.origin.distance_to(curb.origin) > 3.0:
			_plan_leave(trip, door_at + Constants.VAN_DOOR_SLIDE + 3.0)
			_return_trip(true)
		return
	# The legacy crossing teleports them to its lanes: out of the seats first.
	_rpc_release_riders.rpc(trip.id, now)
	var world := _world()
	if world != null and world.has_method("on_ride_arrived"):
		world.call("on_ride_arrived", Net.Zone.BORDER)
	_plan_leave(trip, door_at + Constants.VAN_DOOR_SLIDE + 1.5)


## At the drop curb: the door, then each rider unbuckles and steps down, a beat
## apart; their immunity starts on the curb; the driver waves and it leaves.
func _host_drop(trip: Trip, leg: Dictionary, now: float) -> void:
	var start := float(leg["t"])
	if not trip.dropping.has("door"):
		trip.dropping["door"] = true
		_host_door(trip, "side", true, start + 0.2)
		var order := 0
		var pose := _pose(trip, start)
		for peer_id: int in _riding_peers(trip):
			var at := start + 0.2 + Constants.VAN_DOOR_SLIDE + float(order) * 0.45
			var exit := pose * (_local_marker(trip, "DoorStep").origin + Vector3(0.0, 0.0, -0.9 + float(order) * 0.75))
			_rpc_unseat.rpc(trip.id, peer_id, exit, at)
			trip.dropping[peer_id] = at + Constants.VAN_BUCKLE_SECONDS * 0.6 + Constants.VAN_STEP_SECONDS
			order += 1
		trip.dropping["leave_at"] = start + 0.2 + Constants.VAN_DOOR_SLIDE + float(order) * 0.45 + Constants.VAN_STEP_SECONDS + 1.6
		_rpc_beat.rpc(trip.id, "wave", start + 0.2 + Constants.VAN_DOOR_SLIDE + float(order) * 0.45 + Constants.VAN_STEP_SECONDS + 0.2)
	for key: Variant in trip.dropping.keys():
		if typeof(key) != TYPE_INT or typeof(trip.dropping[key]) != TYPE_FLOAT:
			continue
		if now >= float(trip.dropping[key]):
			var peer := int(key)
			trip.dropping[key] = true
			_release(peer, Constants.DROP_IMMUNITY)
			_stage(peer, STAGE_FREE)
			stats["drops"] = int(stats["drops"]) + 1
			dropped_off.emit(peer)
	if not trip.depart_planned and now >= float(trip.dropping.get("leave_at", INF)):
		trip.depart_planned = true
		_plan_leave(trip, now + Constants.VAN_PLAN_LEAD)


func _host_end_trip(trip: Trip) -> void:
	if trip.ended:
		return
	# Anyone still on board (a straggler on the bumper) goes with the van, out of sight.
	if not _director_has_r2():
		for index: Variant in trip.crew.keys():
			var crew := _crew_node(int(index))
			if crew != null and int((trip.crew[index] as Dictionary)["mode"]) != CREW_HOP_OUT:
				crew.queue_free()
	_rpc_end_trip.rpc(trip.id)
	stats["freed_trips"] = int(stats["freed_trips"]) + 1


func _host_holds(now: float) -> void:
	for rescuer: Variant in _holds.keys():
		var hold: Dictionary = _holds[rescuer]
		if now - float(hold["at"]) > Constants.VAN_UNBUCKLE_HOLD + 3.0:
			_holds.erase(rescuer)


# ---------------------------------------------------------------- planning (host)


func _ensure_raid_trip() -> Trip:
	var existing := _trip(_raid_trip)
	if existing != null and not existing.ended and not existing.depart_planned:
		return existing
	if not Net.is_host():
		return null
	var director := get_parent()
	var now := Net.server_time()
	var arrive_at := float(director.call("arrival_time")) if director != null and director.has_method("arrival_time") else -1.0
	var start := now + Constants.VAN_PLAN_LEAD
	if arrive_at < 0.0:
		# Caught with no raid on (dev and test captures): it pulls up as fast as
		# it can from out of sight.
		arrive_at = -1.0
	elif arrive_at - start < 3.0:
		# A warning set in the past (a scenario): the arrival started back then.
		start = float(director.call("phase_started_at"))
	var park := _host_park()
	var trip := _new_trip("raid")
	trip.info["park"] = park
	trip.legs = _arrival_legs(park, start, arrive_at, Leg.ARRIVE, Leg.PARKED, [])
	trip.info["zone"] = Net.Zone.LOT
	_raid_trip = trip.id
	_send_plan(trip)
	_rpc_raid.rpc(trip.id)
	return trip


func _new_trip(purpose: String) -> Trip:
	var trip := _make_trip(_next_trip_id)
	_next_trip_id += 1
	trip.info["purpose"] = purpose
	stats["trips"] = int(stats["trips"]) + 1
	return trip


## The return van at Annex B's forecourt: the one waiting there, else a new one
## that rolls up from out of sight.
func _return_trip(create: bool) -> Trip:
	for trip: Trip in _trips.values():
		if str(trip.info.get("purpose", "")) == "return" and not trip.depart_planned and not trip.ended:
			return trip
	if not create:
		return null
	# The van that brought them, still parked at the curb, if the Annex has no forecourt.
	var curb := _annex_curb("ForecourtCurb")
	for trip: Trip in _trips.values():
		var leg := _current_leg(trip, Net.server_time())
		if not trip.ended and not trip.depart_planned and not leg.is_empty() and int(leg["k"]) == Leg.ANNEX_PARKED and _pose(trip, Net.server_time()).origin.distance_to(curb.origin) < 1.0:
			trip.info["purpose"] = "return"
			_rpc_info.rpc(trip.id, trip.info)
			return trip
	var trip := _new_trip("return")
	trip.info["zone"] = Net.Zone.BORDER
	trip.legs = _roll_in_legs(curb, Net.server_time() + Constants.VAN_PLAN_LEAD, 60.0)
	_send_plan(trip)
	return trip


## A pull-up to curb (a Transform3D facing the way it parks): down the street's
## lane from out of sight at VAN_ARRIVE_SPEED, merging to the curb, braking at
## VAN_BRAKE_DECEL. arrive_at fixes when it stops (the raid's warning), or -1 for
## as soon as it can. Then a standing leg there.
func _arrival_legs(curb: Transform3D, start: float, arrive_at: float, moving: int, parked: int, avoid: Array) -> Array:
	var v := Constants.VAN_ARRIVE_SPEED
	var a := Constants.VAN_BRAKE_DECEL
	var length := v * v / (2.0 * a) + 4.0
	if arrive_at > 0.0:
		var span := maxf(arrive_at - start, 0.5)
		# Cruise then brake, ending at arrive_at: d = v (T - v / 2a).
		length = maxf(v * (span - v / (2.0 * a)), 2.0)
		if span < v / a:
			# Too short to brake from cruise: slower, braking the whole way.
			v = 2.0 * length / span
			v = minf(v, Constants.VAN_MAX_SCREEN_SPEED)
			a = v / span
	else:
		length = maxf(length, Constants.VAN_HIDE_METERS)
	# Come in from whichever end of the street is farther from everyone on it.
	var h := -curb.basis.z.normalized()
	var flipped := _farther_side(curb.origin, h, length, avoid)
	if flipped:
		curb = Transform3D(curb.basis.rotated(Vector3.UP, PI), curb.origin)
		h = -h
	var points := _street_points(curb, -length, 0.0, true)
	var got := _polyline_length(points)
	var cruise := maxf((got - v * v / (2.0 * a)) / v, 0.0)
	var legs: Array = []
	legs.append({"k": moving, "t": start, "p": points, "v0": v, "segs": PackedFloat32Array([cruise, 0.0, v / a, -a])})
	var end_t := start + cruise + v / a
	legs.append({"k": parked, "t": end_t, "x": curb})
	return legs


## Annex B's roll-in: ANNEX_ROLL_IN_SECONDS braking to its curb from a little way back.
func _roll_in_legs(curb: Transform3D, start: float, min_length: float = 0.0) -> Array:
	var seconds := Constants.ANNEX_ROLL_IN_SECONDS
	var v := 8.0
	var length := v * seconds * 0.5
	var lead := 0.0
	if min_length > length:
		lead = (min_length - length) / v
	var points := _street_points(curb, -(length + lead * v), 0.0, true)
	var got := _polyline_length(points)
	var cruise := maxf((got - length) / v, 0.0)
	return [
		{"k": Leg.ANNEX_ARRIVE, "t": start, "p": points, "v0": v, "segs": PackedFloat32Array([cruise, 0.0, seconds, -v / seconds])},
		{"k": Leg.ANNEX_PARKED, "t": start + cruise + seconds, "x": curb},
	]


## Pulling out from where it stands at start: the pull from the curb, up to a lawful
## cruise, along the street to a route end out of everyone's sight, braking to stop
## there (HIDDEN). The door shuts first and the blinker ticks; a NICE BOY still out
## makes it creep first, back doors open.
func _plan_departure(trip: Trip, at: float, kind: int) -> void:
	_host_door(trip, "side", false, at)
	var pull := at + Constants.VAN_DOOR_SLIDE + Constants.VAN_BLINKER_SECONDS
	_rpc_beat.rpc(trip.id, "blinker", at + Constants.VAN_DOOR_SLIDE)
	_rpc_beat.rpc(trip.id, "whistle", at)
	var straggling := false
	for index: Variant in trip.crew.keys():
		if int((trip.crew[index] as Dictionary)["mode"]) == CREW_HOP_OUT and _crew_node(int(index)) != null:
			straggling = true
	if kind == Leg.DEPART and straggling and str(trip.info.get("purpose", "")) == "raid":
		_host_door(trip, "back", true, pull - 0.3)
		var pose := _pose(trip, pull)
		var points := _street_points_from(trip, pose, 40.0)
		var to_creep := Constants.VAN_CREEP_SPEED / Constants.VAN_PULL_ACCEL
		trip.legs.append({"k": Leg.CREEP, "t": pull, "p": points, "v0": 0.0, "segs": PackedFloat32Array([to_creep, Constants.VAN_PULL_ACCEL])})
		_send_plan(trip)
		return
	_plan_route_from(trip, pull, kind, 0.0)


## A drive from the trip's pose at time at with speed v0, to a route end out of
## sight, then HIDDEN there.
func _plan_route_from(trip: Trip, at: float, kind: int, v0: float) -> void:
	_cut_legs(trip, at)
	var pose := _pose(trip, at)
	var points := _street_points_from(trip, pose, Constants.VAN_HIDE_METERS, _avoid_points(trip))
	var length := _polyline_length(points)
	var segs := _drive_segments(v0, length)
	trip.legs.append({"k": kind, "t": at, "p": points, "v0": v0, "segs": segs})
	var end_t := at + _segs_seconds(segs)
	var end_pose := _route_pose(points, length)
	trip.legs.append({"k": Leg.HIDDEN, "t": end_t, "x": end_pose})
	_send_plan(trip)


## Still pulling up when the call is off: from where it is, at the speed it has,
## on down the street and away.
func _plan_drive_on(trip: Trip, at: float) -> void:
	var v := _speed_at(trip, at)
	_plan_route_from(trip, at, Leg.DEPART, v)


## Off down the street from wherever it stands (the Annex, the drop curb), then gone.
func _plan_leave(trip: Trip, at: float) -> void:
	_host_door(trip, "side", false, at - Constants.VAN_DOOR_SLIDE - 0.1)
	_cut_legs(trip, at)
	var pose := _pose(trip, at)
	var points := _street_points_from(trip, pose, Constants.VAN_HIDE_METERS, _avoid_points(trip))
	var length := _polyline_length(points)
	var segs := _drive_segments(0.0, length)
	trip.legs.append({"k": Leg.LEAVE, "t": at, "p": points, "v0": 0.0, "segs": segs})
	_send_plan(trip)
	_rpc_beat.rpc(trip.id, "pull", at)


## Legs that would start after at are dropped (a new plan replaces them).
func _cut_legs(trip: Trip, at: float) -> void:
	var kept: Array = []
	for leg: Dictionary in trip.legs:
		if float(leg["t"]) < at:
			kept.append(leg)
	trip.legs = kept


## From rest (or v0) to a stop over length meters: cast:5's pull from the curb,
## then up to VAN_CRUISE, a cruise, and braking at VAN_BRAKE_DECEL. Shorter roads
## peak lower.
static func _drive_segments(v0: float, length: float) -> PackedFloat32Array:
	var segs := PackedFloat32Array()
	var v := v0
	var used := 0.0
	var cruise := Constants.VAN_CRUISE
	var brake := Constants.VAN_BRAKE_DECEL
	if v < 0.5:
		var t := Constants.VAN_PULL_SECONDS
		var reach := minf(Constants.VAN_PULL_ACCEL * t, cruise)
		t = reach / Constants.VAN_PULL_ACCEL
		segs.append(t)
		segs.append(Constants.VAN_PULL_ACCEL)
		used += 0.5 * Constants.VAN_PULL_ACCEL * t * t
		v = reach
	if v < cruise:
		var t := (cruise - v) / Constants.VAN_CRUISE_ACCEL
		segs.append(t)
		segs.append(Constants.VAN_CRUISE_ACCEL)
		used += v * t + 0.5 * Constants.VAN_CRUISE_ACCEL * t * t
		v = cruise
	var stop := v * v / (2.0 * brake)
	if used + stop > length:
		# A short road: brake sooner (the profile is cut, never backwards).
		var t := v / brake
		segs.append(t)
		segs.append(-brake)
		return segs
	segs.append((length - used - stop) / v)
	segs.append(0.0)
	segs.append(v / brake)
	segs.append(-brake)
	return segs


## The curb the raid van parks at (see park_point).
func _host_park() -> Transform3D:
	var director := get_parent()
	var key := float(director.call("phase_started_at")) if director != null and director.has_method("phase_started_at") else 0.0
	if _park_cache.get("key", -1.0) == key and _park_cache.has("x"):
		return _park_cache["x"]
	var curb := _default_curb()
	var noisy := _noisiest_player()
	var lot := _lot_zone()
	if noisy != null and lot != null:
		var local := lot.global_transform.affine_inverse() * noisy.global_position
		curb.origin = lot.global_transform * Vector3(clampf(local.x, -40.0, 40.0), 0.0, Constants.VAN_CURB_Z)
	var found := _clear_curb(curb)
	_park_cache = {"key": key, "x": found}
	return found


## The far curb in front of the yard, facing down the street (-x).
func _default_curb() -> Transform3D:
	var lot := _lot_zone()
	var origin := lot.global_transform * Vector3(-6.0, 0.0, Constants.VAN_CURB_Z) if lot != null else Vector3(994.0, 0.0, Constants.VAN_CURB_Z)
	return Transform3D(Basis.looking_at(_NiceVan.STREET_DIR, Vector3.UP), origin)


## Slides a parking spot along its curb (1 m steps either way, up to
## VAN_PARK_SLIDE_MAX) until the van's box, and the stretch it pulls in and out
## over, are clear of trees, props and parked cars.
func _clear_curb(curb: Transform3D) -> Transform3D:
	var h := -curb.basis.z
	for step: int in int(Constants.VAN_PARK_SLIDE_MAX) * 2 + 1:
		var offset := float((step + 1) / 2) * (1.0 if step % 2 == 1 else -1.0)
		var at := Transform3D(curb.basis, curb.origin + h * offset)
		at.origin.y = _ground_y(at.origin, curb.origin.y)
		if _box_clear(at):
			stats["park_slides"] = absf(offset)
			return at
	stats["park_slides"] = -1.0
	return curb


func _box_clear(at: Transform3D) -> bool:
	var space := get_world_3d().direct_space_state if is_inside_tree() else null
	if space == null:
		return true
	var size := Constants.VAN_PARK_CLEARANCE
	var lane := at.basis.x.normalized() * (Constants.VAN_CURB_Z - Constants.VAN_LANE_Z)
	var h := -at.basis.z.normalized()
	var boxes: Array = [
		[at.origin, Vector3(size.x, size.y, size.z)],
		# Where it pulls in from and out to, half in the lane.
		[at.origin - h * (size.z * 0.5 + 3.0) + lane * 0.5, Vector3(size.x, size.y, 6.0)],
		[at.origin + h * (size.z * 0.5 + 3.0) + lane * 0.5, Vector3(size.x, size.y, 6.0)],
	]
	for entry: Array in boxes:
		var shape := BoxShape3D.new()
		shape.size = entry[1]
		var query := PhysicsShapeQueryParameters3D.new()
		query.shape = shape
		query.transform = Transform3D(at.basis, (entry[0] as Vector3) + Vector3(0.0, 0.15 + size.y * 0.5, 0.0))
		query.collision_mask = 0xFFFF & ~Constants.PAD_WALL_LAYER
		query.collide_with_areas = false
		for hit: Dictionary in space.intersect_shape(query, 16):
			var collider := hit.get("collider") as Node
			# People move; trees, props, cars and walls don't.
			if collider is CharacterBody3D or (collider != null and collider.is_in_group("players")):
				continue
			if collider != null and _is_own_van(collider):
				continue
			return false
		if _tree_in(Transform3D(at.basis, entry[0] as Vector3), entry[1] as Vector3):
			return false
	return true


func _is_own_van(node: Node) -> bool:
	for trip: Trip in _trips.values():
		if trip.look != null and trip.look.is_ancestor_of(node):
			return true
	return false


## Which way to come in: true to come from the other end, when that start is
## farther from everyone on the yard.
func _farther_side(park: Vector3, h: Vector3, length: float, avoid: Array) -> bool:
	var here := park - h * length
	var there := park + h * length
	return _nearest_watcher(there, avoid) > _nearest_watcher(here, avoid) + 5.0 and _ground_y(there, park.y, true) > -1000.0


func _nearest_watcher(at: Vector3, avoid: Array) -> float:
	var best := INF
	for point: Vector3 in _watcher_points(avoid):
		best = minf(best, Vector2(point.x - at.x, point.z - at.z).length())
	return best


## Where everyone on the yard (and the town) is, minus those inside a van.
func _watcher_points(avoid: Array) -> Array:
	var out: Array = []
	var riding := boarded_riders()
	for node: Node in get_tree().get_nodes_in_group("players"):
		var peer := node.name.to_int()
		if riding.has(peer) or avoid.has(peer):
			continue
		var zone := Net.player_zone(peer)
		if zone == Net.Zone.LOT or zone == Net.Zone.TOWN or zone == Net.Zone.STORE:
			out.append((node as Node3D).global_position)
	return out


func _avoid_points(trip: Trip) -> Array:
	return trip.seats.keys()


## The street from a curb pose: points every VAN_ROUTE_STEP from s_from to s_to
## (meters along its facing), in the lane and merging to the curb over the last
## (arriving) or first (leaving) VAN_MERGE_METERS, each put on the ground. A point
## with no ground under it ends the route there.
func _street_points(curb: Transform3D, s_from: float, s_to: float, merge_at_end: bool) -> PackedVector3Array:
	var h := -curb.basis.z.normalized()
	var right := curb.basis.x.normalized()
	var lane := Constants.VAN_CURB_Z - Constants.VAN_LANE_Z
	var base: Array[float] = []
	var steps := maxi(1, ceili(absf(s_to - s_from) / Constants.VAN_ROUTE_STEP))
	var along: Array[float] = []
	for index: int in steps + 1:
		var s := lerpf(s_from, s_to, float(index) / float(steps))
		along.append(s)
		# In the lane, onto the curb over the last stretch (arriving) or off it over
		# the first (leaving).
		var w := _merge_weight((s_to - s) / Constants.VAN_MERGE_METERS) if merge_at_end else _merge_weight((s - s_from) / Constants.VAN_MERGE_METERS)
		base.append(lane * w)
	# The curb end is fixed (it's where the van stands); the far end is free.
	return _route(curb.origin, h, right, along, base, steps if merge_at_end else 0)


## The route through these points (origin + h * along[i] + right * base[i]): each
## one swerved around anything standing in the street (a tree, a parked car, a
## prop), eased so it never jinks, and put on the ground. Walked outward from the
## fixed end (index fixed), a point with no ground ends the route there.
func _route(origin: Vector3, h: Vector3, right: Vector3, along: Array[float], base: Array[float], fixed: int) -> PackedVector3Array:
	var count := along.size()
	var need: Array[float] = []
	need.resize(count)
	need.fill(0.0)
	for index: int in count:
		if absi(index - fixed) <= 2:
			continue
		var at := origin + h * along[index] + right * base[index]
		if not _route_blocked(at, h):
			continue
		# The nearest clear offset, toward the street's middle first.
		for step: int in range(1, 9):
			var offset := 0.6 * float((step + 1) / 2) * (1.0 if step % 2 == 1 else -1.0)
			var lateral := base[index] + offset
			if lateral < -Constants.VAN_SWERVE_RANGE.x or lateral > Constants.VAN_SWERVE_RANGE.y:
				continue
			if not _route_blocked(at + right * offset, h):
				need[index] = offset
				break
		stats["swerves"] = int(stats.get("swerves", 0)) + 1
	# Each swerve eased in and out over VAN_SWERVE_EASE meters either side.
	var reach := maxi(1, int(Constants.VAN_SWERVE_EASE / Constants.VAN_ROUTE_STEP))
	var lateral_final: Array[float] = []
	for index: int in count:
		var add := 0.0
		for other: int in range(maxi(0, index - reach), mini(count, index + reach + 1)):
			if need[other] == 0.0:
				continue
			var w := 0.5 + 0.5 * cos(PI * float(absi(other - index)) / float(reach + 1))
			if absf(need[other] * w) > absf(add):
				add = need[other] * w
		if absi(index - fixed) <= 1:
			add = 0.0
		lateral_final.append(base[index] + add)
	var kept: Dictionary = {}
	var order: Array[int] = []
	for index: int in count:
		order.append(count - 1 - index if fixed > 0 else index)
	for index: int in order:
		var point := origin + h * along[index] + right * lateral_final[index]
		var y := _ground_y(point, origin.y, true)
		if y < -1000.0:
			stats["route_ground_misses"] = int(stats["route_ground_misses"]) + 1
			break
		kept[index] = Vector3(point.x, y, point.z)
	var out := PackedVector3Array()
	for index: int in count:
		if kept.has(index):
			out.append(kept[index])
	if out.size() < 2:
		var end := origin + h * along[fixed]
		out = PackedVector3Array([end - h, end] if fixed > 0 else [end, end + h])
	return out


## Something standing where a van-sized slice of road (VAN_ROUTE_CLEARANCE) at
## this point would be: a tree, a car, a post, a prop. People and the yard's
## invisible pad walls don't count.
func _route_blocked(at: Vector3, h: Vector3) -> bool:
	var space := get_world_3d().direct_space_state if is_inside_tree() else null
	if space == null:
		return false
	var shape := BoxShape3D.new()
	shape.size = Constants.VAN_ROUTE_CLEARANCE
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = shape
	query.transform = Transform3D(Basis.looking_at(h, Vector3.UP), at + Vector3(0.0, 0.35 + Constants.VAN_ROUTE_CLEARANCE.y * 0.5, 0.0))
	query.collision_mask = 0xFFFF & ~Constants.PAD_WALL_LAYER
	query.collide_with_areas = false
	for hit: Dictionary in space.intersect_shape(query, 8):
		var collider := hit.get("collider") as Node
		if collider == null or collider is CharacterBody3D or collider.is_in_group("players") or _is_own_van(collider):
			continue
		return true
	return _tree_in(Transform3D(Basis.looking_at(h, Vector3.UP), at), Constants.VAN_ROUTE_CLEARANCE)


## A tree's crown in this box (a van-sized slice at xform, size across, up, along),
## seen from above. Most trees have no collider (the scenery ones), so the
## physics queries can't see them: their spread is worked out from their height.
func _tree_in(xform: Transform3D, size: Vector3) -> bool:
	var now := Time.get_ticks_msec()
	if now - _trees_at > 2000:
		_trees_at = now
		_trees.clear()
		for node: Node in get_tree().get_nodes_in_group("seasonal"):
			var tree := node as Node3D
			if tree == null or not "kind" in tree or not tree.is_visible_in_tree():
				continue
			var height := tree.global_basis.get_scale().x * _Trees.BUILD_HEIGHT
			var spread := height * (Constants.VAN_TREE_SPREAD.x if _Trees.EVERGREEN.has(str(tree.get("kind"))) else Constants.VAN_TREE_SPREAD.y)
			_trees.append([tree.global_position, spread])
	var inverse := xform.affine_inverse()
	for entry: Array in _trees:
		var local := inverse * (entry[0] as Vector3)
		var radius := float(entry[1])
		var dx := maxf(absf(local.x) - size.x * 0.5, 0.0)
		var dz := maxf(absf(local.z) - size.z * 0.5, 0.0)
		if dx * dx + dz * dz < radius * radius:
			return true
	return false


var _trees: Array = []
var _trees_at: int = -100000


## A route on from a pose: along its facing, merging back to the lane over the
## first VAN_MERGE_METERS, at least min_length long and on until its end is
## VAN_HIDE_METERS from everyone watching (or the ground runs out).
func _street_points_from(trip: Trip, pose: Transform3D, min_length: float, avoid: Array = []) -> PackedVector3Array:
	var h := -pose.basis.z
	h.y = 0.0
	h = h.normalized()
	var curb := Transform3D(Basis.looking_at(h, Vector3.UP), pose.origin)
	# How far off the lane it starts (0 when already in it).
	var lane_dir := curb.basis.x.normalized()
	var park: Transform3D = trip.info.get("park", curb)
	var lane_point := park.origin + park.basis.x.normalized() * (Constants.VAN_CURB_Z - Constants.VAN_LANE_Z)
	var off := (lane_point - pose.origin).dot(lane_dir)
	off = clampf(off, -1.5, 1.5)
	var length := min_length
	var watchers := _watcher_points(avoid)
	while length < 200.0:
		var end := pose.origin + h * length
		var near := INF
		for point: Vector3 in watchers:
			near = minf(near, Vector2(point.x - end.x, point.z - end.z).length())
		if near >= Constants.VAN_HIDE_METERS:
			break
		length += 10.0
	var steps := maxi(1, ceili(length / Constants.VAN_ROUTE_STEP))
	var along: Array[float] = []
	var base: Array[float] = []
	for index: int in steps + 1:
		var s := length * float(index) / float(steps)
		along.append(s)
		base.append(off * _merge_weight(s / Constants.VAN_MERGE_METERS))
	return _route(pose.origin, h, lane_dir, along, base, 0)


## 0 at u <= 0, 1 at u >= 1, an eased lane change between.
static func _merge_weight(u: float) -> float:
	var c := clampf(u, 0.0, 1.0)
	return 0.5 - 0.5 * cos(c * PI)


## The ground's height under a point (a ray from just above the road down), or
## fallback; with strict, -INF-ish when there is no ground.
func _ground_y(point: Vector3, fallback: float, strict: bool = false) -> float:
	var space := get_world_3d().direct_space_state if is_inside_tree() else null
	if space == null:
		return fallback
	var exclude: Array[RID] = []
	for _try: int in 4:
		var query := PhysicsRayQueryParameters3D.create(Vector3(point.x, fallback + GROUND_PROBE.x, point.z), Vector3(point.x, fallback - GROUND_PROBE.y, point.z), 0xFFFF)
		query.exclude = exclude
		query.collide_with_areas = false
		var hit := space.intersect_ray(query)
		if hit.is_empty():
			return -INF if strict else fallback
		var collider := hit.get("collider") as Node
		if collider is StaticBody3D or collider is CSGShape3D:
			return (hit["position"] as Vector3).y
		exclude.append(hit["rid"])
	return -INF if strict else fallback


## Annex B's curbs (nice_boys:5's AnnexSet markers), or the fallback in BorderZone.
func _annex_curb(marker_name: String) -> Transform3D:
	var world := _world()
	var marker := world.get_node_or_null("BorderZone/AnnexSet/" + marker_name) as Node3D if world != null else null
	if marker == null and marker_name == "ForecourtCurb":
		marker = world.get_node_or_null("BorderZone/AnnexSet/AnnexCurb") as Node3D if world != null else null
	if marker != null:
		return marker.global_transform
	var border := world.get_node_or_null("BorderZone") as Node3D if world != null else null
	var origin := (border.global_position if border != null else Vector3(0.0, 0.0, 1000.0)) + Constants.VAN_ANNEX_CURB
	return Transform3D(Basis.looking_at(_NiceVan.STREET_DIR, Vector3.UP), origin)


## The curb a return trip drops at: the yard's (LOT, and TOWN in the connected
## town), or Homie Depot's.
func _drop_curb(zone: int) -> Transform3D:
	if zone == Net.Zone.STORE:
		var world := _world()
		var store := world.get_node_or_null("StoreZone") as Node3D if world != null else null
		var origin := (store.global_transform * Constants.SHUTTLE_STORE_STOP) if store != null else Constants.SHUTTLE_STORE_STOP
		return _clear_curb(Transform3D(Basis.looking_at(Vector3.FORWARD, Vector3.UP), origin))
	_park_cache.clear()
	return _clear_curb(_default_curb() if _noisiest_player() == null else _host_park())


func _noisiest_player() -> Node3D:
	var director := get_parent()
	var peer := int(director.call("loudest_peer")) if director != null and director.has_method("loudest_peer") else 0
	var first: Node3D = null
	for node: Node in get_tree().get_nodes_in_group("players"):
		var id := node.name.to_int()
		if Net.player_zone(id) != Net.Zone.LOT and Net.player_zone(id) != Net.Zone.TOWN:
			continue
		if id == peer:
			return node as Node3D
		if first == null:
			first = node as Node3D
	return first


# ---------------------------------------------------------------- seats (host)


func _host_board(trip_id: int, peer_id: int, mode: int) -> int:
	var trip := _trip(trip_id)
	if not Net.is_host() or trip == null:
		return -1
	if trip.seats.has(peer_id):
		return int((trip.seats[peer_id] as Dictionary)["seat"])
	var taken: Array = []
	for entry: Variant in trip.seats.values():
		taken.append(int((entry as Dictionary)["seat"]))
	var seat := -1
	for index: int in _NiceVan.RIDER_SEAT_Z.size():
		if not taken.has(index):
			seat = index
			break
	if seat < 0:
		return -1
	var player := _player(peer_id)
	var from := player.global_position if player != null else Vector3.ZERO
	var at := Net.server_time() + Constants.VAN_PLAN_LEAD * 0.5
	# Walking in, they start once the van has parked.
	if mode == BOARD_WALK:
		at = maxf(at, _arrive_end(trip))
	# Drop anything in the way first (Chefty's seats, a carry).
	for vehicle: Node in get_tree().get_nodes_in_group("vehicles"):
		if vehicle.has_method("drop_rider"):
			vehicle.call("drop_rider", peer_id)
	_rpc_seat.rpc(trip.id, peer_id, seat, at, mode, from)
	_stage(peer_id, STAGE_SEATED)
	stats["seats"] = int(stats["seats"]) + 1
	return seat


func _free_crew_seat(trip: Trip, index: int) -> int:
	var taken: Array = []
	for other: Variant in trip.crew.keys():
		if int(other) != index and int((trip.crew[other] as Dictionary)["mode"]) != CREW_HOP_OUT:
			taken.append(int((trip.crew[other] as Dictionary)["seat"]))
	for seat: int in 3:
		if not taken.has(seat):
			return seat
	return 2


## The rescue: hold interact on the door. start true begins a hold; false says it
## was held long enough (the host times it itself).
@rpc("any_peer", "call_remote", "reliable")
func _rpc_request_unbuckle(target: int, start: bool) -> void:
	if not Net.is_host():
		return
	_host_unbuckle(multiplayer.get_remote_sender_id(), target, start)


func _host_unbuckle(rescuer: int, target: int, start: bool) -> void:
	var now := Net.server_time()
	var info := seat_info(target)
	var trip := _trip(int(info.get("trip", 0)))
	var refusal := _unbuckle_refusal(rescuer, target, trip, now)
	if refusal != "":
		stats["unbuckle_refused"] = int(stats["unbuckle_refused"]) + 1
		stats["last_refusal"] = refusal
		_holds.erase(rescuer)
		if refusal == "mirror" and trip != null:
			# Caught at it: a honk from the cab.
			_rpc_beat.rpc(trip.id, "honk", now + 0.05)
		return
	if start:
		_holds[rescuer] = {"target": target, "trip": trip.id, "at": now}
		return
	var hold: Dictionary = _holds.get(rescuer, {})
	if hold.is_empty() or int(hold["target"]) != target or now - float(hold["at"]) < Constants.VAN_UNBUCKLE_HOLD - 0.15:
		stats["unbuckle_refused"] = int(stats["unbuckle_refused"]) + 1
		stats["last_refusal"] = "short"
		return
	# The driver mustn't have looked during the hold either.
	for sample: int in 6:
		var t := lerpf(float(hold["at"]), now, float(sample) / 5.0)
		if mirror_checking(trip.id, t):
			stats["unbuckle_refused"] = int(stats["unbuckle_refused"]) + 1
			stats["last_refusal"] = "mirror"
			_holds.erase(rescuer)
			_rpc_beat.rpc(trip.id, "honk", now + 0.05)
			return
	_holds.erase(rescuer)
	var pose := _pose(trip, now)
	var exit := pose * (_local_marker(trip, "DoorStep").origin + Vector3(0.0, 0.0, 0.6))
	var at := now + Constants.VAN_PLAN_LEAD * 0.5
	_rpc_unseat.rpc(trip.id, target, exit, at)
	stats["unbuckles"] = int(stats["unbuckles"]) + 1
	var heat := get_tree().get_first_node_in_group("heat")
	if heat != null and heat.has_method("add"):
		heat.call("add", Constants.HEAT_UNBUCKLE, "unbuckle")
	var done_at := at + Constants.VAN_BUCKLE_SECONDS * 0.6 + Constants.VAN_STEP_SECONDS
	get_tree().create_timer(maxf(done_at - Net.server_time(), 0.0)).timeout.connect(func() -> void:
		_free_rescued(target, rescuer))


## Why this unbuckle can't happen ("" when it can).
func _unbuckle_refusal(rescuer: int, target: int, trip: Trip, now: float) -> String:
	if trip == null or not trip.seats.has(target) or trip.unseats.has(target):
		return "no_rider"
	if not _seat_settled(trip, target, now):
		return "not_settled"
	var leg := _current_leg(trip, now)
	if leg.is_empty() or int(leg["k"]) != Leg.PARKED or not bool(trip.doors["side"][0]):
		return "not_parked"
	if seat_info(rescuer).size() > 0:
		return "rider"
	var director := get_parent()
	if director != null and director.has_method("is_captured") and bool(director.call("is_captured", rescuer)):
		return "captured"
	var body := _player(rescuer)
	if body == null:
		return "no_body"
	var step := _pose(trip, now) * _local_marker(trip, "DoorStep").origin
	if Vector2(body.global_position.x - step.x, body.global_position.z - step.z).length() > Constants.VAN_DOOR_REACH:
		return "reach"
	if mirror_checking(trip.id, now):
		return "mirror"
	for crew: Node in get_tree().get_nodes_in_group("crew"):
		var crew_body := crew as Node3D
		if crew_body == null or _crew_entry(trip, crew) != {}:
			continue
		if crew_body.global_position.distance_to(body.global_position) <= Constants.VAN_GUARD_RADIUS and crew.has_method("can_see_peer") and bool(crew.call("can_see_peer", rescuer)):
			# Seen trying: that NICE BOY has you now.
			for spot: String in ["host_spot", "spot_peer", "notice_peer"]:
				if crew.has_method(spot):
					crew.call(spot, rescuer)
					break
			return "guard"
	return ""


func _free_rescued(target: int, rescuer: int) -> void:
	var encounter := get_tree().get_first_node_in_group("nice_encounter")
	if encounter != null and encounter.has_method("host_free"):
		encounter.call("host_free", target, rescuer, &"unbuckle")
	else:
		_release(target, -1.0)
	var campaign := get_node_or_null("/root/Campaign")
	if campaign != null and campaign.has_method("add_rescue") and rescuer != 0:
		if encounter == null:
			campaign.call("add_rescue", rescuer, &"unbuckle")


@rpc("any_peer", "call_remote", "reliable")
func _rpc_request_knock() -> void:
	if not Net.is_host():
		return
	_host_knock(multiplayer.get_remote_sender_id())


func _host_knock(peer_id: int) -> void:
	var info := seat_info(peer_id)
	if info.is_empty() or not bool(info["settled"]) or bool(info["leaving"]):
		return
	var trip := _trip(int(info["trip"]))
	var last := float(trip.knocks.get(peer_id, -10.0))
	var now := Net.server_time()
	if now - last < Constants.VAN_KNOCK_SECONDS:
		return
	_rpc_knock.rpc(trip.id, peer_id, now + 0.05)


@rpc("any_peer", "call_remote", "reliable")
func _rpc_request_snapshot() -> void:
	if Net.is_host():
		_rpc_snapshot.rpc_id(multiplayer.get_remote_sender_id(), snapshot())


# ---------------------------------------------------------------- the RPCs


func _send_plan(trip: Trip) -> void:
	_rpc_plan.rpc(trip.id, trip.legs, trip.info)


@rpc("authority", "call_local", "reliable")
func _rpc_plan(trip_id: int, legs: Array, info: Dictionary) -> void:
	var trip := _trip(trip_id)
	if trip == null:
		trip = _make_trip(trip_id)
	trip.legs = legs.duplicate(true)
	trip.info = info.duplicate(true)
	_next_trip_id = maxi(_next_trip_id, trip_id + 1)


@rpc("authority", "call_local", "reliable")
func _rpc_info(trip_id: int, info: Dictionary) -> void:
	var trip := _trip(trip_id)
	if trip != null:
		trip.info = info.duplicate(true)


@rpc("authority", "call_local", "reliable")
func _rpc_raid(trip_id: int) -> void:
	_raid_trip = trip_id


func _host_door(trip: Trip, which: String, open: bool, at: float) -> void:
	_rpc_door.rpc(trip.id, which, open, at)


@rpc("authority", "call_local", "reliable")
func _rpc_door(trip_id: int, which: String, open: bool, at: float) -> void:
	var trip := _trip(trip_id)
	if trip == null:
		return
	trip.doors[which] = [open, at]
	if trip.look == null:
		return
	var door := trip.look.get_node_or_null("Shell/SideDoor" if which == "side" else "Shell/BackDoors")
	if door != null:
		door.call("slide" if which == "side" else "swing", open, at)


@rpc("authority", "call_local", "reliable")
func _rpc_seat(trip_id: int, peer_id: int, seat: int, at: float, mode: int, from: Vector3) -> void:
	var trip := _trip(trip_id)
	if trip == null:
		return
	var pose := _pose(trip, at)
	trip.seats[peer_id] = {"seat": seat, "at": at, "mode": mode, "from": pose.affine_inverse() * from}
	trip.unseats.erase(peer_id)
	trip.staged_pose.erase(peer_id)
	trip.my_beats.erase("unseat%d" % peer_id)
	if Net.is_host():
		trip.last_seat_done = maxf(trip.last_seat_done, at + _board_seconds(trip, peer_id))


@rpc("authority", "call_local", "reliable")
func _rpc_unseat(trip_id: int, peer_id: int, exit: Vector3, at: float) -> void:
	var trip := _trip(trip_id)
	if trip == null or not trip.seats.has(peer_id):
		return
	trip.unseats[peer_id] = {"at": at, "exit": exit}


## The Annex (or the legacy crossing) has the riders now: off this van's seats.
@rpc("authority", "call_local", "reliable")
func _rpc_release_riders(trip_id: int, at: float) -> void:
	var trip := _trip(trip_id)
	if trip == null:
		return
	trip.info["released_at"] = at
	for peer_id: Variant in trip.seats.keys():
		_unstage_rider(trip, int(peer_id), true)
	trip.seats.clear()
	trip.unseats.clear()


@rpc("authority", "call_local", "reliable")
func _rpc_knock(trip_id: int, peer_id: int, at: float) -> void:
	var trip := _trip(trip_id)
	if trip == null:
		return
	trip.knocks[peer_id] = at
	stats["knocks"] = int(stats["knocks"]) + 1


@rpc("authority", "call_local", "reliable")
func _rpc_crew_seat(trip_id: int, crew_index: int, seat: int, at: float, mode: int, from: Vector3) -> void:
	var trip := _trip(trip_id)
	if trip == null:
		return
	trip.crew[crew_index] = {"seat": seat, "at": at, "mode": mode, "from": from}
	trip.crew_staged.erase(crew_index)


## Cosmetic beats the plan doesn't carry: the blinker, the whistle to the crew, the
## driver's wave, a honk at someone fiddling with the door.
@rpc("authority", "call_local", "reliable")
func _rpc_beat(trip_id: int, kind: String, at: float) -> void:
	var trip := _trip(trip_id)
	if trip == null:
		return
	trip.info["beat_" + kind] = at


@rpc("authority", "call_local", "reliable")
func _rpc_end_trip(trip_id: int) -> void:
	var trip := _trip(trip_id)
	if trip == null:
		return
	trip.ended = true
	trip.ended_at = Net.server_time()
	for peer_id: Variant in trip.seats.keys():
		_unstage_rider(trip, int(peer_id), true)
	trip.seats.clear()
	for index: Variant in trip.crew.keys():
		_unstage_crew(trip, int(index))
	if trip.id == _raid_trip:
		_raid_trip = 0


@rpc("authority", "call_remote", "reliable")
func _rpc_snapshot(data: Dictionary) -> void:
	apply_snapshot(data)


# ---------------------------------------------------------------- drawing (every peer)


func _make_trip(trip_id: int) -> Trip:
	var trip := Trip.new()
	trip.id = trip_id
	_trips[trip_id] = trip
	return trip


func _build_look(trip: Trip) -> void:
	trip.holder = Node3D.new()
	trip.holder.name = "Trip%d" % trip.id
	add_child(trip.holder)
	trip.look = _NiceVan.build(trip.holder)
	var side := trip.look.get_node_or_null("Shell/SideDoor")
	var back := trip.look.get_node_or_null("Shell/BackDoors")
	# Shut while it drives; the door events open it.
	if side != null:
		side.call("set_open_now", false)
		var door: Array = trip.doors["side"]
		if float(door[1]) > -999.0:
			side.call("set_open_now", bool(door[0]) and Net.server_time() >= float(door[1]) + Constants.VAN_DOOR_SLIDE)
			if Net.server_time() < float(door[1]) + Constants.VAN_DOOR_SLIDE:
				side.call("slide", bool(door[0]), float(door[1]))
	if back != null:
		back.call("set_open_now", false)
		var door: Array = trip.doors["back"]
		if float(door[1]) > -999.0:
			back.call("swing", bool(door[0]), float(door[1]))
	trip.driver = _build_driver(trip.look)
	var solid := trip.look.get_node_or_null("Solid") as CollisionObject3D
	if solid != null:
		trip.info["_solid_layers"] = Vector2i(solid.collision_layer, solid.collision_mask)


## The van's own driver: a NICE BOY who never gets out, sat at the wheel with a
## hand on it and a coffee in the other. Local and cosmetic.
func _build_driver(look: Node3D) -> Node3D:
	var seat := _NiceVan.marker(look, "DriverSeat")
	if seat == null:
		return null
	var body: Node3D = _CartoonBody.new()
	body.name = "Driver"
	_CrewMember.dress(body, 4)
	seat.add_child(body)
	body.call("build")
	body.call("sit", 1)
	var cup := MeshInstance3D.new()
	cup.name = "Coffee"
	var mesh := CylinderMesh.new()
	mesh.top_radius = 0.04
	mesh.bottom_radius = 0.035
	mesh.height = 0.11
	mesh.radial_segments = 8
	mesh.rings = 1
	cup.mesh = mesh
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.95, 0.93, 0.88)
	cup.material_override = material
	cup.set_meta("keep_material", true)
	look.get_node("Shell").add_child(cup)
	cup.position = Vector3(-0.2, 1.72, -1.98)
	return body


func _draw_trip(trip: Trip, now: float, delta: float) -> void:
	if trip.legs.is_empty():
		return
	var first := trip.legs[0] as Dictionary
	if now < float(first["t"]) and not trip.placed:
		return
	if trip.look == null:
		_build_look(trip)
	var pose := _pose(trip, now)
	var leg := _current_leg(trip, now)
	var kind := int(leg.get("k", Leg.ARRIVE))
	if not (stats["legs_seen"] as Array).has(LEG_NAMES[kind]):
		(stats["legs_seen"] as Array).append(LEG_NAMES[kind])
	var mine := _local_is_rider(trip)
	var seen := _locally_seen(trip)
	# A jump (a leg in another place) waits until nobody here can see the van, or
	# happens behind our own closed iris when we're riding it.
	var jump := trip.placed and pose.origin.distance_to(trip.drawn.origin) > Constants.VAN_TELEPORT_METERS
	if jump and seen and not mine and not trip.ended:
		pose = trip.drawn
		jump = false
	if trip.ended and seen and not mine and trip.placed:
		# Gone for the host, still in view here: it stays put until we look away.
		pose = trip.drawn
	var snap := not trip.placed or jump
	trip.holder.global_transform = pose
	if snap:
		trip.holder.reset_physics_interpolation()
		var motion := trip.look.get_node_or_null("Motion")
		if motion != null:
			motion.call("settle")
		if trip.placed:
			stats["snaps"] = int(stats["snaps"]) + 1
	# Never faded: hidden only when this peer can't see it and its leg allows.
	var hide_ok := kind == Leg.HIDDEN and _leg_done(trip, now) or trip.ended
	if hide_ok and not seen and not mine:
		trip.hidden_local = true
	elif not hide_ok:
		trip.hidden_local = false
	trip.holder.visible = not trip.hidden_local
	_set_solid(trip, kind in [Leg.PARKED, Leg.ANNEX_PARKED, Leg.DROP_PARKED, Leg.HIDDEN])
	# What this peer saw it do: the fastest and the longest step while in view.
	if trip.placed and not snap and seen and not trip.hidden_local and delta > 0.0:
		var step := pose.origin.distance_to(trip.drawn.origin)
		stats["max_step_m"] = maxf(float(stats["max_step_m"]), step)
		if not _local_iris_closed():
			stats["max_speed_on_screen"] = maxf(float(stats["max_speed_on_screen"]), step / delta)
	trip.drawn = pose
	trip.placed = true
	_doors_and_lights(trip, now)
	_sounds(trip, leg, now)
	_driver(trip, now, kind)
	_place_riders(trip, now)
	_place_crew(trip, now)
	if trip.ended and trip.hidden_local and now - trip.ended_at > 0.5:
		_free_trip(trip)


func _free_trip(trip: Trip) -> void:
	if trip.holder != null:
		trip.holder.queue_free()
		trip.holder = null
	trip.look = null
	if not Net.is_host():
		_trips.erase(trip.id)
	elif Net.server_time() - trip.ended_at > 2.0:
		_trips.erase(trip.id)


func _set_solid(trip: Trip, solid: bool) -> void:
	var body := trip.look.get_node_or_null("Solid") as CollisionObject3D
	if body == null:
		return
	var layers: Vector2i = trip.info.get("_solid_layers", Vector2i(1, 1))
	body.collision_layer = layers.x if solid else 0
	body.collision_mask = layers.y if solid else 0


func _doors_and_lights(trip: Trip, now: float) -> void:
	var shell := trip.look.get_node_or_null("Shell") as Node3D
	var glint := shell.get_node_or_null("MirrorR") as Node3D if shell != null else null
	if glint != null:
		var rel := now - float(_hold_leg(trip, now).get("t", now))
		var window := mirror_window(trip.id, rel)
		glint.visible = not _hold_leg(trip, now).is_empty() and rel >= window.x - Constants.VAN_GLINT_LEAD and rel < window.x
	# The blinker: the door-side front signal, on and off with the ticks.
	var blink_at := float(trip.info.get("beat_blinker", -1000.0))
	var blinking := now >= blink_at and now < blink_at + Constants.VAN_BLINKER_SECONDS + 1.0
	var light := shell.get_node_or_null("BlinkerR") as GeometryInstance3D if shell != null else null
	if light != null:
		light.visible = not blinking or fmod(now - blink_at, 0.8) < 0.4


func _sounds(trip: Trip, leg: Dictionary, now: float) -> void:
	var look := trip.look
	for index: int in trip.legs.size():
		var each := trip.legs[index] as Dictionary
		var t := float(each["t"])
		match int(each["k"]):
			Leg.ARRIVE, Leg.DROP_ARRIVE:
				var segs: PackedFloat32Array = each["segs"]
				var cruise := segs[0] if segs.size() > 0 else 0.0
				var total := _segs_seconds(segs)
				_sound_once(trip, "honk%d" % index, "van_honk", now, t + maxf(total - 5.0, 0.0))
				_sound_once(trip, "brake%d" % index, "skid", now, t + cruise, -8.0)
				_sound_once(trip, "stop%d" % index, "door_slam", now, t + total, -6.0)
			Leg.DEPART, Leg.RETURN_DEPART, Leg.LEAVE:
				_sound_once(trip, "pull%d" % index, "van", now, t)
				if int(each["k"]) != Leg.LEAVE:
					_sound_once(trip, "bump%d" % index, "van_bump", now, t + Constants.VAN_RIDE_IRIS_AT)
					if now >= t + Constants.VAN_RIDE_IRIS_AT and not trip.played.has("kick%d" % index):
						trip.played["kick%d" % index] = true
						var motion := look.get_node_or_null("Motion")
						if motion != null and now - (t + Constants.VAN_RIDE_IRIS_AT) < 0.5:
							motion.call("bump", 1.0)
	for which: String in ["side", "back"]:
		var door: Array = trip.doors[which]
		var at := float(door[1])
		var key := "%s%s%.2f" % [which, str(door[0]), at]
		_sound_once(trip, key, "van_door_slide" if which == "side" else "door_slam", now, at, 0.0 if which == "side" else -6.0)
		if which == "side" and not bool(door[0]):
			_sound_once(trip, key + "shut", "door_slam", now, at + Constants.VAN_DOOR_SLIDE)
	var blink_at := float(trip.info.get("beat_blinker", -1000.0))
	for tick: int in int(Constants.VAN_BLINKER_SECONDS / 0.4) + 1:
		_sound_once(trip, "blink%d_%.2f" % [tick, blink_at], "blinker_tick", now, blink_at + float(tick) * 0.4, -6.0)
	_sound_once(trip, "honkback%.2f" % float(trip.info.get("beat_honk", -1000.0)), "van_honk", now, float(trip.info.get("beat_honk", -1000.0)))
	# The mirror's glint, the hold only.
	var hold := _hold_leg(trip, now)
	if not hold.is_empty():
		var rel := now - float(hold["t"])
		var window := mirror_window(trip.id, rel)
		_sound_once(trip, "glint%.2f" % window.x, "mirror_glint", now, float(hold["t"]) + window.x - Constants.VAN_GLINT_LEAD, -4.0)
	for peer_id: Variant in trip.seats.keys():
		var entry: Dictionary = trip.seats[peer_id]
		var sat := float(entry["at"]) + _board_seconds(trip, int(peer_id))
		_sound_once(trip, "belt%d_%.2f" % [int(peer_id), float(entry["at"])], "seatbelt_click", now, sat - Constants.VAN_BUCKLE_SECONDS * 0.4)
	for peer_id: Variant in trip.unseats.keys():
		_sound_once(trip, "unbelt%d" % int(peer_id), "seatbelt_click", now, float((trip.unseats[peer_id] as Dictionary)["at"]))
	for peer_id: Variant in trip.knocks.keys():
		var at := float(trip.knocks[peer_id])
		_sound_once(trip, "knock%d_%.2f" % [int(peer_id), at], "window_knock", now, at)


## Plays a sound on the van once, at its moment (server time at), unless that
## moment is long past (a peer that got there late hears nothing stale).
func _sound_once(trip: Trip, key: String, id: String, now: float, at: float, db: float = 0.0) -> void:
	if at < -999.0 or trip.played.has(key) or now < at:
		return
	trip.played[key] = true
	if now - at > Constants.VAN_PLAN_LEAD + 0.2 or trip.look == null or trip.hidden_local:
		return
	var sfx := get_tree().get_first_node_in_group("sfx")
	if sfx != null:
		sfx.call("play_on", id, trip.look, db, id != "window_knock")


func _driver(trip: Trip, now: float, kind: int) -> void:
	var body := trip.driver
	if body == null or not is_instance_valid(body):
		return
	body.call("sit", 1)
	var shell := trip.look.get_node("Shell") as Node3D
	var wheel := shell.get_node_or_null("SteeringWheel") as Node3D
	var cup := shell.get_node_or_null("Coffee") as Node3D
	var parked := kind in [Leg.PARKED, Leg.ANNEX_PARKED, Leg.DROP_PARKED, Leg.HIDDEN]
	var right := wheel.global_transform * Vector3(0.12, 0.1, 0.0) if wheel != null else Vector3.INF
	var left := cup.global_position + Vector3(0.0, 0.03, 0.0) if cup != null else Vector3.INF
	if not parked and wheel != null:
		# Driving: both hands on the wheel, the coffee in the cupholder.
		left = wheel.global_transform * Vector3(-0.12, 0.1, 0.0)
	body.call("set_hold", right, left)
	var checking := mirror_checking(trip.id, now)
	body.set("face_turn", -0.9 if checking else (0.0 if not parked else 0.15 * sin(now * 0.7)))
	# Paperwork while he waits, now and then; the wave at the drop curb.
	if parked and not checking and not bool(body.call("is_gesturing")) and fmod(now + float(trip.id) * 1.7, 7.0) < 0.05:
		_VanGestures.play(body, "manifest_read")
	var wave := float(trip.info.get("beat_wave", -1000.0))
	if now >= wave and not trip.played.has("wave%.2f" % wave):
		trip.played["wave%.2f" % wave] = true
		if now - wave < 0.5:
			_VanGestures.play(body, "wave_driver")
			_say(trip, "drop_wave")
	var whistle := float(trip.info.get("beat_whistle", -1000.0))
	if now >= whistle and not trip.played.has("whistle%.2f" % whistle):
		trip.played["whistle%.2f" % whistle] = true
		if now - whistle < 0.5:
			var sfx := get_tree().get_first_node_in_group("sfx")
			if sfx != null:
				sfx.call("play_on", "whistle" if _has_sound("whistle") else "van_honk", body, -2.0)


## A line from the driver, as a caption (nice_boys:1's caption stack) for anyone
## near enough to hear it, with a babble.
func _say(trip: Trip, pool: String) -> void:
	var lines: Array = _Strings.VAN_LINES.get(pool, [])
	if lines.is_empty() or trip.driver == null:
		return
	var line := str(lines[absi(hash("%d%s" % [trip.id, pool])) % lines.size()])
	var sfx := get_tree().get_first_node_in_group("sfx")
	if sfx != null:
		sfx.call("play_on", "babble", trip.driver)
	var me := _player(Net.local_peer_id())
	if me != null and me.global_position.distance_to(trip.driver.global_position) > 18.0:
		return
	var stack := get_tree().get_first_node_in_group("caption_stack")
	if stack != null and stack.has_method("push"):
		stack.call("push", &"subtitle", line, 2.6)


# ---------------------------------------------------------------- riders (every peer)


## Seconds from a seat entry's start until they're sat and buckled.
func _board_seconds(trip: Trip, peer_id: int) -> float:
	var entry: Dictionary = trip.seats.get(peer_id, {})
	if entry.is_empty():
		return 0.0
	var mode := int(entry["mode"])
	if mode == BOARD_NOW:
		return 0.05
	var walk := 0.0
	if mode == BOARD_WALK:
		walk = _flat((entry["from"] as Vector3) - _local_marker(trip, "DoorStep").origin) / Constants.VAN_WALK_IN_SPEED
	return walk + Constants.VAN_STEP_SECONDS + Constants.VAN_BUCKLE_SECONDS


func _seat_settled(trip: Trip, peer_id: int, now: float) -> bool:
	var entry: Dictionary = trip.seats.get(peer_id, {})
	return not entry.is_empty() and now >= float(entry["at"]) + _board_seconds(trip, peer_id)


## A rider's place now, in VanLook space, and whether they're sat.
func _rider_local(trip: Trip, peer_id: int, now: float) -> Array:
	var entry: Dictionary = trip.seats[peer_id]
	var seat := _local_marker(trip, "Seats/Seat%d" % int(entry["seat"]))
	var step := _local_marker(trip, "DoorStep")
	var from := entry["from"] as Vector3
	var tau := now - float(entry["at"])
	var mode := int(entry["mode"])
	if trip.unseats.has(peer_id):
		var leave: Dictionary = trip.unseats[peer_id]
		var u := now - float(leave["at"])
		var exit := _pose(trip, float(leave["at"])).affine_inverse() * (leave["exit"] as Vector3)
		var unbuckle := Constants.VAN_BUCKLE_SECONDS * 0.6
		if u < unbuckle:
			return [seat, true]
		var k := clampf((u - unbuckle) / Constants.VAN_STEP_SECONDS, 0.0, 1.0)
		return [_arc(seat, Transform3D(step.basis, exit), k, 0.35), false]
	if mode == BOARD_NOW:
		return [seat, true]
	var walk := 0.0
	if mode == BOARD_WALK:
		walk = _flat(from - step.origin) / Constants.VAN_WALK_IN_SPEED
		if tau < walk:
			var k := clampf(tau / maxf(walk, 0.01), 0.0, 1.0)
			var at := from.lerp(step.origin, k)
			var dir := step.origin - from
			dir.y = 0.0
			return [Transform3D(Basis.looking_at(dir.normalized() if dir.length() > 0.01 else -step.basis.z, Vector3.UP), at), false]
		from = step.origin
	var start := Transform3D(step.basis, from)
	var k := clampf((tau - walk) / Constants.VAN_STEP_SECONDS, 0.0, 1.0)
	if k < 1.0:
		return [_arc(start, seat, k, 0.45), false]
	var knock := float(trip.knocks.get(peer_id, -10.0))
	if now >= knock and now < knock + Constants.VAN_KNOCK_SECONDS:
		var face := _local_marker(trip, "WindowFace/Seat%d" % int(entry["seat"]))
		var lean := sin((now - knock) / Constants.VAN_KNOCK_SECONDS * PI)
		return [seat.interpolate_with(face, lean), true]
	return [seat, true]


## From a to b along an arc up to lift meters high, turning from a's facing to b's.
static func _arc(a: Transform3D, b: Transform3D, k: float, lift: float) -> Transform3D:
	var e := k * k * (3.0 - 2.0 * k)
	var at := a.origin.lerp(b.origin, e) + Vector3(0.0, lift * sin(k * PI), 0.0)
	var basis := a.basis.orthonormalized().slerp(b.basis.orthonormalized(), clampf(k * 1.4, 0.0, 1.0))
	return Transform3D(basis, at)


func _place_riders(trip: Trip, now: float) -> void:
	for peer_id: Variant in trip.seats.keys().duplicate():
		var peer := int(peer_id)
		var anchor := _anchor(trip, "p%d" % peer)
		var placed := _rider_local(trip, peer, now)
		anchor.transform = placed[0] as Transform3D
		var sat := bool(placed[1])
		var player := _player(peer)
		if player == null:
			continue
		var leaving := trip.unseats.has(peer)
		var done := leaving and now >= float((trip.unseats[peer] as Dictionary)["at"]) + Constants.VAN_BUCKLE_SECONDS * 0.6 + Constants.VAN_STEP_SECONDS
		if done:
			_unstage_rider(trip, peer, false)
			trip.seats.erase(peer)
			trip.unseats.erase(peer)
			continue
		var pose: StringName = &"sit_buckled" if sat else &"stand"
		if trip.staged_pose.get(peer, &"") != pose:
			var first := not trip.staged_pose.has(peer)
			trip.staged_pose[peer] = pose
			if player.has_method("set_staged"):
				player.call("set_staged", anchor, Transform3D.IDENTITY, 0.2 if first else 0.0, pose)
			if first and peer == Net.local_peer_id():
				_seat_camera(trip, peer, true)
		var body := player.get_node_or_null("Visual/CartoonBody")
		if body != null and not player.has_method("set_staged"):
			body.call("sit", 1 if sat else 0)
			# The rides fallback: the owner's movement stays off while seated (a zone
			# change clears it, so it's set again).
			if peer == Net.local_peer_id() and player.get("_ride") != self and player.has_method("set_riding"):
				player.call("set_riding", self, seat_of(peer))
		if leaving and peer == Net.local_peer_id() and not trip.my_beats.has("unseat%d" % peer):
			trip.my_beats["unseat%d" % peer] = true
			_seat_camera(trip, peer, false)


## Off the van: the staged body lets go where it stands (it already holds the
## pose), the seat camera and the lock go.
func _unstage_rider(trip: Trip, peer_id: int, handed_on: bool) -> void:
	var player := _player(peer_id)
	if player != null and not handed_on and player.has_method("clear_staged"):
		player.call("clear_staged")
	if player != null:
		var body := player.get_node_or_null("Visual/CartoonBody")
		if body != null and not player.has_method("set_staged"):
			body.call("sit", 0)
		if player.get("_ride") == self and player.has_method("clear_riding"):
			player.call("clear_riding")
	if peer_id == Net.local_peer_id():
		_seat_camera(trip, peer_id, false)
		_radio_on(false)
	if trip.anchors.has("p%d" % peer_id):
		var anchor := trip.anchors["p%d" % peer_id] as Node3D
		trip.anchors.erase("p%d" % peer_id)
		if handed_on:
			# Whoever takes them next stages them from where this anchor is: keep it
			# a moment, then let go.
			get_tree().create_timer(1.0).timeout.connect(anchor.queue_free)
		else:
			anchor.queue_free()
	trip.staged_pose.erase(peer_id)


## The owner's seat camera and control lock (nice_boys:1), on or off.
func _seat_camera(trip: Trip, peer_id: int, on: bool) -> void:
	var player := _player(peer_id)
	if player == null:
		return
	var key := "cam%d" % peer_id
	if on == trip.my_beats.has(key):
		return
	if on:
		trip.my_beats[key] = true
	else:
		trip.my_beats.erase(key)
	if player.has_method("set_control_lock"):
		player.call("set_control_lock", SHOT_SEAT, on)
	if not player.has_method("stage_push"):
		return
	if on:
		var entry: Dictionary = trip.seats.get(peer_id, {})
		var cam := _NiceVan.marker(trip.look, "CabinCam/Seat%d" % int(entry.get("seat", 0)))
		player.call("stage_push", SHOT_SEAT, {"anchor": cam, "offset": Transform3D.IDENTITY, "blend_in": Constants.VAN_STEP_SECONDS,
			"blend_out": 0.35, "yaw_clamp": Vector2(-deg_to_rad(60.0), deg_to_rad(60.0)), "pitch_clamp": Vector2(-0.6, 0.45),
			"orbit": false, "spring": false, "fov": 0.0, "lag": 0.0, "priority": 30})
	else:
		player.call("stage_pop", SHOT_FRESHENER, 0.0)
		player.call("stage_pop", SHOT_SEAT, 0.35)


## The local rider's ride: the freshener close-up and a radio line, the iris
## closing, and opening again once the van is where it's going.
func _local_rider_beats(now: float) -> void:
	var me := Net.local_peer_id()
	for trip: Trip in _trips.values():
		if not trip.seats.has(me) or trip.unseats.has(me) or trip.look == null:
			continue
		var player := _player(me)
		for index: int in trip.legs.size():
			var leg := trip.legs[index] as Dictionary
			if not int(leg["k"]) in [Leg.DEPART, Leg.RETURN_DEPART]:
				continue
			var t := float(leg["t"])
			var drive := _segs_seconds(leg["segs"])
			# Watch the street go by, then the freshener as it nears the route's end.
			var montage := t + maxf(Constants.VAN_RIDE_IRIS_AT, drive - Constants.VAN_RIDE_MONTAGE - Constants.VAN_IRIS_SECONDS)
			var key := "montage%d" % index
			if now >= montage and not trip.my_beats.has(key):
				trip.my_beats[key] = true
				if player != null and player.has_method("stage_push"):
					player.call("stage_push", SHOT_FRESHENER, {"anchor": _NiceVan.marker(trip.look, "FreshenerCam"), "offset": Transform3D.IDENTITY,
						"blend_in": 0.4, "blend_out": 0.0, "yaw_clamp": Vector2.ZERO, "pitch_clamp": Vector2.ZERO, "orbit": false,
						"spring": false, "fov": 0.0, "lag": 0.0, "priority": 60})
				_radio_on(true)
				var lines: Array = _Strings.VAN_LINES.get("ride_radio", [])
				var stack := get_tree().get_first_node_in_group("caption_stack")
				if not lines.is_empty() and stack != null and stack.has_method("push"):
					stack.call("push", &"radio", str(lines[absi(hash("%d" % trip.id)) % lines.size()]), Constants.VAN_RIDE_MONTAGE + 1.5)
				if trip.driver != null:
					var sfx := get_tree().get_first_node_in_group("sfx")
					if sfx != null:
						sfx.call("play_on", "babble", trip.driver, -6.0)
			var close_key := "iris%d" % index
			if now >= montage + Constants.VAN_RIDE_MONTAGE - 0.05 and not trip.my_beats.has(close_key):
				trip.my_beats[close_key] = true
				var iris := get_tree().get_first_node_in_group("iris")
				if iris != null and iris.has_method("close"):
					iris.call("close", maxf(montage + Constants.VAN_RIDE_MONTAGE, now), Constants.VAN_IRIS_SECONDS, &"seal")
		# Open again where it's going: our zone changed and the van is there.
		var leg_now := _current_leg(trip, now)
		var kind := int(leg_now.get("k", -1))
		var there := kind in [Leg.ANNEX_ARRIVE, Leg.ANNEX_PARKED, Leg.DROP_ARRIVE, Leg.DROP_PARKED]
		var zone_ok := Net.player_zone(me) == int(trip.info.get("zone", Net.player_zone(me)))
		var open_key := "open%d" % int(leg_now.get("t", 0.0) * 100.0)
		if there and zone_ok and trip.my_beats.has("iris%d" % _last_drive_index(trip)) and not trip.my_beats.has(open_key):
			trip.my_beats[open_key] = true
			if player != null and player.has_method("stage_pop"):
				player.call("stage_pop", SHOT_FRESHENER, 0.0)
			_radio_on(false)
			var iris := get_tree().get_first_node_in_group("iris")
			if iris != null and iris.has_method("open"):
				iris.call("open", now + 0.05, Constants.VAN_IRIS_SECONDS)


func _last_drive_index(trip: Trip) -> int:
	var found := -1
	for index: int in trip.legs.size():
		if int((trip.legs[index] as Dictionary)["k"]) in [Leg.DEPART, Leg.RETURN_DEPART]:
			found = index
	return found


func _radio_on(on: bool) -> void:
	if on and _radio == null and not Net.is_automated() and DisplayServer.get_name() != "headless":
		var stream := _Sfx.looped("radio_babble")
		if stream == null:
			return
		_radio = AudioStreamPlayer.new()
		_radio.stream = stream
		_radio.bus = &"Sfx"
		_radio.volume_db = -10.0
		add_child(_radio)
		_radio.play()
	elif not on and _radio != null:
		_radio.stop()
		_radio.queue_free()
		_radio = null


func _local_iris_closed() -> bool:
	var iris := get_tree().get_first_node_in_group("iris")
	return iris != null and iris.has_method("is_closed") and bool(iris.call("is_closed"))


func _riders_iris_closed(trip: Trip, now: float) -> bool:
	if bool(trip.info.get("dev_skip", false)):
		return true
	var index := _last_drive_index(trip)
	if index < 0:
		return true
	var leg := trip.legs[index] as Dictionary
	var drive := _segs_seconds(leg["segs"])
	var montage := float(leg["t"]) + maxf(Constants.VAN_RIDE_IRIS_AT, drive - Constants.VAN_RIDE_MONTAGE - Constants.VAN_IRIS_SECONDS)
	return now >= montage + Constants.VAN_RIDE_MONTAGE + Constants.VAN_IRIS_SECONDS + 0.1


# ---------------------------------------------------------------- the crew (every peer)


static func _crew_turn() -> Transform3D:
	# The crew walk with +Z forward (npcs/crew_member.gd _steer); anchors face -Z.
	return Transform3D(Basis(Vector3.UP, PI), Vector3.ZERO)


func _crew_hop_out_seconds(entry: Dictionary) -> float:
	return 0.35 + 0.9 + Constants.VAN_HOP_SECONDS


## A NICE BOY's place now, in VanLook space: [transform, sitting, done].
func _crew_local(trip: Trip, index: int, now: float) -> Array:
	var entry: Dictionary = trip.crew[index]
	var mode := int(entry["mode"])
	var seat_index := clampi(int(entry["seat"]), 0, 2)
	var seat := _local_marker(trip, "CrewSeats/Seat%d" % seat_index)
	var step := _local_marker(trip, "DoorStep")
	var tau := now - float(entry["at"])
	# The sill inside the door, and a point in the aisle, for the walk out and in.
	var sill := Transform3D(step.basis, Vector3(0.95, 1.01, clampf(seat.origin.z, -0.9, 1.0)))
	var aisle := Transform3D(step.basis, Vector3(0.35, 1.01, clampf(seat.origin.z, -1.3, 1.1)))
	match mode:
		CREW_SEATED:
			return [seat, true, false]
		CREW_HOP_OUT:
			if tau < 0.0:
				return [seat, true, false]
			var order := int((entry["from"] as Vector3).x)
			var land := Transform3D(step.basis, step.origin + Vector3(0.6 * float(order % 2), 0.0, -0.9 + 1.1 * float(order)))
			if tau < 0.35:
				return [_arc(seat, aisle, tau / 0.35, 0.05), false, false]
			if tau < 1.25:
				return [_arc(aisle, sill, (tau - 0.35) / 0.9, 0.0), false, false]
			var k := (tau - 1.25) / Constants.VAN_HOP_SECONDS
			if k < 1.0:
				return [_arc(sill, land, k, 0.35), false, false]
			return [land, false, true]
		CREW_HOP_IN:
			var from := Transform3D(step.basis, entry["from"] as Vector3)
			var walk := _flat(from.origin - step.origin) / 4.0
			if tau < walk:
				return [from.interpolate_with(step, tau / maxf(walk, 0.01)), false, false]
			var k := (tau - walk) / Constants.VAN_HOP_SECONDS
			if k < 1.0:
				return [_arc(step, sill, k, 0.35), false, false]
			var m := (tau - walk - Constants.VAN_HOP_SECONDS) / 0.9
			if m < 1.0:
				return [_arc(sill, aisle, m, 0.0), false, false]
			var n := (tau - walk - Constants.VAN_HOP_SECONDS - 0.9) / 0.35
			if n < 1.0:
				return [_arc(aisle, seat, n, 0.05), false, false]
			return [seat, true, false]
		_:
			var rear := _local_marker(trip, "RearStep")
			var from := Transform3D(rear.basis, entry["from"] as Vector3)
			var k := tau / Constants.VAN_HOP_SECONDS
			if k < 1.0:
				return [_arc(from, rear, k, 0.45), false, false]
			return [rear, false, false]


func _place_crew(trip: Trip, now: float) -> void:
	for index: Variant in trip.crew.keys():
		var i := int(index)
		var crew := _crew_node(i)
		var placed := _crew_local(trip, i, now)
		var anchor := _anchor(trip, "c%d" % i)
		anchor.transform = (placed[0] as Transform3D) * _crew_turn()
		if crew == null:
			continue
		var done := bool(placed[2])
		var sitting := bool(placed[1])
		var state: String = "done" if done else ("sit" if sitting else "stand")
		var was := str(trip.crew_staged.get(i, ""))
		if state != was:
			trip.crew_staged[i] = state
			if done:
				_unstage_crew(trip, i)
			else:
				_stage_crew(crew, anchor, sitting, was == "")
				if was == "sit" and state == "stand" and int((trip.crew[index] as Dictionary)["mode"]) == CREW_HOP_OUT:
					_VanGestures.play(crew.get_node_or_null("Visual/CartoonBody"), "step_up")
				if int((trip.crew[index] as Dictionary)["mode"]) == CREW_REAR and was != "stand":
					_VanGestures.play(crew.get_node_or_null("Visual/CartoonBody"), "straggler_hop")
		if not done and Net.is_host() and not crew.has_method("set_staged"):
			# The fallback, host side: the body itself sits where the anchor is (the
			# synchronizer sends it on), its brain off while it rides.
			(crew as Node3D).global_transform = anchor.global_transform
			(crew as CharacterBody3D).velocity = Vector3.ZERO
		if done and not trip.played.has("land%d_%.2f" % [i, float((trip.crew[index] as Dictionary)["at"])]):
			trip.played["land%d_%.2f" % [i, float((trip.crew[index] as Dictionary)["at"])]] = true
			var sfx := get_tree().get_first_node_in_group("sfx")
			if sfx != null:
				sfx.call("play_on", "hop_land" if _has_sound("hop_land") else "step_hard", crew)


func _stage_crew(crew: Node, anchor: Node3D, sitting: bool, first: bool) -> void:
	if crew.has_method("set_staged"):
		crew.call("set_staged", anchor, Transform3D.IDENTITY, 0.25 if first else 0.0, &"sit_buckled" if sitting else &"stand")
		return
	var body := crew.get_node_or_null("Visual/CartoonBody")
	if body != null:
		body.call("sit", 1 if sitting else 0)
	if Net.is_host():
		crew.set_physics_process(false)
	else:
		var smoother := crew.get_node_or_null("NetSmoother")
		if smoother != null:
			smoother.set_physics_process(false)
			smoother.set_process(false)
		var visual := crew.get_node_or_null("Visual") as Node3D
		if visual != null:
			visual.top_level = true
			visual.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	crew.set_meta("shuttle_staged", true)


func _unstage_crew(trip: Trip, index: int) -> void:
	var crew := _crew_node(index)
	trip.crew_staged[index] = "done"
	if crew == null:
		return
	if crew.has_method("clear_staged"):
		crew.call("clear_staged")
		return
	if not crew.has_meta("shuttle_staged"):
		return
	crew.remove_meta("shuttle_staged")
	var body := crew.get_node_or_null("Visual/CartoonBody")
	if body != null:
		body.call("sit", 0)
	if Net.is_host():
		crew.set_physics_process(true)
	else:
		var visual := crew.get_node_or_null("Visual") as Node3D
		if visual != null:
			visual.top_level = false
			visual.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_INHERIT
			visual.transform = Transform3D.IDENTITY
			visual.reset_physics_interpolation()
		var smoother := crew.get_node_or_null("NetSmoother")
		if smoother != null:
			smoother.set("_samples", [] as Array[Dictionary])
			smoother.set_physics_process(true)
			smoother.set_process(true)


## The crew fallback on clients: their drawn bodies sit on the interpolated anchors,
## not 100 ms behind the van through the network smoother.
func _draw_crew_fallback(trip: Trip) -> void:
	if Net.is_host():
		return
	for index: Variant in trip.crew.keys():
		var crew := _crew_node(int(index))
		if crew == null or not crew.has_meta("shuttle_staged") or not trip.anchors.has("c%d" % int(index)):
			continue
		var visual := crew.get_node_or_null("Visual") as Node3D
		var anchor := trip.anchors["c%d" % int(index)] as Node3D
		if visual != null:
			visual.global_transform = anchor.get_global_transform_interpolated()


func _crew_entry(trip: Trip, crew: Node) -> Dictionary:
	if not crew.has_method("crew_index"):
		return {}
	var entry: Dictionary = trip.crew.get(int(crew.call("crew_index")), {})
	if entry.is_empty() or (int(entry["mode"]) == CREW_HOP_OUT and str(trip.crew_staged.get(int(crew.call("crew_index")), "")) == "done"):
		return {}
	return entry


func _crew_node(index: int) -> Node3D:
	var world := _world()
	return world.get_node_or_null("Npcs/Crew%d" % index) as Node3D if world != null else null


# ---------------------------------------------------------------- local input


func _input(event: InputEvent) -> void:
	if Net.current_state() != Net.State.IN_SESSION or multiplayer.multiplayer_peer == null:
		return
	if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED and not Net.is_automated():
		return
	var me := Net.local_peer_id()
	var mine := seat_info(me)
	if not mine.is_empty():
		# Seated: primary knocks on the glass; nothing else of yours reaches the game.
		if event.is_action_pressed("primary"):
			request_knock()
			get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("interact"):
		var target := _unbuckle_target()
		if not target.is_empty():
			start_unbuckle(int(target["trip"]), int(target["peer"]))
			get_viewport().set_input_as_handled()


## Knock on the van's glass (the local rider). Bots and tests call it too.
func request_knock() -> void:
	var now := Net.server_time()
	if now - _knocked_at < Constants.VAN_KNOCK_SECONDS:
		return
	_knocked_at = now
	if Net.is_host():
		_host_knock(Net.local_peer_id())
	else:
		_rpc_request_knock.rpc_id(1)


## Start holding the door to unbuckle target (the local player); _step_my_hold
## finishes it while interact stays down (or at once for a bot: hold = true).
func start_unbuckle(trip_id: int, target: int, bot: bool = false) -> void:
	_my_hold = {"trip": trip_id, "target": target, "at": Net.server_time(), "bot": bot}
	if Net.is_host():
		_host_unbuckle(Net.local_peer_id(), target, true)
	else:
		_rpc_request_unbuckle.rpc_id(1, target, true)
	var me := _player(Net.local_peer_id())
	var body := me.get_node_or_null("Visual/CartoonBody") if me != null else null
	if body != null:
		body.call("gesture", "scratch")


func _step_my_hold() -> void:
	if _my_hold.is_empty():
		return
	var held := bool(_my_hold.get("bot", false)) or Input.is_action_pressed("interact")
	if not held:
		_my_hold.clear()
		return
	if Net.server_time() - float(_my_hold["at"]) < Constants.VAN_UNBUCKLE_HOLD:
		return
	var target := int(_my_hold["target"])
	_my_hold.clear()
	if Net.is_host():
		_host_unbuckle(Net.local_peer_id(), target, false)
	else:
		_rpc_request_unbuckle.rpc_id(1, target, false)


## The rider the local player could unbuckle from where they stand, {} if none.
func _unbuckle_target() -> Dictionary:
	var me := _player(Net.local_peer_id())
	if me == null:
		return {}
	var now := Net.server_time()
	for trip: Trip in _trips.values():
		if trip.look == null or not bool(trip.doors["side"][0]):
			continue
		var step := _pose(trip, now) * _local_marker(trip, "DoorStep").origin
		if Vector2(me.global_position.x - step.x, me.global_position.z - step.z).length() > Constants.VAN_DOOR_REACH:
			continue
		for peer_id: Variant in trip.seats.keys():
			if _seat_settled(trip, int(peer_id), now) and not trip.unseats.has(peer_id):
				return {"trip": trip.id, "peer": int(peer_id)}
	return {}


# ---------------------------------------------------------------- the pure pose


## The van's pose at server time t: the leg in force then, moving or standing.
func _pose(trip: Trip, t: float) -> Transform3D:
	var leg := _current_leg(trip, t)
	if leg.is_empty():
		if trip.legs.is_empty():
			return Transform3D()
		leg = trip.legs[0]
	return leg_pose(leg, t)


static func leg_pose(leg: Dictionary, t: float) -> Transform3D:
	if leg.has("x"):
		return leg["x"] as Transform3D
	var points: PackedVector3Array = leg["p"]
	var s := leg_distance(leg, t - float(leg["t"]))
	return _route_pose(points, s)


## Where along its route a moving leg is tau seconds in: v0 and the constant-
## acceleration segments, integrated, never backwards.
static func leg_distance(leg: Dictionary, tau: float) -> float:
	var v := float(leg.get("v0", 0.0))
	var s := 0.0
	var left := maxf(tau, 0.0)
	var segs: PackedFloat32Array = leg.get("segs", PackedFloat32Array())
	var index := 0
	while index + 1 < segs.size() and left > 0.0:
		var dt := minf(left, segs[index])
		var acc := segs[index + 1]
		# Braking stops at rest: never rolls back.
		if acc < 0.0 and v + acc * dt < 0.0:
			dt = v / -acc
			s += v * dt * 0.5
			v = 0.0
		else:
			s += v * dt + 0.5 * acc * dt * dt
			v += acc * dt
		left -= minf(left, segs[index])
		index += 2
	if left > 0.0 and v > 0.0:
		s += v * left
	return s


static func leg_speed(leg: Dictionary, tau: float) -> float:
	var v := float(leg.get("v0", 0.0))
	var left := maxf(tau, 0.0)
	var segs: PackedFloat32Array = leg.get("segs", PackedFloat32Array())
	var index := 0
	while index + 1 < segs.size() and left > 0.0:
		var dt := minf(left, segs[index])
		v = maxf(0.0, v + segs[index + 1] * dt)
		left -= dt
		index += 2
	return v


static func _segs_seconds(segs: PackedFloat32Array) -> float:
	var total := 0.0
	var index := 0
	while index < segs.size():
		total += segs[index]
		index += 2
	return total


## A pose s meters along a route: on its points, facing along it (looking a meter
## either way, so a bend never snaps the heading).
static func _route_pose(points: PackedVector3Array, s: float) -> Transform3D:
	var length := _polyline_length(points)
	var at := _point_at(points, clampf(s, 0.0, length))
	var ahead := _point_at(points, clampf(s + 1.0, 0.0, length))
	var behind := _point_at(points, clampf(s - 1.0, 0.0, length))
	var dir := ahead - behind
	dir.y = 0.0
	if dir.length() < 0.001:
		dir = points[points.size() - 1] - points[0]
		dir.y = 0.0
	if dir.length() < 0.001:
		dir = Vector3.FORWARD
	return Transform3D(Basis.looking_at(dir.normalized(), Vector3.UP), at)


static func _point_at(points: PackedVector3Array, s: float) -> Vector3:
	var left := s
	for index: int in points.size() - 1:
		var span := points[index].distance_to(points[index + 1])
		if left <= span or index == points.size() - 2:
			return points[index].lerp(points[index + 1], clampf(left / maxf(span, 0.0001), 0.0, 1.0))
		left -= span
	return points[0] if not points.is_empty() else Vector3.ZERO


static func _polyline_length(points: PackedVector3Array) -> float:
	var total := 0.0
	for index: int in points.size() - 1:
		total += points[index].distance_to(points[index + 1])
	return total


func _current_leg(trip: Trip, t: float) -> Dictionary:
	var found: Dictionary = {}
	for leg: Dictionary in trip.legs:
		if float(leg["t"]) <= t:
			found = leg
		else:
			break
	return found


## The current moving leg has reached its route's end (a standing leg: always).
func _leg_done(trip: Trip, t: float) -> bool:
	var leg := _current_leg(trip, t)
	if leg.is_empty():
		return false
	if not leg.has("segs"):
		return true
	return t - float(leg["t"]) >= _segs_seconds(leg["segs"])


func _speed_at(trip: Trip, t: float) -> float:
	var leg := _current_leg(trip, t)
	if leg.is_empty() or not leg.has("segs"):
		return 0.0
	return leg_speed(leg, t - float(leg["t"]))


## When the raid van's pull-up ends (its PARKED leg starts).
func _arrive_end(trip: Trip) -> float:
	for leg: Dictionary in trip.legs:
		if int(leg["k"]) == Leg.PARKED:
			return float(leg["t"])
	return Net.server_time()


## The PARKED leg in force at t with riders aboard (the hold), or {}.
func _hold_leg(trip: Trip, t: float) -> Dictionary:
	var leg := _current_leg(trip, t)
	if leg.is_empty() or int(leg["k"]) != Leg.PARKED or trip.seats.is_empty():
		return {}
	return leg


# ---------------------------------------------------------------- seeing it


## Whether this peer's camera can see the van now: in front of it, not past
## VAN_HIDE_METERS, and a clear line to the body.
func _locally_seen(trip: Trip) -> bool:
	if trip.holder == null:
		return false
	var camera := get_viewport().get_camera_3d() if is_inside_tree() else null
	var center := trip.holder.global_position + Vector3(0.0, 1.6, 0.0)
	var eye := Vector3.INF
	if camera != null:
		eye = camera.global_position
		if not camera.is_position_in_frustum(center) and not camera.is_position_in_frustum(center + trip.holder.global_basis.z * 3.0) and not camera.is_position_in_frustum(center - trip.holder.global_basis.z * 3.0):
			return false
	else:
		var me := _player(Net.local_peer_id())
		if me == null:
			return false
		eye = me.global_position + Vector3(0.0, 1.6, 0.0)
	if eye.distance_to(center) > Constants.VAN_HIDE_METERS:
		return false
	return _line_clear(eye, center, trip) or _line_clear(eye, center + Vector3(0.0, 1.2, 0.0), trip)


## Host: whether anyone on the yard (not a rider) might see the van now.
func _seen_by_yard(trip: Trip, now: float, riders: Array) -> bool:
	var center := _pose(trip, now).origin + Vector3(0.0, 1.6, 0.0)
	for node: Node in get_tree().get_nodes_in_group("players"):
		var peer := node.name.to_int()
		if riders.has(peer) or seat_info(peer).size() > 0:
			continue
		var zone := Net.player_zone(peer)
		if zone != Net.Zone.LOT and zone != Net.Zone.TOWN:
			continue
		var eye := (node as Node3D).global_position + Vector3(0.0, 1.6, 0.0)
		if eye.distance_to(center) > Constants.VAN_HIDE_METERS:
			continue
		if _line_clear(eye, center, trip) or _line_clear(eye, center + Vector3(0.0, 1.2, 0.0), trip):
			return true
	return false


func _line_clear(from: Vector3, to: Vector3, trip: Trip) -> bool:
	var space := get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.create(from, to, 1)
	query.collide_with_areas = false
	var hit := space.intersect_ray(query)
	if hit.is_empty():
		return true
	var collider := hit.get("collider") as Node
	return collider == null or collider is CharacterBody3D or (trip.look != null and trip.look.is_ancestor_of(collider))


func _local_is_rider(trip: Trip) -> bool:
	return trip.seats.has(Net.local_peer_id())


# ---------------------------------------------------------------- helpers


func _trip(trip_id: int) -> Trip:
	return _trips.get(trip_id) as Trip


func _anchor(trip: Trip, key: String) -> Node3D:
	if trip.anchors.has(key) and is_instance_valid(trip.anchors[key]):
		return trip.anchors[key]
	var anchor := Node3D.new()
	anchor.name = "Anchor_" + key
	trip.look.add_child(anchor)
	trip.anchors[key] = anchor
	return anchor


## A van marker's transform in VanLook space, swaying with the body for those on
## the Shell. Works before the look exists (an unswayed default build).
func _local_marker(trip: Trip, path: String) -> Transform3D:
	var look := trip.look if trip != null and trip.look != null else _reference_look()
	var node := _NiceVan.marker(look, path)
	if node == null:
		return Transform3D()
	var xform := node.transform
	var parent := node.get_parent() as Node3D
	while parent != null and parent != look:
		xform = parent.transform * xform
		parent = parent.get_parent() as Node3D
	return xform


var _reference: Node3D


func _reference_look() -> Node3D:
	if _reference == null:
		var holder := Node3D.new()
		_reference = _NiceVan.build(holder)
	return _reference


func _riding_peers(trip: Trip) -> Array:
	var out: Array = []
	for peer_id: Variant in trip.seats.keys():
		if not trip.unseats.has(peer_id):
			out.append(int(peer_id))
	return out


func _seat_info_any(peer_id: int) -> Variant:
	var info := seat_info(peer_id)
	return null if info.is_empty() else info


## Tells the Encounter (nice_boys:2) a rider's stage, when there is one.
func _stage(peer_id: int, stage: int) -> void:
	var encounter := get_tree().get_first_node_in_group("nice_encounter")
	if encounter != null and encounter.has_method("host_set_stage"):
		encounter.call("host_set_stage", peer_id, stage, {})


## Out of the cohort with immunity: the R2 director takes the seconds, the old one
## gives its own.
func _release(peer_id: int, immunity: float) -> void:
	var director := get_parent()
	if director == null or not director.has_method("release_peer"):
		return
	if _director_has_r2() and immunity >= 0.0:
		director.call("release_peer", peer_id, immunity)
	else:
		director.call("release_peer", peer_id)


func _director_has_r2() -> bool:
	var director := get_parent()
	return director != null and director.has_method("host_begin_departure")


func _encounter_present() -> bool:
	return get_tree().get_first_node_in_group("nice_encounter") != null


func _player_has_staging() -> bool:
	if _has_staging < 0:
		_has_staging = 0
		var script := load("res://player/player.gd") as Script
		if script != null:
			for method: Dictionary in script.get_script_method_list():
				if str(method.get("name", "")) == "set_staged":
					_has_staging = 1
	return _has_staging == 1


func _has_sound(id: String) -> bool:
	return preload("res://audio/sound_bank.gd").has(id)


func _player(peer_id: int) -> Node3D:
	for node: Node in get_tree().get_nodes_in_group("players"):
		if node.name == str(peer_id):
			return node as Node3D
	return null


func _world() -> Node:
	return get_tree().get_first_node_in_group("world") if is_inside_tree() else null


func _lot_zone() -> Node3D:
	var world := _world()
	return world.get_node_or_null("LotZone") as Node3D if world != null else null


static func _flat(v: Vector3) -> float:
	return Vector2(v.x, v.z).length()


static func _int_keys(source: Variant) -> Dictionary:
	var out: Dictionary = {}
	for key: Variant in (source as Dictionary).keys():
		out[int(key)] = (source as Dictionary)[key]
	return out


func _on_player_left(peer_id: int) -> void:
	_holds.erase(peer_id)
	for trip: Trip in _trips.values():
		if trip.seats.has(peer_id):
			if trip.anchors.has("p%d" % peer_id):
				(trip.anchors["p%d" % peer_id] as Node3D).queue_free()
				trip.anchors.erase("p%d" % peer_id)
			trip.seats.erase(peer_id)
			trip.unseats.erase(peer_id)
			trip.staged_pose.erase(peer_id)
	_handled.erase(peer_id)


func _exit_tree() -> void:
	if _reference != null:
		var holder := _reference.get_parent()
		if holder != null:
			holder.free()
		_reference = null
