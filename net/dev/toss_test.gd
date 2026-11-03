extends Node

## Authority: host, plus a client half. --toss-test checks tossing leaf bags into
## Chefty's bed with G the way a player does it, holding the real key (docs/GAME.md
## "Tossing bags into Chefty"):
##   H1/H2. the host tosses a bag in from 3 m and from 6 m (a long toss, which the
##          crew reacts to now and then): the bed catches it,
##          counts it once with its dollars, the bag glides into its spot in the
##          load without a jump and goes, and the load's own bag shows there
##   H3.    a toss from 5 m wound up a touch too short is bent in by the aim help
##   H4.    a toss along the truck misses: the bag stays on the ground, uncounted
##   H5.    the arc preview (ui/toss_arc.gd) agreed with each of those
##   C1/C2. a lagged client (--sim-lag) tosses from 3 m and 6 m: counted once each
##   H6.    a wheelbarrow thrown at the truck still unloads into it
##   H7.    a full Chefty bats a tossed bag back out: not counted, and it ends up
##          outside the bed
##   H8.    a toss from 2 m (right by the bed, it hops in over the side) and E
##          from 0.9 m and 3 m off the side wall: in, and the drawn bag goes over
##          the rail, never through the wall (bed_toss.gd cut_depth)
##   H9.    the same for every start beside the truck into every kind of spot,
##          worked out (bed_toss.gd settle_plan): no glide cuts into the truck
##   H10.   through the host's own eyes (props/carry_view.gd): the bag was drawn
##          in its hands, every toss left them without a jump, and, measured off
##          the drawn meshes projected through the camera every tick from the
##          release to the landing, no thrown bag covered more of the screen
##          than one in the hands, nor more than FP_FLIGHT_SHARE_LIMIT once off
##          on its flight (nothing thrown swallows the view)
## The client half (the same flag, CI's Extra) throws its two bags, watches its
## own drawn bag for jumps, sees the catches, landings and the full bounce, and
## makes the same H10 measurement of its own predicted tosses.
## --toss-survey prints a table of throws from 2, 4 and 6 m instead.

const _BedToss = preload("res://net/components/bed_toss.gd")
const _TossArc = preload("res://ui/toss_arc.gd")
const _BedLoad = preload("res://props/truck_bed_load.gd")
const _CarryView = preload("res://props/carry_view.gd")
## H10: the most a drawn bag may move in one tick through your own eyes (m);
## how many times as much of the screen a thrown bag may cover as one in your
## hands (it leaves from there, rising a touch toward the middle of the view on
## the release ease: measured up to 1.03; with no cap it's 2.3, in your face);
## and the most it may cover once the ease is over and it's on its flight.
const FP_STEP_LIMIT_M: float = 0.35
const FP_SHARE_GROWTH: float = 1.1
const FP_FLIGHT_SHARE_LIMIT: float = 0.2
## A bag's drawn look moving farther than this in one 60 Hz frame is a jump (m).
## A longer frame (a loaded machine: one took 0.14 s, and a bag flying at 6 m/s
## covered 0.8 m in it) may move it proportionally farther, so the check is a
## speed: the step over the frame's own time, never less than JUMP_FRAME_S.
## A teleport (meters in one frame) still fails at any frame length.
const JUMP_LIMIT_M: float = 0.6
const JUMP_FRAME_S: float = 1.0 / 60.0
## How far off its stack spot a bag may be drawn when the load's bag replaces it (m).
const POP_LIMIT_M: float = 0.08
## How much deeper than at its ends a settling bag may cut into the truck (m).
const CUT_LIMIT_M: float = 0.03
const CLIENT_SPOTS: Array[float] = [3.0, 6.0]
## H9's settle sweep works through this many plans a frame (see _settle_sweep).
const SWEEP_PLANS_PER_FRAME: int = 20
const BAG_VALUE: int = 10
## The client's bags are worth a dollar more, so it takes only the ones put out for it.
const CLIENT_BAG_VALUE: int = 11

static var result: Dictionary = {}

var _started: bool = false
var _last_wind_up: float = -1.0
var _arc: Node3D
var _checks: Array = []
var _ok: bool = true


func _process(_delta: float) -> void:
	if _started or _own_player() == null or _truck() == null:
		return
	if Net.is_host() and get_tree().get_first_node_in_group("job_lot") == null:
		return
	_started = true
	_arc = _TossArc.new()
	add_child(_arc)
	if bool(Net.dev_options().get("toss_survey")):
		_survey()
	elif Net.is_host():
		_run_host()
	else:
		_run_client()


# ---------------------------------------------------------------- host


