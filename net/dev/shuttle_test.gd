extends Node

## --shuttle-test (nice_boys:4, port 7829, host plus a Target client, both with
## --sim-lag=150 --shuttle-test). Both peers run this node; the host drives and
## asks the client through this node's own RPCs. Each step prints a
## [ShuttleTest] line; steps that need another R2 chunk (the Encounter's stages,
## the iris in a headless run) say "pending" instead of failing.
##
##   park      a tree and a prop on the curb move the park point along it, and its
##             clearance box is empty
##   raid      the van pulls up during the warning with the crew seated in it: the
##             crew stay on their seat anchors on the client while it moves, and
##             every route point has ground under it
##   poses     host and client work out the same van pose at the same server time
##             (within 0.05 m) on every leg the trip had
##   seats     a boarded client sits; seats == boarded on both peers
##   unbuckle  refused next to a NICE BOY who can see you, refused while the driver
##             checks his mirror, and done unseen: the rider steps out, released
##   straggler the van leaving with the crew out creeps with its back doors open
##             and a NICE BOY hops onto the bumper
##   ride      the rider's zone moves only after their iris has closed (the host's
##             schedule; the client's iris too when it has one), the van is freed
##             after it leaves, and nothing the client saw moved faster than
##             VAN_MAX_SCREEN_SPEED or more than 1 m a tick
##   dropoff   the return shuttle puts the rider on the curb, released, immune
##   rides     no Rides/Van node; another ride arriving leaves Chefty's riders alone

const _Trees = preload("res://props/trees.gd")
const _RideScript: Script = preload("res://net/components/ride.gd")
const _ShuttleScript = preload("res://net/run_events/shuttle.gd")
const CLIENT_WAIT_SECONDS: float = 20.0
const STEP_WAIT_SECONDS: float = 30.0
const POSE_TOLERANCE: float = 0.05
const SEAT_TOLERANCE: float = 0.05
const STEP_MAX_METERS: float = 1.0

static var result: Dictionary = {}

var _started: bool = false
var _steps: Dictionary = {}
var _problems: Array[String] = []
var _client: int = 0
var _reply: Dictionary = {}
# Client: what it measured, sent to the host at the end.
var _crew_err_max: float = 0.0
var _crew_samples: int = 0
var _zone_iris: Array = []
var _watching: bool = false


func _ready() -> void:
	# After the Shuttle draws the crew this frame (priority 50).
	process_priority = 200
	if not Net.player_zone_changed.is_connected(_on_zone_changed):
		Net.player_zone_changed.connect(_on_zone_changed)


func _physics_process(_delta: float) -> void:
	if _started or not Net.is_host() or get_tree().get_first_node_in_group("world") == null:
		return
	_started = true
	_run()


func _process(_delta: float) -> void:
	if Net.is_host() or not _watching:
		return
	# Client: every crew member the van carries stays on its anchor while it moves.
	var shuttle := _shuttle()
	if shuttle == null:
		return
	for trip_id: Variant in shuttle.call("trip_ids"):
		var leg := str(shuttle.call("leg_name", int(trip_id)))
		if not leg in ["arrive", "depart", "creep"]:
			continue
		for crew: Node in get_tree().get_nodes_in_group("crew"):
			var index := int(crew.call("crew_index"))
			var anchor: Transform3D = shuttle.call("anchor_transform", int(trip_id), "c%d" % index, true)
			var visual := crew.get_node_or_null("Visual") as Node3D
			if anchor == Transform3D() or visual == null or not crew.has_meta("shuttle_staged"):
				continue
			_crew_err_max = maxf(_crew_err_max, visual.global_position.distance_to(anchor.origin))
			_crew_samples += 1


func _on_zone_changed(peer_id: int, zone: Net.Zone) -> void:
	if peer_id != Net.local_peer_id() or Net.is_host():
		return
	var iris := get_tree().get_first_node_in_group("iris")
	_zone_iris.append({"zone": int(zone), "iris": "none" if iris == null else str(bool(iris.call("is_closed")))})


