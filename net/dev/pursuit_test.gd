extends Node

## Authority: host. --pursuit-test (with --town-map --job-seed=777 --yard-size=1,
## and a client named Target joined) runs the NICE BOYS' pursuit through the
## town (driving:F, net/run_events/pursuit.gd) through the real paths:
##   a. the yard at the test house, Chefty at its curb facing up the street, the
##      host at the wheel and the client in the bed. The raid is called; the van
##      pulls up and the crew climbs out.
##   b. the host drives off: past CREW_LEASH_METERS at speed with a catchable
##      rider aboard, the crew piles back in and the van chases (its CHASE leg).
##   c. the host stops: the van pulls in, stops, they climb out round the truck,
##      and the one after the client (the host is kept safe for this step) pulls
##      them out of the bed: caught, and seated in the van.
##   d. the host drives off again: they pile back in and the chase is back on.
##   e. Chefty is put far up County Road 9: past PURSUIT_LOSE_DISTANCE for
##      PURSUIT_LOSE_SECONDS they give up: "lost", XP_ESCAPE paid once, the heat
##      at HEAT_AFTER_ESCAPE, and the raid over (the van leaves with the client).
##   f. a second raid: the chase on, Chefty is put on Homie Depot's lot: an
##      instant getaway ("store").
##   h. a third raid: the chase on, the host stops and steps out with the van
##      behind: no getaway (no escape, no XP); the van pulls in behind the truck.
##   g. a fourth raid: the chase on, Chefty floored head-on into the van: a ram,
##      the van spins out, the heat up by HEAT_VAN_RAM.
##   i. (fx-w9) a fifth, pulled over: Chefty floored into the parked van's side
##      slews it round where it stood, and it stands there again.
## The client's view (it saw the chase start, drew the van's CHASE leg from the
## host's track) is checked by CI from the probe reports. Each step prints a
## [PursuitTest] line.

const _Vehicles = preload("res://props/vehicles.gd")
const _Pursuit = preload("res://net/run_events/pursuit.gd")
const _Shuttle = preload("res://net/run_events/shuttle.gd")
const _FenceGive = preload("res://net/components/fence_give.gd")
## How long the raid's warning has left when a step calls it (s): the van pulls up
## that soon (the scenarios' backdated warning).
const WARN_LEAD: float = 2.0
## How long the host floors it to get away from the yard (s).
const DRIVE_OFF_SECONDS: float = 3.0
## Where Chefty is put for the long getaway: County Road 9, short of the store.
const FAR_AWAY := Vector3(70.0, 0.0, 10.0)
## How far ahead of the van Chefty is put to ram it (m).
const RAM_RUN_UP: float = 32.0
## The eastbound lane, from the street's centerline (m, yard space +Z).
const EASTBOUND_LANE: float = 2.2
## i (fx-w9): how far off the parked van's side Chefty is lined up to ram it (m),
## and how far round (rad) it must slew.
const PARKED_RAM_RUN_UP: float = 11.0
const PARKED_RAM_MIN_TURN: float = 0.6

static var result: Dictionary = {}

var _started: bool = false


func _process(_delta: float) -> void:
	if _started or not Net.is_host():
		return
	var world := get_tree().get_first_node_in_group("world")
	if world == null or get_tree().get_first_node_in_group("chefty") == null or get_tree().get_first_node_in_group("run_director") == null:
		return
	_started = true
	_run(world)