func _run_host() -> void:
	await get_tree().create_timer(1.5).timeout
	var h1: Dictionary = await _toss(3.0, 0.0, false)
	_check("H1 a toss from 3 m: %s" % JSON.stringify(h1), _caught_ok(h1))
	var long_before := int(_BedToss.stats["long"])
	var h2: Dictionary = await _toss(6.0, 0.0, false)
	_check("H2 a toss from 6 m, a long one (the crew may react): %s" % JSON.stringify(h2), _caught_ok(h2) and int(_BedToss.stats["long"]) > long_before)
	var assisted_before := int(_BedToss.stats["assisted"])
	var h3: Dictionary = await _toss(5.0, 0.0, true)
	_check("H3 a toss from 5 m wound up a touch short, bent in by the aim help (helped %d): %s" % [int(_BedToss.stats["assisted"]) - assisted_before, JSON.stringify(h3)], _caught_ok(h3) and int(_BedToss.stats["assisted"]) > assisted_before)
	var h4: Dictionary = await _toss(3.0, PI * 0.5, false)
	_check("H4 a toss along Chefty, not at it: %s" % JSON.stringify(h4), not bool(h4["counted"]) and bool(h4["still_there"]) and bool(h4["on_ground"]))
	_check("H5 the arc preview agreed: %s, %s caught, %s not" % [h1["arc_caught"], h2["arc_caught"], h4["arc_caught"]], bool(h1["arc_caught"]) and bool(h2["arc_caught"]) and not bool(h4["arc_caught"]))
	await _client_turns()
	await _wheelbarrow()
	var sweep: Dictionary = await _settle_sweep()
	_check("H9 every settle from beside the truck clears it: %s" % JSON.stringify(sweep), float(sweep["worst_m"]) <= CUT_LIMIT_M)
	var h8a: Dictionary = await _toss(2.0, 0.0, false)
	_check("H8 a toss from 2 m hops in over the rail: %s" % JSON.stringify(h8a), _caught_ok(h8a) and _over_rail(h8a))
	var h8b: Dictionary = await _heave(2.0)
	_check("H8 E from 0.9 m off the side heaves it over the rail: %s" % JSON.stringify(h8b), _caught_ok(h8b) and _over_rail(h8b))
	var h8c: Dictionary = await _heave(4.1)
	_check("H8 E from 3 m off the side heaves it over the rail: %s" % JSON.stringify(h8c), _caught_ok(h8c) and _over_rail(h8c))
	var h7: Dictionary = await _toss_full()
	_check("H7 a full Chefty bats it back out: %s" % JSON.stringify(h7), not bool(h7["counted"]) and bool(h7["refused"]) and bool(h7["still_there"]) and not bool(h7["in_bed"]))
	var view: Dictionary = _CarryView.stats
	_check("H10 your own bag through your own eyes: %s" % JSON.stringify(view), _own_eyes_ok(view, 5))
	result["stats"] = _BedToss.stats.duplicate()
	result["view"] = view.duplicate()
	result["checks"] = _checks
	result["ok"] = _ok
	result["done"] = true
	print("[TossTest] all ok: %s" % _ok)


## H10 (and the client's own): the bag was drawn in the hands, at least `throws`
## left them, none jumped, and what the camera really got (carry_view.gd
## seen_from, every tick from the release to the landing): no thrown bag ever
## covered more than FP_SHARE_GROWTH times the screen one in your hands did
## (nothing thrown swallows the view), nor more than FP_FLIGHT_SHARE_LIMIT once
## it was off on its flight.
func _own_eyes_ok(view: Dictionary, throws: int) -> bool:
	return int(view["held_ticks"]) > 0 and int(view["throws"]) >= throws and int(view["thrown_ticks"]) > 0 \
		and float(view["max_step_m"]) < FP_STEP_LIMIT_M \
		and float(view["held_share"]) > 0.0 \
		and float(view["thrown_share"]) <= float(view["held_share"]) * FP_SHARE_GROWTH \
		and float(view["flight_share"]) <= FP_FLIGHT_SHARE_LIMIT


func _check(line: String, passed: bool) -> void:
	_ok = _ok and passed
	_checks.append({"step": line.substr(0, 3), "ok": passed})
	print("[TossTest] %s %s (at %.1f s)" % ["ok  " if passed else "FAIL", line, _clock()])


## Seconds since this process started, to line the host's and the client's logs up.
static func _clock() -> float:
	return float(Time.get_ticks_msec()) / 1000.0


## The drawn bag never cut into the truck deeper than where its glide began or ended.
func _over_rail(row: Dictionary) -> bool:
	return float(row.get("cut_m", 1.0)) <= CUT_LIMIT_M and bool(row.get("settled", false))


func _caught_ok(row: Dictionary) -> bool:
	return bool(row["counted"]) and int(row["added"]) == 1 and int(row["value_added"]) == BAG_VALUE and not bool(row["still_there"]) and float(row["max_jump_m"]) < JUMP_LIMIT_M and float(row["pop_m"]) < POP_LIMIT_M and bool(row["stack_matches"])