func _run() -> void:
	var waited := 0.0
	while Net.peer_ids().size() < 2 and waited < CLIENT_WAIT_SECONDS:
		await get_tree().create_timer(0.25).timeout
		waited += 0.25
	for peer_id: int in Net.peer_ids():
		if peer_id != 1:
			_client = peer_id
	if _client == 0:
		_finish(false, "no client joined")
		return
	await get_tree().create_timer(2.0).timeout
	_rpc_watch.rpc_id(_client)
	var shuttle := _shuttle()
	if shuttle == null:
		_finish(false, "no Shuttle under the run director")
		return
	await _step_park(shuttle)
	await _step_raid(shuttle)
	await _step_seats(shuttle)
	await _step_unbuckle(shuttle)
	await _step_straggler(shuttle)
	await _step_ride(shuttle)
	await _step_dropoff(shuttle)
	_step_rides()
	_finish(_problems.is_empty(), "")


# ---------------------------------------------------------------- steps


func _step_park(shuttle: Node) -> void:
	var lot := get_tree().get_first_node_in_group("world").get_node("LotZone") as Node3D
	var plain: Transform3D = shuttle.call("_default_curb")
	shuttle.set("_park_cache", {})
	var free: Transform3D = shuttle.call("_host_park")
	# A tree on that spot and a prop just past it: the van slides along the curb.
	var tree := _Trees.spawn(lot, lot.global_transform.affine_inverse() * free.origin, 8.0, "pine")
	var prop := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(0.8, 1.0, 0.8)
	shape.shape = box
	shape.position.y = 0.5
	prop.add_child(shape)
	lot.add_child(prop)
	prop.global_position = free.origin - free.basis.z * 4.0
	await get_tree().physics_frame
	await get_tree().physics_frame
	shuttle.set("_trees_at", -100000)
	shuttle.set("_park_cache", {})
	var moved: Transform3D = shuttle.call("_host_park")
	var slid := moved.origin.distance_to(free.origin)
	var clear := bool(shuttle.call("_box_clear", moved))
	_check("park", slid >= 1.0 and clear and absf((moved.origin - plain.origin).dot(plain.basis.x)) < 0.3, "slid %.1f m along the curb, box clear %s" % [slid, clear])
	tree.queue_free()
	prop.queue_free()
	await get_tree().physics_frame
	shuttle.set("_trees_at", -100000)
	shuttle.set("_park_cache", {})


func _step_raid(shuttle: Node) -> void:
	var director := _director()
	director.call("force_event")
	var trip := 0
	var waited := 0.0
	while waited < 2.0 and trip == 0:
		await get_tree().physics_frame
		waited += get_physics_process_delta_time()
		trip = int(shuttle.call("raid_trip_id"))
	var crew_seated := get_tree().get_nodes_in_group("crew").size()
	var parked: Variant = await _wait_for(func() -> Variant:
		return true if str(shuttle.call("leg_name", trip)) == "parked" and int(director.call("phase")) == 2 else null)
	# Freeze the crew where they land, so nobody is caught by the old chase.
	await get_tree().create_timer(3.0).timeout
	for crew: Node in get_tree().get_nodes_in_group("crew"):
		crew.set("_stun_left", 1000.0)
	var ground_ok := _routes_on_ground(shuttle, trip)
	_check("raid", trip > 0 and parked != null and crew_seated >= 1 and ground_ok, "trip %d parked %s with %d NICE BOYS seated at the call; routes on ground %s" % [trip, parked != null, crew_seated, ground_ok])
	_steps["trip"] = trip