func _run(world: Node) -> void:
	if not bool(world.call("is_town_map")):
		_finish(false, ["not the connected town: run with --town-map"])
		return
	var waited := 0.0
	while (_client_id() == 0 or _player(_client_id()) == null) and waited < 15.0:
		await get_tree().create_timer(0.25).timeout
		waited += 0.25
	var client := _client_id()
	if client == 0:
		_finish(false, ["no client joined"])
		return
	await get_tree().create_timer(1.5).timeout
	var problems: Array[String] = []
	var host := Net.local_peer_id()
	var director := get_tree().get_first_node_in_group("run_director")
	var pursuit: Node = director.call("pursuit")
	var shuttle := get_tree().get_first_node_in_group("nice_shuttle")
	var chefty := get_tree().get_first_node_in_group("chefty")
	var heat := get_tree().get_first_node_in_group("heat")
	_Pursuit.reset_stats()
	# The yard at the test house (what a picked job does), nobody on it.
	var house := TownMap.test_site_house()
	if get_tree().get_first_node_in_group("job_lot") == null:
		world.call("place_job_site", TownMap.yard_transform(house), house)
		world.call("_load_job_lot")
	var lot_wait := 0.0
	while get_tree().get_first_node_in_group("job_lot") == null and lot_wait < 10.0:
		await get_tree().create_timer(0.25).timeout
		lot_wait += 0.25
	await get_tree().create_timer(1.0).timeout
	# a. Seated at the curb, the raid called.
	var ok_a: bool = await _seat_at_curb(chefty, host, client, house)
	if not ok_a:
		_finish(false, ["a. couldn't seat the host at the wheel and the client in the bed"])
		return
	var out: bool = await _raid(director, shuttle)
	_verdict(out, "a. the raid's van pulled up at the yard and the crew climbed out (phase %d, van %s)" % [int(director.call("phase")), str(shuttle.call("raid_leg"))], problems)
	if not out:
		_finish(false, problems)
		return
	# b. Off up the street.
	chefty.call("dev_script", host, [{"seconds": DRIVE_OFF_SECONDS, "throttle": 1.0}, {"seconds": 1.3, "throttle": -1.0}, {"seconds": 6.0, "handbrake": true}])
	var chasing: bool = await _until(func() -> bool: return str(pursuit.call("state_name")) == "chasing" and str(shuttle.call("raid_leg")) == "chase", 16.0)
	var siren := bool((shuttle.call("trip_info", int(shuttle.call("raid_trip_id"))) as Dictionary).get("siren", false))
	_verdict(chasing and siren and bool(pursuit.call("is_active")), "b. driven off, the van gives chase (state %s, leg %s, siren %s)" % [str(pursuit.call("state_name")), str(shuttle.call("raid_leg")), siren], problems)
	if not chasing:
		_finish(false, problems)
		return
	# c. Stopped (the script's brakes): pulled over, the client pulled out of the bed.
	_safe(director, host, 40.0)
	var pulled: bool = await _until(func() -> bool: return str(pursuit.call("state_name")) == "pullover" and _crew_near(chefty, 12.0) > 0, 20.0)
	_verdict(pulled, "c. pulled over: the van stopped behind the truck and %d NICE BOY(s) are out within 12 m of it" % _crew_near(chefty, 12.0), problems)
	var grabbed: bool = await _until(func() -> bool: return bool(director.call("is_captured", client)), 14.0)
	_verdict(grabbed and int(chefty.call("seat_of", client)) < 0 and int(_Pursuit.stats["seat_grabs"]) >= 1,
		"c. the client was pulled out of the bed (%d seat grab(s)) and caught" % int(_Pursuit.stats["seat_grabs"]), problems)
	# d. Off again while they walk the client to the van: once the client's seated
	# and the crew's back in, the chase resumes.
	_safe(director, host, 0.0)
	chefty.call("dev_script", host, [{"seconds": 3.5, "throttle": 1.0}, {"seconds": 2.0, "throttle": 0.4}])
	var seated: bool = await _until(func() -> bool: return not (shuttle.call("seat_info", client) as Dictionary).is_empty(), 25.0)
	var resumed: bool = await _until(func() -> bool: return str(pursuit.call("state_name")) == "chasing" and str(shuttle.call("raid_leg")) == "chase", 18.0)
	_verdict(seated and resumed and int(_Pursuit.stats["chases"]) >= 2, "d. driven off from the pull-over: the client seated in the van (%s), they piled back in and gave chase again (%d chases)" % [shuttle.call("seat_info", client), int(_Pursuit.stats["chases"])], problems)
	# e. Far up County Road 9: lost them.
	var xp_before := Campaign.pending_xp()
	var escapes_before := int(_Pursuit.stats["escapes"])
	chefty.call("dev_script", host, [{"seconds": 9.0, "throttle": -1.0, "handbrake": true}])
	chefty.call("dev_place", FAR_AWAY, PI * 0.5)
	var lost: bool = await _until(func() -> bool: return int(_Pursuit.stats["escapes"]) > escapes_before, Constants.PURSUIT_LOSE_SECONDS + 4.0)
	var quiet: bool = await _until(func() -> bool: return int(director.call("phase")) == 0, 15.0)
	var reasons: Array = _Pursuit.stats["reasons"]
	var heat_now := float(heat.get("heat")) if heat != null else -1.0
	_verdict(lost and quiet and not reasons.is_empty() and str(reasons.back()) == "far" and Campaign.pending_xp() - xp_before == Constants.XP_ESCAPE and absf(heat_now - Constants.HEAT_AFTER_ESCAPE) < 0.5,
		"e. far away: lost them (%s), the raid over (phase %d), +%d XP (want %d), heat %.1f (want %.0f)" % [reasons, int(director.call("phase")), Campaign.pending_xp() - xp_before, Constants.XP_ESCAPE, heat_now, Constants.HEAT_AFTER_ESCAPE], problems)
	# f. A second raid: into Homie Depot's lot.
	await _quiet_down(director, shuttle)
	var ok_f: bool = await _seat_at_curb(chefty, host, 0, house)
	var chased_f := false
	var raided_f := false
	if ok_f:
		raided_f = await _raid(director, shuttle)
	if raided_f:
		chefty.call("dev_script", host, [{"seconds": DRIVE_OFF_SECONDS, "throttle": 1.0}, {"seconds": 1.0, "throttle": 0.6}, {"seconds": 6.0, "throttle": 0.3}])
		chased_f = await _until(func() -> bool: return str(pursuit.call("state_name")) == "chasing" and str(shuttle.call("raid_leg")) == "chase", 18.0)
	escapes_before = int(_Pursuit.stats["escapes"])
	if chased_f:
		chefty.call("dev_script", host, [{"seconds": 4.0, "throttle": -1.0, "handbrake": true}])
		chefty.call("dev_place", Constants.CHEFTY_PARK_SPOT, Constants.CHEFTY_PARK_YAW)
	var store := false
	if chased_f:
		store = await _until(func() -> bool: return int(_Pursuit.stats["escapes"]) > escapes_before, 2.0)
	reasons = _Pursuit.stats["reasons"]
	_verdict(store and str(reasons.back()) == "store", "f. a chase (%s) ended the moment Chefty was on Homie Depot's lot (%s)" % [chased_f, reasons], problems)
	await _until(func() -> bool: return int(director.call("phase")) == 0, 15.0)
	# h. Another raid: the chase on, the host stops and steps out with the van behind.
	# Getting out is no getaway: no escape, no XP; the van comes on and pulls in
	# behind the empty truck.
	await _quiet_down(director, shuttle)
	var ok_h: bool = await _seat_at_curb(chefty, host, 0, house)
	var chased_h := false
	var raided_h := false
	if ok_h:
		raided_h = await _raid(director, shuttle)
	if raided_h:
		chefty.call("dev_script", host, [{"seconds": DRIVE_OFF_SECONDS, "throttle": 1.0}, {"seconds": 2.0, "throttle": -1.0}, {"seconds": 6.0, "handbrake": true}])
		chased_h = await _until(func() -> bool: return str(pursuit.call("state_name")) == "chasing" and str(shuttle.call("raid_leg")) == "chase", 18.0)
	var stepped_out := false
	var escaped_h := false
	var pulled_h := false
	var xp_before_h := Campaign.pending_xp()
	var escapes_before_h := int(_Pursuit.stats["escapes"])
	if chased_h:
		await _until(func() -> bool: return float(chefty.call("ground_speed")) < 0.5, 10.0)
		chefty.call("_handle_exit", host)
		stepped_out = int(chefty.call("seat_of", host)) < 0
		escaped_h = await _until(func() -> bool: return int(_Pursuit.stats["escapes"]) > escapes_before_h, 3.0)
		pulled_h = await _until(func() -> bool: return str(pursuit.call("state_name")) == "pullover", 15.0)
	_verdict(chased_h and stepped_out and not escaped_h and pulled_h and int(_Pursuit.stats["escapes"]) == escapes_before_h and Campaign.pending_xp() == xp_before_h,
		"h. stepped out of the stopped truck mid-chase (chase %s, out %s): no getaway (%d escapes, +%d XP), the van pulled in behind it (%s)" % [chased_h, stepped_out, int(_Pursuit.stats["escapes"]) - escapes_before_h, Campaign.pending_xp() - xp_before_h, str(pursuit.call("state_name"))], problems)
	# Kept safe from here, nobody's left to catch round the truck: they wrap it up.
	_safe(director, host, 60.0)
	await _until(func() -> bool: return int(director.call("phase")) == 0, 20.0)
	_safe(director, host, 0.0)
	# g. A third raid: ram the van.
	await _quiet_down(director, shuttle)
	var ok_g: bool = await _seat_at_curb(chefty, host, 0, house)
	var chased_g := false
	var raided_g := false
	if ok_g:
		raided_g = await _raid(director, shuttle)
	if raided_g:
		chefty.call("dev_script", host, [{"seconds": DRIVE_OFF_SECONDS, "throttle": 1.0}, {"seconds": 2.0, "throttle": -1.0}])
		chased_g = await _until(func() -> bool:
			var van: Dictionary = shuttle.call("host_chase_pose")
			return str(pursuit.call("state_name")) == "chasing" and not van.is_empty() and bool(van["driving"]) and float(van["speed"]) > 3.0, 20.0)
	var rams_before := int(_Pursuit.stats["rams"])
	var spins_before := int(_Pursuit.stats["spins"])
	var heat_before := float(heat.get("heat")) if heat != null else 0.0
	if chased_g:
		# fx-w9: the town's fences hold Chefty now, so it's lined up once the straight
		# run ahead of the van is clear of them (a van mid-turn points it across a
		# front yard's fence); it follows the truck's road meanwhile.
		var lined := func() -> bool:
			var pose: Transform3D = shuttle.call("raid_pose")
			var fore := Vector3(-pose.basis.z.x, 0.0, -pose.basis.z.z).normalized()
			return _fence_free(pose.origin + fore * RAM_RUN_UP, pose.origin, atan2(fore.x, fore.z))
		var clear_ahead: bool = await _until(lined, 8.0)
		var van: Transform3D = shuttle.call("raid_pose")
		var ahead := -van.basis.z
		ahead.y = 0.0
		ahead = ahead.normalized()
		var from := van.origin + ahead * RAM_RUN_UP
		# Facing the van, nose to nose.
		chefty.call("dev_place", Vector3(from.x, van.origin.y, from.z), atan2(ahead.x, ahead.z))
		chefty.call("dev_script", host, [{"seconds": 4.0, "throttle": 1.0}])
		print("[PursuitTest] g: lined up %.0f m ahead of the van, the run clear of fences %s" % [RAM_RUN_UP, clear_ahead])
	var rammed := false
	if chased_g:
		rammed = await _until(func() -> bool: return int(_Pursuit.stats["rams"]) > rams_before, 6.0)
	var heat_after := float(heat.get("heat")) if heat != null else 0.0
	_verdict(rammed and int(_Pursuit.stats["spins"]) > spins_before and heat_after - heat_before >= Constants.HEAT_VAN_RAM - 0.5,
		"g. rammed head-on (chase %s): %d ram(s), %d spin(s), heat %.1f -> %.1f" % [chased_g, int(_Pursuit.stats["rams"]) - rams_before, int(_Pursuit.stats["spins"]) - spins_before, heat_before, heat_after], problems)
	chefty.call("dev_script", host, [{"seconds": 1.0, "throttle": -1.0}])
	# Spun out, sat there dazed for VAN_STUN_SECONDS, then back after the truck.
	var recovered := false
	if rammed:
		await get_tree().create_timer(Constants.VAN_STUN_SECONDS).timeout
		recovered = await _until(func() -> bool:
			var van: Dictionary = shuttle.call("host_chase_pose")
			return str(pursuit.call("state_name")) != "chasing" or (not van.is_empty() and float(van["speed"]) > 1.0), 4.0)
	_verdict(recovered, "g. the van got going again after its spin-out (state %s)" % str(pursuit.call("state_name")), problems)
	# i (fx-w9), last: the parked van rammed.
	_safe(director, host, 60.0)
	await _until(func() -> bool: return int(director.call("phase")) == 0, 30.0)
	_safe(director, host, 0.0)
	await _ram_parked(director, shuttle, pursuit, chefty, host, house, problems)
	_finish(problems.is_empty(), problems)