## The host's own toss: stand distance m from the bed's middle (on the yard's
## side), face it (turned by yaw_off), pick up a fresh bag, wind up for as long
## as lands it in the middle (or, short, a touch less than any that would go in
## on its own), and let go. Watches the bag until it's gone or lies still, then
## a second more, so a double count would show.
func _toss(distance: float, yaw_off: float, short: bool) -> Dictionary:
	var truck := _truck()
	var me := _own_player()
	var spot := _spot(distance)
	await _stand(me, spot)
	var yaw := _yaw_to_bed(me.global_position) + yaw_off
	var bag: Node3D = await _fresh_bag(me.global_position + _facing(yaw) * 0.7)
	await _grab(bag, yaw)
	var count_before := int(truck.call("bag_count"))
	var value_before := int(truck.call("bag_value"))
	var stood := _from_middle(me.global_position)
	var hold := _hold_for(bag, me, short)
	_BedToss.stats["max_pop_m"] = 0.0
	# The homeowner wanders the yard: wait for them to be out of the way, or a
	# bag bonks them (fair, but not this test's question).
	await _until(func() -> bool: return _lane_clear(me.global_position, me.global_position + _facing(yaw) * (distance + 1.5)), 10.0)
	var held_at_go := int(bag.get("held_by")) == Net.local_peer_id()
	var arc_caught := false
	if short:
		# An exact wind-up (a key held for frames can't be this exact): straight to the throw.
		await get_tree().physics_frame
		bag.call("request_throw", -me.global_basis.z, _BedToss.power_for_seconds(hold), me.global_position)
	else:
		arc_caught = await _hold_drop(hold)
	var watch: Dictionary = await _watch(bag, 4.0)
	await get_tree().create_timer(1.0).timeout
	var row := {
		"distance": distance,
		"from_m": snappedf(stood, 0.01),
		"hold": snappedf(hold, 0.01),
		"added": int(truck.call("bag_count")) - count_before,
		"value_added": int(truck.call("bag_value")) - value_before,
		"arc_caught": arc_caught,
		"wound_up_s": snappedf(_last_wind_up, 0.01),
		"arc_end": str(_TossArc.stats["last_end"]),
		"held_at_go": held_at_go,
		"pop_m": snappedf(float(_BedToss.stats["max_pop_m"]), 0.001),
		"stack_matches": int((truck.call("bed_load") as Node).call("shown_count")) == int(truck.call("bag_count")),
	}
	row.merge(watch)
	row["counted"] = int(row["added"]) > 0
	if is_instance_valid(bag):
		bag.queue_free()
		await _ticks(2)
	return row


## Hold G that long and let go; whether the arc preview showed the bag going in
## just before.
func _hold_drop(hold: float) -> bool:
	Input.action_press(&"drop")
	var waited := 0.0
	while waited < hold:
		await get_tree().physics_frame
		waited += get_physics_process_delta_time()
	await get_tree().process_frame
	var arc_caught := bool(_TossArc.stats["last_caught"])
	var me := _own_player()
	_last_wind_up = float(me.call("wind_up_seconds"))
	Input.action_release(&"drop")
	return arc_caught


## Follows a thrown bag: its biggest jump between frames, whether it went (the
## bed took it) or is still there, and if so whether it lies on the ground.
func _watch(bag: Node3D, seconds: float) -> Dictionary:
	var truck := _truck()
	var max_jump := 0.0
	var last := (bag.get_node("Visual") as Node3D).global_position
	var waited := 0.0
	var still := 0.0
	var path: Array = []

	var jump_at: Array = []
	# While it settles into the load: how deep its drawn look cuts into the truck,
	# where it started and ended, and at worst.
	var cut_start := -1.0
	var cut_end := 0.0
	var cut_worst := 0.0
	var rest := Transform3D(Basis.IDENTITY, Vector3(0.0, 0.35, 0.0)).affine_inverse()
	while waited < seconds:
		await get_tree().process_frame
		waited += get_process_delta_time()
		if not is_instance_valid(bag) or bag.is_queued_for_deletion():
			break
		var now := (bag.get_node("Visual") as Node3D).global_position
		var moved := now.distance_to(last)
		# As far as it went at that speed in one 60 Hz frame (see JUMP_LIMIT_M).
		var frame := get_process_delta_time()
		var step := moved * JUMP_FRAME_S / maxf(frame, JUMP_FRAME_S)
		if bool(bag.call("is_settling")):
			var body := (truck.call("bed_transform") as Transform3D).affine_inverse() * ((bag.get_node("Visual") as Node3D).global_transform * rest)
			body.basis = body.basis.orthonormalized()
			var depth := _BedToss.cut_depth(body * _BedToss.LOOK_MIDDLE, _BedToss.look_reach(body.basis))
			if cut_start < 0.0:
				cut_start = depth
			cut_end = depth
			cut_worst = maxf(cut_worst, depth)
		if step > max_jump:
			max_jump = step
			jump_at = [snappedf(waited, 0.01), bool(bag.call("is_settling")), int(bag.get("held_by")), snappedf(moved, 0.001), snappedf(frame, 0.001)]

		if path.size() < 60 and Engine.get_process_frames() % 4 == 0:
			var p: Vector3 = (truck.call("bed_transform") as Transform3D).affine_inverse() * now
			path.append([snappedf(p.x, 0.01), snappedf(p.y, 0.01), snappedf(p.z, 0.01), snappedf(waited, 0.01)])
		last = now
		# Judged by the drawn look: a client's body is frozen and never says it moves.
		var moving := moved > 0.003 or bool(bag.call("is_settling")) or int(bag.get("held_by")) != 0
		still = 0.0 if moving else still + get_process_delta_time()
		if still > 0.6:
			break
	var there := is_instance_valid(bag) and not bag.is_queued_for_deletion()
	var out := {"max_jump_m": snappedf(max_jump, 0.001), "jump_at": jump_at, "still_there": there, "on_ground": false, "in_bed": false, "settled": cut_start >= 0.0, "cut_m": snappedf(maxf(cut_worst - maxf(cut_start, cut_end), 0.0), 0.001), "cut_ends_m": [snappedf(cut_start, 0.001), snappedf(cut_end, 0.001)]}
	if bool(Net.dev_options().get("toss_survey")) or there:
		out["path"] = path

	if there:
		var local: Vector3 = (truck.call("bed_transform") as Transform3D).affine_inverse() * bag.global_position
		out["in_bed"] = _BedToss.BED.has_point(local)
		out["on_ground"] = bag.global_position.y < 0.8 and bool(bag.call("is_loose")) and not bool(out["in_bed"])
		out["rest_local"] = [snappedf(local.x, 0.01), snappedf(local.y, 0.01), snappedf(local.z, 0.01)]
	return out