func _step_seats(shuttle: Node) -> void:
	var trip := int(_steps.get("trip", 0))
	var seat := int(shuttle.call("host_board", _client))
	var sat: Variant = await _wait_for(func() -> Variant:
		return true if bool((shuttle.call("seat_info", _client) as Dictionary).get("settled", false)) else null)
	var reply: Dictionary = await _ask("seats", {})
	var host_seats := (shuttle.call("seated_riders") as Array).size()
	var director := _director()
	var cohort_free := not bool(director.call("is_captured", _client))
	_check("seats", seat >= 0 and sat != null and host_seats == 1 and int(reply.get("seated", -1)) == host_seats and int(reply.get("boarded", -1)) == 1, "seat %d, host seated %d, client seated %s boarded %s (cohort %s)" % [seat, host_seats, reply.get("seated"), reply.get("boarded"), "no" if cohort_free else "yes"])
	_steps["trip"] = trip


func _step_unbuckle(shuttle: Node) -> void:
	var trip := int(_steps.get("trip", 0))
	var me := _me()
	var step: Vector3 = shuttle.call("door_step_point")
	var pose: Transform3D = shuttle.call("trip_pose", trip, Net.server_time())
	me.call("apply_network_teleport", Transform3D(Basis.IDENTITY, step + pose.basis.x.normalized() * 0.8 + Vector3(0.0, 0.1, 0.0)))
	await get_tree().create_timer(0.3).timeout
	# A NICE BOY right beside you, looking.
	var guard := get_tree().get_nodes_in_group("crew")[0] as Node3D
	var guard_was := guard.global_position
	guard.global_position = me.global_position + pose.basis.x.normalized() * 1.5
	await get_tree().physics_frame
	await get_tree().physics_frame
	print("[ShuttleTest] at the door: %.2f m from the step" % Vector2(me.global_position.x - step.x, me.global_position.z - step.z).length())
	shuttle.call("_host_unbuckle", 1, _client, true)
	var guarded := str((shuttle.get("stats") as Dictionary).get("last_refusal", ""))
	guard.global_position = guard_was + Vector3(0.0, 0.0, -40.0)
	await get_tree().physics_frame
	# The driver's mirror check.
	var mirror_seen := ""
	var hold_start := float(_hold_started(shuttle, trip))
	var window: Vector2 = shuttle.call("mirror_window", trip, Net.server_time() - hold_start)
	while Net.server_time() - hold_start < window.x + 0.2:
		await get_tree().physics_frame
	shuttle.call("_host_unbuckle", 1, _client, true)
	mirror_seen = str((shuttle.get("stats") as Dictionary).get("last_refusal", ""))
	# Unseen: right after a check, with time to spare before the next.
	while bool(shuttle.call("mirror_checking", trip, Net.server_time())):
		await get_tree().physics_frame
	var next: Vector2 = shuttle.call("mirror_window", trip, Net.server_time() - hold_start + Constants.VAN_MIRROR_SECONDS + 0.01)
	var left := next.x - (Net.server_time() - hold_start)
	if left < Constants.VAN_UNBUCKLE_HOLD + 0.4:
		await get_tree().create_timer(left + Constants.VAN_MIRROR_SECONDS + 0.1).timeout
	var before := int((shuttle.get("stats") as Dictionary).get("unbuckles", 0))
	shuttle.call("_host_unbuckle", 1, _client, true)
	await get_tree().create_timer(Constants.VAN_UNBUCKLE_HOLD).timeout
	shuttle.call("_host_unbuckle", 1, _client, false)
	var out: Variant = await _wait_for(func() -> Variant:
		return true if (shuttle.call("seat_info", _client) as Dictionary).is_empty() else null)
	var done := int((shuttle.get("stats") as Dictionary).get("unbuckles", 0)) - before
	var director := _director()
	var safe := float((director.get("_safe_until") as Dictionary).get(_client, 0.0)) > Net.server_time()
	_check("unbuckle", guarded == "guard" and mirror_seen == "mirror" and done == 1 and out != null and safe, "guard refusal '%s', mirror refusal '%s', unbuckled %d, out %s, immune %s" % [guarded, mirror_seen, done, out != null, safe])