## Whether a truck driven straight from a to b (heading yaw) meets no fence
## (net/components/fence_give.gd), sampled every meter.
func _fence_free(a: Vector3, b: Vector3, yaw: float) -> bool:
	var steps := int(a.distance_to(b))
	for index: int in steps + 1:
		var at := a.lerp(b, float(index) / float(maxi(steps, 1)))
		if not _FenceGive.contact(at, yaw).is_empty():
			return false
	return true


## i (fx-w9). A raid, the chase, the pull-over: once the crew are out on the
## street, Chefty is lined up on the parked van's side and floored into it. It
## slews round where it stood (about a quarter turn, the heat up as for any ram)
## and stands again; it used to just rock in place.
func _ram_parked(director: Node, shuttle: Node, pursuit: Node, chefty: Node, host: int, house: int, problems: Array[String]) -> void:
	await _quiet_down(director, shuttle)
	var seated: bool = await _seat_at_curb(chefty, host, 0, house)
	var raided := false
	if seated:
		raided = await _raid(director, shuttle)
	var chased := false
	if raided:
		chefty.call("dev_script", host, [{"seconds": DRIVE_OFF_SECONDS, "throttle": 1.0}, {"seconds": 2.0, "throttle": -1.0}, {"seconds": 6.0, "handbrake": true}])
		chased = await _until(func() -> bool: return str(pursuit.call("state_name")) == "chasing" and str(shuttle.call("raid_leg")) == "chase", 18.0)
	var out := false
	if chased:
		out = await _until(func() -> bool: return str(pursuit.call("state_name")) == "pullover" and str(pursuit.get("_pull_stage")) == "out", 20.0)
	var spun := false
	var turned := 0.0
	var stood := false
	var heat := get_tree().get_first_node_in_group("heat")
	var heat_before := float(heat.get("heat")) if heat != null else 0.0
	if out:
		# Kept safe while they climb out (nobody's pulled from the seat before the run).
		_safe(director, host, 20.0)
		var van: Transform3D = shuttle.call("raid_pose")
		var side := van.basis.x
		side.y = 0.0
		side = side.normalized()
		var from := van.origin + side * PARKED_RAM_RUN_UP
		chefty.call("dev_place", Vector3(from.x, van.origin.y, from.z), atan2(side.x, side.z))
		var hopping := func() -> bool:
			for crew: Node in get_tree().get_nodes_in_group("nice_crew"):
				if int(crew.get("mode")) == preload("res://npcs/crew_member.gd").Mode.HOP_OUT:
					return true
			return false
		# With nobody to catch they'd wrap up after PULLOVER_IDLE_SECONDS: held off
		# here (test only) while they climb out and the truck runs at them.
		var hold_idle := func() -> bool:
			pursuit.set("_idle_for", 0.0)
			return false
		await _until(func() -> bool: return bool(hold_idle.call()) or not bool(hopping.call()), 4.0)
		hold_idle.call()
		await get_tree().create_timer(0.4).timeout
		hold_idle.call()
		var spins_before := int(_Shuttle.stats.get("parked_spins", 0))
		chefty.call("dev_script", host, [{"seconds": 2.6, "throttle": 1.0}, {"seconds": 1.0, "throttle": -1.0}])
		spun = await _until(func() -> bool:
			hold_idle.call()
			return int(_Shuttle.stats.get("parked_spins", 0)) > spins_before, 4.0)
		if spun:
			# Its short slide (a CHASE leg from VAN_PLAN_LEAD on), then standing again.
			await _until(func() -> bool: return str(shuttle.call("raid_leg")) == "chase", 2.0)
			stood = await _until(func() -> bool: return str(shuttle.call("raid_leg")) == "parked", 6.0)
			var after: Transform3D = shuttle.call("raid_pose")
			turned = Vector3(van.basis.z.x, 0.0, van.basis.z.z).normalized().angle_to(Vector3(after.basis.z.x, 0.0, after.basis.z.z).normalized())
	var heat_after := float(heat.get("heat")) if heat != null else 0.0
	_verdict(spun and stood and turned >= PARKED_RAM_MIN_TURN and heat_after - heat_before >= Constants.HEAT_VAN_RAM - 0.5,
		"i. rammed the pulled-over van side-on (chase %s, pull-over %s): it slewed round %.0f deg (want %.0f+) where it stood and stood again (%s), heat %.1f -> %.1f" % [chased, out, rad_to_deg(turned), rad_to_deg(PARKED_RAM_MIN_TURN), stood, heat_before, heat_after], problems)
	await _until(func() -> bool: return int(director.call("phase")) == 0, 20.0)
	_safe(director, host, 0.0)