## The two client tosses: the host brings the client to the yard, the client
## stands at each spot (it moves itself), the host puts a bag at its feet and
## counts what the truck takes while it flies.
func _client_turns() -> void:
	var client: Node3D = await _client_player(25.0)
	if client == null:
		print("[TossTest] no client joined; the client tosses are skipped")
		result["client"] = "none"
		return
	var client_id := client.name.to_int()
	if Net.player_zone(client_id) != Net.Zone.LOT:
		Net.move_player_to_zone(client_id, Net.Zone.LOT)
	var truck := _truck()
	# The host steps out of the client's line, past the cab.
	var bed: Transform3D = truck.call("bed_transform")
	await _stand(_own_player(), _spot(3.0) - bed.basis.z.normalized() * 5.0)
	await get_tree().create_timer(1.0).timeout
	for index: int in CLIENT_SPOTS.size():
		var distance: float = CLIENT_SPOTS[index]
		var spot := _spot(distance)
		# The bag goes down at the spot; the client walks up to it when it sees it.
		var bag: Node3D = await _fresh_bag(spot + _facing(_yaw_to_bed(spot)) * 0.7, CLIENT_BAG_VALUE)
		var bag_id := bag.get_instance_id()
		var count_before := int(truck.call("bag_count"))
		var value_before := int(truck.call("bag_value"))
		var held: bool = await _until(func() -> bool: return not _gone(bag_id) and int(instance_from_id(bag_id).get("held_by")) == client_id, 10.0)
		var thrown := false
		if held:
			thrown = await _until(func() -> bool: return _gone(bag_id) or int(instance_from_id(bag_id).get("held_by")) == 0, 10.0)
		var gone := false
		if thrown:
			gone = await _until(func() -> bool: return _gone(bag_id), 5.0)
		await get_tree().create_timer(1.0).timeout
		var added := int(truck.call("bag_count")) - count_before
		var value_added := int(truck.call("bag_value")) - value_before
		_check("C%d the client's toss from %.0f m: held %s, thrown %s, gone %s, +%d bag(s), +$%d" % [index + 1, distance, held, thrown, gone, added, value_added], gone and added == 1 and value_added == CLIENT_BAG_VALUE)
		if not _gone(bag_id):
			instance_from_id(bag_id).call("queue_free")


func _player_node(peer_id: int) -> Node3D:
	for node: Node in get_tree().get_nodes_in_group("players"):
		if node.name == str(peer_id):
			return node as Node3D
	return null


func _player_near(peer_id: int, spot: Vector3, reach: float) -> bool:
	var node := _player_node(peer_id)
	return node != null and Vector2(node.global_position.x - spot.x, node.global_position.z - spot.z).length() < reach


## A wheelbarrow with two bags in it, thrown at Chefty, still unloads into it;
## then it's wheeled off out of the way (a bag near it would go in it).
func _wheelbarrow() -> void:
	var barrow := _prop("wheelbarrow")
	if barrow == null:
		_check("H6 no wheelbarrow on this lot", false)
		return
	var truck := _truck()
	var me := _own_player()
	await _stand(me, _spot(3.0))
	var yaw := _yaw_to_bed(me.global_position)
	barrow.set("stored_bags", 2)
	barrow.set("stored_value", 2 * BAG_VALUE)
	await _grab(barrow, yaw)
	var before := int(truck.call("bag_count"))
	await _hold_drop(0.4)
	await _until(func() -> bool: return int(barrow.get("stored_bags")) == 0, 3.0)
	await get_tree().create_timer(0.8).timeout
	var added := int(truck.call("bag_count")) - before
	_check("H6 a wheelbarrow thrown at Chefty unloads: +%d bags, %d left in it, %d drawn in the bed" % [added, int(barrow.get("stored_bags")), int((truck.call("bed_load") as Node).call("shown_count"))], added == 2 and int(barrow.get("stored_bags")) == 0)
	var lot := get_tree().get_first_node_in_group("job_lot") as Node3D
	barrow.global_position = lot.global_position + Vector3(0.0, 0.5, 0.0)
	(barrow as RigidBody3D).linear_velocity = Vector3.ZERO