func _step_straggler(shuttle: Node) -> void:
	var trip := int(_steps.get("trip", 0))
	# Back in for the ride, then off with every NICE BOY still out on the lawn.
	shuttle.call("host_board", _client)
	await _wait_for(func() -> Variant:
		return true if bool((shuttle.call("seat_info", _client) as Dictionary).get("settled", false)) else null)
	var crew := get_tree().get_nodes_in_group("crew")[0] as Node3D
	var pose: Transform3D = shuttle.call("trip_pose", trip, Net.server_time())
	crew.global_position = pose * Vector3(1.0, 0.0, 9.0)
	shuttle.call("dev_straggle", int(crew.call("crew_index")))
	shuttle.call("host_depart", Net.server_time() + 0.3)
	var crept: Variant = await _wait_for(func() -> Variant:
		return true if str(shuttle.call("leg_name", trip)) == "creep" else null)
	var hopped: Variant = await _wait_for(func() -> Variant:
		return true if int((shuttle.get("stats") as Dictionary).get("stragglers", 0)) >= 1 else null)
	var back := shuttle.get_node_or_null("Trip%d/VanLook/Shell/BackDoors" % trip)
	var doors_open := back != null and float(back.get("openness")) > 0.5
	_check("straggler", crept != null and hopped != null and doors_open, "crept %s, a NICE BOY on the bumper %s, back doors open %s" % [crept != null, hopped != null, doors_open])


func _step_ride(shuttle: Node) -> void:
	var trip := int(_steps.get("trip", 0))
	var moved: Variant = await _wait_for(func() -> Variant:
		return true if Net.player_zone(_client) == Net.Zone.BORDER else null, 45.0)
	var host_stats: Dictionary = shuttle.get("stats")
	var moves: Array = host_stats.get("zone_moves", [])
	# The host's own schedule: every move after the rider's iris had closed.
	var iris_ok := moved != null
	for entry: Variant in moves:
		var at := float((entry as Dictionary)["at"])
		iris_ok = iris_ok and _iris_closed_by(shuttle, trip, at)
	var poses: Dictionary = await _compare_poses(shuttle, trip)
	var gone: Variant = await _wait_for(func() -> Variant:
		return true if not (shuttle.call("trip_ids") as Array).has(trip) else null, 45.0)
	var reply: Dictionary = await _ask("ride", {})
	var client_iris: Array = reply.get("zone_iris", [])
	var iris_pending := client_iris.is_empty() or str((client_iris[0] as Dictionary).get("iris", "none")) == "none"
	var client_iris_ok := iris_pending or str((client_iris[0] as Dictionary)["iris"]) == "true"
	var speed := float(reply.get("max_speed_on_screen", 99.0))
	var step := float(reply.get("max_step_m", 99.0))
	var crew_err := float(reply.get("crew_err_max", 99.0))
	_check("poses", bool(poses.get("ok", false)), "host and client poses within %.2f m on %d samples over legs %s (worst %.4f m)" % [POSE_TOLERANCE, int(poses.get("samples", 0)), poses.get("legs", []), float(poses.get("worst", 99.0))])
	_check("ride", moved != null and iris_ok and client_iris_ok and gone != null and speed <= Constants.VAN_MAX_SCREEN_SPEED + 0.5 and step <= STEP_MAX_METERS and crew_err <= SEAT_TOLERANCE, "zone move %s after the iris %s (client iris %s), freed after it left %s, client on-screen speed %.1f m/s, step %.2f m, crew off their seats %.3f m over %d samples" % [moved != null, iris_ok, "pending (no iris headless)" if iris_pending else str(client_iris_ok), gone != null, speed, step, crew_err, int(reply.get("crew_samples", 0))])