## Chefty at the test house's curb facing up the street (away from where the van
## parks), the host at the wheel, the client (if any) in a bed seat, zones set.
func _seat_at_curb(chefty: Node, host: int, client: int, house: int) -> bool:
	for peer_id: int in [host, client]:
		if peer_id != 0 and int(chefty.call("seat_of", peer_id)) >= 0:
			chefty.call("drop_rider", peer_id)
	await get_tree().create_timer(0.3).timeout
	# The eastbound lane across the street from the yard's curb (the van pulls up
	# westbound at the curb), facing +X up the street: yaw -PI/2 (VehicleSim: 0
	# faces -Z).
	var lane := TownMap.yard_transform(house) * Vector3(TownMap.CURB_POINT.x, 0.0, TownMap.YARD_STREET_Z + EASTBOUND_LANE)
	chefty.call("dev_place", lane, -PI * 0.5)
	await get_tree().create_timer(0.3).timeout
	var waited := 0.0
	while waited < 6.0:
		chefty.call("dev_seat", host, 0)
		if client != 0:
			chefty.call("dev_seat", client, _Vehicles.CHEFTY_CAB_SEATS)
		await get_tree().create_timer(0.4).timeout
		waited += 0.4
		if int(chefty.call("driver")) == host and (client == 0 or int(chefty.call("seat_of", client)) >= _Vehicles.CHEFTY_CAB_SEATS):
			for peer_id: int in [host, client]:
				if peer_id != 0:
					Net.set_player_zone(peer_id, Net.Zone.TOWN)
			await get_tree().create_timer(0.5).timeout
			return true
	return false