## E by the bed: stand distance m from the bed's middle (beside the side wall),
## pick up a fresh bag, and heave it in from the hands the way E does.
func _heave(distance: float) -> Dictionary:
	var truck := _truck()
	var me := _own_player()
	await _stand(me, _spot(distance))
	var yaw := _yaw_to_bed(me.global_position)
	var bag: Node3D = await _fresh_bag(me.global_position + _facing(yaw) * 0.7)
	await _grab(bag, yaw)
	await get_tree().create_timer(0.3).timeout
	var count_before := int(truck.call("bag_count"))
	var value_before := int(truck.call("bag_value"))
	_BedToss.stats["max_pop_m"] = 0.0
	var near := bool(bag.call("near_truck"))
	bag.call("request_load_truck")
	var watch: Dictionary = await _watch(bag, 3.0)
	await get_tree().create_timer(0.5).timeout
	var row := {
		"distance": distance,
		"near": near,
		"added": int(truck.call("bag_count")) - count_before,
		"value_added": int(truck.call("bag_value")) - value_before,
		"pop_m": snappedf(float(_BedToss.stats["max_pop_m"]), 0.001),
		"stack_matches": int((truck.call("bed_load") as Node).call("shown_count")) == int(truck.call("bag_count")),
	}
	row.merge(watch)
	row["counted"] = int(row["added"]) > 0
	if is_instance_valid(bag):
		bag.queue_free()
		await _ticks(2)
	return row


## H9: plans a settle from every kind of start beside the truck (a bag in the
## hands 0.2 to 3 m off a side wall or the tailgate, heaved up or lobbed in;
## one caught just past a wall, falling in) into spots across the load, and
## measures how much deeper than at its ends any of them cuts into the truck.
## A few plans a frame: all at once it held the host's frame for 5 s or more,
## and ENet dropped the client mid-test (it then never saw the full bounce).
func _settle_sweep() -> Dictionary:
	var starts: Array = []
	for side: float in [-1.0, 1.0]:
		for off: float in [0.2, 0.5, 1.0, 2.0, 3.0]:
			for z: float in [-0.8, 0.7, 2.2]:
				for bottom: float in [0.53, 1.2]:
					starts.append([Vector3(side * (1.18 + off + 0.27), bottom, z), Vector3(-side, 0.0, 0.0)])
		for off: float in [0.0, 0.3, 0.6]:
			for bottom: float in [1.4, 1.7, 2.2]:
				starts.append([Vector3(side * (1.05 + off), bottom, 0.7), Vector3(-side * 3.0, -3.0, 0.0), true])
	for off: float in [0.2, 1.0, 3.0]:
		for x: float in [-0.6, 0.0, 0.6]:
			starts.append([Vector3(x, 0.53, 2.74 + off + 0.23), Vector3(0.0, 0.0, -1.0)])
	var slots: Array[int] = [0, 1, 2, 5, 15, 16, 20, 30, 31, 40, 49]
	var worst := 0.0
	var worst_case: Array = []
	var plans := 0
	for start: Array in starts:
		var at: Vector3 = start[0]
		var toward: Vector3 = start[1]
		var turn := Basis(Vector3.UP, atan2(-toward.x, -toward.z)) if start.size() < 3 else Basis(Vector3(0.3, 0.2, 0.9).normalized(), 1.1)
		var ways: Array = [toward] if start.size() == 3 else [Vector3.UP * Constants.BED_HAND_IN_LIFT, _BedToss.launch_velocity("leaf_bag", 4.0, toward, Constants.THROW_POWER_MIN), _BedToss.launch_velocity("leaf_bag", 4.0, toward, Constants.THROW_POWER_MAX)]
		for moving: Vector3 in ways:
			for index: int in slots:
				var from := Transform3D(turn, at)
				var to := _BedLoad.slot(index)
				var plan := _BedToss.settle_plan(from, moving, to, _BedToss.settle_seconds(from, to))
				var ends := maxf(_BedToss.cut_depth(from * _BedToss.LOOK_MIDDLE, _BedToss.look_reach(turn)), _BedToss.cut_depth(to * _BedToss.LOOK_MIDDLE, _BedToss.look_reach(to.basis.orthonormalized())))
				var excess := _fine_cut(plan) - ends
				plans += 1
				if plans % SWEEP_PLANS_PER_FRAME == 0:
					await get_tree().process_frame
				if excess > worst:
					worst = excess
					worst_case = [str(at), str(moving), index]
	return {"plans": plans, "worst_m": snappedf(worst, 0.001), "worst_case": worst_case}