func _step_dropoff(shuttle: Node) -> void:
	Net.move_player_to_zone(_client, Net.Zone.LOT, &"", false)
	await get_tree().create_timer(0.3).timeout
	var trip := int(shuttle.call("dev_dropoff", [_client]))
	var parked: Variant = await _wait_for(func() -> Variant:
		return true if str(shuttle.call("leg_name", trip)) == "drop_parked" else null)
	var out: Variant = await _wait_for(func() -> Variant:
		return true if (shuttle.call("seat_info", _client) as Dictionary).is_empty() else null)
	await get_tree().create_timer(0.6).timeout
	var pose: Transform3D = shuttle.call("trip_pose", trip, Net.server_time())
	var body := _player(_client)
	var on_curb := body != null and Vector2(body.global_position.x - pose.origin.x, body.global_position.z - pose.origin.z).length() < 4.5 and absf(body.global_position.y - pose.origin.y) < 0.6
	var director := _director()
	var safe := float((director.get("_safe_until") as Dictionary).get(_client, 0.0)) > Net.server_time()
	var dropped := int((shuttle.get("stats") as Dictionary).get("drops", 0)) >= 1
	var encounter := get_tree().get_first_node_in_group("nice_encounter")
	var stage := "pending (no Encounter, nice_boys:2)"
	if encounter != null and encounter.has_method("stage_of"):
		stage = str(int(encounter.call("stage_of", _client)) == 10)
	var where := body.global_position - pose.origin if body != null else Vector3.INF
	_check("dropoff", parked != null and out != null and on_curb and safe and dropped, "parked %s, out %s, on the curb %s (%s from the van), immune %s, dropped %s, stage FREE %s" % [parked != null, out != null, on_curb, where, safe, dropped, stage])


func _step_rides() -> void:
	var world := get_tree().get_first_node_in_group("world")
	var no_van := world.get_node_or_null("Rides/Van") == null
	# Another ride arriving leaves a Chefty rider in Chefty.
	var chefty := world.get_node_or_null("Rides/Chefty") as Node3D
	var me := _me()
	var other: Node3D = _RideScript.new()
	other.name = "TestRide"
	world.get_node("Rides").add_child(other)
	me.call("set_riding", chefty, 0)
	other.call("_rpc_arrived")
	var kept: bool = me.get("_ride") == chefty
	me.call("clear_riding")
	world.get_node("Rides").remove_child(other)
	other.queue_free()
	_check("rides", no_van and kept, "no Rides/Van %s, Chefty's rider kept %s" % [no_van, kept])


# ---------------------------------------------------------------- helpers


func _routes_on_ground(shuttle: Node, trip: int) -> bool:
	var space := get_viewport().get_world_3d().direct_space_state
	for route: Variant in shuttle.call("trip_routes", trip):
		for point: Vector3 in route as PackedVector3Array:
			var query := PhysicsRayQueryParameters3D.create(point + Vector3(0.0, 0.5, 0.0), point - Vector3(0.0, 1.0, 0.0), 0xFFFF)
			if space.intersect_ray(query).is_empty():
				return false
	return true


## The PARKED leg's start, which the mirror schedule counts from.
func _hold_started(shuttle: Node, trip: int) -> float:
	var trips: Dictionary = shuttle.get("_trips")
	var data: Object = trips.get(trip)
	for leg: Dictionary in data.get("legs"):
		if int(leg["k"]) == 1:
			return float(leg["t"])
	return 0.0


func _iris_closed_by(shuttle: Node, trip: int, at: float) -> bool:
	var trips: Dictionary = shuttle.get("_trips")
	var data: Object = trips.get(trip)
	if data == null:
		return true
	return bool(shuttle.call("_riders_iris_closed", data, at))