## The raid called with WARN_LEAD left on the warning; true once the van has
## pulled up and its crew are climbing out.
func _raid(director: Node, shuttle: Node) -> bool:
	var fresh := int(director.call("phase")) == 0
	if not fresh:
		return false
	# Backdated like the scenarios' (net/dev/scenarios.gd _warn_with): the van's
	# arrival is planned from the director's arrival time.
	director.rpc("_rpc_phase", 1, Net.server_time() - (Constants.RUN_WARNING_SECONDS - WARN_LEAD), "")
	director.set("_raid_caught", 0)
	director.set("_first_seat_at", -1.0)
	(director.get("_spotted") as Dictionary).clear()
	(director.get("_hops") as Array).clear()
	director.call("_spawn_crew")
	return await _until(func() -> bool:
		if int(director.call("phase")) != 2 or str(shuttle.call("raid_leg")) != "parked":
			return false
		for crew: Node in get_tree().get_nodes_in_group("nice_crew"):
			if int(crew.get("mode")) == preload("res://npcs/crew_member.gd").Mode.HOP_OUT:
				return true
		return false, 14.0)


## Between raids: the last van gone, its crew freed, the director quiet.
func _quiet_down(director: Node, shuttle: Node) -> void:
	await _until(func() -> bool: return int(director.call("phase")) == 0, 10.0)
	director.call("dev_reset")
	shuttle.call("dev_reset")
	await get_tree().create_timer(0.6).timeout
	# The director rolls nothing of its own meanwhile (nobody's on the yard).
	director.set("_next_roll", Net.server_time() + 600.0)