## The deepest a planned settle cuts into the truck, looked at five times as
## finely as the plan checks itself.
static func _fine_cut(plan: Dictionary) -> float:
	var deepest := 0.0
	var samples := _BedToss.SETTLE_SAMPLES * 5
	for index: int in samples + 1:
		var body := _BedToss.settle_at(plan, float(plan["seconds"]) * float(index) / float(samples))
		deepest = maxf(deepest, _BedToss.cut_depth(body * _BedToss.LOOK_MIDDLE, _BedToss.look_reach(body.basis)))
	return deepest


## Fills Chefty to the brim and tosses one more from 3 m.
func _toss_full() -> Dictionary:
	var truck := _truck()
	var room := Constants.TRUCK_BAG_CAPACITY - int(truck.call("bag_count"))
	if room > 0:
		truck.call("accept_bags", room, 0)
	await get_tree().create_timer(1.0).timeout
	var refused_before := int(_BedToss.stats["refused"])
	var row: Dictionary = await _toss(3.0, 0.0, false)
	row["refused"] = int(_BedToss.stats["refused"]) > refused_before
	return row


# ---------------------------------------------------------------- client


func _run_client() -> void:
	var me := _own_player()
	# The host brings this player to the yard first.
	await _until(func() -> bool: return Net.player_zone(Net.local_peer_id()) == Net.Zone.LOT, 45.0)
	await get_tree().create_timer(1.5).timeout
	# Out of the host's line of fire: well back in the yard, past every throwing spot.
	await _stand(_own_player(), _spot(11.0))
	var throws: Array = []
	var max_jump := 0.0
	for distance: float in CLIENT_SPOTS:
		# Wait out of the way (where it joined) for the host to put a bag down at
		# the spot, then walk up to it.
		var spot := _spot(distance)
		var bag: Node3D = null
		var waited := 0.0
		while bag == null and waited < 60.0:
			await get_tree().create_timer(0.2).timeout
			waited += 0.2
			bag = _loose_bag_near(spot, 2.0)
		if bag == null:
			throws.append({"distance": distance, "error": "no bag"})
			continue
		me = _own_player()
		await _stand(me, spot)
		var yaw := _yaw_to_bed(me.global_position)
		me.set("body_yaw", yaw)
		var bag_id := bag.get_instance_id()
		await get_tree().create_timer(0.3).timeout
		bag.call("request_grab")
		var got: bool = await _until(func() -> bool: return not _gone(bag_id) and int(instance_from_id(bag_id).get("held_by")) == Net.local_peer_id(), 5.0)
		if not got:
			throws.append({"distance": distance, "error": "could not pick it up", "bag_m": snappedf(bag.global_position.distance_to(me.global_position), 0.01) if not _gone(bag_id) else -1.0})
			print("[TossTest] client %s" % JSON.stringify(throws[throws.size() - 1]))
			continue
		await get_tree().create_timer(0.4).timeout
		me.set("body_yaw", yaw)
		await _ticks(2)
		var hold := _hold_for(bag, me)
		await _until(func() -> bool: return _lane_clear(me.global_position, me.global_position + _facing(yaw) * (distance + 1.5)), 10.0)
		var catches_before := int(_BedToss.stats["catch_seen"])
		var lands_before := int(_BedToss.stats["land_seen"])
		_BedToss.stats["max_pop_m"] = 0.0
		await _hold_drop(hold)
		var watch := {"max_jump_m": 0.0}
		if not _gone(bag_id):
			watch = await _watch(bag, 6.0)
		max_jump = maxf(max_jump, float(watch["max_jump_m"]))
		throws.append({"distance": distance, "hold": snappedf(hold, 0.01), "caught_seen": int(_BedToss.stats["catch_seen"]) > catches_before, "landed_seen": int(_BedToss.stats["land_seen"]) > lands_before, "max_jump_m": watch["max_jump_m"], "jump_at": watch.get("jump_at", []), "pop_m": snappedf(float(_BedToss.stats["max_pop_m"]), 0.001)})
		print("[TossTest] client toss %s (at %.1f s)" % [JSON.stringify(throws[throws.size() - 1]), _clock()])
	# Out of the way, then watch for the full bed's bounce.
	await _stand(_own_player(), _spot(11.0))
	var bounce_from := _clock()
	await _until(func() -> bool: return int(_BedToss.stats["full_seen"]) > 0, 60.0)
	print("[TossTest] client waited %.1f s for the full bounce (from %.1f s): seen %d" % [_clock() - bounce_from, bounce_from, int(_BedToss.stats["full_seen"])])
	var ok := throws.size() == CLIENT_SPOTS.size() and int(_BedToss.stats["full_seen"]) > 0 and max_jump < JUMP_LIMIT_M
	for row: Dictionary in throws:
		ok = ok and bool(row.get("caught_seen", false)) and bool(row.get("landed_seen", false)) and float(row.get("pop_m", 1.0)) < POP_LIMIT_M
	# Its own predicted tosses through its own eyes (fp_carried flips on the
	# prediction and the settle here, not on the host's say-so).
	var view: Dictionary = _CarryView.stats
	var eyes_ok := _own_eyes_ok(view, CLIENT_SPOTS.size())
	print("[TossTest] client %s its own bag through its own eyes: %s" % ["ok" if eyes_ok else "FAIL", JSON.stringify(view)])
	ok = ok and eyes_ok
	result["view"] = view.duplicate()
	result["throws"] = throws
	result["stats"] = _BedToss.stats.duplicate()
	result["ok"] = ok
	result["done"] = true
	print("[TossTest] client all ok: %s" % ok)