## Samples the trip's pose on the host and the client at the same server times,
## two per leg it had.
func _compare_poses(shuttle: Node, trip: int) -> Dictionary:
	var trips: Dictionary = shuttle.get("_trips")
	var data: Object = trips.get(trip)
	if data == null:
		return {"ok": false}
	var times: Array = []
	var names: Array = []
	var legs: Array = data.get("legs")
	for index: int in legs.size():
		var start := float((legs[index] as Dictionary)["t"])
		var end := float((legs[index + 1] as Dictionary)["t"]) if index + 1 < legs.size() else start + 2.0
		times.append(lerpf(start, end, 0.3))
		times.append(lerpf(start, end, 0.8))
		names.append(_ShuttleScript.LEG_NAMES[int((legs[index] as Dictionary)["k"])])
	var reply: Dictionary = await _ask("poses", {"trip": trip, "times": times})
	var theirs: Array = reply.get("poses", [])
	var worst := 0.0
	for index: int in times.size():
		var mine: Transform3D = shuttle.call("trip_pose", trip, float(times[index]))
		if index >= theirs.size():
			return {"ok": false, "samples": index, "legs": names, "worst": 99.0}
		worst = maxf(worst, mine.origin.distance_to(theirs[index] as Vector3))
	return {"ok": worst <= POSE_TOLERANCE and times.size() >= 6, "samples": times.size(), "legs": names, "worst": worst}


## Asks the client a question and waits for the answer.
func _ask(what: String, args: Dictionary) -> Dictionary:
	_reply = {}
	_rpc_ask.rpc_id(_client, what, args)
	var waited := 0.0
	while _reply.is_empty() and waited < 5.0:
		await get_tree().process_frame
		waited += get_process_delta_time()
	return _reply


@rpc("authority", "call_remote", "reliable")
func _rpc_watch() -> void:
	_watching = true


@rpc("authority", "call_remote", "reliable")
func _rpc_ask(what: String, args: Dictionary) -> void:
	var shuttle := _shuttle()
	var out: Dictionary = {}
	match what:
		"seats":
			out = {"seated": (shuttle.call("seated_riders") as Array).size(), "boarded": (shuttle.call("boarded_riders") as Array).size()}
		"poses":
			var poses: Array = []
			for t: Variant in args.get("times", []):
				poses.append((shuttle.call("trip_pose", int(args["trip"]), float(t)) as Transform3D).origin)
			out = {"poses": poses}
		"ride":
			var stats: Dictionary = shuttle.get("stats")
			out = {"max_speed_on_screen": float(stats.get("max_speed_on_screen", 0.0)), "max_step_m": float(stats.get("max_step_m", 0.0)),
				"crew_err_max": _crew_err_max, "crew_samples": _crew_samples, "zone_iris": _zone_iris}
	_rpc_answer.rpc_id(1, out)


@rpc("any_peer", "call_remote", "reliable")
func _rpc_answer(out: Dictionary) -> void:
	_reply = out
	if _reply.is_empty():
		_reply = {"empty": true}


func _wait_for(check: Callable, seconds: float = STEP_WAIT_SECONDS) -> Variant:
	var waited := 0.0
	while waited < seconds:
		var value: Variant = check.call()
		if value != null:
			return value
		await get_tree().create_timer(0.1).timeout
		waited += 0.1
	return null


func _check(step: String, ok: bool, line: String) -> void:
	print("[ShuttleTest] %s: %s (%s)" % [step, "ok" if ok else "FAIL", line])
	_steps[step] = ok
	if not ok:
		_problems.append("%s: %s" % [step, line])


func _finish(ok: bool, why: String) -> void:
	if why != "":
		_problems.append(why)
	var shuttle := _shuttle()
	result = {"ok": ok and _problems.is_empty(), "done": true, "problems": _problems.duplicate(), "steps": _steps.duplicate(),
		"stats": (shuttle.get("stats") as Dictionary).duplicate(true) if shuttle != null else {}}
	print("[ShuttleTest] all ok: %s %s" % [result["ok"], _problems])


func _shuttle() -> Node:
	return get_tree().get_first_node_in_group("nice_shuttle")


func _director() -> Node:
	return get_tree().get_first_node_in_group("run_director")


func _me() -> Node3D:
	return _player(Net.local_peer_id())


func _player(peer_id: int) -> Node3D:
	for node: Node in get_tree().get_nodes_in_group("players"):
		if node.name == str(peer_id):
			return node as Node3D
	return null