func _safe(director: Node, peer_id: int, seconds: float) -> void:
	var safe: Dictionary = director.get("_safe_until")
	if seconds <= 0.0:
		safe.erase(peer_id)
	else:
		safe[peer_id] = Net.server_time() + seconds


func _crew_near(chefty: Node, meters: float) -> int:
	var count := 0
	var at: Vector3 = chefty.call("body_position")
	for crew: Node in get_tree().get_nodes_in_group("nice_crew"):
		if bool(crew.call("in_brain_mode")) and Vector2((crew as Node3D).global_position.x - at.x, (crew as Node3D).global_position.z - at.z).length() <= meters:
			count += 1
	return count


func _until(check: Callable, seconds: float) -> bool:
	var waited := 0.0
	while waited < seconds:
		if bool(check.call()):
			return true
		await get_tree().create_timer(0.1).timeout
		waited += 0.1
	return bool(check.call())


func _client_id() -> int:
	for peer_id: int in Net.peer_ids():
		if peer_id != Net.local_peer_id():
			return peer_id
	return 0


func _player(peer_id: int) -> Node3D:
	for node: Node in get_tree().get_nodes_in_group("players"):
		if node.name == str(peer_id):
			return node as Node3D
	return null


func _verdict(ok: bool, line: String, problems: Array[String]) -> void:
	print("[PursuitTest] %s: %s" % [line, ok])
	if not ok:
		problems.append(line)


func _finish(ok: bool, problems: Array) -> void:
	result = {"ok": ok, "problems": problems, "stats": _Pursuit.stats.duplicate(true), "done": true}
	print("[PursuitTest] done: ok=%s %s" % [ok, problems])