func _loose_bag_near(at: Vector3, reach: float) -> Node3D:
	for node: Node in get_tree().get_nodes_in_group("props"):
		if str(node.get("kind")) == "leaf_bag" and int(node.get("value")) == CLIENT_BAG_VALUE and bool(node.call("is_loose")) and not node.is_queued_for_deletion() and (node as Node3D).global_position.distance_to(at) < reach:
			return node as Node3D
	return null


# ---------------------------------------------------------------- shared


## Where to stand distance m from the bed's middle, beside the truck on the
## yard's side (the side nearer the lot), on the ground.
func _spot(distance: float) -> Vector3:
	var truck := _truck()
	var bed: Transform3D = truck.call("bed_transform")
	var middle := bed * _BedToss.BED_MIDDLE
	var lot := get_tree().get_first_node_in_group("job_lot") as Node3D
	var toward := lot.global_position if lot != null else middle + bed.basis.x
	var side := bed.basis.x
	side.y = 0.0
	side = side.normalized()
	if (middle - side).distance_to(toward) < (middle + side).distance_to(toward):
		side = -side
	var at := middle + side * distance
	at.y = bed.origin.y + 0.1
	return at


## Puts a player at a spot (dropped from a little above, so a curb can't swallow
## them) and waits for them to land.
func _stand(me: Node3D, spot: Vector3) -> void:
	await get_tree().physics_frame
	me.call("apply_network_teleport", Transform3D(Basis.IDENTITY, spot + Vector3(0.0, 0.5, 0.0)))
	await _ticks(3)
	await _until(func() -> bool: return (me as CharacterBody3D).is_on_floor(), 2.0)
	await _ticks(2)


## How far a point is from the bed's middle, along the ground.
## True when nobody a bag could bonk (net_prop.gd _check_bonks) stands within
## 1.6 m of the line from a to b, along the ground.
func _lane_clear(a: Vector3, b: Vector3) -> bool:
	var me := _own_player()
	for node: Node in get_tree().get_nodes_in_group("bonkable") + get_tree().get_nodes_in_group("players"):
		if node == me or not node is Node3D:
			continue
		var p := Vector2((node as Node3D).global_position.x, (node as Node3D).global_position.z)
		var start := Vector2(a.x, a.z)
		var end := Vector2(b.x, b.z)
		var along := clampf((p - start).dot(end - start) / maxf((end - start).length_squared(), 0.01), 0.0, 1.0)
		if p.distance_to(start.lerp(end, along)) < 1.6:
			return false
	return true


func _from_middle(at: Vector3) -> float:
	var middle := (_truck().call("bed_transform") as Transform3D) * _BedToss.BED_MIDDLE
	return Vector2(at.x - middle.x, at.z - middle.z).length()


func _gone(id: int) -> bool:
	var node := instance_from_id(id) as Node
	return node == null or not is_instance_valid(node) or node.is_queued_for_deletion()


func _yaw_to_bed(from: Vector3) -> float:
	var middle := (_truck().call("bed_transform") as Transform3D) * _BedToss.BED_MIDDLE
	var dir := Vector3(middle.x - from.x, 0.0, middle.z - from.z).normalized()
	return atan2(-dir.x, -dir.z)


func _facing(yaw: float) -> Vector3:
	return Vector3(-sin(yaw), 0.0, -cos(yaw))


## The wind-up a player who knows the arc would use: of the holds that land it
## in the bed (no aim help), the middle one.
func _hold_for(bag: Node3D, me: Node3D, short: bool = false) -> float:
	var truck := _truck()
	var feet := me.global_position
	var kg := float(bag.call("weight_kg"))
	# Aimed straight at the bed (a near miss is the same wind-up, turned off).
	var forward := _facing(_yaw_to_bed(feet))
	var from: Vector3 = bag.call("_hold_position", me)
	var good: Array[float] = []
	var hold := Constants.THROW_TAP_SECONDS + 0.02
	while hold <= Constants.THROW_CHARGE_SECONDS:
		var vel := _BedToss.launch_velocity("leaf_bag", kg, forward, _BedToss.power_for_seconds(hold))
		if bool(_BedToss.flight(from, vel, feet.y, truck)["caught"]):
			good.append(hold)
		hold += 0.01
	if good.is_empty():
		print("[TossTest] no wind-up goes in: feet %s (%.2f m from the middle), hands %s, %.1f kg, held by %d" % [feet, _from_middle(feet), from, kg, int(bag.get("held_by"))])
		return 0.6
	if short:
		# Below the shortest that goes in by itself: the middle of the ones only the
		# aim help saves (not the edge, where a hair decides it).
		var saved: Array[float] = []
		hold = good[0] - 0.01
		while hold > Constants.THROW_TAP_SECONDS:
			var vel := _BedToss.launch_velocity("leaf_bag", kg, forward, _BedToss.power_for_seconds(hold))
			if not bool(_BedToss.flight(from, vel, feet.y, truck)["caught"]) and bool(_BedToss.flight(from, _BedToss.assist(truck, from, vel, feet.y), feet.y, truck)["caught"]):
				saved.append(hold)
			hold -= 0.01
		print("[TossTest] holds that go in by themselves %s..%s; only with help: %s" % [good[0], good[good.size() - 1], saved])
		return saved[saved.size() / 2] if not saved.is_empty() else good[0]
	return good[good.size() / 2]


func _fresh_bag(at: Vector3, worth: int = BAG_VALUE) -> Node3D:
	var world := get_tree().get_first_node_in_group("world")
	world.call("_spawn_bag", at, 0)
	await _ticks(3)
	var bag := _newest_bag()
	bag.set("value", worth)
	await _ticks(2)
	return bag


func _client_player(seconds: float) -> Node3D:
	var waited := 0.0
	while waited < seconds:
		for node: Node in get_tree().get_nodes_in_group("players"):
			if node.name != str(Net.local_peer_id()) and node is Node3D:
				return node as Node3D
		await get_tree().create_timer(0.25).timeout
		waited += 0.25
	return null


func _until(test: Callable, seconds: float) -> bool:
	var waited := 0.0
	while waited < seconds:
		if bool(test.call()):
			return true
		await get_tree().physics_frame
		waited += get_physics_process_delta_time()
	return bool(test.call())


## --toss-survey: throws bags at the bed from several distances and wind-ups and
## prints what happened to each.
func _survey() -> void:
	await get_tree().create_timer(1.5).timeout
	var truck := _truck()
	var rows: Array = []
	for distance: float in [2.0, 3.0, 4.0, 6.0]:
		for step: int in 11:
			rows.append(await _survey_one(truck, distance, 0.2 + 0.1 * float(step), BAG_VALUE))
	result["survey"] = rows
	result["done"] = true
	result["ok"] = true


func _survey_one(truck: Node3D, distance: float, hold: float, value: int) -> Dictionary:
	var me := _own_player()
	var bed: Transform3D = truck.call("bed_transform")
	var spot := _spot(distance)
	await _stand(me, spot)
	var yaw := _yaw_to_bed(me.global_position)
	var before := int(truck.call("bag_count"))
	var bag: Node3D = await _fresh_bag(me.global_position + _facing(yaw) * 0.7)
	bag.set("value", value)
	await _grab(bag, yaw)
	var arc_caught: bool = await _hold_drop(hold)
	var watch: Dictionary = await _watch(bag, 3.0)
	await get_tree().create_timer(0.5).timeout
	var row := {"distance": distance, "hold": hold, "value": value, "caught": int(truck.call("bag_count")) > before, "arc_caught": arc_caught}
	row.merge(watch)
	if bool(row["caught"]) == arc_caught:
		row.erase("path")
	print("[TossTest] survey %s" % JSON.stringify(row))
	if is_instance_valid(bag):
		bag.queue_free()
	await _ticks(3)
	return row


func _truck() -> Node3D:
	var truck := get_tree().get_first_node_in_group("chefty") as Node3D
	return truck if truck != null and truck.has_method("bed_transform") else null


func _newest_bag() -> Node3D:
	var best: Node3D = null
	for node: Node in get_tree().get_nodes_in_group("props"):
		if str(node.get("kind")) == "leaf_bag" and not node.is_queued_for_deletion():
			if best == null or node.get_index() > best.get_index():
				best = node as Node3D
	return best


func _prop(kind: String) -> Node3D:
	for node: Node in get_tree().get_nodes_in_group("props"):
		if str(node.get("kind")) == kind and not node.is_queued_for_deletion():
			return node as Node3D
	return null


func _grab(item: Node3D, yaw: float) -> void:
	var me := _own_player()
	await get_tree().physics_frame
	me.set("body_yaw", yaw)
	me.rotation.y = yaw
	item.global_position = me.global_position + Vector3(0.0, 0.4, 0.0) + (-me.global_basis.z) * 0.8
	item.set("linear_velocity", Vector3.ZERO)
	await _ticks(3)
	item.call("request_grab")
	await _ticks(3)


func _ticks(count: int) -> void:
	for _tick: int in count:
		await get_tree().physics_frame


func _own_player() -> Node3D:
	for node: Node in get_tree().get_nodes_in_group("players"):
		if node.name == str(Net.local_peer_id()):
			return node as Node3D
	return null
